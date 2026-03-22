#!/usr/bin/env bash
# Metrics Stop hook (direct mode) — computes and injects metrics inline.
# Version: 1
# Last Changed: 2026-03-22 UTC
#
# Unlike metrics-stop-check.sh which tells Claude to call the MCP server,
# this hook computes the one-liner directly and injects it in the block
# reason. Result: ~200ms vs ~3-4s, no visible MCP tool call in the UI.

set -Eeuo pipefail
IFS=$'\n\t'

SERVER_PY="${HOME}/.claude/mcp-servers/claude-metrics/server.py"

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

if [[ ! -f "${SERVER_PY}" ]]; then
  echo "server.py not found at ${SERVER_PY} — skipping" >&2
  exit 0
fi

INPUT=$(cat)

# Single Python call: check if metrics already present, if not compute
# them directly from server.py and return a block with the formatted line.
# Ensure UTF-8 output on Windows (emoji in metrics line)
export PYTHONIOENCODING=utf-8

RESULT=$(echo "${INPUT}" | "${PYTHON}" -c "
import sys, json, os

try:
    data = json.load(sys.stdin)
except Exception:
    print('ALLOW')
    sys.exit(0)

# Prevent infinite loop
if data.get('stop_hook_active', False):
    print('ALLOW')
    sys.exit(0)

msg = data.get('last_assistant_message', '')

# Check if metrics one-liner is already present
# Progress bar chars: \u2593 (dark shade) \u2591 (light shade) \u2502 (pipe)
if ('\u2593' in msg or '\u2591' in msg) and '%' in msg and '\u2502' in msg:
    print('ALLOW')
    sys.exit(0)

# ASCII fallback pattern
if 'ctx:' in msg and '%' in msg and 'Tools:' in msg:
    print('ALLOW')
    sys.exit(0)

# Metrics not found — compute them directly
server_path = os.path.expanduser('~/.claude/mcp-servers/claude-metrics')
sys.path.insert(0, server_path)

try:
    from server import compute_formatted_metrics
    formatted = compute_formatted_metrics()
    if formatted:
        print('METRICS:' + formatted)
    else:
        print('BLOCK_FALLBACK')
except Exception:
    # If computation fails, fall back to asking Claude to call MCP
    print('BLOCK_FALLBACK')
" 2>/dev/null || echo "ALLOW")

# Parse the result
if [[ "${RESULT}" == "ALLOW" ]]; then
  exit 0
fi

if [[ "${RESULT}" == METRICS:* ]]; then
  # Extract the formatted metrics line
  METRICS_LINE="${RESULT#METRICS:}"
  # Inject the pre-computed metrics — Claude just pastes it
  cat <<HOOK_JSON
{
  "decision": "block",
  "reason": "[METRICS] Append this exact line at the very end of your response (do not call any MCP tool, just paste it):\n\n\`${METRICS_LINE}\`"
}
HOOK_JSON
  exit 0
fi

# Fallback: tell Claude to call the MCP tool (version 2 behavior)
cat <<'HOOK_JSON'
{
  "decision": "block",
  "reason": "[METRICS] Append the session metrics one-liner. Call mcp__claude-metrics__get_session_metrics and paste the 'formatted' field at the end of your response. Skip only for quick clarifications or multi-step tool chains."
}
HOOK_JSON
