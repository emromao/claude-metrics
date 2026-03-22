# claude-metrics

A lightweight [MCP server](https://modelcontextprotocol.io/) that gives Claude Code real-time visibility into its own session — token usage, costs, context window health, and activity breakdown.

It reads the JSONL session files that Claude Code already writes, computes metrics, and returns them as structured data or a compact one-liner that fits at the end of any response.

## Example output

**Compact one-liner** (appended to every response via the stop hook):

```text
🟢▓▓▓░░░░░░░ 9.1% 91.4K/1M │ 🔼1.6K 🔽74K │ $40.14 │ Tools:87 End:28 │ opus-4-6 v2.1.79 │ ▁▂▃▃▂ ↘ -1.8%
```

**Detailed view** (`get_session_detail`):

```text
┌────────────────────────────────────────────────────────┐
│  ◆ Claude Session Metrics                              │
├────────────────────────────────────────────────────────┤
│  🤖 Model:     claude-opus-4-6                         │
│  📦 Version:   2.1.79  │  🔗 vscode                   │
│  ⏱  Duration:  45 min  │  🔄 Turns: 32                │
│  💰 Cost:      $40.14                                  │
│  ...                                                   │
└────────────────────────────────────────────────────────┘
```

## What you get

| Tool                     | Description                                                                                |
| ------------------------ | ------------------------------------------------------------------------------------------ |
| `get_session_metrics`    | Compact one-liner with progress bar, token counts, cost, sparkline trend                   |
| `get_session_detail`     | Full box-drawn view with token breakdown, cache stats, activity counters                   |
| `get_context_breakdown`  | Estimates what's filling the context window (CLAUDE.md, memory, MCP schemas, conversation) |

## Quick install

```bash
git clone https://github.com/YOUR_USER/claude-metrics.git
cd claude-metrics
bash install.sh
```

This will:

1. Install the Python dependency (`mcp`)
2. Copy `server.py` to `~/.claude/mcp-servers/claude-metrics/`
3. Copy the stop hook to `~/.claude/hooks/`
4. Register the MCP server via `claude mcp add`

### Installation modes

| Command                     | Hook mode        | Speed  | Behavior                                            |
| --------------------------- | ---------------- | ------ | --------------------------------------------------- |
| `bash install.sh`           | Direct (default) | ~200ms | Hook computes metrics inline, no MCP call visible   |
| `bash install.sh --mcp`     | MCP-based        | ~3-4s  | Hook tells Claude to call MCP tool (extra LLM turn) |
| `bash install.sh --no-hook` | No hook          | —      | MCP server only, call tools manually                |

**Direct mode** (default) is faster and cleaner — the hook computes the one-liner
itself and hands it to Claude to paste. No extra LLM turn, no tool call in the UI.

**MCP mode** is the original approach — the hook blocks Claude, Claude calls the
MCP tool, gets the result, and appends it. Slower but you see the tool call happen.

Both modes install the MCP server, so `get_session_detail` and
`get_context_breakdown` are always available for interactive use.

### Post-install: enable the stop hook

Add this to your `~/.claude/settings.json` (the installer will tell you the
exact hook filename):

```json
{
  "hooks": {
    "Stop": [{
      "hooks": [{
        "type": "command",
        "command": "bash ~/.claude/hooks/metrics-stop-direct.sh"
      }]
    }]
  }
}
```

Then restart Claude Code.

## Manual install

If you prefer not to use the script:

```bash
# 1. Install dependency
pip install "mcp>=1.0.0"

# 2. Register the MCP server (adjust python path as needed)
claude mcp add claude-metrics -s user -- python /path/to/server.py
```

## Requirements

- **Python 3.8+** (`python3`, `python`, or `py` — the installer detects automatically)
- **Claude Code** (CLI or VS Code extension)
- **mcp** Python package (`pip install mcp`)

## How it works

Claude Code writes a JSONL session file for each conversation at `~/.claude/projects/<workspace>/`. This MCP server:

1. Finds the most recently modified session file
2. Parses every line to accumulate token counts, cache stats, and activity data
3. Computes cost using per-model pricing (Opus, Sonnet, Haiku)
4. Estimates context window composition (CLAUDE.md files, memory, MCP schemas, conversation)
5. Returns structured JSON and/or a formatted one-liner

The stop hook (optional) intercepts Claude's stop signal and checks if the
metrics one-liner is already present in the response. If not, it either computes
the metrics directly (direct mode) or tells Claude to call the MCP tool (MCP mode).

## Uninstall

```bash
bash install.sh --uninstall
```

Then remove the hook entry from `~/.claude/settings.json` and the `claude-metrics` entry from your MCP config.

## Project structure

```text
claude-metrics/
├── src/
│   └── server.py                # MCP server (all logic here)
├── hooks/
│   ├── metrics-stop-direct.sh   # Stop hook — direct mode (default)
│   └── metrics-stop-check.sh    # Stop hook — MCP mode (--mcp)
├── scripts/
│   ├── hook_check_deps.sh       # PostToolUse hook for dependency checks
│   └── hook_simplify.sh         # PostToolUse hook for code hints
├── install.sh                   # One-liner installer
├── requirements.txt             # Python dependencies (mcp>=1.0.0)
└── .gitea/workflows/
    └── security-scan.yml        # CI: Trivy SCA, Gitleaks, SBOM
```

## License

MIT
