#!/usr/bin/env bash
# PostToolUse hook: check requirements.txt sync after .py edits.
# Last Changed: 2026-03-10 UTC

set -Eeuo pipefail
IFS=$'\n\t'

INPUT=$(cat)

# Extract file_path from tool_input using Python (jq not on Windows)
FILE_PATH=$(echo "$INPUT" | python -c \
  "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))" \
  2>/dev/null) || true

# Only run on Python files
if [[ "$FILE_PATH" != *.py ]]; then
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

py "$PROJECT_ROOT/scripts/check_deps.py" 2>&1
exit 0
