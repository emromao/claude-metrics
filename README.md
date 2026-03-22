# claude-metrics

Session metrics for Claude Code. See your token usage, costs, and context health after every response.

![Architecture](https://draw.emromao.com/api/drawing/19c6f8d3-8557-4b8f-b66e-1f166cceb31c/svg)

## What it looks like

After every response, a one-liner is appended automatically:

```text
🟢▓▓▓░░░░░░░ 9.1% 91.4K/1M ┃ 🔼1.6K 🔽74K ┃ $40.14 ┃ Tool:87 End:28 ┃ opus-4-6 v2.1.79 ┃ ▁▂▃▃▂ ↘ -1.8%
```

Type `/metrics` for the full breakdown:

```text
┌───────────────────────────────────────────────────────
│ ◆ Claude Session Metrics
├───────────────────────────────────────────────────────
│ 🤖 Model:     claude-opus-4-6
│ 📦 Version:   2.1.81  │  🔗 claude-vscode
│ ⏱  Duration:  45 min  │  🔄 Turns: 32
│ 💰 Cost:      $40.14
├───────────────────────────────────────────────────────
│ 📊 Context Composition (estimated)
│   Global CLAUDE.md               4.5K    2.6%
│   MCP schemas (×9 servers)       4.5K    2.6%
│   System prompt & tools          3.0K    1.7%
│   Conversation history         161.5K   93.1%
└───────────────────────────────────────────────────────
```

## Install

```bash
git clone https://github.com/emromao/claude-metrics.git
cd claude-metrics
bash install.sh
```

This copies three files into `~/.claude/` (nothing else is touched):

| File                     | Location                        | Purpose            |
| ------------------------ | ------------------------------- | ------------------ |
| `server.py`              | `~/.claude/lib/claude-metrics/` | Metrics engine     |
| `metrics-stop-direct.sh` | `~/.claude/hooks/`              | Stop hook          |
| `SKILL.md`               | `~/.claude/skills/metrics/`     | `/metrics` command |

### Activate

Add the stop hook to your `~/.claude/settings.json` under `hooks`:

```json
"Stop": [{
  "hooks": [{
    "type": "command",
    "command": "bash ~/.claude/hooks/metrics-stop-direct.sh",
    "timeout": 10
  }]
}]
```

Then add this to your CLAUDE.md (global `~/.claude/CLAUDE.md` or per-project):

```markdown
## Session Metrics

The metrics one-liner is appended automatically by the stop hook.
Do NOT manually append metrics — the hook handles it.

**CRITICAL: The metrics line must appear exactly ONCE per user interaction.**
When responding to subsequent hook blocks, do NOT paste the metrics line again.
```

Restart Claude Code.

### Or just ask Claude

Paste this in your Claude Code prompt:

> Install <https://github.com/emromao/claude-metrics>

Claude will clone the repo, run `install.sh`, and configure the hook for you.

## One-liner styles

Switch styles anytime with `/metrics-style`:

| Style                | Example                                                                       |
| -------------------- | ----------------------------------------------------------------------------- |
| **simple** (default) | `🟢▓▓░░░ 18% 181K/1M ┃ 🔼10K 🔽92K ┃ $114 ┃ Tool:175 End:46 ┃ opus-4-6`    |
| **ext-context**      | `🟢▓▓░░░ 18% 181K/1M [ 3% CLAUDE.md \| 2% MCP \| 93% CONVO ]`               |
| **ext-all**          | `🟢▓▓░░░ 18% [ 3% CLAUDE.md \| 93% CONVO ] ┃ 🔼10K ┃ $114 ┃ Tool:175`      |
| **minimal**          | `🟢 18% ┃ $114 ┃ T:435`                                                      |
| **cost-focus**       | `🟢▓▓░░░ 18% 181K/1M ┃ $114 ┃ 🔼10K 🔽92K ┃ Tool:175`                       |
| **compact**          | `🟢 18% 181K/1M ┃ 🔼10K 🔽92K ┃ $114 ┃ T:175 E:46 ┃ opus-4-6`              |

## How it works

Claude Code writes a JSONL session file for each conversation. The stop hook:

1. Fires when Claude finishes responding
2. Calls `server.py` which parses the JSONL for token counts, costs, and activity
3. Returns a block response with the formatted one-liner
4. Claude pastes it at the end of the response

No MCP server, no background processes, no pip packages. Just a bash script that calls Python.

## Requirements

- Python 3.8+ (auto-detected: `python3`, `python`, or `py`)
- Claude Code (CLI or VS Code)

## Uninstall

```bash
bash install.sh --uninstall
```

Then remove the Stop hook entry from `settings.json` and the Session Metrics section from CLAUDE.md.

## Architecture

[View the full architecture diagram](https://draw.emromao.com/editor/19c6f8d3-8557-4b8f-b66e-1f166cceb31c)

The stop hook computes metrics inline (~200ms) by importing `server.py` directly — no MCP server or extra LLM turn needed. A 15-second marker file prevents duplicates when other stop hooks (like cognee) cause re-fire cycles.

## License

MIT
