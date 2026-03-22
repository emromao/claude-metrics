#!/usr/bin/env bash
# Version: 16
# Last Changed: 2026-03-22 UTC
# Installs claude-metrics: copies files only.
# NEVER modifies settings.json, CLAUDE.md, or any existing user config.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"
SERVER_DIR="${CLAUDE_DIR}/lib/claude-metrics"
HOOKS_DIR="${CLAUDE_DIR}/hooks"
SKILL_DIR="${CLAUDE_DIR}/skills/metrics"

function usage() {
  # Print help text.
  # Inputs: none / Outputs: stdout
  cat <<'HELP'
Usage: install.sh [OPTIONS]

Installs the claude-metrics stop hook for Claude Code.

Copies three files (never modifies existing config):
  ~/.claude/lib/claude-metrics/server.py    (metrics engine)
  ~/.claude/hooks/metrics-stop-direct.sh    (stop hook)
  ~/.claude/skills/metrics/SKILL.md         (/metrics command)

Options:
  --uninstall   Remove installed files only
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
  echo "[claude-metrics] $*" >&2
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

function install_files() {
  # Copy all claude-metrics files to their destinations.
  # Inputs: none / Outputs: files copied
  mkdir -p "${SERVER_DIR}" "${HOOKS_DIR}" "${SKILL_DIR}"

  [[ -f "${SERVER_DIR}/server.py" ]] \
    && log_info "Updating existing server.py"
  cp "${SCRIPT_DIR}/src/server.py" "${SERVER_DIR}/server.py"
  log_info "Copied server.py"

  [[ -f "${HOOKS_DIR}/metrics-stop-direct.sh" ]] \
    && log_info "Updating existing stop hook"
  cp "${SCRIPT_DIR}/hooks/metrics-stop-direct.sh" \
    "${HOOKS_DIR}/metrics-stop-direct.sh"
  log_info "Copied stop hook"

  [[ -f "${SKILL_DIR}/SKILL.md" ]] \
    && log_info "Updating existing /metrics skill"
  cp "${SCRIPT_DIR}/skills/metrics/SKILL.md" "${SKILL_DIR}/SKILL.md"
  log_info "Copied /metrics skill"

  local style_dir="${CLAUDE_DIR}/skills/metrics-style"
  mkdir -p "${style_dir}"
  cp "${SCRIPT_DIR}/skills/metrics-style/SKILL.md" "${style_dir}/SKILL.md"
  log_info "Copied /metrics-style skill"
}

function uninstall() {
  # Remove only claude-metrics files. Never touches settings.json.
  # Inputs: none / Outputs: files removed
  rm -f "${SERVER_DIR}/server.py"
  rmdir "${SERVER_DIR}" 2>/dev/null || true
  rmdir "${CLAUDE_DIR}/lib" 2>/dev/null || true
  rm -f "${HOOKS_DIR}/metrics-stop-direct.sh"
  rm -f "${SKILL_DIR}/SKILL.md"
  rmdir "${SKILL_DIR}" 2>/dev/null || true
  rm -f "${CLAUDE_DIR}/skills/metrics-style/SKILL.md"
  rmdir "${CLAUDE_DIR}/skills/metrics-style" 2>/dev/null || true
  rm -f "${TMPDIR:-/tmp}/claude-metrics-injected"
  log_info "Files removed."
  echo ""
  echo "To finish uninstalling:"
  echo "  1. Remove the Stop hook entry from ~/.claude/settings.json"
  echo "  2. Remove the Session Metrics section from CLAUDE.md"
}

function main() {
  # Entry point.
  # Inputs: $@=args / Outputs: installed files + instructions
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
  # shellcheck disable=SC2310
  py=$(find_python) || true
  if [[ -z "${py}" ]]; then
    echo "Error: Python not found. Install Python 3.8+ first." >&2
    exit 1
  fi
  log_info "Using $("${py}" --version 2>&1)"

  # Validate Python 3 (server.py uses f-strings, type unions, etc.)
  local major
  major=$("${py}" -c "import sys; print(sys.version_info.major)" 2>/dev/null) \
    || true
  if [[ "${major}" != "3" ]]; then
    echo "Error: Python 3.8+ required; '${py}' is Python ${major:-unknown}." >&2
    exit 1
  fi

  install_files

  echo ""
  echo "=== claude-metrics installed ==="
  echo ""
  echo "To activate, add this Stop hook to ~/.claude/settings.json:"
  echo ""
  echo '  "Stop": [{'
  echo '    "hooks": [{'
  echo '      "type": "command",'
  echo '      "command": "bash ~/.claude/hooks/metrics-stop-direct.sh",'
  echo '      "timeout": 10'
  echo '    }]'
  echo '  }]'
  echo ""
  echo "Then add this to your CLAUDE.md (global or project):"
  echo ""
  echo '  ## Session Metrics'
  echo '  The metrics one-liner is appended automatically by the stop hook.'
  echo '  Do NOT manually append metrics — the hook handles it.'
  echo '  **CRITICAL: The metrics line must appear exactly ONCE per user'
  echo '  interaction.** When responding to subsequent hook blocks, do NOT'
  echo '  paste the metrics line again.'
  echo ""
  echo "Restart Claude Code to activate."
}

main "$@"
