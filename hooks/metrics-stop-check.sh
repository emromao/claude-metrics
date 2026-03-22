#!/usr/bin/env bash
# Metrics Stop hook — reminds Claude to append session metrics one-liner.
# Version: 11
# Last Changed: 2026-03-22 UTC

set -Eeuo pipefail
IFS=$'\n\t'

# Detect available Python binary (cross-platform: Windows, macOS, Linux)
function _find_python() {
  # Try common Python binary names in preference order.
  # Inputs: none / Outputs: stdout (binary name) or exit 1
  local bin
  for bin in python3 python py; do
    if command -v "${bin}" &>/dev/null; then
      echo "${bin}"
      return 0
    fi
  done
  return 1
}

PYTHON=""
PYTHON=$(_find_python) || true
if [[ -z "${PYTHON}" ]]; then
  echo "No Python found — skipping metrics hook" >&2
  exit 0
fi

INPUT=$(cat)

# Single Python call: parse JSON, check stop_hook_active, check for metrics
# pattern in last_assistant_message. Exits 0 if metrics already present or
# hook is re-firing; prints "block" if metrics are missing.
DECISION=$(echo "${INPUT}" | "${PYTHON}" -c "
import sys, json

try:
    data = json.load(sys.stdin)
except Exception:
    print('allow')
    sys.exit(0)

if data.get('stop_hook_active', False):
    print('allow')
    sys.exit(0)

msg = data.get('last_assistant_message', '')

# Progress bar chars: \u2593 (dark shade) \u2591 (light shade) \u2502 (pipe)
if ('\u2593' in msg or '\u2591' in msg) and '%' in msg and '\u2502' in msg:
    print('allow')
    sys.exit(0)

# ASCII fallback pattern
if 'ctx:' in msg and '%' in msg and 'Tools:' in msg:
    print('allow')
    sys.exit(0)

print('block')
" 2>/dev/null || echo "allow")

if [[ "${DECISION}" == "allow" ]]; then
  exit 0
fi

# Metrics not found — block and remind
cat <<'HOOK_JSON'
{
  "decision": "block",
  "reason": "[METRICS] Append the session metrics one-liner. Call mcp__claude-metrics__get_session_metrics and paste the 'formatted' field at the end of your response. Skip only for quick clarifications or multi-step tool chains."
}
HOOK_JSON
