#!/usr/bin/env bash
# Version: 13
# Last Changed: 2026-03-22 UTC
# Installs claude-metrics in one of three modes:
#   hook-only (default) — lightweight, no MCP server
#   full                — MCP server + direct hook
#   mcp                 — MCP server + MCP-based hook

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"
MCP_DIR="${CLAUDE_DIR}/mcp-servers/claude-metrics"
HOOKS_DIR="${CLAUDE_DIR}/hooks"
# Modes: "hook-only" (default), "full", "mcp", "no-hook"
INSTALL_MODE="hook-only"

function usage() {
  # Print help text.
  # Inputs: none / Outputs: stdout
  cat <<'HELP'
Usage: install.sh [OPTIONS]

Installs claude-metrics for Claude Code.

Modes:
  (default)     Hook-only — lightweight, no MCP server registered.
                The stop hook computes metrics directly (~200ms).
                No extra dependencies beyond Python stdlib + server.py.

  --full        Hook + MCP server — installs the direct hook AND
                registers the MCP server for interactive tools
                (get_session_detail, get_context_breakdown).

  --mcp         MCP-based hook — original approach where the hook
                tells Claude to call the MCP tool (~3-4s, tool call
                visible in the UI). Also registers the MCP server.

  --no-hook     MCP server only — no automatic metrics appending.
                Call tools manually mid-conversation.

Other options:
  --uninstall   Remove all installed files
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
  log_info "Installed server.py to ${MCP_DIR}/"
}

function install_hook_direct() {
  # Copy the direct-mode stop hook.
  # Inputs: none / Outputs: files copied
  mkdir -p "${HOOKS_DIR}"
  cp "${SCRIPT_DIR}/hooks/metrics-stop-direct.sh" \
    "${HOOKS_DIR}/metrics-stop-direct.sh"
  log_info "Installed direct-mode hook"
}

function install_hook_mcp() {
  # Copy the MCP-mode stop hook.
  # Inputs: none / Outputs: files copied
  mkdir -p "${HOOKS_DIR}"
  cp "${SCRIPT_DIR}/hooks/metrics-stop-check.sh" \
    "${HOOKS_DIR}/metrics-stop-check.sh"
  log_info "Installed MCP-mode hook"
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
    log_info "  claude mcp add claude-metrics -s user -- " \
      "${py} ${server_path}"
  fi
}

function uninstall() {
  # Remove all installed files (both hook variants + MCP server).
  # Inputs: none / Outputs: files removed
  rm -f "${MCP_DIR}/server.py"
  rm -f "${MCP_DIR}/requirements.txt"
  rmdir "${MCP_DIR}" 2>/dev/null || true
  rm -f "${HOOKS_DIR}/metrics-stop-check.sh"
  rm -f "${HOOKS_DIR}/metrics-stop-direct.sh"
  if command -v claude &>/dev/null; then
    claude mcp remove claude-metrics -s user 2>/dev/null || true
    log_info "Removed MCP server registration"
  fi
  log_info "Uninstalled. Remove the hook entry from settings.json manually."
}

function print_hook_config() {
  # Print the settings.json snippet for the installed hook.
  # Inputs: $1=hook filename / Outputs: stdout
  local hook_file="$1"
  echo "  Add the stop hook to ~/.claude/settings.json:"
  echo ""
  echo '     "hooks": {'
  echo '       "Stop": [{'
  echo '         "hooks": [{"type": "command",'
  echo "           \"command\": \"bash ~/.claude/hooks/${hook_file}\","
  echo '           "timeout": 10}]'
  echo '       }]'
  echo '     }'
}

function main() {
  # Entry point — parses args and runs install or uninstall.
  # Inputs: $@=args / Outputs: installed files
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)    usage; exit 0 ;;
      --uninstall)  uninstall; exit 0 ;;
      --full)       INSTALL_MODE="full"; shift ;;
      --mcp)        INSTALL_MODE="mcp"; shift ;;
      --no-hook)    INSTALL_MODE="no-hook"; shift ;;
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

  # Always install server.py (needed by both hook and MCP modes)
  install_server

  case "${INSTALL_MODE}" in
    hook-only)
      # Lightweight: hook + server.py only, no MCP registration
      install_hook_direct
      echo ""
      echo "=== Installed (hook-only mode) ==="
      echo ""
      echo "  No MCP server registered — the hook computes metrics"
      echo "  directly from server.py (~200ms, no UI noise)."
      echo ""
      print_hook_config "metrics-stop-direct.sh"
      echo ""
      echo "  To also get interactive tools (get_session_detail,"
      echo "  get_context_breakdown), re-run with --full."
      ;;

    full)
      # Hook + MCP server for interactive tools
      install_deps "${py}"
      install_hook_direct
      register_mcp "${py}"
      echo ""
      echo "=== Installed (full mode) ==="
      echo ""
      echo "  Direct hook (~200ms) + MCP server for interactive tools."
      echo ""
      print_hook_config "metrics-stop-direct.sh"
      ;;

    mcp)
      # MCP-based hook + MCP server
      install_deps "${py}"
      install_hook_mcp
      register_mcp "${py}"
      echo ""
      echo "=== Installed (MCP mode) ==="
      echo ""
      echo "  Hook tells Claude to call MCP tool (~3-4s, visible in UI)."
      echo ""
      print_hook_config "metrics-stop-check.sh"
      ;;

    no-hook)
      # MCP server only, no hook
      install_deps "${py}"
      register_mcp "${py}"
      echo ""
      echo "=== Installed (no-hook mode) ==="
      echo ""
      echo "  MCP server only — call tools manually:"
      echo "    get_session_metrics, get_session_detail, get_context_breakdown"
      ;;

    *)
      echo "Error: unknown install mode '${INSTALL_MODE}'" >&2
      exit 1
      ;;
  esac

  echo ""
  echo "  Restart Claude Code to apply changes."
}

main "$@"
