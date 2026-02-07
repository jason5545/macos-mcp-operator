import AuditLogger
import AutomationCore
import ConfigStore
import Foundation
import MCPCore
import MacOSAdapters
import SafetyEngine

public enum OperatorRuntime {
    public static func run() async throws {
        let configStore = ConfigStore()
        let config = try await configStore.load()

        let safetyEngine = SafetyEngine(mode: config.defaultMode, appWhitelist: config.appWhitelist)
        let queue = AutomationQueue()
        let permissionChecker = PermissionChecker()
        let inputAdapter = SystemInputAdapter()
        let windowAdapter = SystemWindowAdapter()
        let captureAdapter = SystemCaptureAdapter()
        let auditLogger = AuditLogger(enabled: config.auditEnabled)
        let brokerClient = BrokerClient(configStore: configStore)

        let toolExecutor = OperatorToolExecutor(
            configStore: configStore,
            auditLogger: auditLogger,
            safetyEngine: safetyEngine,
            automationQueue: queue,
            permissionChecker: permissionChecker,
            brokerClient: brokerClient,
            inputAdapter: inputAdapter,
            windowAdapter: windowAdapter,
            captureAdapter: captureAdapter
        )

        let writer = StdioResponseWriter()
        let server = MCPServer(
            name: "macos-mcp-operator",
            version: "0.1.0",
            writer: writer,
            toolExecutor: toolExecutor
        )

        let monitor = KillSwitchMonitor {
            Task {
                _ = await queue.stopAll()
            }
        }
        _ = monitor.start()

        while let line = readLine(strippingNewline: true) {
            await server.receive(line: line)
        }

        await server.waitForInFlightRequests()
        monitor.stop()
    }
}
