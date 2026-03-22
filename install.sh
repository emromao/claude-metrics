#!/usr/bin/env bash
# Version: 12
# Last Changed: 2026-03-22 UTC
# Installs the claude-metrics MCP server and stop hook into the user's
# Claude Code configuration. Supports two hook modes: direct (default)
# and MCP-based.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"
MCP_DIR="${CLAUDE_DIR}/mcp-servers/claude-metrics"
HOOKS_DIR="${CLAUDE_DIR}/hooks"
INSTALL_HOOK=true
HOOK_MODE="direct"  # "direct" = fast hook-only, "mcp" = current MCP-based

function usage() {
  # Print help text.
  # Inputs: none / Outputs: stdout
  cat <<'HELP'
Usage: install.sh [OPTIONS]

Installs the claude-metrics MCP server and stop hook.

Options:
  --mcp         Use MCP-based hook (slower but shows tool call in UI)
  --no-hook     Skip installing the stop hook (MCP server only)
  --uninstall   Remove installed files (does not modify settings.json)
  -h, --help    Show this help

Hook modes:
  Default (direct):  Hook computes metrics inline (~200ms, no UI noise)
  --mcp:             Hook tells Claude to call the MCP tool (~3-4s,
                     MCP tool call visible in the UI)

Both modes install the MCP server for interactive use of
get_session_detail and get_context_breakdown.
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

function install_deps() {
  # Install Python dependencies from requirements.txt.
  # Inputs: $1=python binary / Outputs: pip packages installed
  local py="$1"
  if [[ -f "${SCRIPT_DIR}/requirements.txt" ]]; then
    log_info "Installing Python dependencies..."
    "${py}" -m pip install -q -r "${SCRIPT_DIR}/requirements.txt" || {
      log_info "Warning: pip install failed — install 'mcp' manually:"
      log_info "  ${py} -m pip install mcp"
    }
  fi
}

function install_server() {
  # Copy server.py to the MCP server directory.
  # Inputs: none / Outputs: files copied
  mkdir -p "${MCP_DIR}"
  cp "${SCRIPT_DIR}/src/server.py" "${MCP_DIR}/server.py"
  log_info "Installed server to ${MCP_DIR}/server.py"
}

function install_hook() {
  # Copy the appropriate stop hook based on mode.
  # Inputs: none / Outputs: files copied
  mkdir -p "${HOOKS_DIR}"
  local hook_src hook_name
  if [[ "${HOOK_MODE}" == "direct" ]]; then
    hook_src="${SCRIPT_DIR}/hooks/metrics-stop-direct.sh"
    hook_name="metrics-stop-direct.sh"
    log_info "Installing direct-mode hook (fast, no MCP call)"
  else
    hook_src="${SCRIPT_DIR}/hooks/metrics-stop-check.sh"
    hook_name="metrics-stop-check.sh"
    log_info "Installing MCP-mode hook (calls MCP tool)"
  fi
  cp "${hook_src}" "${HOOKS_DIR}/${hook_name}"
  log_info "Installed hook to ${HOOKS_DIR}/${hook_name}"
}

function register_mcp() {
  # Register the MCP server using claude CLI.
  # Inputs: $1=python binary / Outputs: claude config updated
  local py="$1"
  local server_path
  server_path="$(cygpath -w "${MCP_DIR}/server.py" 2>/dev/null \
    || echo "${MCP_DIR}/server.py")"
  # Normalize to forward slashes for JSON
  server_path="${server_path//\\//}"

  if command -v claude &>/dev/null; then
    claude mcp add claude-metrics -s user -- \
      "${py}" "${server_path}"
    log_info "Registered MCP server via claude CLI"
  else
    log_info "claude CLI not found — add manually:"
    log_info "  claude mcp add claude-metrics -s user -- ${py} ${server_path}"
  fi
}

function uninstall() {
  # Remove installed files (both hook variants).
  # Inputs: none / Outputs: files removed
  rm -f "${MCP_DIR}/server.py"
  rmdir "${MCP_DIR}" 2>/dev/null || true
  rm -f "${HOOKS_DIR}/metrics-stop-check.sh"
  rm -f "${HOOKS_DIR}/metrics-stop-direct.sh"
  log_info "Uninstalled. Remove MCP entry and hook from settings.json manually."
}

function main() {
  # Entry point — parses args and runs install or uninstall.
  # Inputs: $@=args / Outputs: installed files
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)    usage; exit 0 ;;
      --uninstall)  uninstall; exit 0 ;;
      --no-hook)    INSTALL_HOOK=false; shift ;;
      --mcp)        HOOK_MODE="mcp"; shift ;;
      *)
        echo "Unknown option: $1" >&2
        usage >&2
        exit 1
        ;;
    esac
  done

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

  install_deps "${py}"
  install_server

  if [[ "${INSTALL_HOOK}" == "true" ]]; then
    install_hook
  else
    log_info "Skipping stop hook (--no-hook)"
  fi

  register_mcp "${py}"

  echo ""
  echo "=== Installation Complete ==="
  echo ""

  if [[ "${INSTALL_HOOK}" == "true" ]]; then
    local hook_file
    if [[ "${HOOK_MODE}" == "direct" ]]; then
      hook_file="metrics-stop-direct.sh"
    else
      hook_file="metrics-stop-check.sh"
    fi
    echo "Next steps:"
    echo "  1. Add the stop hook to ~/.claude/settings.json:"
    echo '     "hooks": {'
    echo '       "Stop": [{'
    echo '         "hooks": [{"type": "command",'
    echo "           \"command\": \"bash ~/.claude/hooks/${hook_file}\"}]"
    echo '       }]'
    echo '     }'
    echo "  2. Restart Claude Code to load the new MCP server"
    echo ""
    if [[ "${HOOK_MODE}" == "direct" ]]; then
      echo "Mode: direct (metrics computed in hook, ~200ms, no UI noise)"
    else
      echo "Mode: MCP (Claude calls MCP tool, ~3-4s, tool call visible)"
    fi
  else
    echo "Restart Claude Code to load the new MCP server."
    echo ""
    echo "To also install the stop hook later, re-run without --no-hook."
  fi
}

main "$@"
