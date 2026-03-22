---
name: metrics
description: >-
  This skill should be used when the user asks to see session metrics,
  cost breakdown, context composition, or token usage details.
  Trigger phrases: "show metrics", "session stats", "how much context",
  "what's my cost", "token breakdown", "/metrics"
metadata:
  trigger: Show detailed session metrics, cost, context breakdown
---

# Metrics

Show detailed Claude Code session metrics by running the metrics engine
directly via Python.

## Workflow

1. Run the following command to get the detailed metrics view:

```bash
PYTHONIOENCODING=utf-8 python -c "
import importlib.util, os
spec = importlib.util.spec_from_file_location('server',
    os.path.expanduser('~/.claude/mcp-servers/claude-metrics/server.py'))
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
detail = mod.compute_detail_metrics()
if detail:
    print(detail)
else:
    print('No session data found')
"
```

2. Present the output directly — it is pre-formatted with box-drawing
   characters. Do not reformat or parse it.

3. If the user asks about context specifically, mention which components
   are estimates (MCP schemas, system prompt) vs measured (file sizes).

4. If context usage exceeds 70%, suggest starting a new conversation.
   If it exceeds 90%, strongly recommend it.
