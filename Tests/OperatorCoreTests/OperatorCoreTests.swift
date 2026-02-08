import XCTest
@testable import AuditLogger
@testable import AutomationCore
@testable import BrokerCore
@testable import ConfigStore
@testable import CoreTypes
@testable import MCPCore
@testable import MacOSAdapters
@testable import OperatorCore
@testable import SafetyEngine

private struct MockPermissionChecker: PermissionChecking {
    let accessibility: Bool
    let screenRecording: Bool

    func hasAccessibilityPermission(prompt _: Bool) -> Bool { accessibility }
    func hasScreenRecordingPermission(prompt _: Bool) -> Bool { screenRecording }
}

private actor MockInputAdapter: InputAdapting {
    private(set) var recordedModes: [TextInputMode] = []

    func moveMouse(x _: Double, y _: Double, durationMS _: Int) async throws {}
    func clickMouse(x _: Double, y _: Double, button _: MouseButton, clickCount _: Int) async throws {}
    func dragMouse(fromX _: Double, fromY _: Double, toX _: Double, toY _: Double, durationMS _: Int) async throws {}
    func scroll(deltaX _: Double, deltaY _: Double) async throws {}

    func textInput(_ text: String, mode: TextInputMode) async throws {
        _ = text
        recordedModes.append(mode)
    }

    func keyChord(keys _: [String], repeatCount _: Int) async throws {}

    func modes() -> [TextInputMode] { recordedModes }
}

private actor MockWindowAdapter: WindowAdapting {
    private var frontmost: String?
    private let windows: [WindowDescriptor]
    private(set) var focusCalls: Int = 0
    private(set) var lastActivateAllWindows: Bool?

    init(frontmost: String?, windows: [WindowDescriptor] = []) {
        self.frontmost = frontmost
        self.windows = windows
    }

    func listWindows(includeMinimized _: Bool) async -> [WindowDescriptor] { windows }

    func focusWindow(
        windowID: UInt32?,
        bundleID: String?,
        launchIfNeeded _: Bool,
        activateAllWindows: Bool
    ) async throws -> String? {
        focusCalls += 1
        lastActivateAllWindows = activateAllWindows

        if let bundleID {
            frontmost = bundleID
            return bundleID
        }

        if let windowID, let window = windows.first(where: { $0.windowID == windowID }) {
            frontmost = window.bundleID
            return window.bundleID
        }

        return frontmost
    }

    func frontmostBundleID() async -> String? { frontmost }
    func focusCallCount() -> Int { focusCalls }
    func lastActivateAllWindowsValue() -> Bool? { lastActivateAllWindows }
}

private actor MockCaptureAdapter: CaptureAdapting {
    func capture(region _: CaptureRegion?, quality: Double?) async throws -> CaptureResult {
        let format = quality != nil ? "jpeg" : "png"
        return CaptureResult(imageBase64: "YmFzZTY0", format: format, width: 10, height: 10)
    }
}

private actor MockBrokerClient: BrokerClientProtocol {
    var shouldFailWithUnavailable = false
    private(set) var applescriptRunCalls = 0
    private(set) var applescriptAppCommandCalls = 0

    func runAppleScript(script _: String, targetBundleID _: String?) async throws -> BrokerResponse {
        if shouldFailWithUnavailable {
            throw BrokerClientError(code: .brokerUnavailable, message: "Broker down")
        }
        applescriptRunCalls += 1
        return BrokerResponse.success(id: UUID().uuidString, message: "ok", stdout: "hello")
    }

    func runAppleScriptAppCommand(bundleID _: String?, appName _: String?, command _: String, activate _: Bool) async throws -> BrokerResponse {
        if shouldFailWithUnavailable {
            throw BrokerClientError(code: .brokerUnavailable, message: "Broker down")
        }
        applescriptAppCommandCalls += 1
        return BrokerResponse.success(id: UUID().uuidString, message: "ok")
    }

    func probeAutomation(bundleID _: String?, appName _: String?) async throws -> PermissionProbeResult {
        PermissionProbeResult(status: .granted, errorCode: nil, message: "granted")
    }

    func health(autostart _: Bool) async -> Bool { true }

    func stopActive() async -> Int { 0 }

    func identity() async throws -> BrokerIdentity {
        BrokerIdentity(bundleID: "com.example.host", path: "/tmp/host.app", signed: false)
    }

    func setUnavailable(_ value: Bool) {
        shouldFailWithUnavailable = value
    }

    func runCalls() -> Int { applescriptRunCalls }
}

final class OperatorCoreTests: XCTestCase {
    func testToolSchemasIncludeBackgroundGlobalTools() {
        let tools = ToolSchemas.allTools()
        XCTAssertEqual(tools.count, 21)

        let names = Set(tools.map(\.name))
        XCTAssertTrue(names.contains("mouse_click"))
        XCTAssertTrue(names.contains("automation_stop"))
        XCTAssertTrue(names.contains("app_open_url"))
        XCTAssertTrue(names.contains("app_launch"))
        XCTAssertTrue(names.contains("applescript_run"))
        XCTAssertTrue(names.contains("applescript_app_command"))
        XCTAssertTrue(names.contains("permissions_status"))
        XCTAssertTrue(names.contains("permissions_probe_automation"))
        XCTAssertTrue(names.contains("permissions_open_settings"))
    }

    func testMouseClickSchemaRejectsUnknownField() {
        let schema = ToolSchemas.allTools().first(where: { $0.name == "mouse_click" })!.inputSchema
        let args: JSONValue = .object([
            "x": .number(10),
            "y": .number(20),
            "unknown": .bool(true),
        ])

        let errors = schema.validate(arguments: args)
        XCTAssertTrue(errors.contains(where: { $0.contains("unknown field") }))
    }

    func testAuditLogRedactsSensitiveTextAndDoesNotPersistCapturePayload() async throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let configURL = tempDirectory.appendingPathComponent("config.json")
        let logURL = tempDirectory.appendingPathComponent("audit.jsonl")

        let configStore = ConfigStore(configURL: configURL)
        try await configStore.save(
            AppConfig(
                defaultMode: .restricted,
                appWhitelist: ["com.apple.Notes"],
                sensitiveBundleIDs: [],
                dangerousKeyChords: [],
                auditEnabled: true,
                killSwitchHotkey: "ctrl+opt+cmd+."
            )
        )

        let auditLogger = AuditLogger(enabled: true, logURL: logURL)
        let safetyEngine = SafetyEngine(mode: .restricted, appWhitelist: ["com.apple.Notes"])
        let queue = AutomationQueue()
        let inputAdapter = MockInputAdapter()
        let windowAdapter = MockWindowAdapter(frontmost: "com.apple.Notes")
        let captureAdapter = MockCaptureAdapter()
        let permissions = MockPermissionChecker(accessibility: true, screenRecording: true)
        let brokerClient = MockBrokerClient()

        let executor = OperatorToolExecutor(
            configStore: configStore,
            auditLogger: auditLogger,
            safetyEngine: safetyEngine,
            automationQueue: queue,
            permissionChecker: permissions,
            brokerClient: brokerClient,
            inputAdapter: inputAdapter,
            windowAdapter: windowAdapter,
            captureAdapter: captureAdapter
        )

        _ = try await executor.callTool(
            name: "text_input",
            arguments: .object([
                "text": .string("super-secret"),
                "mode": .string("auto"),
            ])
        )

        _ = try await executor.callTool(name: "screen_capture", arguments: .object([:]))

        let content = try String(contentsOf: logURL)
        XCTAssertFalse(content.contains("super-secret"))
        XCTAssertFalse(content.contains("YmFzZTY0"))

        let modes = await inputAdapter.modes()
        XCTAssertEqual(modes, [.auto])
    }

    func testSetSafetyModeIsDeprecatedNoOp() async throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let configStore = ConfigStore(configURL: tempDirectory.appendingPathComponent("config.json"))
        try await configStore.save(AppConfig(defaultMode: .restricted))

        let executor = OperatorToolExecutor(
            configStore: configStore,
            auditLogger: AuditLogger(enabled: false, logURL: tempDirectory.appendingPathComponent("audit.jsonl")),
            safetyEngine: SafetyEngine(mode: .restricted, appWhitelist: []),
            automationQueue: AutomationQueue(),
            permissionChecker: MockPermissionChecker(accessibility: true, screenRecording: true),
            brokerClient: MockBrokerClient(),
            inputAdapter: MockInputAdapter(),
            windowAdapter: MockWindowAdapter(frontmost: "com.apple.Notes"),
            captureAdapter: MockCaptureAdapter()
        )

        let result = try await executor.callTool(
            name: "set_safety_mode",
            arguments: .object([
                "mode": .string("full_auto"),
                "persist": .bool(true),
            ])
        )

        XCTAssertEqual(result.structuredContent.objectValue?["deprecated"]?.boolValue, true)
        XCTAssertTrue(result.text.contains("deprecated no-op"))

        let updatedConfig = try await configStore.load()
        XCTAssertEqual(updatedConfig.defaultMode, .restricted)
    }

    func testAppleScriptRunUsesBrokerClient() async throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let configStore = ConfigStore(configURL: tempDirectory.appendingPathComponent("config.json"))
        try await configStore.save(AppConfig(defaultMode: .restricted))
        let broker = MockBrokerClient()

        let executor = OperatorToolExecutor(
            configStore: configStore,
            auditLogger: AuditLogger(enabled: false, logURL: tempDirectory.appendingPathComponent("audit.jsonl")),
            safetyEngine: SafetyEngine(mode: .restricted, appWhitelist: []),
            automationQueue: AutomationQueue(),
            permissionChecker: MockPermissionChecker(accessibility: true, screenRecording: true),
            brokerClient: broker,
            inputAdapter: MockInputAdapter(),
            windowAdapter: MockWindowAdapter(frontmost: "com.apple.Notes"),
            captureAdapter: MockCaptureAdapter()
        )

        _ = try await executor.callTool(
            name: "applescript_run",
            arguments: .object([
                "script": .string("return \"ok\""),
            ])
        )

        let calls = await broker.runCalls()
        XCTAssertEqual(calls, 1)
    }

    func testAppleScriptRunReturnsBrokerUnavailableError() async throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let configStore = ConfigStore(configURL: tempDirectory.appendingPathComponent("config.json"))
        try await configStore.save(AppConfig(defaultMode: .restricted))
        let broker = MockBrokerClient()
        await broker.setUnavailable(true)

        let executor = OperatorToolExecutor(
            configStore: configStore,
            auditLogger: AuditLogger(enabled: false, logURL: tempDirectory.appendingPathComponent("audit.jsonl")),
            safetyEngine: SafetyEngine(mode: .restricted, appWhitelist: []),
            automationQueue: AutomationQueue(),
            permissionChecker: MockPermissionChecker(accessibility: true, screenRecording: true),
            brokerClient: broker,
            inputAdapter: MockInputAdapter(),
            windowAdapter: MockWindowAdapter(frontmost: "com.apple.Notes"),
            captureAdapter: MockCaptureAdapter()
        )

        do {
            _ = try await executor.callTool(
                name: "applescript_run",
                arguments: .object([
                    "script": .string("return \"ok\""),
                ])
            )
            XCTFail("Expected failure")
        } catch let error as MCPToolError {
            XCTAssertEqual(error.code, JSONRPCErrorCode.toolExecutionFailed)
            XCTAssertTrue(error.message.contains("BROKER_UNAVAILABLE"))
        }
    }

    func testTextInputTargetWithoutAutoFocusFailsWhenNotFrontmost() async throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let configStore = ConfigStore(configURL: tempDirectory.appendingPathComponent("config.json"))
        try await configStore.save(AppConfig(defaultMode: .restricted, appWhitelist: ["com.apple.Terminal", "com.apple.Notes"]))

        let inputAdapter = MockInputAdapter()
        let windowAdapter = MockWindowAdapter(frontmost: "com.apple.Terminal")
        let executor = OperatorToolExecutor(
            configStore: configStore,
            auditLogger: AuditLogger(enabled: false, logURL: tempDirectory.appendingPathComponent("audit.jsonl")),
            safetyEngine: SafetyEngine(mode: .restricted, appWhitelist: ["com.apple.Terminal", "com.apple.Notes"]),
            automationQueue: AutomationQueue(),
            permissionChecker: MockPermissionChecker(accessibility: true, screenRecording: true),
            brokerClient: MockBrokerClient(),
            inputAdapter: inputAdapter,
            windowAdapter: windowAdapter,
            captureAdapter: MockCaptureAdapter()
        )

        do {
            _ = try await executor.callTool(
                name: "text_input",
                arguments: .object([
                    "text": .string("hello"),
                    "bundle_id": .string("com.apple.Notes"),
                    "auto_focus": .bool(false),
                ])
            )
            XCTFail("Expected TARGET_NOT_FRONTMOST")
        } catch let error as MCPToolError {
            XCTAssertEqual(error.code, JSONRPCErrorCode.toolExecutionFailed)
            XCTAssertTrue(error.message.contains("TARGET_NOT_FRONTMOST"))
        }

        let modes = await inputAdapter.modes()
        XCTAssertTrue(modes.isEmpty)
        let focusCalls = await windowAdapter.focusCallCount()
        XCTAssertEqual(focusCalls, 0)
    }

    func testTextInputTargetWithAutoFocusFocusesAndExecutes() async throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let configStore = ConfigStore(configURL: tempDirectory.appendingPathComponent("config.json"))
        try await configStore.save(AppConfig(defaultMode: .restricted, appWhitelist: ["com.apple.Terminal", "com.apple.Notes"]))

        let inputAdapter = MockInputAdapter()
        let windowAdapter = MockWindowAdapter(frontmost: "com.apple.Terminal")
        let executor = OperatorToolExecutor(
            configStore: configStore,
            auditLogger: AuditLogger(enabled: false, logURL: tempDirectory.appendingPathComponent("audit.jsonl")),
            safetyEngine: SafetyEngine(mode: .restricted, appWhitelist: ["com.apple.Terminal", "com.apple.Notes"]),
            automationQueue: AutomationQueue(),
            permissionChecker: MockPermissionChecker(accessibility: true, screenRecording: true),
            brokerClient: MockBrokerClient(),
            inputAdapter: inputAdapter,
            windowAdapter: windowAdapter,
            captureAdapter: MockCaptureAdapter()
        )

        _ = try await executor.callTool(
            name: "text_input",
            arguments: .object([
                "text": .string("hello"),
                "bundle_id": .string("com.apple.Notes"),
                "auto_focus": .bool(true),
            ])
        )

        let modes = await inputAdapter.modes()
        XCTAssertEqual(modes, [.auto])
        let focusCalls = await windowAdapter.focusCallCount()
        XCTAssertEqual(focusCalls, 1)
    }

    func testFocusWindowDefaultDoesNotActivateAllWindows() async throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let configStore = ConfigStore(configURL: tempDirectory.appendingPathComponent("config.json"))
        try await configStore.save(AppConfig(defaultMode: .restricted, appWhitelist: ["com.apple.Notes"]))

        let windowAdapter = MockWindowAdapter(frontmost: "com.apple.Terminal")
        let executor = OperatorToolExecutor(
            configStore: configStore,
            auditLogger: AuditLogger(enabled: false, logURL: tempDirectory.appendingPathComponent("audit.jsonl")),
            safetyEngine: SafetyEngine(mode: .restricted, appWhitelist: ["com.apple.Terminal", "com.apple.Notes"]),
            automationQueue: AutomationQueue(),
            permissionChecker: MockPermissionChecker(accessibility: true, screenRecording: true),
            brokerClient: MockBrokerClient(),
            inputAdapter: MockInputAdapter(),
            windowAdapter: windowAdapter,
            captureAdapter: MockCaptureAdapter()
        )

        _ = try await executor.callTool(
            name: "focus_window",
            arguments: .object([
                "bundle_id": .string("com.apple.Notes"),
            ])
        )
        let defaultValue = await windowAdapter.lastActivateAllWindowsValue()
        XCTAssertEqual(defaultValue, false)

        _ = try await executor.callTool(
            name: "focus_window",
            arguments: .object([
                "bundle_id": .string("com.apple.Notes"),
                "activate_all_windows": .bool(true),
            ])
        )
        let explicitValue = await windowAdapter.lastActivateAllWindowsValue()
        XCTAssertEqual(explicitValue, true)
    }
}
