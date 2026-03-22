#!/usr/bin/env python3
# Version: 18
# Last Changed: 2026-03-22 UTC
"""Claude Metrics — session metrics engine.

Reads Claude Code session JSONL files to provide real-time token usage,
cost tracking, and context window composition analysis.

No external dependencies — Python 3.8+ stdlib only.
"""
from __future__ import annotations

import json
import math
import os
import subprocess
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

# ── Configuration ────────────────────────────────────────────────────────

CLAUDE_DIR = Path.home() / ".claude"
PROJECTS_DIR = CLAUDE_DIR / "projects"

# Pricing per million tokens (USD)
PRICING: dict[str, dict[str, float]] = {
    "claude-opus-4": {
        "input": 15.0,
        "output": 75.0,
        "cache_write": 18.75,
        "cache_read": 1.50,
    },
    "claude-sonnet-4": {
        "input": 3.0,
        "output": 15.0,
        "cache_write": 3.75,
        "cache_read": 0.30,
    },
    "claude-haiku-4": {
        "input": 0.80,
        "output": 4.0,
        "cache_write": 1.0,
        "cache_read": 0.08,
    },
}

# Max context window per model family (tokens)
MAX_CONTEXT: dict[str, int] = {
    "claude-opus-4": 1_000_000,
    "claude-sonnet-4": 200_000,
    "claude-haiku-4": 200_000,
}

# Chars-per-token estimation heuristic
CHARS_PER_TOKEN = 4

# One-liner style: "simple" (default) or "ext-context"
METRICS_STYLE = "simple"

VALID_STYLES = (
    "simple",
    "ext-context",
    "ext-all",
    "minimal",
    "cost-focus",
    "compact",
    "git-status",
    "git-diff",
    "git-compact",
    "ctx-git",
    "simple-git",
    "minimal-git",
)


# ── Helpers ──────────────────────────────────────────────────────────────


def _path_to_workspace_hash(cwd: str) -> str:
    """Convert a filesystem path to the Claude projects directory hash.

    Example: 'd:\\Lab\\workspaces\\Homelab' -> 'd--Lab-workspaces-Homelab'
    """
    p = cwd.replace("\\", "/").rstrip("/")
    p = p.replace(":/", "--")
    p = p.replace("/", "-")
    return p


def _find_session_file(workspace: str = "") -> Path | None:
    """Find the most recently modified JSONL session file.

    If workspace is provided, search only that workspace directory.
    Otherwise, search all workspace directories for the latest file.
    """
    if workspace:
        if os.sep in workspace or "/" in workspace or "\\" in workspace:
            workspace = _path_to_workspace_hash(workspace)
        target = PROJECTS_DIR / workspace
        if target.is_dir():
            search_dirs = [target]
        elif PROJECTS_DIR.is_dir():
            # Case-insensitive fallback (Windows drive letter casing varies)
            lower = workspace.lower()
            search_dirs = [
                d for d in PROJECTS_DIR.iterdir()
                if d.is_dir() and d.name.lower() == lower
            ]
        else:
            return None
    else:
        if not PROJECTS_DIR.is_dir():
            return None
        search_dirs = [d for d in PROJECTS_DIR.iterdir() if d.is_dir()]

    latest: Path | None = None
    latest_mtime: float = 0.0

    for d in search_dirs:
        if not d.is_dir():
            continue
        for f in d.glob("*.jsonl"):
            try:
                mt = f.stat().st_mtime
            except OSError:
                continue
            if mt > latest_mtime:
                latest_mtime = mt
                latest = f

    return latest


def _get_pricing(model: str) -> dict[str, float]:
    """Look up pricing by matching the longest model prefix."""
    for prefix in sorted(PRICING.keys(), key=len, reverse=True):
        if model.startswith(prefix):
            return PRICING[prefix]
    return PRICING["claude-sonnet-4"]


def _get_max_context(model: str) -> int:
    """Look up max context window for a model."""
    for prefix in sorted(MAX_CONTEXT.keys(), key=len, reverse=True):
        if model.startswith(prefix):
            return MAX_CONTEXT[prefix]
    return 200_000


def _format_tokens(n: int) -> str:
    """Format token count as human-readable string (e.g., 45.2K, 1.3M)."""
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}M"
    if n >= 1_000:
        return f"{n / 1_000:.1f}K"
    return str(n)


def _format_number(n: int) -> str:
    """Format a number with comma separators."""
    return f"{n:,}"


def _estimate_tokens_from_file(path: Path) -> int:
    """Estimate token count from file size using chars/token heuristic."""
    try:
        size = path.stat().st_size
        return math.ceil(size / CHARS_PER_TOKEN)
    except OSError:
        return 0


def _ctx_emoji(pct: float) -> str:
    """Return color emoji based on context usage percentage."""
    if pct < 50:
        return "\U0001f7e2"  # green circle
    if pct < 80:
        return "\U0001f7e1"  # yellow circle
    return "\U0001f534"  # red circle


def _progress_bar(pct: float, width: int = 30) -> str:
    """Render a unicode progress bar."""
    filled = round(pct / 100 * width)
    filled = max(0, min(width, filled))
    return "\u2593" * filled + "\u2591" * (width - filled)


def _parse_session(session_file: Path) -> dict[str, Any]:
    """Parse a session JSONL file and extract all metrics.

    Returns a dict with accumulated token counts, cost, model info,
    timestamps, turn count, and extended metadata.
    """
    totals: dict[str, Any] = {
        "input_tokens": 0,
        "output_tokens": 0,
        "cache_write_tokens": 0,
        "cache_read_tokens": 0,
        "cache_1h_tokens": 0,
        "cache_5m_tokens": 0,
        "turns": 0,
        "model": "",
        "first_ts": "",
        "last_ts": "",
        "last_turn_input": 0,
        # Extended fields
        "stop_reasons": Counter(),
        "speed": "standard",
        "service_tier": "standard",
        "web_searches": 0,
        "web_fetches": 0,
        "sidechain_turns": 0,
        "sidechain_input": 0,
        "sidechain_output": 0,
        "tool_calls": 0,
        "permission_mode": "",
        "version": "",
        "entrypoint": "",
        "git_branch": "",
        "session_slug": "",
        "max_context_seen": 0,
        "context_history": [],  # list of (turn, input_tokens) for trend
        "skipped_lines": 0,
    }

    with open(session_file, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                totals["skipped_lines"] += 1
                continue

            entry_type = entry.get("type", "")
            ts = entry.get("timestamp", "")

            if ts:
                if not totals["first_ts"]:
                    totals["first_ts"] = ts
                totals["last_ts"] = ts

            # Capture metadata from any entry
            if not totals["version"] and entry.get("version"):
                totals["version"] = entry["version"]
            if not totals["entrypoint"] and entry.get("entrypoint"):
                totals["entrypoint"] = entry["entrypoint"]
            if not totals["git_branch"] and entry.get("gitBranch"):
                totals["git_branch"] = entry["gitBranch"]
            if not totals["session_slug"] and entry.get("slug"):
                totals["session_slug"] = entry["slug"]

            if entry_type == "assistant":
                msg = entry.get("message", {})
                usage = msg.get("usage", {})

                if not usage:
                    continue

                if not totals["model"] and msg.get("model"):
                    totals["model"] = msg["model"]

                inp = usage.get("input_tokens", 0)
                out = usage.get("output_tokens", 0)
                cw = usage.get("cache_creation_input_tokens", 0)
                cr = usage.get("cache_read_input_tokens", 0)

                # Use top-level cache fields only (avoid double-count
                # with cache_creation.ephemeral_* sub-fields)
                totals["input_tokens"] += inp
                totals["output_tokens"] += out
                totals["cache_write_tokens"] += cw
                totals["cache_read_tokens"] += cr

                # Track cache TTL breakdown from sub-fields
                cache_sub = usage.get("cache_creation", {})
                if isinstance(cache_sub, dict):
                    totals["cache_1h_tokens"] += cache_sub.get(
                        "ephemeral_1h_input_tokens", 0
                    )
                    totals["cache_5m_tokens"] += cache_sub.get(
                        "ephemeral_5m_input_tokens", 0
                    )

                turn_input = inp + cw + cr
                totals["turns"] += 1
                totals["last_turn_input"] = turn_input
                totals["max_context_seen"] = max(
                    totals["max_context_seen"], turn_input
                )

                # Sample context history (every 10th turn to keep compact)
                if totals["turns"] % 10 == 1 or totals["turns"] <= 5:
                    totals["context_history"].append(
                        (totals["turns"], turn_input)
                    )

                # Stop reason
                sr = msg.get("stop_reason")
                if sr:
                    totals["stop_reasons"][sr] += 1

                # Speed and tier from latest turn
                totals["speed"] = usage.get("speed", totals["speed"])
                totals["service_tier"] = usage.get(
                    "service_tier", totals["service_tier"]
                )

                # Web tool usage
                server_tools = usage.get("server_tool_use", {})
                if isinstance(server_tools, dict):
                    totals["web_searches"] += server_tools.get(
                        "web_search_requests", 0
                    )
                    totals["web_fetches"] += server_tools.get(
                        "web_fetch_requests", 0
                    )

                # Sidechain tracking
                if entry.get("isSidechain"):
                    totals["sidechain_turns"] += 1
                    totals["sidechain_input"] += inp + cw + cr
                    totals["sidechain_output"] += out

            elif entry_type == "user":
                # Track permission mode from latest user entry
                pm = entry.get("permissionMode")
                if pm:
                    totals["permission_mode"] = pm

                # Count subagent tool results
                tool_result = entry.get("toolUseResult")
                if isinstance(tool_result, dict):
                    usage = tool_result.get("usage", {})
                    if isinstance(usage, dict):
                        totals["input_tokens"] += usage.get(
                            "input_tokens", 0
                        )
                        totals["output_tokens"] += usage.get(
                            "output_tokens", 0
                        )
                        totals["cache_write_tokens"] += usage.get(
                            "cache_creation_input_tokens", 0
                        )
                        totals["cache_read_tokens"] += usage.get(
                            "cache_read_input_tokens", 0
                        )

            elif entry_type == "progress":
                data = entry.get("data", {})
                if isinstance(data, dict):
                    # Count tool executions (not hooks)
                    dtype = data.get("type", "")
                    if dtype not in ("hook_progress", ""):
                        totals["tool_calls"] += 1

    # Always append the final turn to context history
    if totals["turns"] > 0:
        last = totals["context_history"]
        if not last or last[-1][0] != totals["turns"]:
            totals["context_history"].append(
                (totals["turns"], totals["last_turn_input"])
            )

    return totals


def _compute_cost(totals: dict[str, Any], pricing: dict[str, float]) -> float:
    """Calculate total cost in USD from token totals and pricing."""
    return (
        totals["input_tokens"] * pricing["input"]
        + totals["output_tokens"] * pricing["output"]
        + totals["cache_write_tokens"] * pricing["cache_write"]
        + totals["cache_read_tokens"] * pricing["cache_read"]
    ) / 1_000_000


def _compute_duration(first_ts: str, last_ts: str) -> float:
    """Calculate duration in minutes between two ISO timestamps."""
    if not first_ts or not last_ts:
        return 0.0
    try:
        t0 = datetime.fromisoformat(first_ts.replace("Z", "+00:00"))
        t1 = datetime.fromisoformat(last_ts.replace("Z", "+00:00"))
        return (t1 - t0).total_seconds() / 60
    except (ValueError, TypeError):
        return 0.0


def _sparkline(history: list[tuple[int, int]], max_ctx: int) -> str:
    """Build a sparkline string from context history data points.

    Uses block characters to show context growth over time.
    Normalizes to 0-max so all blocks grow upward from a common
    baseline — no values cross the x-axis.
    """
    blocks = "\u2581\u2582\u2583\u2584\u2585\u2586\u2587\u2588"
    if not history:
        return ""
    values = [ctx for _, ctx in history]
    hi = max(values)
    if hi == 0:
        return blocks[0] * len(values)
    result = []
    for v in values:
        idx = min(int(v / hi * (len(blocks) - 1)), len(blocks) - 1)
        result.append(blocks[idx])
    return "".join(result)


def _trend_indicator(history: list[tuple[int, int]]) -> tuple[str, float]:
    """Compute trend direction and delta % from context history.

    Compares the last data point to the second-to-last to determine
    if context is growing or shrinking.

    Returns (arrow_icon, delta_percentage).
    """
    if len(history) < 2:
        return ("\u2194", 0.0)  # left-right arrow = no data
    prev_ctx = history[-2][1]
    curr_ctx = history[-1][1]
    if prev_ctx == 0:
        return ("\u2194", 0.0)
    delta_pct = (curr_ctx - prev_ctx) / prev_ctx * 100
    if delta_pct > 1.0:
        return ("\u2197", delta_pct)   # ↗ rising
    if delta_pct < -1.0:
        return ("\u2198", delta_pct)   # ↘ falling
    return ("\u2192", delta_pct)       # → stable


def _build_compact_line(
    totals: dict[str, Any],
    cost: float,
    ctx_pct: float,
    duration_min: float,
) -> str:
    """Build the compact one-liner with progress bar and emoji indicators.

    Format:
    🟢▓▓▓░░░░░░░ 9.1% 91.4K/1M ┃ 🔼1.6K 🔽74K ┃ $40.14
      ┃ Tools:87 End:28 ┃ opus-4-6 v2.1.79 ┃ ▁▂▃▃▂ ↘ -1.8%
    """
    emoji = _ctx_emoji(ctx_pct)
    bar = _progress_bar(ctx_pct, 10)
    max_ctx = _get_max_context(totals["model"] or "unknown")

    # Token arrows
    inp_str = _format_tokens(totals["input_tokens"])
    out_str = _format_tokens(totals["output_tokens"])

    # Stop reason counts
    tools = totals["stop_reasons"].get("tool_use", 0)
    ends = totals["stop_reasons"].get("end_turn", 0)

    # Model name — strip "claude-" prefix for compactness
    model = (totals["model"] or "unknown").replace("claude-", "")

    # Sparkline and trend (limit to last 20 points for compact display)
    history = totals.get("context_history", [])
    history = history[-20:] if len(history) > 20 else history
    spark = _sparkline(history, max_ctx)
    trend_arrow, trend_delta = _trend_indicator(history)
    trend_str = f"{trend_arrow} {trend_delta:+.1f}%" if history else ""

    return (
        f"{emoji}{bar} {ctx_pct:.1f}%"
        f" {_format_tokens(totals['last_turn_input'])}"
        f"/{_format_tokens(max_ctx)}"
        f" \u2503 \U0001f53c{inp_str} \U0001f53d{out_str}"
        f" \u2503 ${cost:.2f}"
        f" \u2503 Tool:{tools} End:{ends}"
        f" \u2503 {model} v{totals['version'] or '?'}"
        f" \u2503 {spark} {trend_str}"
    )


def _build_ext_context_line(
    totals: dict[str, Any],
    cost: float,
    ctx_pct: float,
    components: list[dict[str, Any]],
) -> str:
    """Build one-liner with inline context composition breakdown.

    Format:
    🟢▓▓░░░░░░░░ 18.1% 181.1K/1.0M [ 3% CLAUDE.md | 2% MCP | 2% SYS | 93% CONVO ]
    """
    emoji = _ctx_emoji(ctx_pct)
    bar = _progress_bar(ctx_pct, 10)
    max_ctx = _get_max_context(totals["model"] or "unknown")

    # Build context composition summary
    parts: list[str] = []
    for c in components:
        pct = c.get("pct", 0)
        if pct < 0.5:
            continue  # skip negligible
        # Shorten names for compact display
        name = c["name"]
        if "CLAUDE.md" in name:
            label = "CLAUDE.md"
        elif "MCP" in name:
            label = "MCP"
        elif "System" in name:
            label = "SYS"
        elif "Memory" in name:
            label = "MEM"
        elif "Conversation" in name:
            label = "CONVO"
        else:
            label = name[:8]
        parts.append(f"{pct:.0f}% {label}")

    comp_str = " | ".join(parts)

    return (
        f"{emoji}{bar} {ctx_pct:.1f}%"
        f" {_format_tokens(totals['last_turn_input'])}"
        f"/{_format_tokens(max_ctx)}"
        f" [ {comp_str} ]"
    )


def _build_ext_all_line(
    totals: dict[str, Any],
    cost: float,
    ctx_pct: float,
    duration_min: float,
    components: list[dict[str, Any]],
) -> str:
    """Build one-liner combining context composition with full metrics.

    Format:
    🟢▓▓░░░░░░░░ 18.1% 181.1K/1.0M [ 3% CLAUDE.md | 2% MCP | 2% SYS | 93% CONVO ]
      ┃ 🔼10.0K 🔽92.3K ┃ $114.79 ┃ Tool:175 End:46 ┃ opus-4-6 v2.1.81 ┃ ▁▂▃▄▅ ↗ +1.2%
    """
    emoji = _ctx_emoji(ctx_pct)
    bar = _progress_bar(ctx_pct, 10)
    max_ctx = _get_max_context(totals["model"] or "unknown")

    # Context composition summary
    parts: list[str] = []
    for c in components:
        pct = c.get("pct", 0)
        if pct < 0.5:
            continue
        name = c["name"]
        if "CLAUDE.md" in name:
            label = "CLAUDE.md"
        elif "MCP" in name:
            label = "MCP"
        elif "System" in name:
            label = "SYS"
        elif "Memory" in name:
            label = "MEM"
        elif "Conversation" in name:
            label = "CONVO"
        else:
            label = name[:8]
        parts.append(f"{pct:.0f}% {label}")
    comp_str = " | ".join(parts)

    # Token arrows
    inp_str = _format_tokens(totals["input_tokens"])
    out_str = _format_tokens(totals["output_tokens"])

    # Stop reason counts
    tools = totals["stop_reasons"].get("tool_use", 0)
    ends = totals["stop_reasons"].get("end_turn", 0)

    # Model name — strip "claude-" prefix for compactness
    model = (totals["model"] or "unknown").replace("claude-", "")

    # Sparkline and trend
    history = totals.get("context_history", [])
    history = history[-20:] if len(history) > 20 else history
    spark = _sparkline(history, max_ctx)
    trend_arrow, trend_delta = _trend_indicator(history)
    trend_str = f"{trend_arrow} {trend_delta:+.1f}%" if history else ""

    return (
        f"{emoji}{bar} {ctx_pct:.1f}%"
        f" {_format_tokens(totals['last_turn_input'])}"
        f"/{_format_tokens(max_ctx)}"
        f" [ {comp_str} ]"
        f" \u2503 \U0001f53c{inp_str} \U0001f53d{out_str}"
        f" \u2503 ${cost:.2f}"
        f" \u2503 Tool:{tools} End:{ends}"
        f" \u2503 {model} v{totals['version'] or '?'}"
        f" \u2503 {spark} {trend_str}"
    )


def _build_minimal_line(
    totals: dict[str, Any],
    cost: float,
    ctx_pct: float,
) -> str:
    """Build minimal one-liner: context %, cost, turn count.

    Format:
    🟢 18.1% ┃ $114.79 ┃ T:435
    """
    emoji = _ctx_emoji(ctx_pct)
    return (
        f"{emoji} {ctx_pct:.1f}%"
        f" \u2503 ${cost:.2f}"
        f" \u2503 T:{totals['turns']}"
    )


def _build_cost_focus_line(
    totals: dict[str, Any],
    cost: float,
    ctx_pct: float,
) -> str:
    """Build spending-oriented one-liner with progress bar.

    Format:
    🟢▓▓░░░░░░░░ 18.1% 181.1K/1.0M ┃ $114.79 ┃ 🔼10.0K 🔽92.3K ┃ Tool:175 End:46
    """
    emoji = _ctx_emoji(ctx_pct)
    bar = _progress_bar(ctx_pct, 10)
    max_ctx = _get_max_context(totals["model"] or "unknown")

    inp_str = _format_tokens(totals["input_tokens"])
    out_str = _format_tokens(totals["output_tokens"])

    tools = totals["stop_reasons"].get("tool_use", 0)
    ends = totals["stop_reasons"].get("end_turn", 0)

    return (
        f"{emoji}{bar} {ctx_pct:.1f}%"
        f" {_format_tokens(totals['last_turn_input'])}"
        f"/{_format_tokens(max_ctx)}"
        f" \u2503 ${cost:.2f}"
        f" \u2503 \U0001f53c{inp_str} \U0001f53d{out_str}"
        f" \u2503 Tool:{tools} End:{ends}"
    )


def _build_compact_style_line(
    totals: dict[str, Any],
    cost: float,
    ctx_pct: float,
) -> str:
    """Build dense one-liner without sparkline.

    Format:
    🟢 18.1% 181.1K/1.0M ┃ 🔼10K 🔽92K ┃ $114 ┃ T:175 E:46 ┃ opus-4-6
    """
    emoji = _ctx_emoji(ctx_pct)
    max_ctx = _get_max_context(totals["model"] or "unknown")

    inp_str = _format_tokens(totals["input_tokens"])
    out_str = _format_tokens(totals["output_tokens"])

    tools = totals["stop_reasons"].get("tool_use", 0)
    ends = totals["stop_reasons"].get("end_turn", 0)

    model = (totals["model"] or "unknown").replace("claude-", "")

    return (
        f"{emoji} {ctx_pct:.1f}%"
        f" {_format_tokens(totals['last_turn_input'])}"
        f"/{_format_tokens(max_ctx)}"
        f" \u2503 \U0001f53c{inp_str} \U0001f53d{out_str}"
        f" \u2503 ${cost:.0f}"
        f" \u2503 T:{tools} E:{ends}"
        f" \u2503 {model}"
    )


def set_metrics_style(style: str) -> None:
    """Set the global one-liner style.

    Valid values: see VALID_STYLES.
    Raises ValueError for unrecognized styles.
    """
    global METRICS_STYLE
    if style not in VALID_STYLES:
        raise ValueError(
            f"Unknown metrics style {style!r}; expected one of {VALID_STYLES}"
        )
    METRICS_STYLE = style


def _build_detail_view(
    totals: dict[str, Any],
    cost: float,
    ctx_pct: float,
    duration_min: float,
    max_ctx: int,
    context_components: list[dict[str, Any]] | None = None,
) -> str:
    """Build the detailed box-drawn metrics view."""
    W = 55  # horizontal rule width

    def row(text: str) -> str:
        return f"\u2502 {text}"

    def sep() -> str:
        return f"\u251c{'\u2500' * W}"

    lines = [
        f"\u250c{'\u2500' * W}",
        row(f"\u25c6 Claude Session Metrics"),
        sep(),
        # Session info
        row(
            f"\U0001f916 Model:     {totals['model'] or 'unknown'}"
        ),
        row(
            f"\U0001f4e6 Version:   {totals['version'] or '?'}"
            f"  \u2502  \U0001f517 {totals['entrypoint'] or '?'}"
        ),
        row(
            f"\u23f1  Duration:  {duration_min:.0f} min"
            f"  \u2502  \U0001f504 Turns: {totals['turns']}"
        ),
        row(f"\U0001f4b0 Cost:      ${cost:.2f}"),
        row(
            f"\u26a1 Speed:     {totals['speed']}"
            f"  \u2502  \U0001f3ab Tier: {totals['service_tier']}"
        ),
        row(
            f"\U0001f500 Branch:    {totals['git_branch'] or '?'}"
            f"  \u2502  \U0001f512 Mode: {totals['permission_mode'] or '?'}"
        ),
        sep(),
        # Context window
        row(f"\U0001f4ca Context Window"),
        row(f"{_progress_bar(ctx_pct)}  {ctx_pct:.1f}%"),
        row(
            f"Used: {_format_number(totals['last_turn_input'])}"
            f" / {_format_number(max_ctx)} tokens"
        ),
        row(
            f"Peak: {_format_number(totals['max_context_seen'])} tokens"
            f" ({totals['max_context_seen'] / max_ctx * 100:.1f}%)"
            if max_ctx
            else "Peak: N/A"
        ),
    ]

    # Context composition (if provided)
    if context_components:
        lines.append(sep())
        lines.append(row(f"\U0001f4ca Context Composition (estimated)"))
        for comp in context_components:
            name = comp["name"]
            tokens = _format_tokens(comp["tokens"])
            pct = comp.get("pct", 0)
            lines.append(row(f"  {name:<28s} {tokens:>6s}  {pct:>5.1f}%"))

    # Token breakdown
    lines.append(sep())
    lines.append(row(f"\U0001fa99 Token Breakdown"))
    lines.append(
        row(f"  Input (fresh):     {_format_tokens(totals['input_tokens']):>8s}")
    )
    lines.append(
        row(f"  Output:            {_format_tokens(totals['output_tokens']):>8s}")
    )
    cw = totals["cache_write_tokens"]
    c1h = totals["cache_1h_tokens"]
    c5m = totals["cache_5m_tokens"]
    cache_detail = f"  Cache write:       {_format_tokens(cw):>8s}"
    if c1h or c5m:
        cache_detail += f"  (1h: {_format_tokens(c1h)}, 5m: {_format_tokens(c5m)})"
    lines.append(row(cache_detail))
    lines.append(
        row(f"  Cache read:        {_format_tokens(totals['cache_read_tokens']):>8s}")
    )
    total_tokens = (
        totals["input_tokens"]
        + totals["output_tokens"]
        + totals["cache_write_tokens"]
        + totals["cache_read_tokens"]
    )
    lines.append(
        row(f"  Total processed:   {_format_tokens(total_tokens):>8s}")
    )

    # Activity
    lines.append(sep())
    lines.append(row(f"\U0001f527 Activity"))
    sr = totals["stop_reasons"]
    sr_str = ", ".join(f"{k}: {v}" for k, v in sr.most_common())
    lines.append(row(f"  Stop reasons:  {sr_str}"))
    lines.append(
        row(
            f"  Web: {totals['web_searches']} search,"
            f" {totals['web_fetches']} fetch"
            f"  \u2502  Tool: {totals['tool_calls']}"
        )
    )
    if totals["sidechain_turns"] > 0:
        lines.append(
            row(
                f"  Subagents: {totals['sidechain_turns']} turns"
                f" (in: {_format_tokens(totals['sidechain_input'])},"
                f" out: {_format_tokens(totals['sidechain_output'])})"
            )
        )

    # Context trend (sparkline-like)
    history = totals.get("context_history", [])
    if len(history) >= 3:
        lines.append(sep())
        lines.append(row(f"\U0001f4c8 Context Trend"))
        trend_parts = []
        for turn, ctx in history:
            trend_parts.append(f"T{turn}:{_format_tokens(ctx)}")
        # Show up to 6 data points
        if len(trend_parts) <= 6:
            shown = trend_parts
        else:
            shown = trend_parts[:3] + ["..."] + trend_parts[-3:]
        lines.append(row(f"  {' \u2192 '.join(shown)}"))

    lines.append(f"\u2514{'\u2500' * W}")
    return "\n".join(lines)


# ── Context breakdown helpers ────────────────────────────────────────────


def _get_cwd_from_session(session_file: Path) -> str | None:
    """Extract the cwd from the first entry in a session JSONL file."""
    try:
        with open(session_file, "r", encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                except json.JSONDecodeError:
                    continue
                cwd = entry.get("cwd")
                if cwd:
                    return cwd
    except OSError:
        pass
    return None


def _count_mcp_servers() -> tuple[int, int]:
    """Count user-level and project-level MCP servers.

    Returns (user_count, project_count) from ~/.claude.json.
    """
    config_file = Path.home() / ".claude.json"
    if not config_file.is_file():
        return 0, 0

    try:
        with open(config_file, "r", encoding="utf-8") as f:
            cfg = json.load(f)
    except (json.JSONDecodeError, OSError):
        return 0, 0

    user_count = len(cfg.get("mcpServers", {}))
    # Sum project-level MCP servers across all projects
    proj_count = 0
    for proj_data in cfg.get("projects", {}).values():
        if isinstance(proj_data, dict):
            proj_count += len(proj_data.get("mcpServers", {}))

    return user_count, proj_count


def _build_context_components(
    session_file: Path,
    last_turn_input: int,
) -> list[dict[str, Any]]:
    """Build the context composition breakdown."""
    components: list[dict[str, Any]] = []

    # 1. Global CLAUDE.md
    global_claude_md = CLAUDE_DIR / "CLAUDE.md"
    global_tokens = _estimate_tokens_from_file(global_claude_md)
    components.append({
        "name": "Global CLAUDE.md",
        "tokens": global_tokens,
    })

    # 2. Project CLAUDE.md
    project_cwd = _get_cwd_from_session(session_file)
    if project_cwd:
        project_claude_md = Path(project_cwd) / "CLAUDE.md"
        proj_tokens = _estimate_tokens_from_file(project_claude_md)
        components.append({
            "name": "Project CLAUDE.md",
            "tokens": proj_tokens,
        })

    # 3. Memory files
    workspace_dir = session_file.parent
    memory_dir = workspace_dir / "memory"
    memory_tokens = 0
    memory_count = 0
    if memory_dir.is_dir():
        for md_file in memory_dir.glob("*.md"):
            memory_tokens += _estimate_tokens_from_file(md_file)
            memory_count += 1
    components.append({
        "name": f"Memory files (\u00d7{memory_count})",
        "tokens": memory_tokens,
    })

    # 4. MCP tool definitions (estimated)
    user_mcps, proj_mcps = _count_mcp_servers()
    total_mcps = user_mcps + proj_mcps
    # ~150 tokens per tool, ~5-10 tools per server on average
    mcp_tokens = total_mcps * 500
    components.append({
        "name": f"MCP schemas (\u00d7{total_mcps} servers)",
        "tokens": mcp_tokens,
    })

    # 5. System prompt + built-in tools
    system_tokens = 3000
    components.append({
        "name": "System prompt & tools",
        "tokens": system_tokens,
    })

    # 6. Conversation = remainder
    static_total = sum(c["tokens"] for c in components)
    conversation_tokens = max(0, last_turn_input - static_total)
    components.append({
        "name": "Conversation history",
        "tokens": conversation_tokens,
    })

    # Calculate percentages relative to last_turn_input
    for c in components:
        if last_turn_input > 0:
            c["pct"] = round(c["tokens"] / last_turn_input * 100, 1)
        else:
            c["pct"] = 0.0

    return components


# ── Git helpers ─────────────────────────────────────────────────────────


def _run_git(cwd: str, *args: str) -> str:
    """Run a git command and return stripped stdout, or '' on failure."""
    try:
        r = subprocess.run(
            ["git", "-C", cwd, *args],
            capture_output=True, text=True, timeout=5,
        )
        return r.stdout.strip() if r.returncode == 0 else ""
    except (OSError, subprocess.TimeoutExpired):
        return ""


def _get_git_info(session_file: Path) -> dict[str, Any]:
    """Gather git status from the session's working directory.

    Returns dict with branch, staged, modified, untracked counts,
    and lines added/removed.
    """
    info: dict[str, Any] = {
        "branch": "",
        "staged": 0,
        "modified": 0,
        "untracked": 0,
        "lines_added": 0,
        "lines_removed": 0,
        "files_changed": 0,
    }
    cwd = _get_cwd_from_session(session_file)
    if not cwd:
        return info

    info["branch"] = _run_git(cwd, "branch", "--show-current") or "detached"

    # Staged files (cached)
    staged_out = _run_git(cwd, "diff", "--cached", "--numstat")
    if staged_out:
        info["staged"] = len(staged_out.splitlines())

    # Modified (unstaged, tracked)
    modified_out = _run_git(cwd, "diff", "--numstat")
    if modified_out:
        lines = modified_out.splitlines()
        info["modified"] = len(lines)
        for line in lines:
            parts = line.split("\t")
            if len(parts) >= 2:
                try:
                    info["lines_added"] += int(parts[0])
                    info["lines_removed"] += int(parts[1])
                except ValueError:
                    pass  # binary files show "-"

    # Also count staged lines
    staged_diff = staged_out  # reuse — avoid double subprocess call
    if staged_diff:
        for line in staged_diff.splitlines():
            parts = line.split("\t")
            if len(parts) >= 2:
                try:
                    info["lines_added"] += int(parts[0])
                    info["lines_removed"] += int(parts[1])
                except ValueError:
                    pass

    info["files_changed"] = info["staged"] + info["modified"]

    # Untracked files
    untracked_out = _run_git(cwd, "ls-files", "--others", "--exclude-standard")
    if untracked_out:
        info["untracked"] = len(untracked_out.splitlines())

    return info


def _git_summary(git: dict[str, Any]) -> str:
    """Build a short git change summary like '✎3 ✚2 ?1'."""
    parts: list[str] = []
    if git["staged"]:
        parts.append(f"\u270e{git['staged']}")     # ✎ staged
    if git["modified"]:
        parts.append(f"\u271a{git['modified']}")    # ✚ modified
    if git["untracked"]:
        parts.append(f"?{git['untracked']}")
    return " ".join(parts) if parts else "\u2713"   # ✓ clean


# ── Git style builders ──────────────────────────────────────────────────


def _build_git_status_line(git: dict[str, Any]) -> str:
    """Git-only: branch + working tree state.

    Format:
    🔀 master ┃ ✎ 3 staged ┃ ✚ 2 modified ┃ ? 1 untracked
    """
    parts = [f"\U0001f500 {git['branch']}"]
    if git["staged"]:
        parts.append(f"\u270e {git['staged']} staged")
    if git["modified"]:
        parts.append(f"\u271a {git['modified']} modified")
    if git["untracked"]:
        parts.append(f"? {git['untracked']} untracked")
    if not git["staged"] and not git["modified"] and not git["untracked"]:
        parts.append("\u2713 clean")
    return f" \u2503 ".join(parts)


def _build_git_diff_line(git: dict[str, Any]) -> str:
    """Git-only: branch + lines changed.

    Format:
    🔀 master ┃ +142 -38 ┃ 3 files changed
    """
    return (
        f"\U0001f500 {git['branch']}"
        f" \u2503 +{git['lines_added']} -{git['lines_removed']}"
        f" \u2503 {git['files_changed']} files changed"
    )


def _build_git_compact_line(git: dict[str, Any]) -> str:
    """Git-only: dense summary.

    Format:
    🔀 master ┃ S:3 M:2 U:1 ┃ +142/-38
    """
    return (
        f"\U0001f500 {git['branch']}"
        f" \u2503 S:{git['staged']} M:{git['modified']}"
        f" U:{git['untracked']}"
        f" \u2503 +{git['lines_added']}/-{git['lines_removed']}"
    )


def _build_ctx_git_line(
    totals: dict[str, Any],
    cost: float,
    ctx_pct: float,
    git: dict[str, Any],
) -> str:
    """Mixed: context health + git at a glance.

    Format:
    🟢▓▓░░░░░░░░ 21% 212K/1M ┃ $185 ┃ 🔀 master ┃ ✎3 ✚2 ?1
    """
    emoji = _ctx_emoji(ctx_pct)
    bar = _progress_bar(ctx_pct, 10)
    max_ctx = _get_max_context(totals["model"] or "unknown")
    return (
        f"{emoji}{bar} {ctx_pct:.0f}%"
        f" {_format_tokens(totals['last_turn_input'])}"
        f"/{_format_tokens(max_ctx)}"
        f" \u2503 ${cost:.0f}"
        f" \u2503 \U0001f500 {git['branch']}"
        f" \u2503 {_git_summary(git)}"
    )


def _build_simple_git_line(
    totals: dict[str, Any],
    cost: float,
    ctx_pct: float,
    git: dict[str, Any],
) -> str:
    """Mixed: full simple style + branch and changes.

    Format:
    🟢▓▓░░░░░░░░ 21% 212K/1M ┃ 🔼10K 🔽125K ┃ $185 ┃ Tool:231 ┃ 🔀 master ✎3 ✚2
    """
    emoji = _ctx_emoji(ctx_pct)
    bar = _progress_bar(ctx_pct, 10)
    max_ctx = _get_max_context(totals["model"] or "unknown")
    inp_str = _format_tokens(totals["input_tokens"])
    out_str = _format_tokens(totals["output_tokens"])
    tools = totals["stop_reasons"].get("tool_use", 0)
    return (
        f"{emoji}{bar} {ctx_pct:.0f}%"
        f" {_format_tokens(totals['last_turn_input'])}"
        f"/{_format_tokens(max_ctx)}"
        f" \u2503 \U0001f53c{inp_str} \U0001f53d{out_str}"
        f" \u2503 ${cost:.0f}"
        f" \u2503 Tool:{tools}"
        f" \u2503 \U0001f500 {git['branch']} {_git_summary(git)}"
    )


def _build_minimal_git_line(
    totals: dict[str, Any],
    cost: float,
    ctx_pct: float,
    git: dict[str, Any],
) -> str:
    """Mixed: essentials + git.

    Format:
    🟢 21% ┃ $185 ┃ T:508 ┃ 🔀 master +142/-38
    """
    emoji = _ctx_emoji(ctx_pct)
    return (
        f"{emoji} {ctx_pct:.0f}%"
        f" \u2503 ${cost:.0f}"
        f" \u2503 T:{totals['turns']}"
        f" \u2503 \U0001f500 {git['branch']}"
        f" +{git['lines_added']}/-{git['lines_removed']}"
    )


# ── Standalone helpers (used by stop hook via import) ────────────────────


def compute_formatted_metrics(
    workspace: str = "", style: str = ""
) -> str | None:
    """Compute the compact one-liner.

    Called by the stop hook to auto-append metrics.
    The ``style`` parameter overrides the global METRICS_STYLE when set.
    Returns the formatted string, or None on error.
    """
    use_style = style or METRICS_STYLE

    session_file = _find_session_file(workspace)
    if not session_file:
        return None

    totals = _parse_session(session_file)
    if totals["turns"] == 0:
        return None

    model = totals["model"] or "unknown"
    pricing = _get_pricing(model)
    max_ctx = _get_max_context(model)
    cost = _compute_cost(totals, pricing)
    ctx_pct = (totals["last_turn_input"] / max_ctx * 100) if max_ctx else 0
    duration_min = _compute_duration(totals["first_ts"], totals["last_ts"])

    if use_style == "ext-context":
        components = _build_context_components(
            session_file, totals["last_turn_input"]
        )
        return _build_ext_context_line(totals, cost, ctx_pct, components)

    if use_style == "ext-all":
        components = _build_context_components(
            session_file, totals["last_turn_input"]
        )
        return _build_ext_all_line(
            totals, cost, ctx_pct, duration_min, components
        )

    if use_style == "minimal":
        return _build_minimal_line(totals, cost, ctx_pct)

    if use_style == "cost-focus":
        return _build_cost_focus_line(totals, cost, ctx_pct)

    if use_style == "compact":
        return _build_compact_style_line(totals, cost, ctx_pct)

    # Git styles — gather git info lazily (only when needed)
    if use_style in (
        "git-status", "git-diff", "git-compact",
        "ctx-git", "simple-git", "minimal-git",
    ):
        git = _get_git_info(session_file)

        if use_style == "git-status":
            return _build_git_status_line(git)
        if use_style == "git-diff":
            return _build_git_diff_line(git)
        if use_style == "git-compact":
            return _build_git_compact_line(git)
        if use_style == "ctx-git":
            return _build_ctx_git_line(totals, cost, ctx_pct, git)
        if use_style == "simple-git":
            return _build_simple_git_line(totals, cost, ctx_pct, git)
        if use_style == "minimal-git":
            return _build_minimal_git_line(totals, cost, ctx_pct, git)

    return _build_compact_line(totals, cost, ctx_pct, duration_min)


def compute_detail_metrics(workspace: str = "") -> str | None:
    """Compute the full box-drawn detail view.

    Called by the /metrics skill for extended stats.
    Returns the detail string, or None on error.
    """
    session_file = _find_session_file(workspace)
    if not session_file:
        return None

    totals = _parse_session(session_file)
    if totals["turns"] == 0:
        return None

    model = totals["model"] or "unknown"
    pricing = _get_pricing(model)
    max_ctx = _get_max_context(model)
    cost = _compute_cost(totals, pricing)
    ctx_pct = (totals["last_turn_input"] / max_ctx * 100) if max_ctx else 0
    duration_min = _compute_duration(totals["first_ts"], totals["last_ts"])

    components = _build_context_components(
        session_file, totals["last_turn_input"]
    )

    return _build_detail_view(
        totals, cost, ctx_pct, duration_min, max_ctx, components
    )
