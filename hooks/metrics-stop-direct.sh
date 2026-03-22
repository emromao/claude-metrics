#!/usr/bin/env bash
# Combined Stop hook — metrics injection + Cognee check in ONE block.
# Version: 5
# Last Changed: 2026-03-22 UTC
#
# Combines metrics and cognee into a single hook to prevent the
# duplicate-injection problem caused by parallel stop hooks.
# When two hooks block independently, each re-fire cycle can
# produce a separate metrics line. One hook = one block = one line.

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

# Check marker: if we already injected in the last 60s, allow stop.
if [[ -f "${MARKER_FILE}" ]]; then
  marker_age=$(( $(date +%s) - $(date -r "${MARKER_FILE}" +%s 2>/dev/null || echo 0) ))
  if (( marker_age < 60 )); then
    exit 0
  fi
fi

# Read stdin (hook input JSON) with a size guard (max 2MB)
INPUT=$(head -c 2097152)

export PYTHONIOENCODING=utf-8

# Single Python call: check stop_hook_active, check if metrics present,
# compute metrics if missing, build combined block reason.
RESULT=$(echo "${INPUT}" | "${PYTHON}" -c "
import sys, json, os, importlib.util

try:
    data = json.load(sys.stdin)
except Exception:
    print('ALLOW')
    sys.exit(0)

if data.get('stop_hook_active', False):
    print('ALLOW')
    sys.exit(0)

msg = data.get('last_assistant_message', '')

# Check if metrics already present (heavy pipe U+2503 or light U+2502)
has_metrics = (
    (('\u2593' in msg or '\u2591' in msg) and '%' in msg and ('\u2503' in msg or '\u2502' in msg))
    or ('ctx:' in msg and '%' in msg and 'Tool:' in msg)
)

if has_metrics:
    print('ALLOW')
    sys.exit(0)

# Compute metrics
metrics_line = None
server_file = os.path.expanduser('~/.claude/lib/claude-metrics/server.py')
if os.path.isfile(server_file):
    try:
        spec = importlib.util.spec_from_file_location('server', server_file)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        metrics_line = mod.compute_formatted_metrics()
    except Exception:
        pass

if metrics_line:
    print('BLOCK:' + metrics_line)
else:
    print('ALLOW')
" 2>/dev/null || echo "ALLOW")

if [[ "${RESULT}" == "ALLOW" ]]; then
  exit 0
fi

if [[ "${RESULT}" == BLOCK:* ]]; then
  METRICS_LINE="${RESULT#BLOCK:}"
  # Write marker BEFORE outputting — prevents duplicates on re-fire
  touch "${MARKER_FILE}"

  # Combined block reason: metrics + cognee in ONE decision
  cat <<HOOK_JSON
{
  "decision": "block",
  "reason": "[METRICS] Append this exact line at the very end of your response (do not call any tool, just paste it):\n\n\`${METRICS_LINE}\`\n\n[COGNEE CHECK] Before appending the metrics line, review this conversation for insights worth storing to Cognee. Auto-store triggers: (1) non-obvious bug fix, (2) architecture decision, (3) cross-project pattern, (4) user personal info, (5) infrastructure change, (6) debugging insight. If ANY trigger applies, call mcp__cognee-memory__cognify NOW. If nothing to store, say so briefly, then append the metrics line."
}
HOOK_JSON
  exit 0
fi

exit 0
