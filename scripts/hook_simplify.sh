#!/usr/bin/env bash
# Version: 1
# Last Changed: 2026-03-14 UTC
# PostToolUse hook: suggest code simplification after .py edits in LIVE/.
# Outputs a hint message that nudges Claude to run the code-simplifier agent.

set -Eeuo pipefail
IFS=$'\n\t'

INPUT=$(cat)

# Extract file_path from tool_input using Python (jq not on Windows)
FILE_PATH=$(echo "${INPUT}" | python -c \
  "import sys,json
print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))" \
  2>/dev/null) || true

# Only trigger on Python files under LIVE/
if [[ "${FILE_PATH}" != *.py ]]; then
  exit 0
fi

case "${FILE_PATH}" in
  *LIVE/*|*tests/*)
    echo "hint: consider running /simplify to review this change"
    ;;
esac

exit 0
