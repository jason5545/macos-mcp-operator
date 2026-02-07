# macos-mcp-operator v1.1

Local MCP (Model Context Protocol) server for macOS 14+ desktop automation, optimized for single-user self-host workflows.

## What changed in v1.1

- Approval/token flow is disabled (`risk_class` and `confirmation_token` are ignored for compatibility).
- AppleScript execution now goes through a local broker host process (`macos-mcp-operator-host`) via Unix socket.
- Added permissions tools:
  - `permissions_status`
  - `permissions_probe_automation`
  - `permissions_open_settings`
- `set_safety_mode` and `update_app_whitelist` remain available as deprecated no-op tools.

## Build

```bash
swift build -c release
```

Binary paths:

```bash
.build/release/macos-mcp-operator
.build/release/macos-mcp-operator-host
```

## Permissions

Grant permissions to the host app/processes:

- Accessibility (mouse/keyboard control)
- Screen Recording (`screen_capture`)
- Automation (Apple Events, target app specific)

If permissions are missing, tool calls return explicit error codes/messages such as:

- `ACCESSIBILITY_MISSING`
- `SCREEN_RECORDING_MISSING`
- `AUTOMATION_NOT_ALLOWED`
- `BROKER_UNAVAILABLE`

## Configuration

Path:

`~/.config/macos-mcp-operator/config.json`

v1.1 default shape:

```json
{
  "default_mode": "restricted",
  "app_whitelist": [
    "com.apple.Notes"
  ],
  "sensitive_bundle_ids": [
    "com.apple.systempreferences"
  ],
  "dangerous_key_chords": [
    ["cmd", "q"],
    ["cmd", "w"],
    ["cmd", "delete"]
  ],
  "audit_enabled": true,
  "kill_switch_hotkey": "ctrl+opt+cmd+.",
  "approval_enabled": false,
  "execution_backend": "broker",
  "broker": {
    "bundle_id": "com.jianruicheng.macos-mcp-operator.host",
    "app_path": "~/Applications/macos-mcp-operator-host.app",
    "socket_path": "~/.local/share/macos-mcp-operator/broker.sock",
    "launch_agent_label": "com.jianruicheng.macos-mcp-operator.host"
  }
}
```

Audit log path:

`~/Library/Logs/macos-mcp-operator/audit.jsonl`

## Tools

1. `set_safety_mode` (deprecated no-op)
2. `update_app_whitelist` (deprecated no-op)
3. `list_windows`
4. `focus_window`
5. `mouse_move`
6. `mouse_click`
7. `mouse_drag`
8. `mouse_scroll`
9. `text_input`
10. `key_chord`
11. `screen_capture`
12. `app_launch`
13. `app_open_url`
14. `app_open_path`
15. `app_quit`
16. `applescript_run` (broker-backed)
17. `applescript_app_command` (broker-backed)
18. `permissions_status`
19. `permissions_probe_automation`
20. `permissions_open_settings`
21. `automation_stop`

## Scripts

- `scripts/package-host-app.sh`
  - Builds and packages `~/Applications/macos-mcp-operator-host.app`
  - Installs/starts LaunchAgent: `com.jianruicheng.macos-mcp-operator.host`
- `scripts/sign-host-app.sh`
  - Signs host app
  - Auto-detects TeamID (`MW4GWYGX56`) and matching identity when possible
- `scripts/install-claude-mcp.sh`
  - Updates:
    - `~/Library/Application Support/Claude/claude_desktop_config.json`
    - `~/.claude.json`
  - Verifies with `claude mcp get macos-mcp-operator`

## Suggested setup order

```bash
./scripts/package-host-app.sh
./scripts/sign-host-app.sh
./scripts/install-claude-mcp.sh
```

## Permission recovery runbook

Open settings pages quickly:

- Accessibility:
  - `open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"`
- Screen Recording:
  - `open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"`
- Automation:
  - `open "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"`

Reset TCC entries if needed (you will need to re-grant):

```bash
tccutil reset Accessibility com.jianruicheng.macos-mcp-operator.host
tccutil reset ScreenCapture com.jianruicheng.macos-mcp-operator.host
tccutil reset AppleEvents com.jianruicheng.macos-mcp-operator.host
```

## MCP protocol versions

Supported protocol versions (newest to oldest):

- `2025-11-25`
- `2025-06-18`
- `2025-03-26`
