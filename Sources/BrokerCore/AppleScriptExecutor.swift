import Foundation

public struct AppleScriptExecutionResult: Sendable {
    public let stdout: String
    public let stderr: String

    public init(stdout: String, stderr: String) {
        self.stdout = stdout
        self.stderr = stderr
    }
}

public struct BrokerExecutionError: LocalizedError, Sendable {
    public let message: String
    public let stderr: String

    public init(message: String, stderr: String = "") {
        self.message = message
        self.stderr = stderr
    }

    public var errorDescription: String? {
        message
    }
}

public final class ProcessRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var processes: [UUID: Process] = [:]

    public init() {}

    @discardableResult
    public func register(_ process: Process) -> UUID {
        let id = UUID()
        lock.lock()
        processes[id] = process
        lock.unlock()
        return id
    }

    public func unregister(_ id: UUID) {
        lock.lock()
        processes[id] = nil
        lock.unlock()
    }

    public func terminateAll() -> Int {
        lock.lock()
        let active = Array(processes.values)
        processes.removeAll()
        lock.unlock()

        for process in active {
            if process.isRunning {
                process.terminate()
            }
        }
        return active.count
    }
}

public final class AppleScriptExecutor: @unchecked Sendable {
    private let registry: ProcessRegistry

    public init(registry: ProcessRegistry) {
        self.registry = registry
    }

    public func run(script: String) throws -> AppleScriptExecutionResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        let processID = registry.register(process)
        defer { registry.unregister(processID) }

        do {
            try process.run()
        } catch {
            throw BrokerExecutionError(message: "Failed to run osascript: \(error.localizedDescription)")
        }

        if let data = (script + "\n").data(using: .utf8) {
            stdin.fileHandleForWriting.write(data)
        }
        try? stdin.fileHandleForWriting.close()

        process.waitUntilExit()

        let stdoutString = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stderrString = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            let message = stderrString.isEmpty
                ? "osascript failed with status \(process.terminationStatus)"
                : stderrString
            throw BrokerExecutionError(message: message, stderr: stderrString)
        }

        return AppleScriptExecutionResult(stdout: stdoutString, stderr: stderrString)
    }
}
