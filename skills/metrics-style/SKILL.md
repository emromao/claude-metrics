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

1. Show the user the available styles with examples:

**simple** (default) -- Full metrics with token counts, cost, activity, sparkline:
```
🟢▓▓░░░░░░░░ 18.1% 181.1K/1.0M │ 🔼10.0K 🔽92.3K │ $114.79 │ Tools:175 End:46 │ opus-4-6 v2.1.81 │ ▁▂▃▄▅ ↗ +1.2%
```

**ext-context** -- Context composition focus, shows what fills the window:
```
🟢▓▓░░░░░░░░ 18.1% 181.1K/1.0M [ 3% CLAUDE.md | 2% MCP | 2% SYS | 93% CONVO ]
```

2. Ask the user which style they prefer (use the `AskUserQuestion` tool).

3. After the user selects a style, update the configuration by running:

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

Replace `SELECTED_STYLE` in **both** places in the command above with the
user's choice (`simple` or `ext-context`).

4. Confirm the change to the user. Mention that the new style takes effect
   on the next response (no restart needed).
