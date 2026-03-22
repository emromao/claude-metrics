# claude-metrics

A lightweight stop hook that gives Claude Code real-time visibility into its own session — token usage, costs, context window health, and activity breakdown.

No extra dependencies — just a bash hook and Python 3.8+.

## Example output

**Compact one-liner** (appended automatically to every response):

```text
🟢▓▓▓░░░░░░░ 9.1% 91.4K/1M │ 🔼1.6K 🔽74K │ $40.14 │ Tools:87 End:28 │ opus-4-6 v2.1.79 │ ▁▂▃▃▂ ↘ -1.8%
```

**Detailed view** (via `/metrics` skill):

```text
┌─────────────────────────────────────────────────────────┐
│ ◆ Claude Session Metrics                                │
├─────────────────────────────────────────────────────────┤
│ 🤖 Model:     claude-opus-4-6                           │
│ 📦 Version:   2.1.81  │  🔗 claude-vscode               │
│ ⏱  Duration:  45 min  │  🔄 Turns: 32                   │
│ 💰 Cost:      $40.14                                    │
├─────────────────────────────────────────────────────────┤
│ 📊 Context Composition (estimated)                      │
│   Global CLAUDE.md               4.5K    2.6%           │
│   MCP schemas (×9 servers)       4.5K    2.6%           │
│   System prompt & tools          3.0K    1.7%           │
│   Conversation history         161.5K   93.1%           │
└─────────────────────────────────────────────────────────┘
```

## Install

```bash
git clone https://github.com/YOUR_USER/claude-metrics.git
cd claude-metrics
bash install.sh
```

This copies three files:

1. `server.py` to `~/.claude/lib/claude-metrics/` (metrics engine)
2. `metrics-stop-direct.sh` to `~/.claude/hooks/` (stop hook)
3. `SKILL.md` to `~/.claude/skills/metrics/` (`/metrics` command)

### Enable the stop hook

Add this to your `~/.claude/settings.json`:

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

## Usage

The stop hook automatically appends a metrics one-liner to every response.
For detailed stats, type `/metrics` in the conversation.

## Requirements

- **Python 3.8+** (`python3`, `python`, or `py` — auto-detected)
- **Claude Code** (CLI or VS Code extension)
- No pip packages needed

## How it works

Claude Code writes a JSONL session file for each conversation at
`~/.claude/projects/<workspace>/`. The metrics engine:

1. Finds the most recently modified session file
2. Parses every line to accumulate token counts, cache stats, and activity
3. Computes cost using per-model pricing (Opus, Sonnet, Haiku)
4. Estimates context window composition (CLAUDE.md, memory, MCP schemas)
5. Returns a formatted one-liner or full detail view

The stop hook intercepts Claude's stop signal, checks if the metrics
one-liner is already present, and if not computes it directly (~200ms).

## Security

- Only reads Claude's own session files (under `~/.claude/`)
- No network access, no external APIs, no data leaves your machine
- server.py loaded via `importlib` with explicit file path
- Hook input size-limited (2MB max)
- All errors default to "allow" — never blocks indefinitely
- `stop_hook_active` flag prevents infinite loops

## Uninstall

```bash
bash install.sh --uninstall
```

Then remove the hook entry from `~/.claude/settings.json`.

## Project structure

```text
claude-metrics/
├── src/
│   └── server.py                # Metrics engine (stdlib only)
├── hooks/
│   └── metrics-stop-direct.sh   # Stop hook (~200ms)
├── skills/
│   └── metrics/
│       └── SKILL.md             # /metrics skill for detailed view
├── install.sh                   # One-liner installer
└── .gitea/workflows/
    └── security-scan.yml        # CI: Trivy SCA, Gitleaks, SBOM
```

## License

MIT
