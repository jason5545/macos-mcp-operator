#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_PATH="${ROOT_DIR}/.build/release/macos-mcp-operator"
DESKTOP_CONFIG="${HOME}/Library/Application Support/Claude/claude_desktop_config.json"
CLI_CONFIG="${HOME}/.claude.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for this script." >&2
  exit 1
fi

if [[ ! -x "${BIN_PATH}" ]]; then
  swift build -c release --package-path "${ROOT_DIR}" --product macos-mcp-operator
fi

mkdir -p "$(dirname "${DESKTOP_CONFIG}")"
mkdir -p "$(dirname "${CLI_CONFIG}")"

if [[ ! -f "${DESKTOP_CONFIG}" ]]; then
  echo '{}' > "${DESKTOP_CONFIG}"
fi
if [[ ! -f "${CLI_CONFIG}" ]]; then
  echo '{}' > "${CLI_CONFIG}"
fi

desktop_tmp="$(mktemp)"
jq --arg cmd "${BIN_PATH}" '
  .mcpServers = (.mcpServers // {}) |
  .mcpServers["macos-mcp-operator"] = {
    "command": $cmd
  }
' "${DESKTOP_CONFIG}" > "${desktop_tmp}"
mv "${desktop_tmp}" "${DESKTOP_CONFIG}"

cli_tmp="$(mktemp)"
jq --arg cmd "${BIN_PATH}" '
  .mcpServers = (.mcpServers // {}) |
  .mcpServers["macos-mcp-operator"] = {
    "type": "stdio",
    "command": $cmd,
    "args": [],
    "env": {}
  }
' "${CLI_CONFIG}" > "${cli_tmp}"
mv "${cli_tmp}" "${CLI_CONFIG}"

claude mcp get macos-mcp-operator >/dev/null

echo "Updated Desktop config: ${DESKTOP_CONFIG}"
echo "Updated CLI config: ${CLI_CONFIG}"
echo "Verified: claude mcp get macos-mcp-operator"
