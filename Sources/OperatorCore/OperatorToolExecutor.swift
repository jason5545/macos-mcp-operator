import AppKit
import BrokerCore
import AuditLogger
import AutomationCore
import ConfigStore
import CoreTypes
import Foundation
import MCPCore
import MacOSAdapters
import SafetyEngine

public actor OperatorToolExecutor: ToolExecutorProtocol {
    private let tools: [ToolDefinition]
    private let toolsByName: [String: ToolDefinition]

    private let configStore: ConfigStore
    private let auditLogger: AuditLogger
    private let safetyEngine: SafetyEngine
    private let automationQueue: AutomationQueue
    private let permissionChecker: PermissionChecking
    private let brokerClient: BrokerClientProtocol
    private let inputAdapter: InputAdapting
    private let windowAdapter: WindowAdapting
    private let captureAdapter: CaptureAdapting

    private struct InteractionTarget {
        let windowID: UInt32?
        let bundleID: String?
        let autoFocus: Bool
        let launchIfNeeded: Bool
    }

    public init(
        tools: [ToolDefinition] = ToolSchemas.allTools(),
        configStore: ConfigStore,
        auditLogger: AuditLogger,
        safetyEngine: SafetyEngine,
        automationQueue: AutomationQueue,
        permissionChecker: PermissionChecking,
        brokerClient: BrokerClientProtocol,
        inputAdapter: InputAdapting,
        windowAdapter: WindowAdapting,
        captureAdapter: CaptureAdapting
    ) {
        self.tools = tools
        self.toolsByName = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })
        self.configStore = configStore
        self.auditLogger = auditLogger
        self.safetyEngine = safetyEngine
        self.automationQueue = automationQueue
        self.permissionChecker = permissionChecker
        self.brokerClient = brokerClient
        self.inputAdapter = inputAdapter
        self.windowAdapter = windowAdapter
        self.captureAdapter = captureAdapter
    }

    public func listTools() async -> [ToolDefinition] {
        tools
    }

    public func callTool(name: String, arguments: JSONValue?) async throws -> ToolCallResult {
        guard let definition = toolsByName[name] else {
            throw MCPToolError.invalidParams("Unknown tool: \(name)")
        }

        let validationErrors = definition.inputSchema.validate(arguments: arguments)
        if !validationErrors.isEmpty {
            throw MCPToolError.invalidParams(validationErrors.joined(separator: "; "))
        }

        do {
            switch name {
            case "set_safety_mode":
                return try await handleSetSafetyMode(arguments)
            case "update_app_whitelist":
                return try await handleUpdateWhitelist(arguments)
            case "list_windows":
                return await handleListWindows(arguments)
            case "focus_window":
                return try await handleFocusWindow(arguments)
            case "mouse_move":
                return try await handleMouseMove(arguments)
            case "mouse_click":
                return try await handleMouseClick(arguments)
            case "mouse_drag":
                return try await handleMouseDrag(arguments)
            case "mouse_scroll":
                return try await handleMouseScroll(arguments)
            case "text_input":
                return try await handleTextInput(arguments)
            case "key_chord":
                return try await handleKeyChord(arguments)
            case "screen_capture":
                return try await handleScreenCapture(arguments)
            case "app_launch":
                return try await handleAppLaunch(arguments)
            case "app_open_url":
                return try await handleAppOpenURL(arguments)
            case "app_open_path":
                return try await handleAppOpenPath(arguments)
            case "app_quit":
                return try await handleAppQuit(arguments)
            case "applescript_run":
                return try await handleAppleScriptRun(arguments)
            case "applescript_app_command":
                return try await handleAppleScriptAppCommand(arguments)
            case "permissions_status":
                return try await handlePermissionsStatus()
            case "permissions_probe_automation":
                return try await handlePermissionsProbeAutomation(arguments)
            case "permissions_open_settings":
                return try await handlePermissionsOpenSettings(arguments)
            case "automation_stop":
                return await handleAutomationStop()
            default:
                throw MCPToolError.invalidParams("Tool not implemented: \(name)")
            }
        } catch let error as MCPToolError {
            throw error
        } catch {
            throw MCPToolError.executionFailed(error.localizedDescription)
        }
    }

    private func handleSetSafetyMode(_ arguments: JSONValue?) async throws -> ToolCallResult {
        let modeRaw = try requiredString(arguments, key: "mode")
        guard let mode = SafetyMode(rawValue: modeRaw) else {
            throw MCPToolError.invalidParams("mode must be restricted or full_auto")
        }
        let persistRequested = optionalBool(arguments, key: "persist") ?? false

        let structured: JSONValue = .object([
            "mode": .string((try await configStore.load()).defaultMode.rawValue),
            "requested_mode": .string(mode.rawValue),
            "persist_requested": .bool(persistRequested),
            "deprecated": .bool(true),
            "approval_flow_disabled": .bool(true),
        ])

        await auditLogger.log(
            AuditEvent(
                tool: "set_safety_mode",
                targetBundleID: nil,
                status: .executed,
                message: "set_safety_mode is deprecated and is now a no-op",
                metadata: ["requested_mode": mode.rawValue, "persist_requested": String(persistRequested)]
            )
        )

        return ToolCallResult(
            structuredContent: structured,
            text: "approval flow disabled; set_safety_mode is deprecated no-op",
            isError: false
        )
    }

    private func handleUpdateWhitelist(_ arguments: JSONValue?) async throws -> ToolCallResult {
        let operation = try requiredString(arguments, key: "operation")
        _ = try requiredStringArray(arguments, key: "bundle_ids")

        let effective = (try await configStore.load()).appWhitelist

        await auditLogger.log(
            AuditEvent(
                tool: "update_app_whitelist",
                targetBundleID: nil,
                status: .executed,
                message: "update_app_whitelist is deprecated and is now a no-op",
                metadata: ["operation": operation]
            )
        )

        return ToolCallResult(
            structuredContent: .object([
                "effective_whitelist": .array(effective.map(JSONValue.string)),
                "deprecated": .bool(true),
                "approval_flow_disabled": .bool(true),
            ]),
            text: "approval flow disabled; update_app_whitelist is deprecated no-op",
            isError: false
        )
    }

    private func handleListWindows(_ arguments: JSONValue?) async -> ToolCallResult {
        let includeMinimized = optionalBool(arguments, key: "include_minimized") ?? false
        let windows = await windowAdapter.listWindows(includeMinimized: includeMinimized)
        let payload = windows.map(windowToJSON)

        return ToolCallResult(
            structuredContent: .object([
                "windows": .array(payload),
            ]),
            text: "Listed \(windows.count) windows",
            isError: false
        )
    }

    private func handleFocusWindow(_ arguments: JSONValue?) async throws -> ToolCallResult {
        let windowID: UInt32?
        if let rawWindowID = optionalInt(arguments, key: "window_id") {
            windowID = UInt32(rawWindowID)
        } else {
            windowID = nil
        }

        let bundleID = optionalString(arguments, key: "bundle_id")
        let launchIfNeeded = optionalBool(arguments, key: "launch_if_needed") ?? false
        let activateAllWindows = optionalBool(arguments, key: "activate_all_windows") ?? false

        guard windowID != nil || bundleID != nil else {
            throw MCPToolError.invalidParams("focus_window requires window_id or bundle_id")
        }

        let targetBundle: String?
        if let bundleID {
            targetBundle = bundleID
        } else {
            targetBundle = await bundleIDForWindow(windowID)
        }
        let decision = await evaluateSafety(
            toolName: "focus_window",
            riskClass: .low,
            confirmationToken: nil,
            targetBundleID: targetBundle,
            arguments: [
                "window_id": windowID.map(String.init) ?? "",
                "bundle_id": bundleID ?? "",
                "launch_if_needed": String(launchIfNeeded),
                "activate_all_windows": String(activateAllWindows),
            ]
        )

        if let decisionResult = decision {
            return decisionResult
        }

        let receipt = try await automationQueue.enqueue(label: "focus_window") {
            let focusedBundle = try await self.windowAdapter.focusWindow(
                windowID: windowID,
                bundleID: bundleID,
                launchIfNeeded: launchIfNeeded,
                activateAllWindows: activateAllWindows
            )

            return ActionReceipt(
                actionID: "",
                status: .executed,
                message: "Window focused",
                data: ["bundle_id": focusedBundle ?? ""]
            )
        }

        await auditLogger.log(
            AuditEvent(
                tool: "focus_window",
                targetBundleID: targetBundle,
                status: receipt.status,
                message: receipt.message,
                metadata: ["bundle_id": targetBundle ?? ""]
            )
        )

        return receiptResult(receipt)
    }

    private func handleMouseMove(_ arguments: JSONValue?) async throws -> ToolCallResult {
        try ensureAccessibilityPermission()

        let x = try requiredDouble(arguments, key: "x")
        let y = try requiredDouble(arguments, key: "y")
        let durationMS = optionalInt(arguments, key: "duration_ms") ?? 0
        let targetBundle = await windowAdapter.frontmostBundleID()

        let decision = await evaluateSafety(
            toolName: "mouse_move",
            riskClass: .low,
            confirmationToken: nil,
            targetBundleID: targetBundle,
            arguments: [
                "x": String(x),
                "y": String(y),
                "duration_ms": String(durationMS),
            ]
        )
        if let decision {
            return decision
        }

        let receipt = try await automationQueue.enqueue(label: "mouse_move") {
            try await self.inputAdapter.moveMouse(x: x, y: y, durationMS: durationMS)
            return ActionReceipt(actionID: "", status: .executed, message: "Mouse moved")
        }

        await auditLogger.log(
            AuditEvent(
                tool: "mouse_move",
                targetBundleID: targetBundle,
                status: receipt.status,
                message: receipt.message,
                metadata: ["x": String(x), "y": String(y)]
            )
        )

        return receiptResult(receipt)
    }

    private func handleMouseClick(_ arguments: JSONValue?) async throws -> ToolCallResult {
        try ensureAccessibilityPermission()

        let x = try requiredDouble(arguments, key: "x")
        let y = try requiredDouble(arguments, key: "y")
        let button = MouseButton(rawValue: optionalString(arguments, key: "button") ?? "left") ?? .left
        let clickCount = optionalInt(arguments, key: "click_count") ?? 1
        let riskClass = RiskClass(rawValue: optionalString(arguments, key: "risk_class") ?? "low") ?? .low
        let confirmationToken = optionalString(arguments, key: "confirmation_token")
        let targetBundle = try await resolveTargetBundleForInteraction(arguments, toolName: "mouse_click")

        let decision = await evaluateSafety(
            toolName: "mouse_click",
            riskClass: riskClass,
            confirmationToken: confirmationToken,
            targetBundleID: targetBundle,
            arguments: [
                "x": String(x),
                "y": String(y),
                "button": button.rawValue,
                "click_count": String(clickCount),
                "window_id": optionalInt(arguments, key: "window_id").map(String.init) ?? "",
                "bundle_id": optionalString(arguments, key: "bundle_id") ?? "",
                "auto_focus": String(optionalBool(arguments, key: "auto_focus") ?? false),
                "launch_if_needed": String(optionalBool(arguments, key: "launch_if_needed") ?? false),
            ]
        )

        if let decision {
            return decision
        }

        let receipt = try await automationQueue.enqueue(label: "mouse_click") {
            try await self.inputAdapter.clickMouse(x: x, y: y, button: button, clickCount: clickCount)
            return ActionReceipt(actionID: "", status: .executed, message: "Mouse click executed")
        }

        await auditLogger.log(
            AuditEvent(
                tool: "mouse_click",
                targetBundleID: targetBundle,
                status: receipt.status,
                message: receipt.message,
                metadata: ["button": button.rawValue, "click_count": String(clickCount)]
            )
        )

        return receiptResult(receipt)
    }

    private func handleMouseDrag(_ arguments: JSONValue?) async throws -> ToolCallResult {
        try ensureAccessibilityPermission()

        let fromX = try requiredDouble(arguments, key: "from_x")
        let fromY = try requiredDouble(arguments, key: "from_y")
        let toX = try requiredDouble(arguments, key: "to_x")
        let toY = try requiredDouble(arguments, key: "to_y")
        let durationMS = optionalInt(arguments, key: "duration_ms") ?? 150
        let riskClass = RiskClass(rawValue: optionalString(arguments, key: "risk_class") ?? "low") ?? .low
        let confirmationToken = optionalString(arguments, key: "confirmation_token")
        let targetBundle = try await resolveTargetBundleForInteraction(arguments, toolName: "mouse_drag")

        let decision = await evaluateSafety(
            toolName: "mouse_drag",
            riskClass: riskClass,
            confirmationToken: confirmationToken,
            targetBundleID: targetBundle,
            arguments: [
                "from_x": String(fromX),
                "from_y": String(fromY),
                "to_x": String(toX),
                "to_y": String(toY),
                "duration_ms": String(durationMS),
                "window_id": optionalInt(arguments, key: "window_id").map(String.init) ?? "",
                "bundle_id": optionalString(arguments, key: "bundle_id") ?? "",
                "auto_focus": String(optionalBool(arguments, key: "auto_focus") ?? false),
                "launch_if_needed": String(optionalBool(arguments, key: "launch_if_needed") ?? false),
            ]
        )
        if let decision {
            return decision
        }

        let receipt = try await automationQueue.enqueue(label: "mouse_drag") {
            try await self.inputAdapter.dragMouse(fromX: fromX, fromY: fromY, toX: toX, toY: toY, durationMS: durationMS)
            return ActionReceipt(actionID: "", status: .executed, message: "Mouse drag executed")
        }

        await auditLogger.log(
            AuditEvent(
                tool: "mouse_drag",
                targetBundleID: targetBundle,
                status: receipt.status,
                message: receipt.message,
                metadata: ["from": "\(fromX),\(fromY)", "to": "\(toX),\(toY)"]
            )
        )

        return receiptResult(receipt)
    }

    private func handleMouseScroll(_ arguments: JSONValue?) async throws -> ToolCallResult {
        try ensureAccessibilityPermission()

        let deltaX = try requiredDouble(arguments, key: "delta_x")
        let deltaY = try requiredDouble(arguments, key: "delta_y")
        let riskClass = RiskClass(rawValue: optionalString(arguments, key: "risk_class") ?? "low") ?? .low
        let confirmationToken = optionalString(arguments, key: "confirmation_token")
        let targetBundle = try await resolveTargetBundleForInteraction(arguments, toolName: "mouse_scroll")

        let decision = await evaluateSafety(
            toolName: "mouse_scroll",
            riskClass: riskClass,
            confirmationToken: confirmationToken,
            targetBundleID: targetBundle,
            arguments: [
                "delta_x": String(deltaX),
                "delta_y": String(deltaY),
                "window_id": optionalInt(arguments, key: "window_id").map(String.init) ?? "",
                "bundle_id": optionalString(arguments, key: "bundle_id") ?? "",
                "auto_focus": String(optionalBool(arguments, key: "auto_focus") ?? false),
                "launch_if_needed": String(optionalBool(arguments, key: "launch_if_needed") ?? false),
            ]
        )
        if let decision {
            return decision
        }

        let receipt = try await automationQueue.enqueue(label: "mouse_scroll") {
            try await self.inputAdapter.scroll(deltaX: deltaX, deltaY: deltaY)
            return ActionReceipt(actionID: "", status: .executed, message: "Scroll executed")
        }

        await auditLogger.log(
            AuditEvent(
                tool: "mouse_scroll",
                targetBundleID: targetBundle,
                status: receipt.status,
                message: receipt.message,
                metadata: ["delta_x": String(deltaX), "delta_y": String(deltaY)]
            )
        )

        return receiptResult(receipt)
    }

    private func handleTextInput(_ arguments: JSONValue?) async throws -> ToolCallResult {
        try ensureAccessibilityPermission()

        let text = try requiredString(arguments, key: "text")
        let mode = TextInputMode(rawValue: optionalString(arguments, key: "mode") ?? "auto") ?? .auto
        let riskClass = RiskClass(rawValue: optionalString(arguments, key: "risk_class") ?? "low") ?? .low
        let confirmationToken = optionalString(arguments, key: "confirmation_token")
        let targetBundle = try await resolveTargetBundleForInteraction(arguments, toolName: "text_input")

        let decision = await evaluateSafety(
            toolName: "text_input",
            riskClass: riskClass,
            confirmationToken: confirmationToken,
            targetBundleID: targetBundle,
            arguments: [
                "text": text,
                "mode": mode.rawValue,
                "window_id": optionalInt(arguments, key: "window_id").map(String.init) ?? "",
                "bundle_id": optionalString(arguments, key: "bundle_id") ?? "",
                "auto_focus": String(optionalBool(arguments, key: "auto_focus") ?? false),
                "launch_if_needed": String(optionalBool(arguments, key: "launch_if_needed") ?? false),
            ]
        )
        if let decision {
            return decision
        }

        let receipt = try await automationQueue.enqueue(label: "text_input") {
            try await self.inputAdapter.textInput(text, mode: mode)
            return ActionReceipt(actionID: "", status: .executed, message: "Text input executed")
        }

        await auditLogger.log(
            AuditEvent(
                tool: "text_input",
                targetBundleID: targetBundle,
                status: receipt.status,
                message: receipt.message,
                metadata: ["mode": mode.rawValue, "text": text]
            )
        )

        return receiptResult(receipt)
    }

    private func handleKeyChord(_ arguments: JSONValue?) async throws -> ToolCallResult {
        try ensureAccessibilityPermission()

        let keys = try requiredStringArray(arguments, key: "keys")
        let repeatCount = optionalInt(arguments, key: "repeat") ?? 1
        let incomingRisk = RiskClass(rawValue: optionalString(arguments, key: "risk_class") ?? "low") ?? .low
        let confirmationToken = optionalString(arguments, key: "confirmation_token")

        let config = try await configStore.load()
        let normalizedDangerous = Set(config.dangerousKeyChords.map(normalizeKeyChord))
        let normalizedCurrent = normalizeKeyChord(keys)
        let riskClass: RiskClass = normalizedDangerous.contains(normalizedCurrent) ? .high : incomingRisk

        let targetBundle = try await resolveTargetBundleForInteraction(arguments, toolName: "key_chord")
        let decision = await evaluateSafety(
            toolName: "key_chord",
            riskClass: riskClass,
            confirmationToken: confirmationToken,
            targetBundleID: targetBundle,
            arguments: [
                "keys": normalizedCurrent,
                "repeat": String(repeatCount),
                "window_id": optionalInt(arguments, key: "window_id").map(String.init) ?? "",
                "bundle_id": optionalString(arguments, key: "bundle_id") ?? "",
                "auto_focus": String(optionalBool(arguments, key: "auto_focus") ?? false),
                "launch_if_needed": String(optionalBool(arguments, key: "launch_if_needed") ?? false),
            ]
        )
        if let decision {
            return decision
        }

        let receipt = try await automationQueue.enqueue(label: "key_chord") {
            try await self.inputAdapter.keyChord(keys: keys, repeatCount: repeatCount)
            return ActionReceipt(actionID: "", status: .executed, message: "Key chord executed")
        }

        await auditLogger.log(
            AuditEvent(
                tool: "key_chord",
                targetBundleID: targetBundle,
                status: receipt.status,
                message: receipt.message,
                metadata: ["keys": normalizedCurrent, "repeat": String(repeatCount)]
            )
        )

        return receiptResult(receipt)
    }

    private func handleScreenCapture(_ arguments: JSONValue?) async throws -> ToolCallResult {
        if !permissionChecker.hasScreenRecordingPermission(prompt: false) {
            _ = permissionChecker.hasScreenRecordingPermission(prompt: true)
        }
        guard permissionChecker.hasScreenRecordingPermission(prompt: false) else {
            let message = "SCREEN_RECORDING_MISSING: Enable permission in System Settings > Privacy & Security > Screen Recording."
            return ToolCallResult(
                structuredContent: .object([
                    "error": .string(message),
                ]),
                text: message,
                isError: true
            )
        }

        let explicitFormat = optionalString(arguments, key: "format")
        let rawQuality = optionalDouble(arguments, key: "quality")

        if let f = explicitFormat, f != "png" && f != "jpeg" {
            throw MCPToolError.invalidParams("format must be png or jpeg")
        }

        // Determine effective quality (nil = PNG, non-nil = JPEG)
        let effectiveQuality: Double?
        if explicitFormat == "jpeg" {
            effectiveQuality = rawQuality ?? 0.7
        } else if explicitFormat == "png" {
            effectiveQuality = nil // PNG is lossless, ignore quality
        } else if let q = rawQuality {
            effectiveQuality = q // No format specified + quality given → auto JPEG
        } else {
            effectiveQuality = 0.7 // No format, no quality → JPEG with default quality
        }

        let region: CaptureRegion?
        if let regionObject = arguments?.objectValue?["region"]?.objectValue {
            let x = try requiredDouble(regionObject, key: "x")
            let y = try requiredDouble(regionObject, key: "y")
            let width = try requiredDouble(regionObject, key: "width")
            let height = try requiredDouble(regionObject, key: "height")
            region = CaptureRegion(x: x, y: y, width: width, height: height)
        } else {
            region = nil
        }

        let result = try await captureAdapter.capture(region: region, quality: effectiveQuality)
        await auditLogger.log(
            AuditEvent(
                tool: "screen_capture",
                targetBundleID: await windowAdapter.frontmostBundleID(),
                status: .executed,
                message: "Screen captured",
                metadata: ["width": String(result.width), "height": String(result.height)]
            )
        )

        let mimeType = result.format == "jpeg" ? "image/jpeg" : "image/png"

        return ToolCallResult(
            structuredContent: .object([
                "format": .string(result.format),
                "width": .number(Double(result.width)),
                "height": .number(Double(result.height)),
            ]),
            text: "Captured screen image \(result.width)x\(result.height)",
            isError: false,
            imageBase64: result.imageBase64,
            imageMimeType: mimeType
        )
    }

    private func handleAppLaunch(_ arguments: JSONValue?) async throws -> ToolCallResult {
        let bundleID = optionalString(arguments, key: "bundle_id")
        let appName = optionalString(arguments, key: "app_name")
        let activate = optionalBool(arguments, key: "activate") ?? false

        guard bundleID != nil || appName != nil else {
            throw MCPToolError.invalidParams("app_launch requires bundle_id or app_name")
        }

        let decision = await evaluateSafety(
            toolName: "app_launch",
            riskClass: .low,
            confirmationToken: nil,
            targetBundleID: bundleID,
            arguments: [
                "bundle_id": bundleID ?? "",
                "app_name": appName ?? "",
                "activate": String(activate),
            ]
        )
        if let decision {
            return decision
        }

        let receipt = try await automationQueue.enqueue(label: "app_launch") {
            var openArgs: [String] = []
            if !activate {
                openArgs.append("-g")
            }
            if let bundleID {
                openArgs += ["-b", bundleID]
            } else if let appName {
                openArgs += ["-a", appName]
            }
            try self.runOpenCommand(arguments: openArgs)

            return ActionReceipt(
                actionID: "",
                status: .executed,
                message: "App launched",
                data: ["bundle_id": bundleID ?? "", "app_name": appName ?? ""]
            )
        }

        await auditLogger.log(
            AuditEvent(
                tool: "app_launch",
                targetBundleID: bundleID,
                status: receipt.status,
                message: receipt.message,
                metadata: ["bundle_id": bundleID ?? "", "app_name": appName ?? "", "activate": String(activate)]
            )
        )

        return receiptResult(receipt)
    }

    private func handleAppOpenURL(_ arguments: JSONValue?) async throws -> ToolCallResult {
        let urlString = try requiredString(arguments, key: "url")
        guard let url = URL(string: urlString), let scheme = url.scheme, !scheme.isEmpty else {
            throw MCPToolError.invalidParams("url must be an absolute URL")
        }

        let bundleID = optionalString(arguments, key: "bundle_id")
        let activate = optionalBool(arguments, key: "activate") ?? false

        let decision = await evaluateSafety(
            toolName: "app_open_url",
            riskClass: .low,
            confirmationToken: nil,
            targetBundleID: bundleID,
            arguments: [
                "url": urlString,
                "bundle_id": bundleID ?? "",
                "activate": String(activate),
            ]
        )
        if let decision {
            return decision
        }

        let receipt = try await automationQueue.enqueue(label: "app_open_url") {
            var openArgs: [String] = []
            if !activate {
                openArgs.append("-g")
            }
            if let bundleID {
                openArgs += ["-b", bundleID]
            }
            openArgs.append(urlString)
            try self.runOpenCommand(arguments: openArgs)

            return ActionReceipt(
                actionID: "",
                status: .executed,
                message: "URL opened",
                data: ["url": urlString, "bundle_id": bundleID ?? ""]
            )
        }

        await auditLogger.log(
            AuditEvent(
                tool: "app_open_url",
                targetBundleID: bundleID,
                status: receipt.status,
                message: receipt.message,
                metadata: ["url": urlString, "bundle_id": bundleID ?? "", "activate": String(activate)]
            )
        )

        return receiptResult(receipt)
    }

    private func handleAppOpenPath(_ arguments: JSONValue?) async throws -> ToolCallResult {
        let path = try requiredString(arguments, key: "path")
        let bundleID = optionalString(arguments, key: "bundle_id")
        let activate = optionalBool(arguments, key: "activate") ?? false

        let expandedPath = NSString(string: path).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expandedPath) else {
            throw MCPToolError.invalidParams("path does not exist: \(path)")
        }

        let decision = await evaluateSafety(
            toolName: "app_open_path",
            riskClass: .low,
            confirmationToken: nil,
            targetBundleID: bundleID,
            arguments: [
                "path": expandedPath,
                "bundle_id": bundleID ?? "",
                "activate": String(activate),
            ]
        )
        if let decision {
            return decision
        }

        let receipt = try await automationQueue.enqueue(label: "app_open_path") {
            var openArgs: [String] = []
            if !activate {
                openArgs.append("-g")
            }
            if let bundleID {
                openArgs += ["-b", bundleID]
            }
            openArgs.append(expandedPath)
            try self.runOpenCommand(arguments: openArgs)

            return ActionReceipt(
                actionID: "",
                status: .executed,
                message: "Path opened",
                data: ["path": expandedPath, "bundle_id": bundleID ?? ""]
            )
        }

        await auditLogger.log(
            AuditEvent(
                tool: "app_open_path",
                targetBundleID: bundleID,
                status: receipt.status,
                message: receipt.message,
                metadata: ["path": expandedPath, "bundle_id": bundleID ?? "", "activate": String(activate)]
            )
        )

        return receiptResult(receipt)
    }

    private func handleAppQuit(_ arguments: JSONValue?) async throws -> ToolCallResult {
        let bundleID = try requiredString(arguments, key: "bundle_id")
        let riskClass = RiskClass(rawValue: optionalString(arguments, key: "risk_class") ?? "high") ?? .high
        let confirmationToken = optionalString(arguments, key: "confirmation_token")

        let decision = await evaluateSafety(
            toolName: "app_quit",
            riskClass: riskClass,
            confirmationToken: confirmationToken,
            targetBundleID: bundleID,
            arguments: ["bundle_id": bundleID]
        )
        if let decision {
            return decision
        }

        let receipt = try await automationQueue.enqueue(label: "app_quit") {
            let apps = await MainActor.run {
                NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            }
            guard !apps.isEmpty else {
                throw OperatorError("No running app found for bundle id \(bundleID)")
            }

            await MainActor.run {
                for app in apps {
                    if !app.terminate() {
                        app.forceTerminate()
                    }
                }
            }

            return ActionReceipt(
                actionID: "",
                status: .executed,
                message: "App quit requested",
                data: ["bundle_id": bundleID, "count": String(apps.count)]
            )
        }

        await auditLogger.log(
            AuditEvent(
                tool: "app_quit",
                targetBundleID: bundleID,
                status: receipt.status,
                message: receipt.message,
                metadata: ["bundle_id": bundleID]
            )
        )

        return receiptResult(receipt)
    }

    private func handleAppleScriptRun(_ arguments: JSONValue?) async throws -> ToolCallResult {
        let script = try requiredString(arguments, key: "script")
        let targetBundleID = optionalString(arguments, key: "target_bundle_id")

        let decision = await evaluateSafety(
            toolName: "applescript_run",
            riskClass: .low,
            confirmationToken: nil,
            targetBundleID: targetBundleID,
            arguments: [
                "script": script,
                "target_bundle_id": targetBundleID ?? "",
            ]
        )
        if let decision {
            return decision
        }

        let receipt = try await automationQueue.enqueue(label: "applescript_run") {
            let result = try await self.brokerClient.runAppleScript(script: script, targetBundleID: targetBundleID)
            return ActionReceipt(
                actionID: "",
                status: .executed,
                message: "AppleScript executed",
                data: [
                    "stdout": result.stdout ?? "",
                    "stderr": result.stderr ?? "",
                    "target_bundle_id": targetBundleID ?? "",
                ]
            )
        }

        await auditLogger.log(
            AuditEvent(
                tool: "applescript_run",
                targetBundleID: targetBundleID,
                status: receipt.status,
                message: receipt.message,
                metadata: ["target_bundle_id": targetBundleID ?? ""]
            )
        )

        return receiptResult(receipt)
    }

    private func handleAppleScriptAppCommand(_ arguments: JSONValue?) async throws -> ToolCallResult {
        let bundleID = optionalString(arguments, key: "bundle_id")
        let appName = optionalString(arguments, key: "app_name")
        let command = try requiredString(arguments, key: "command")
        let activate = optionalBool(arguments, key: "activate") ?? false

        guard bundleID != nil || appName != nil else {
            throw MCPToolError.invalidParams("applescript_app_command requires bundle_id or app_name")
        }

        let targetBundle = bundleID
        let decision = await evaluateSafety(
            toolName: "applescript_app_command",
            riskClass: .low,
            confirmationToken: nil,
            targetBundleID: targetBundle,
            arguments: [
                "bundle_id": bundleID ?? "",
                "app_name": appName ?? "",
                "command": command,
                "activate": String(activate),
            ]
        )
        if let decision {
            return decision
        }

        let receipt = try await automationQueue.enqueue(label: "applescript_app_command") {
            let result = try await self.brokerClient.runAppleScriptAppCommand(
                bundleID: bundleID,
                appName: appName,
                command: command,
                activate: activate
            )
            return ActionReceipt(
                actionID: "",
                status: .executed,
                message: "AppleScript app command executed",
                data: [
                    "bundle_id": bundleID ?? "",
                    "app_name": appName ?? "",
                    "stdout": result.stdout ?? "",
                    "stderr": result.stderr ?? "",
                ]
            )
        }

        await auditLogger.log(
            AuditEvent(
                tool: "applescript_app_command",
                targetBundleID: targetBundle,
                status: receipt.status,
                message: receipt.message,
                metadata: [
                    "bundle_id": bundleID ?? "",
                    "app_name": appName ?? "",
                    "activate": String(activate),
                ]
            )
        )

        return receiptResult(receipt)
    }

    private func handlePermissionsStatus() async throws -> ToolCallResult {
        let config = try await configStore.load()
        let accessibility = permissionChecker.hasAccessibilityPermission(prompt: false)
        let screenRecording = permissionChecker.hasScreenRecordingPermission(prompt: false)
        let brokerRunning = await brokerClient.health(autostart: false)
        let identity = try await brokerClient.identity()

        let structured: JSONValue = .object([
            "accessibility": .bool(accessibility),
            "screen_recording": .bool(screenRecording),
            "broker_running": .bool(brokerRunning),
            "broker_identity": .object([
                "bundle_id": .string(identity.bundleID),
                "path": .string(identity.path),
                "signed": .bool(identity.signed),
            ]),
            "automation_known_targets": .array(config.sensitiveBundleIDs.map(JSONValue.string)),
        ])

        return ToolCallResult(
            structuredContent: structured,
            text: "Collected local permission status",
            isError: false
        )
    }

    private func handlePermissionsProbeAutomation(_ arguments: JSONValue?) async throws -> ToolCallResult {
        let bundleID = optionalString(arguments, key: "bundle_id")
        let appName = optionalString(arguments, key: "app_name")

        guard bundleID != nil || appName != nil else {
            throw MCPToolError.invalidParams("permissions_probe_automation requires bundle_id or app_name")
        }

        let probe = try await brokerClient.probeAutomation(bundleID: bundleID, appName: appName)
        let structured: JSONValue = .object([
            "status": .string(probe.status.rawValue),
            "error_code": probe.errorCode.map { .string($0.rawValue) } ?? .null,
            "message": .string(probe.message),
            "remediation": .array(probe.remediation.map(JSONValue.string)),
        ])

        return ToolCallResult(
            structuredContent: structured,
            text: probe.message,
            isError: probe.status == .error
        )
    }

    private func handlePermissionsOpenSettings(_ arguments: JSONValue?) async throws -> ToolCallResult {
        let section = try requiredString(arguments, key: "section")
        let url: String
        switch section {
        case "accessibility":
            url = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case "screen_recording":
            url = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case "automation":
            url = "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        default:
            throw MCPToolError.invalidParams("section must be accessibility|screen_recording|automation")
        }

        let receipt = try await automationQueue.enqueue(label: "permissions_open_settings") {
            try self.runOpenCommand(arguments: [url])
            return ActionReceipt(
                actionID: "",
                status: .executed,
                message: "Opened System Settings section \(section)",
                data: ["section": section]
            )
        }

        return receiptResult(receipt)
    }

    private func handleAutomationStop() async -> ToolCallResult {
        let queueCancelledActions = await automationQueue.stopAll()
        let brokerCancelledActions = await brokerClient.stopActive()
        let cancelledActions = queueCancelledActions + brokerCancelledActions
        let structured: JSONValue = .object([
            "stopped": .bool(true),
            "cancelled_actions": .number(Double(cancelledActions)),
            "queue_cancelled_actions": .number(Double(queueCancelledActions)),
            "broker_cancelled_actions": .number(Double(brokerCancelledActions)),
        ])

        await auditLogger.log(
            AuditEvent(
                tool: "automation_stop",
                targetBundleID: nil,
                status: .executed,
                message: "automation_stop called",
                metadata: [
                    "cancelled_actions": String(cancelledActions),
                    "queue_cancelled_actions": String(queueCancelledActions),
                    "broker_cancelled_actions": String(brokerCancelledActions),
                ]
            )
        )

        return ToolCallResult(
            structuredContent: structured,
            text: "Stopped automation queue; cancelled actions: \(cancelledActions)",
            isError: false
        )
    }

    private func evaluateSafety(
        toolName: String,
        riskClass: RiskClass,
        confirmationToken: String?,
        targetBundleID: String?,
        arguments: [String: String]
    ) async -> ToolCallResult? {
        let fingerprint = await safetyEngine.makeFingerprint(toolName: toolName, arguments: arguments)
        let decision = await safetyEngine.evaluate(
            toolName: toolName,
            riskClass: riskClass,
            targetBundleID: targetBundleID,
            confirmationToken: confirmationToken,
            argumentsFingerprint: fingerprint
        )

        switch decision {
        case .allow:
            return nil
        case .reject(let message):
            let receipt = ActionReceipt(
                actionID: UUID().uuidString,
                status: .rejected,
                message: message
            )
            return receiptResult(receipt, isError: true)
        }
    }

    private func ensureAccessibilityPermission() throws {
        if !permissionChecker.hasAccessibilityPermission(prompt: false) {
            _ = permissionChecker.hasAccessibilityPermission(prompt: true)
        }
        guard permissionChecker.hasAccessibilityPermission(prompt: false) else {
            throw MCPToolError.executionFailed(
                "ACCESSIBILITY_MISSING: Enable permission in System Settings > Privacy & Security > Accessibility."
            )
        }
    }

    private func receiptResult(_ receipt: ActionReceipt, isError: Bool = false) -> ToolCallResult {
        let payload: JSONValue = .object([
            "action_id": .string(receipt.actionID),
            "status": .string(receipt.status.rawValue),
            "message": .string(receipt.message),
            "confirmation_token": receipt.confirmationToken.map(JSONValue.string) ?? .null,
            "expires_at": receipt.expiresAt.map { .string(ISO8601DateFormatter().string(from: $0)) } ?? .null,
            "data": .object(receipt.data?.reduce(into: [String: JSONValue]()) { partialResult, pair in
                partialResult[pair.key] = .string(pair.value)
            } ?? [:]),
        ])

        return ToolCallResult(structuredContent: payload, text: receipt.message, isError: isError)
    }

    private func windowToJSON(_ window: WindowDescriptor) -> JSONValue {
        .object([
            "window_id": .number(Double(window.windowID)),
            "bundle_id": window.bundleID.map(JSONValue.string) ?? .null,
            "app_name": .string(window.appName),
            "title": .string(window.title),
            "frame": .object([
                "x": .number(window.frame.x),
                "y": .number(window.frame.y),
                "width": .number(window.frame.width),
                "height": .number(window.frame.height),
            ]),
            "is_focused": .bool(window.isFocused),
        ])
    }

    private func bundleIDForWindow(_ windowID: UInt32?) async -> String? {
        guard let windowID else { return nil }
        let windows = await windowAdapter.listWindows(includeMinimized: true)
        return windows.first(where: { $0.windowID == windowID })?.bundleID
    }

    private func resolveTargetBundleForInteraction(_ arguments: JSONValue?, toolName: String) async throws -> String? {
        let target = parseInteractionTarget(arguments)
        let frontmostBundle = await windowAdapter.frontmostBundleID()

        guard target.windowID != nil || target.bundleID != nil else {
            return frontmostBundle
        }

        let targetBundle: String?
        if let bundleID = target.bundleID {
            targetBundle = bundleID
        } else {
            targetBundle = await bundleIDForWindow(target.windowID)
        }
        guard let targetBundle else {
            throw MCPToolError.executionFailed("TARGET_UNRESOLVED: unable to resolve target bundle for \(toolName)")
        }

        if frontmostBundle == targetBundle {
            return targetBundle
        }

        guard target.autoFocus else {
            throw MCPToolError.executionFailed(
                "TARGET_NOT_FRONTMOST: \(targetBundle) is not frontmost. Set auto_focus=true to focus before \(toolName)."
            )
        }

        _ = try await windowAdapter.focusWindow(
            windowID: target.windowID,
            bundleID: target.bundleID,
            launchIfNeeded: target.launchIfNeeded,
            activateAllWindows: false
        )

        return await windowAdapter.frontmostBundleID() ?? targetBundle
    }

    private func parseInteractionTarget(_ arguments: JSONValue?) -> InteractionTarget {
        let windowID = optionalInt(arguments, key: "window_id").map(UInt32.init)
        let bundleID = optionalString(arguments, key: "bundle_id")
        let autoFocus = optionalBool(arguments, key: "auto_focus") ?? false
        let launchIfNeeded = optionalBool(arguments, key: "launch_if_needed") ?? false

        return InteractionTarget(
            windowID: windowID,
            bundleID: bundleID,
            autoFocus: autoFocus,
            launchIfNeeded: launchIfNeeded
        )
    }

    private func normalizeKeyChord(_ keys: [String]) -> String {
        keys.map { $0.lowercased() }.sorted().joined(separator: "+")
    }

    private func requiredString(_ arguments: JSONValue?, key: String) throws -> String {
        guard let value = arguments?.objectValue?[key]?.stringValue else {
            throw MCPToolError.invalidParams("\(key) is required")
        }
        return value
    }

    private func optionalString(_ arguments: JSONValue?, key: String) -> String? {
        arguments?.objectValue?[key]?.stringValue
    }

    private func optionalBool(_ arguments: JSONValue?, key: String) -> Bool? {
        arguments?.objectValue?[key]?.boolValue
    }

    private func optionalInt(_ arguments: JSONValue?, key: String) -> Int? {
        arguments?.objectValue?[key]?.intValue
    }

    private func optionalDouble(_ arguments: JSONValue?, key: String) -> Double? {
        arguments?.objectValue?[key]?.doubleValue
    }

    private func requiredDouble(_ arguments: JSONValue?, key: String) throws -> Double {
        guard let value = arguments?.objectValue?[key]?.doubleValue else {
            throw MCPToolError.invalidParams("\(key) is required")
        }
        return value
    }

    private func requiredDouble(_ object: [String: JSONValue], key: String) throws -> Double {
        guard let value = object[key]?.doubleValue else {
            throw MCPToolError.invalidParams("\(key) is required")
        }
        return value
    }

    private func requiredStringArray(_ arguments: JSONValue?, key: String) throws -> [String] {
        guard let values = arguments?.objectValue?[key]?.arrayValue else {
            throw MCPToolError.invalidParams("\(key) is required")
        }
        let strings = values.compactMap { $0.stringValue }
        guard strings.count == values.count else {
            throw MCPToolError.invalidParams("\(key) must be an array of strings")
        }
        return strings
    }

    private nonisolated func runOpenCommand(arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = arguments
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw OperatorError("open command failed with status \(process.terminationStatus)")
        }
    }
}
