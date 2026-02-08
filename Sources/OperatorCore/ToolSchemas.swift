import MCPCore

public enum ToolSchemas {
    public static func allTools() -> [ToolDefinition] {
        [
            ToolDefinition(
                name: "set_safety_mode",
                description: "Deprecated no-op. Approval flow is disabled in v1.1.",
                inputSchema: ToolSchema(
                    required: ["mode"],
                    properties: [
                        "mode": .enumString(["restricted", "full_auto"]),
                        "persist": .scalar(.boolean),
                    ]
                )
            ),
            ToolDefinition(
                name: "update_app_whitelist",
                description: "Deprecated no-op. Approval flow is disabled in v1.1.",
                inputSchema: ToolSchema(
                    required: ["operation", "bundle_ids"],
                    properties: [
                        "operation": .enumString(["set", "add", "remove"]),
                        "bundle_ids": .array(of: .scalar(.string)),
                    ]
                )
            ),
            ToolDefinition(
                name: "list_windows",
                description: "List windows on the current display.",
                inputSchema: ToolSchema(
                    properties: [
                        "include_minimized": .scalar(.boolean),
                    ]
                )
            ),
            ToolDefinition(
                name: "focus_window",
                description: "Focus a window by window_id or bundle_id.",
                inputSchema: ToolSchema(
                    properties: [
                        "window_id": .scalar(.integer),
                        "bundle_id": .scalar(.string),
                        "launch_if_needed": .scalar(.boolean),
                        "activate_all_windows": .scalar(.boolean),
                    ]
                )
            ),
            ToolDefinition(
                name: "mouse_move",
                description: "Move the mouse cursor to absolute screen coordinates.",
                inputSchema: ToolSchema(
                    required: ["x", "y"],
                    properties: [
                        "x": .scalar(.number),
                        "y": .scalar(.number),
                        "duration_ms": .scalar(.integer),
                    ]
                )
            ),
            ToolDefinition(
                name: "mouse_click",
                description: "Click mouse at coordinates. risk_class/confirmation_token are accepted for backward compatibility but ignored.",
                inputSchema: ToolSchema(
                    required: ["x", "y"],
                    properties: [
                        "x": .scalar(.number),
                        "y": .scalar(.number),
                        "button": .enumString(["left", "right", "center"]),
                        "click_count": .scalar(.integer),
                        "window_id": .scalar(.integer),
                        "bundle_id": .scalar(.string),
                        "auto_focus": .scalar(.boolean),
                        "launch_if_needed": .scalar(.boolean),
                        "risk_class": .enumString(["low", "high"]),
                        "confirmation_token": .scalar(.string),
                    ]
                )
            ),
            ToolDefinition(
                name: "mouse_drag",
                description: "Drag from one coordinate to another. risk_class/confirmation_token are accepted for backward compatibility but ignored.",
                inputSchema: ToolSchema(
                    required: ["from_x", "from_y", "to_x", "to_y"],
                    properties: [
                        "from_x": .scalar(.number),
                        "from_y": .scalar(.number),
                        "to_x": .scalar(.number),
                        "to_y": .scalar(.number),
                        "duration_ms": .scalar(.integer),
                        "window_id": .scalar(.integer),
                        "bundle_id": .scalar(.string),
                        "auto_focus": .scalar(.boolean),
                        "launch_if_needed": .scalar(.boolean),
                        "risk_class": .enumString(["low", "high"]),
                        "confirmation_token": .scalar(.string),
                    ]
                )
            ),
            ToolDefinition(
                name: "mouse_scroll",
                description: "Scroll by horizontal/vertical deltas. risk_class/confirmation_token are accepted for backward compatibility but ignored.",
                inputSchema: ToolSchema(
                    required: ["delta_x", "delta_y"],
                    properties: [
                        "delta_x": .scalar(.number),
                        "delta_y": .scalar(.number),
                        "window_id": .scalar(.integer),
                        "bundle_id": .scalar(.string),
                        "auto_focus": .scalar(.boolean),
                        "launch_if_needed": .scalar(.boolean),
                        "risk_class": .enumString(["low", "high"]),
                        "confirmation_token": .scalar(.string),
                    ]
                )
            ),
            ToolDefinition(
                name: "text_input",
                description: "Input text using paste/keystroke strategy. risk_class/confirmation_token are accepted for backward compatibility but ignored.",
                inputSchema: ToolSchema(
                    required: ["text"],
                    properties: [
                        "text": .scalar(.string),
                        "mode": .enumString(["auto", "paste", "keystroke"]),
                        "window_id": .scalar(.integer),
                        "bundle_id": .scalar(.string),
                        "auto_focus": .scalar(.boolean),
                        "launch_if_needed": .scalar(.boolean),
                        "risk_class": .enumString(["low", "high"]),
                        "confirmation_token": .scalar(.string),
                    ]
                )
            ),
            ToolDefinition(
                name: "key_chord",
                description: "Execute a keyboard chord, optionally repeated. risk_class/confirmation_token are accepted for backward compatibility but ignored.",
                inputSchema: ToolSchema(
                    required: ["keys"],
                    properties: [
                        "keys": .array(of: .scalar(.string)),
                        "repeat": .scalar(.integer),
                        "window_id": .scalar(.integer),
                        "bundle_id": .scalar(.string),
                        "auto_focus": .scalar(.boolean),
                        "launch_if_needed": .scalar(.boolean),
                        "risk_class": .enumString(["low", "high"]),
                        "confirmation_token": .scalar(.string),
                    ]
                )
            ),
            ToolDefinition(
                name: "screen_capture",
                description: "Capture screen image; response image delivery is client-aware for Codex/Claude compatibility.",
                inputSchema: ToolSchema(
                    properties: [
                        "region": .object(required: ["x", "y", "width", "height"], properties: [
                            "x": .scalar(.number),
                            "y": .scalar(.number),
                            "width": .scalar(.number),
                            "height": .scalar(.number),
                        ]),
                        "format": .enumString(["png", "jpeg"]),
                        "quality": .scalar(.number),
                    ]
                )
            ),
            ToolDefinition(
                name: "app_launch",
                description: "Launch an app globally without mouse interaction.",
                inputSchema: ToolSchema(
                    properties: [
                        "bundle_id": .scalar(.string),
                        "app_name": .scalar(.string),
                        "activate": .scalar(.boolean),
                    ]
                )
            ),
            ToolDefinition(
                name: "app_open_url",
                description: "Open a URL globally using the system or a specific app.",
                inputSchema: ToolSchema(
                    required: ["url"],
                    properties: [
                        "url": .scalar(.string),
                        "bundle_id": .scalar(.string),
                        "activate": .scalar(.boolean),
                    ]
                )
            ),
            ToolDefinition(
                name: "app_open_path",
                description: "Open a local path globally using the system or a specific app.",
                inputSchema: ToolSchema(
                    required: ["path"],
                    properties: [
                        "path": .scalar(.string),
                        "bundle_id": .scalar(.string),
                        "activate": .scalar(.boolean),
                    ]
                )
            ),
            ToolDefinition(
                name: "app_quit",
                description: "Quit a running app globally without mouse interaction. risk_class/confirmation_token are accepted for backward compatibility but ignored.",
                inputSchema: ToolSchema(
                    required: ["bundle_id"],
                    properties: [
                        "bundle_id": .scalar(.string),
                        "risk_class": .enumString(["low", "high"]),
                        "confirmation_token": .scalar(.string),
                    ]
                )
            ),
            ToolDefinition(
                name: "applescript_run",
                description: "Run AppleScript via local broker app. risk_class/confirmation_token are accepted for backward compatibility but ignored.",
                inputSchema: ToolSchema(
                    required: ["script"],
                    properties: [
                        "script": .scalar(.string),
                        "target_bundle_id": .scalar(.string),
                        "risk_class": .enumString(["low", "high"]),
                        "confirmation_token": .scalar(.string),
                    ]
                )
            ),
            ToolDefinition(
                name: "applescript_app_command",
                description: "Run an AppleScript command inside a specific app via local broker app. risk_class/confirmation_token are accepted for backward compatibility but ignored.",
                inputSchema: ToolSchema(
                    required: ["command"],
                    properties: [
                        "bundle_id": .scalar(.string),
                        "app_name": .scalar(.string),
                        "command": .scalar(.string),
                        "activate": .scalar(.boolean),
                        "risk_class": .enumString(["low", "high"]),
                        "confirmation_token": .scalar(.string),
                    ]
                )
            ),
            ToolDefinition(
                name: "permissions_status",
                description: "Get local Accessibility/Screen Recording/Automation broker status.",
                inputSchema: ToolSchema()
            ),
            ToolDefinition(
                name: "permissions_probe_automation",
                description: "Probe Apple Events automation permission for a target app using a minimal broker-side script.",
                inputSchema: ToolSchema(
                    properties: [
                        "bundle_id": .scalar(.string),
                        "app_name": .scalar(.string),
                    ]
                )
            ),
            ToolDefinition(
                name: "permissions_open_settings",
                description: "Open System Settings Privacy section for accessibility, screen recording, or automation.",
                inputSchema: ToolSchema(
                    required: ["section"],
                    properties: [
                        "section": .enumString(["accessibility", "screen_recording", "automation"]),
                    ]
                )
            ),
            ToolDefinition(
                name: "automation_stop",
                description: "Cancel queued and in-flight automation actions.",
                inputSchema: ToolSchema()
            ),
        ]
    }
}
