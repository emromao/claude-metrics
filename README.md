# claude-metrics

A lightweight tool that gives Claude Code real-time visibility into its own session — token usage, costs, context window health, and activity breakdown.

It reads the JSONL session files that Claude Code already writes, computes metrics, and returns them as a compact one-liner appended to every response.

## Example output

**Compact one-liner** (appended automatically via the stop hook):

```text
🟢▓▓▓░░░░░░░ 9.1% 91.4K/1M │ 🔼1.6K 🔽74K │ $40.14 │ Tools:87 End:28 │ opus-4-6 v2.1.79 │ ▁▂▃▃▂ ↘ -1.8%
```

**Detailed view** (via MCP tool `get_session_detail`, requires `--full` install):

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

## Quick install

```bash
git clone https://github.com/YOUR_USER/claude-metrics.git
cd claude-metrics
bash install.sh
```

The default install is **hook-only** — lightweight, no MCP server, no extra
dependencies. The hook computes metrics directly (~200ms per response).

### Installation modes

| Command                     | What it installs              | Speed  | Dependencies        |
| --------------------------- | ----------------------------- | ------ | ------------------- |
| `bash install.sh`           | Hook only (default)           | ~200ms | Python 3.8+ only    |
| `bash install.sh --full`    | Hook + MCP server             | ~200ms | Python 3.8+ + `mcp` |
| `bash install.sh --mcp`     | MCP-based hook + MCP server   | ~3-4s  | Python 3.8+ + `mcp` |
| `bash install.sh --no-hook` | MCP server only (no hook)     | —      | Python 3.8+ + `mcp` |

**Hook-only** (default) is the recommended mode — it computes the one-liner
directly in the stop hook with zero extra dependencies beyond Python. No MCP
server process, no extra LLM turn, no tool call visible in the UI.

**Full mode** (`--full`) adds the MCP server for interactive tools:
`get_session_detail` (box-drawn breakdown) and `get_context_breakdown`
(what's filling your context window). Requires the `mcp` Python package.

**MCP mode** (`--mcp`) is the original approach where the hook tells Claude
to call the MCP tool. Slower (~3-4s, extra LLM turn) but you see the tool
call happen in the UI.

### Post-install: enable the stop hook

Add this to your `~/.claude/settings.json` (the installer prints the exact
config to copy):

```json
{
  "hooks": {
    "Stop": [{
      "hooks": [{
        "type": "command",
        "command": "bash ~/.claude/hooks/metrics-stop-direct.sh",
        "timeout": 10
      }]
    }]
  }
}
```

Then restart Claude Code.

### Interactive tools (--full or --mcp)

When installed with `--full` or `--mcp`, three MCP tools are available:

| Tool                     | Description                                                                                |
| ------------------------ | ------------------------------------------------------------------------------------------ |
| `get_session_metrics`    | Compact one-liner with progress bar, token counts, cost, sparkline trend                   |
| `get_session_detail`     | Full box-drawn view with token breakdown, cache stats, activity counters                   |
| `get_context_breakdown`  | Estimates what's filling the context window (CLAUDE.md, memory, MCP schemas, conversation) |

## Manual install

If you prefer not to use the script:

```bash
# 1. Copy server.py where the hook expects it
mkdir -p ~/.claude/mcp-servers/claude-metrics
cp src/server.py ~/.claude/mcp-servers/claude-metrics/

# 2. Copy the stop hook
mkdir -p ~/.claude/hooks
cp hooks/metrics-stop-direct.sh ~/.claude/hooks/

# 3. Add the hook to ~/.claude/settings.json (see Post-install above)

# 4. (Optional) Register MCP server for interactive tools
pip install "mcp>=1.0.0"
claude mcp add claude-metrics -s user -- python ~/.claude/mcp-servers/claude-metrics/server.py
```

## Requirements

- **Python 3.8+** (`python3`, `python`, or `py` — auto-detected)
- **Claude Code** (CLI or VS Code extension)
- **mcp** Python package — only needed for `--full`, `--mcp`, or `--no-hook` modes

## How it works

Claude Code writes a JSONL session file for each conversation at
`~/.claude/projects/<workspace>/`. The metrics engine (server.py):

1. Finds the most recently modified session file
2. Parses every line to accumulate token counts, cache stats, and activity data
3. Computes cost using per-model pricing (Opus, Sonnet, Haiku)
4. Estimates context window composition (CLAUDE.md, memory, MCP schemas, conversation)
5. Returns a formatted one-liner

The stop hook intercepts Claude's stop signal and checks if the metrics
one-liner is already present. If not, it computes the metrics directly
(hook-only/full mode) or tells Claude to call the MCP tool (MCP mode).

## Security

- The hook only reads Claude's own session JSONL files (under `~/.claude/`)
- No network access, no external APIs, no data leaves your machine
- server.py is loaded via `importlib` with an explicit file path (no sys.path manipulation)
- Hook input is size-limited (2MB max) to prevent memory exhaustion
- All errors default to "allow" (Claude stops normally) — never blocks indefinitely
- The `stop_hook_active` flag prevents infinite loops

## Uninstall

```bash
bash install.sh --uninstall
```

Then remove the hook entry from `~/.claude/settings.json`.

## Project structure

```text
claude-metrics/
├── src/
│   └── server.py                # Metrics engine (shared by hook and MCP)
├── hooks/
│   ├── metrics-stop-direct.sh   # Stop hook — direct mode (default)
│   └── metrics-stop-check.sh    # Stop hook — MCP mode (--mcp)
├── install.sh                   # Installer with mode selection
├── requirements.txt             # Python dependencies (mcp>=1.0.0)
└── .gitea/workflows/
    └── security-scan.yml        # CI: Trivy SCA, Gitleaks, SBOM
```

## License

MIT
