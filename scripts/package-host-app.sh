#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST_BUNDLE_ID="com.jianruicheng.macos-mcp-operator.host"
HOST_LABEL="com.jianruicheng.macos-mcp-operator.host"
HOST_APP_PATH="${HOME}/Applications/macos-mcp-operator-host.app"
HOST_BIN_NAME="macos-mcp-operator-host"
SOCKET_PATH="${HOME}/.local/share/macos-mcp-operator/broker.sock"
LAUNCH_AGENT_PATH="${HOME}/Library/LaunchAgents/${HOST_LABEL}.plist"

swift build -c release --package-path "${ROOT_DIR}" --product "${HOST_BIN_NAME}"

mkdir -p "${HOME}/Applications"
rm -rf "${HOST_APP_PATH}"
mkdir -p "${HOST_APP_PATH}/Contents/MacOS"

cp "${ROOT_DIR}/.build/release/${HOST_BIN_NAME}" "${HOST_APP_PATH}/Contents/MacOS/${HOST_BIN_NAME}"
chmod +x "${HOST_APP_PATH}/Contents/MacOS/${HOST_BIN_NAME}"

cat > "${HOST_APP_PATH}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>macos-mcp-operator-host</string>
  <key>CFBundleIdentifier</key>
  <string>com.jianruicheng.macos-mcp-operator.host</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>macos-mcp-operator-host</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.1</string>
  <key>CFBundleVersion</key>
  <string>11</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

mkdir -p "$(dirname "${LAUNCH_AGENT_PATH}")"
cat > "${LAUNCH_AGENT_PATH}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${HOST_LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${HOST_APP_PATH}/Contents/MacOS/${HOST_BIN_NAME}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key>
    <string>${HOME}</string>
  </dict>
  <key>StandardOutPath</key>
  <string>${HOME}/Library/Logs/macos-mcp-operator/host.stdout.log</string>
  <key>StandardErrorPath</key>
  <string>${HOME}/Library/Logs/macos-mcp-operator/host.stderr.log</string>
</dict>
</plist>
PLIST

mkdir -p "${HOME}/Library/Logs/macos-mcp-operator"
mkdir -p "$(dirname "${SOCKET_PATH}")"

launchctl bootout "gui/$(id -u)/${HOST_LABEL}" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "${LAUNCH_AGENT_PATH}"
launchctl kickstart -k "gui/$(id -u)/${HOST_LABEL}"

echo "Packaged host app at: ${HOST_APP_PATH}"
echo "Installed LaunchAgent: ${LAUNCH_AGENT_PATH}"
