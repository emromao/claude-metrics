#!/usr/bin/env bash
# Metrics Stop hook (direct mode) — computes and injects metrics inline.
# Version: 2
# Last Changed: 2026-03-22 UTC
#
# Computes the metrics one-liner directly via server.py import (~200ms).
# No MCP server or extra LLM turn required.

set -Eeuo pipefail
IFS=$'\n\t'

SERVER_PY="${HOME}/.claude/mcp-servers/claude-metrics/server.py"

# Detect available Python binary (cross-platform: Windows, macOS, Linux).
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
  # No Python — can't run, allow Claude to stop
  exit 0
fi

if [[ ! -f "${SERVER_PY}" ]]; then
  # server.py missing — can't compute, allow Claude to stop
  exit 0
fi

# Read stdin (hook input JSON) with a size guard (max 2MB)
INPUT=$(head -c 2097152)

# Ensure UTF-8 output on Windows (emoji in metrics line)
export PYTHONIOENCODING=utf-8

# Single Python call: check if metrics present, compute if missing.
# Uses importlib for explicit file loading (no sys.path manipulation).
RESULT=$(echo "${INPUT}" | "${PYTHON}" -c "
import sys, json, os, importlib.util

# Parse hook input
try:
    data = json.load(sys.stdin)
except Exception:
    print('ALLOW')
    sys.exit(0)

# Prevent infinite loop — if already re-firing after a block, allow stop
if data.get('stop_hook_active', False):
    print('ALLOW')
    sys.exit(0)

msg = data.get('last_assistant_message', '')

# Check if metrics one-liner is already present in the response.
# Progress bar chars: U+2593 (dark shade), U+2591 (light shade), U+2502 (pipe)
if ('\u2593' in msg or '\u2591' in msg) and '%' in msg and '\u2502' in msg:
    print('ALLOW')
    sys.exit(0)

# ASCII fallback pattern
if 'ctx:' in msg and '%' in msg and 'Tools:' in msg:
    print('ALLOW')
    sys.exit(0)

# Metrics not found — compute directly via importlib (explicit file load)
server_file = os.path.expanduser(
    '~/.claude/mcp-servers/claude-metrics/server.py'
)
if not os.path.isfile(server_file):
    print('BLOCK_FALLBACK')
    sys.exit(0)

try:
    spec = importlib.util.spec_from_file_location('server', server_file)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    formatted = mod.compute_formatted_metrics()
    if formatted:
        print('METRICS:' + formatted)
    else:
        print('BLOCK_FALLBACK')
except Exception:
    print('BLOCK_FALLBACK')
" 2>/dev/null || echo "ALLOW")

# Parse the result
if [[ "${RESULT}" == "ALLOW" ]]; then
  exit 0
fi

if [[ "${RESULT}" == METRICS:* ]]; then
  # Extract the formatted metrics line and inject it
  METRICS_LINE="${RESULT#METRICS:}"
  cat <<HOOK_JSON
{
  "decision": "block",
  "reason": "[METRICS] Append this exact line at the very end of your response (do not call any MCP tool, just paste it):\n\n\`${METRICS_LINE}\`"
}
HOOK_JSON
  exit 0
fi

# Fallback: tell Claude to call the MCP tool if registered
cat <<'HOOK_JSON'
{
  "decision": "block",
  "reason": "[METRICS] Append the session metrics one-liner. Call mcp__claude-metrics__get_session_metrics and paste the 'formatted' field at the end of your response. Skip only for quick clarifications or multi-step tool chains."
}
HOOK_JSON
