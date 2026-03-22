#!/usr/bin/env bash
# Metrics Stop hook — computes and injects metrics inline.
# Version: 9
# Last Changed: 2026-03-22 UTC
#
# Computes the metrics one-liner directly via server.py import (~200ms).
# Self-contained — works alongside any other stop hooks without conflicts.
#
# Dedup: uses a 60-second marker file to prevent duplicate injection when
# parallel stop hooks (e.g. cognee) cause additional stop cycles.

set -Eeuo pipefail
IFS=$'\n\t'

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

# Dedup: skip if we already injected metrics in the last 60 seconds.
if [[ -f "${MARKER_FILE}" ]]; then
  last_inject=$(cat "${MARKER_FILE}" 2>/dev/null || echo "0")
  now=$(date +%s)
  if (( now - last_inject < 15 )); then
    exit 0
  fi
fi

# Read stdin (hook input JSON) with a size guard (max 2MB)
INPUT=$(head -c 2097152)

export PYTHONIOENCODING=utf-8

# Single Python call: check guards, compute metrics if needed.
RESULT=$(echo "${INPUT}" | "${PYTHON}" -c "
import sys, json, os, importlib.util

try:
    data = json.load(sys.stdin)
except Exception:
    print('ALLOW')
    sys.exit(0)

# Guard: if Claude is retrying after a block, allow stop
if data.get('stop_hook_active', False):
    print('ALLOW')
    sys.exit(0)

msg = data.get('last_assistant_message', '')

# Check if metrics already in this response (progress bar + % + pipe)
if ('\u2593' in msg or '\u2591' in msg) and '%' in msg and ('\u2503' in msg or '\u2502' in msg):
    print('ALLOW')
    sys.exit(0)

# Compute metrics via importlib (explicit file path, no sys.path manip)
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
        print('BLOCK:' + formatted)
    else:
        print('ALLOW')
except Exception:
    print('ALLOW')
" 2>/dev/null || echo "ALLOW")

if [[ "${RESULT}" == "ALLOW" ]]; then
  exit 0
fi

if [[ "${RESULT}" == BLOCK:* ]]; then
  METRICS_LINE="${RESULT#BLOCK:}"
  # Write marker BEFORE outputting block
  date +%s > "${MARKER_FILE}" 2>/dev/null || true
  cat <<HOOK_JSON
{
  "decision": "block",
  "reason": "[METRICS] Append this line ONCE at the very end of your response. Do NOT paste it again if you already pasted it. Do NOT paste it in follow-up responses to other hooks.\n\n\`${METRICS_LINE}\`"
}
HOOK_JSON
  exit 0
fi

exit 0
