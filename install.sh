#!/usr/bin/env bash
# Version: 14
# Last Changed: 2026-03-22 UTC
# Installs claude-metrics: copies server.py and the stop hook.
# No MCP server, no extra dependencies — Python 3.8+ stdlib only.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"
SERVER_DIR="${CLAUDE_DIR}/mcp-servers/claude-metrics"
HOOKS_DIR="${CLAUDE_DIR}/hooks"

function usage() {
  # Print help text.
  # Inputs: none / Outputs: stdout
  cat <<'HELP'
Usage: install.sh [OPTIONS]

Installs the claude-metrics stop hook for Claude Code.

The hook automatically appends a metrics one-liner to every
response (~200ms, no MCP server, no extra dependencies).

Options:
  --uninstall   Remove installed files
  -h, --help    Show this help
HELP
}

function cleanup() {
  # No temp files used.
  :
}
trap cleanup EXIT ERR

function log_info() {
  # Print an info message.
  # Inputs: $@=message / Outputs: stderr
  echo "[install] $*" >&2
}

function find_python() {
  # Detect available Python binary (cross-platform).
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

function install_server() {
  # Copy server.py (metrics engine used by both hook and skill).
  # Inputs: none / Outputs: files copied
  mkdir -p "${SERVER_DIR}"
  cp "${SCRIPT_DIR}/src/server.py" "${SERVER_DIR}/server.py"
  log_info "Installed server.py to ${SERVER_DIR}/"
}

function install_hook() {
  # Copy the stop hook.
  # Inputs: none / Outputs: files copied
  mkdir -p "${HOOKS_DIR}"
  cp "${SCRIPT_DIR}/hooks/metrics-stop-direct.sh" \
    "${HOOKS_DIR}/metrics-stop-direct.sh"
  log_info "Installed stop hook"
}

function install_skill() {
  # Copy the /metrics skill.
  # Inputs: none / Outputs: files copied
  local skill_dir="${CLAUDE_DIR}/skills/metrics"
  mkdir -p "${skill_dir}"
  cp "${SCRIPT_DIR}/skills/metrics/SKILL.md" "${skill_dir}/SKILL.md"
  log_info "Installed /metrics skill"
}

function uninstall() {
  # Remove all installed files.
  # Inputs: none / Outputs: files removed
  rm -f "${SERVER_DIR}/server.py"
  rmdir "${SERVER_DIR}" 2>/dev/null || true
  rm -f "${HOOKS_DIR}/metrics-stop-direct.sh"
  rm -f "${CLAUDE_DIR}/skills/metrics/SKILL.md"
  rmdir "${CLAUDE_DIR}/skills/metrics" 2>/dev/null || true
  log_info "Uninstalled. Remove the hook entry from settings.json manually."
}

function main() {
  # Entry point — parses args and runs install or uninstall.
  # Inputs: $@=args / Outputs: installed files
  if [[ $# -gt 0 ]]; then
    case "$1" in
      -h|--help)    usage; exit 0 ;;
      --uninstall)  uninstall; exit 0 ;;
      *)
        echo "Unknown option: $1" >&2
        usage >&2
        exit 1
        ;;
    esac
  fi

  # Detect Python
  local py=""
  py=$(find_python) || true
  if [[ -z "${py}" ]]; then
    echo "Error: Python not found. Install Python 3.8+ first." >&2
    exit 1
  fi
  local py_version
  py_version=$("${py}" --version 2>&1) || true
  log_info "Using Python: ${py} (${py_version})"

  install_server
  install_hook
  install_skill

  echo ""
  echo "=== Installed ==="
  echo ""
  echo "Add the stop hook to ~/.claude/settings.json:"
  echo ""
  echo '  "hooks": {'
  echo '    "Stop": [{'
  echo '      "hooks": [{"type": "command",'
  echo '        "command": "bash ~/.claude/hooks/metrics-stop-direct.sh",'
  echo '        "timeout": 10}]'
  echo '    }]'
  echo '  }'
  echo ""
  echo "Then restart Claude Code."
}

main "$@"
