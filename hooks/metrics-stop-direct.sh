#!/usr/bin/env bash
# Metrics Stop hook — computes and injects metrics inline.
# Version: 4
# Last Changed: 2026-03-22 UTC
#
# Computes the metrics one-liner directly via server.py import (~200ms).
# No extra dependencies or background processes required.
#
# Uses a marker file to prevent duplicate injection when other stop hooks
# (e.g. Cognee) cause additional stop cycles in the same interaction.

set -Eeuo pipefail
IFS=$'\n\t'

SERVER_PY="${HOME}/.claude/lib/claude-metrics/server.py"
MARKER_FILE="${TMPDIR:-/tmp}/claude-metrics-injected"

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
# shellcheck disable=SC2310
PYTHON=$(_find_python) || true
if [[ -z "${PYTHON}" ]]; then
  exit 0
fi

if [[ ! -f "${SERVER_PY}" ]]; then
  exit 0
fi

# Check marker: if we already injected metrics in the last 30s, skip.
# This prevents duplicates when other stop hooks cause re-fire cycles.
if [[ -f "${MARKER_FILE}" ]]; then
  marker_age=$(( $(date +%s) - $(date -r "${MARKER_FILE}" +%s 2>/dev/null || echo 0) ))
  if (( marker_age < 30 )); then
    exit 0
  fi
fi

# Read stdin (hook input JSON) with a size guard (max 2MB)
INPUT=$(head -c 2097152)

# Ensure UTF-8 output on Windows (emoji in metrics line)
export PYTHONIOENCODING=utf-8

# Single Python call: check if metrics present, compute if missing.
RESULT=$(echo "${INPUT}" | "${PYTHON}" -c "
import sys, json, os, importlib.util

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
if ('\u2593' in msg or '\u2591' in msg) and '%' in msg and '\u2502' in msg:
    print('ALLOW')
    sys.exit(0)

if 'ctx:' in msg and '%' in msg and 'Tool:' in msg:
    print('ALLOW')
    sys.exit(0)

# Compute metrics
server_file = os.path.expanduser('~/.claude/lib/claude-metrics/server.py')
if not os.path.isfile(server_file):
    print('ALLOW')
    sys.exit(0)

try:
    spec = importlib.util.spec_from_file_location('server', server_file)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    formatted = mod.compute_formatted_metrics()
    if formatted:
        print('METRICS:' + formatted)
    else:
        print('ALLOW')
except Exception:
    print('ALLOW')
" 2>/dev/null || echo "ALLOW")

if [[ "${RESULT}" == "ALLOW" ]]; then
  exit 0
fi

if [[ "${RESULT}" == METRICS:* ]]; then
  METRICS_LINE="${RESULT#METRICS:}"
  # Write marker BEFORE outputting block — prevents duplicates
  touch "${MARKER_FILE}"
  cat <<HOOK_JSON
{
  "decision": "block",
  "reason": "[METRICS] Append this exact line at the very end of your response (do not call any tool, just paste it):\n\n\`${METRICS_LINE}\`"
}
HOOK_JSON
  exit 0
fi

exit 0
