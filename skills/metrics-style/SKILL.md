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
```text
🟢▓▓░░░░░░░░ 18.1% 181K/1M ┃ 🔼10K 🔽92K ┃ $114.79 ┃ Tool:175 End:46 ┃ opus-4-6 v2.1.81 ┃ ▁▂▃▄▅ ↗ +1.2%
```

**ext-context** -- Context composition focus:
```text
🟢▓▓░░░░░░░░ 18.1% 181K/1M [ 3% CLAUDE.md | 2% MCP | 2% SYS | 93% CONVO ]
```

**ext-all** -- Context composition + full metrics:
```text
🟢▓▓░░░░░░░░ 18.1% 181K/1M [ 3% CLAUDE.md | 93% CONVO ] ┃ 🔼10K 🔽92K ┃ $114 ┃ Tool:175 ┃ ▁▂▃▄▅ ↗ +1.2%
```

**minimal** -- Just the essentials:
```text
🟢 18.1% ┃ $114.79 ┃ T:435
```

**cost-focus** -- Spending-oriented:
```text
🟢▓▓░░░░░░░░ 18.1% 181K/1M ┃ $114.79 ┃ 🔼10K 🔽92K ┃ Tool:175 End:46
```

**compact** -- Dense, no sparkline:
```text
🟢 18.1% 181K/1M ┃ 🔼10K 🔽92K ┃ $114 ┃ T:175 E:46 ┃ opus-4-6
```

2. Ask the user which style they prefer (use the `AskUserQuestion` tool
   with preview showing the example for each option).

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
user's choice (one of: simple, ext-context, ext-all, minimal, cost-focus,
compact).

4. Confirm the change to the user. Mention that the new style takes effect
   on the next response (no restart needed).
