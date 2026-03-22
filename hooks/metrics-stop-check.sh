#!/usr/bin/env bash
# Metrics Stop hook — reminds Claude to append session metrics one-liner.
# Version: 10
# Last Changed: 2026-03-21 UTC

set -Eeuo pipefail
IFS=$'\n\t'

INPUT=$(cat)

# Prevent infinite loop — if already triggered, let Claude stop
STOP_ACTIVE=$(echo "${INPUT}" | python3 -c "
import sys, json
print(json.load(sys.stdin).get('stop_hook_active', False))
" 2>/dev/null || echo "False")

if [[ "${STOP_ACTIVE}" == "True" ]]; then
  exit 0
fi

# Extract last assistant message directly from the hook input
LAST_MSG=$(echo "${INPUT}" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data.get('last_assistant_message', ''))
" 2>/dev/null || echo "")

# Check if the metrics one-liner is already present
# Look for the progress bar + pipe separator pattern
if echo "${LAST_MSG}" | grep -qP '[\x{2593}\x{2591}].*%.*\x{2502}'; then
  exit 0
fi

# Also check for the simpler ascii fallback pattern
if echo "${LAST_MSG}" | grep -qE 'ctx:.*%.*Tools:'; then
  exit 0
fi

# Metrics not found — block and remind
cat <<'HOOK_JSON'
{
  "decision": "block",
  "reason": "[METRICS] Append the session metrics one-liner. Call mcp__claude-metrics__get_session_metrics and paste the 'formatted' field at the end of your response. Skip only for quick clarifications or multi-step tool chains."
}
HOOK_JSON
