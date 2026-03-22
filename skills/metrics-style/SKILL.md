---
name: metrics-style
description: >-
  This skill should be used when the user wants to change the metrics
  one-liner style/format. Trigger phrases: "change metrics style",
  "switch metrics format", "/metrics-style"
metadata:
  trigger: Change the metrics one-liner display style
---

# Metrics Style Selector

Change the compact one-liner format appended after each response.

## Workflow

1. Show the user the available styles with examples, organized by category.
   Use `AskUserQuestion` with preview showing each style's example.

### Session styles
- **simple** (default): `🟢▓▓░░░░░░░░ 18% 181K/1M ┃ 🔼10K 🔽92K ┃ $114 ┃ Tool:175 End:46 ┃ opus-4-6 v2.1.81 ┃ ▁▂▃▄▅ ↗ +1.2%`
- **ext-context**: `🟢▓▓░░░░░░░░ 18% 181K/1M [ 3% CLAUDE.md | 2% MCP | 2% SYS | 93% CONVO ]`
- **ext-all**: `🟢▓▓░░░░░░░░ 18% 181K/1M [ 3% CLAUDE.md | 93% CONVO ] ┃ 🔼10K 🔽92K ┃ $114 ┃ Tool:175 ┃ ▁▂▃▄▅ ↗ +1.2%`
- **minimal**: `🟢 18% ┃ $114 ┃ T:435`
- **cost-focus**: `🟢▓▓░░░░░░░░ 18% 181K/1M ┃ $114 ┃ 🔼10K 🔽92K ┃ Tool:175 End:46`
- **compact**: `🟢 18% 181K/1M ┃ 🔼10K 🔽92K ┃ $114 ┃ T:175 E:46 ┃ opus-4-6`

### Git styles (git-only)
- **git-status**: `🔀 master ┃ ✎ 3 staged ┃ ✚ 2 modified ┃ ? 1 untracked`
- **git-diff**: `🔀 master ┃ +142 -38 ┃ 3 files changed`
- **git-compact**: `🔀 master ┃ S:3 M:2 U:1 ┃ +142/-38`

### Mixed styles (context + git)
- **ctx-git**: `🟢▓▓░░░░░░░░ 21% 212K/1M ┃ $185 ┃ 🔀 master ┃ ✎3 ✚2 ?1`
- **simple-git**: `🟢▓▓░░░░░░░░ 21% 212K/1M ┃ 🔼10K 🔽125K ┃ $185 ┃ Tool:231 ┃ 🔀 master ✎3 ✚2`
- **minimal-git**: `🟢 21% ┃ $185 ┃ T:508 ┃ 🔀 master +142/-38`

2. After the user selects a style, update the configuration by running:

```bash
python -c "
import re, os
path = os.path.expanduser('~/.claude/lib/claude-metrics/server.py')
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()
content = re.sub(
    r'^METRICS_STYLE\s*=\s*\"[^\"]*\"',
    'METRICS_STYLE = \"SELECTED_STYLE\"',
    content,
    count=1,
    flags=re.MULTILINE,
)
with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
print('Updated METRICS_STYLE to: SELECTED_STYLE')
"
```

Replace `SELECTED_STYLE` in **both** places with the user's choice.

3. Confirm the change. New style takes effect on the next response
   (no restart needed).
