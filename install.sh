#!/usr/bin/env bash
# Version: 10
# Last Changed: 2026-03-22 UTC
# Installs the claude-metrics MCP server and stop hook into the user's
# Claude Code configuration.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"
MCP_DIR="${CLAUDE_DIR}/mcp-servers/claude-metrics"
HOOKS_DIR="${CLAUDE_DIR}/hooks"

function usage() {
  # Print help text.
  # Inputs: none / Outputs: stdout
  cat <<'HELP'
Usage: install.sh [--uninstall]

Installs the claude-metrics MCP server and stop hook.

  --uninstall   Remove installed files (does not modify settings.json)
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

function install_server() {
  # Copy server.py to the MCP server directory.
  # Inputs: none / Outputs: files copied
  mkdir -p "${MCP_DIR}"
  cp "${SCRIPT_DIR}/src/server.py" "${MCP_DIR}/server.py"
  log_info "Installed server to ${MCP_DIR}/server.py"
}

function install_hook() {
  # Copy the metrics stop hook.
  # Inputs: none / Outputs: files copied
  mkdir -p "${HOOKS_DIR}"
  cp "${SCRIPT_DIR}/hooks/metrics-stop-check.sh" \
    "${HOOKS_DIR}/metrics-stop-check.sh"
  log_info "Installed hook to ${HOOKS_DIR}/metrics-stop-check.sh"
}

function register_mcp() {
  # Register the MCP server using claude CLI.
  # Inputs: none / Outputs: claude config updated
  local server_path
  server_path="$(cygpath -w "${MCP_DIR}/server.py" 2>/dev/null \
    || echo "${MCP_DIR}/server.py")"
  # Normalize to forward slashes for JSON
  server_path="${server_path//\\//}"

  if command -v claude &>/dev/null; then
    claude mcp add claude-metrics -s user -- \
      python "${server_path}"
    log_info "Registered MCP server via claude CLI"
  else
    log_info "claude CLI not found — add manually to ~/.claude.json:"
    log_info "  claude mcp add claude-metrics -s user -- python ${server_path}"
  fi
}

function uninstall() {
  # Remove installed files.
  # Inputs: none / Outputs: files removed
  rm -f "${MCP_DIR}/server.py"
  rmdir "${MCP_DIR}" 2>/dev/null || true
  rm -f "${HOOKS_DIR}/metrics-stop-check.sh"
  log_info "Uninstalled. Remove MCP entry and hook from settings.json manually."
}

function main() {
  # Entry point.
  # Inputs: $@=args / Outputs: installed files
  case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    --uninstall) uninstall; exit 0 ;;
  esac

  install_server
  install_hook
  register_mcp

  echo ""
  echo "=== Installation Complete ==="
  echo ""
  echo "Next steps:"
  echo "  1. Add the stop hook to ~/.claude/settings.json:"
  echo '     "Stop": [{"hooks": [{"type": "command",'
  echo '       "command": "bash ~/.claude/hooks/metrics-stop-check.sh"}]}]'
  echo "  2. Restart Claude Code to load the new MCP server"
}

main "$@"
