# claude-metrics — Installation Guide for Claude

When a user asks to install this project (e.g., "Install https://github.com/emromao/claude-metrics"),
follow these steps exactly. **Never overwrite existing user configuration — only append.**

## Step 1: Run the installer

```bash
bash install.sh
```

This copies three files into `~/.claude/` (nothing else is touched):
- `~/.claude/lib/claude-metrics/server.py`
- `~/.claude/hooks/metrics-stop-direct.sh`
- `~/.claude/skills/metrics/SKILL.md`

## Step 2: Add the Stop hook to settings.json

Read `~/.claude/settings.json`. If a `"hooks"` key exists, **merge** the Stop hook
entry into the existing hooks. If `"hooks"` does not exist, create it.

**SAFETY RULES:**
- NEVER overwrite the file — read it first, parse the JSON, merge, then write back.
- If a Stop hook array already exists, APPEND this entry to it. Do NOT replace existing entries.
- If `metrics-stop-direct.sh` is already configured, skip this step.
- Always confirm with the user before writing to settings.json.

Add this entry to the `"Stop"` array inside `"hooks"`:

```json
{
  "hooks": [{
    "type": "command",
    "command": "bash ~/.claude/hooks/metrics-stop-direct.sh",
    "timeout": 10
  }]
}
```

## Step 3: Add the CLAUDE.md instruction

Read the user's global `~/.claude/CLAUDE.md`. If it exists, **append** the section
below to the end of the file. If it does not exist, create it with this content.

**SAFETY RULES:**
- NEVER overwrite existing content — only append.
- If a "Session Metrics" section already exists, skip this step.
- Always confirm with the user before writing to CLAUDE.md.

Append this block:

```markdown
---

## Session Metrics

The metrics one-liner is appended automatically by the stop hook
(`metrics-stop-direct.sh`). Do NOT manually append metrics or call
any metrics tool — the hook handles it.

**CRITICAL: The metrics line must appear exactly ONCE per user interaction.**
When multiple stop hooks fire (metrics + cognee), paste the metrics line
ONLY in your first response. When responding to subsequent hook blocks
(e.g. cognee's "store insights" prompt), do NOT paste the metrics line
again — it is already in the conversation from your first response.

When the user asks about context composition or detailed metrics,
use the `/metrics` skill.
```

## Step 4: Confirm and restart

Tell the user:
1. What files were copied
2. What was added to settings.json (show the diff)
3. What was added to CLAUDE.md (show the section)
4. Ask them to restart Claude Code to activate
