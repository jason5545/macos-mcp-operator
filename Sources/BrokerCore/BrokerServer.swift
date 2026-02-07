import Darwin
import Foundation

public final class BrokerServer: @unchecked Sendable {
    private let socketPath: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let registry = ProcessRegistry()
    private lazy var appleScriptExecutor = AppleScriptExecutor(registry: registry)
    private lazy var probeExecutor = PermissionProbeExecutor(appleScriptExecutor: appleScriptExecutor)

    private let stateLock = NSLock()
    private var isRunning = false
    private var serverFD: Int32 = -1

    public init(socketPath: String) {
        self.socketPath = NSString(string: socketPath).expandingTildeInPath
    }

    public func run() throws {
        try prepareSocketDirectory()
        unlink(socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw BrokerExecutionError(message: "Failed to create Unix socket: \(String(cString: strerror(errno)))")
        }
        serverFD = fd

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
#if os(macOS)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
#endif

        let pathBytes = socketPath.utf8CString
        let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)
        guard pathBytes.count <= pathCapacity else {
            close(fd)
            throw BrokerExecutionError(message: "Socket path is too long: \(socketPath)")
        }

        withUnsafeMutableBytes(of: &address.sun_path) { rawBuffer in
            rawBuffer.initializeMemory(as: UInt8.self, repeating: 0)
            pathBytes.withUnsafeBytes { source in
                if let sourceBase = source.baseAddress, let targetBase = rawBuffer.baseAddress {
                    memcpy(targetBase, sourceBase, min(source.count, rawBuffer.count))
                }
            }
        }

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bindResult == 0 else {
            let message = String(cString: strerror(errno))
            close(fd)
            throw BrokerExecutionError(message: "Failed to bind broker socket: \(message)")
        }

        guard listen(fd, 32) == 0 else {
            let message = String(cString: strerror(errno))
            close(fd)
            throw BrokerExecutionError(message: "Failed to listen on broker socket: \(message)")
        }

        stateLock.lock()
        isRunning = true
        stateLock.unlock()

        while shouldKeepRunning() {
            let clientFD = accept(fd, nil, nil)
            if clientFD < 0 {
                if errno == EINTR {
                    continue
                }
                if !shouldKeepRunning() {
                    break
                }
                continue
            }

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.handleClient(clientFD: clientFD)
            }
        }

        stop()
    }

    public func stop() {
        stateLock.lock()
        isRunning = false
        let fd = serverFD
        serverFD = -1
        stateLock.unlock()

        if fd >= 0 {
            shutdown(fd, SHUT_RDWR)
            close(fd)
        }

        _ = registry.terminateAll()
        unlink(socketPath)
    }

    private func shouldKeepRunning() -> Bool {
        stateLock.lock()
        let value = isRunning
        stateLock.unlock()
        return value
    }

    private func prepareSocketDirectory() throws {
        let directory = URL(fileURLWithPath: socketPath).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func handleClient(clientFD: Int32) {
        defer { close(clientFD) }

        guard let line = readLine(from: clientFD), !line.isEmpty else {
            return
        }

        let response: BrokerResponse
        do {
            let request = try decoder.decode(BrokerRequest.self, from: line)
            response = handleRequest(request)
        } catch {
            response = BrokerResponse.failure(
                id: UUID().uuidString,
                code: "BAD_REQUEST",
                message: "Invalid broker request: \(error.localizedDescription)"
            )
        }

        do {
            let data = try encoder.encode(response)
            _ = writeAll(data: data + Data([0x0A]), to: clientFD)
        } catch {
            _ = writeAll(data: Data("{\"ok\":false,\"message\":\"encode failure\"}\n".utf8), to: clientFD)
        }
    }

    private func handleRequest(_ request: BrokerRequest) -> BrokerResponse {
        switch request.method {
        case .health:
            return .success(id: request.id, message: "broker_ok")
        case .stop:
            let cancelled = registry.terminateAll()
            return BrokerResponse(
                id: request.id,
                ok: true,
                message: "broker_stop_completed",
                cancelledActions: cancelled
            )
        case .applescriptRun:
            guard let script = request.script, !script.isEmpty else {
                return .failure(id: request.id, code: "INVALID_PARAMS", message: "script is required")
            }
            do {
                let result = try appleScriptExecutor.run(script: script)
                return .success(id: request.id, message: "applescript_executed", stdout: result.stdout, stderr: result.stderr)
            } catch let error as BrokerExecutionError {
                return .failure(id: request.id, code: "EXEC_FAILED", message: error.message, stderr: error.stderr)
            } catch {
                return .failure(id: request.id, code: "EXEC_FAILED", message: error.localizedDescription)
            }
        case .applescriptAppCommand:
            guard request.bundleID != nil || request.appName != nil else {
                return .failure(id: request.id, code: "INVALID_PARAMS", message: "bundle_id or app_name is required")
            }
            guard let command = request.command, !command.isEmpty else {
                return .failure(id: request.id, code: "INVALID_PARAMS", message: "command is required")
            }
            let script = makeAppCommandScript(
                bundleID: request.bundleID,
                appName: request.appName,
                command: command,
                activate: request.activate ?? false
            )
            do {
                let result = try appleScriptExecutor.run(script: script)
                return .success(id: request.id, message: "applescript_app_command_executed", stdout: result.stdout, stderr: result.stderr)
            } catch let error as BrokerExecutionError {
                return .failure(id: request.id, code: "EXEC_FAILED", message: error.message, stderr: error.stderr)
            } catch {
                return .failure(id: request.id, code: "EXEC_FAILED", message: error.localizedDescription)
            }
        case .probeAutomation:
            let probe = probeExecutor.probe(bundleID: request.bundleID, appName: request.appName)
            return BrokerResponse(
                id: request.id,
                ok: probe.status == .granted,
                message: probe.message,
                code: probe.errorCode?.rawValue,
                probeStatus: probe.status,
                probeErrorCode: probe.errorCode,
                remediation: probe.remediation
            )
        }
    }

    private func makeAppCommandScript(bundleID: String?, appName: String?, command: String, activate: Bool) -> String {
        let targetSpecifier: String
        if let bundleID {
            targetSpecifier = "application id \"\(escapeAppleScriptString(bundleID))\""
        } else if let appName {
            targetSpecifier = "application \"\(escapeAppleScriptString(appName))\""
        } else {
            targetSpecifier = "application \"Finder\""
        }

        var lines: [String] = []
        lines.append("tell \(targetSpecifier)")
        if activate {
            lines.append("activate")
        }
        lines.append(command)
        lines.append("end tell")
        return lines.joined(separator: "\n")
    }

    private func escapeAppleScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func readLine(from fd: Int32) -> Data? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)

        while true {
            let received = read(fd, &buffer, buffer.count)
            if received < 0 {
                if errno == EINTR {
                    continue
                }
                return nil
            }
            if received == 0 {
                break
            }
            data.append(buffer, count: received)
            if data.contains(0x0A) {
                break
            }
        }

        guard !data.isEmpty else { return nil }
        if let newlineIndex = data.firstIndex(of: 0x0A) {
            return data.prefix(upTo: newlineIndex)
        }
        return data
    }

    private func writeAll(data: Data, to fd: Int32) -> Bool {
        var offset = 0
        return data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return false
            }

            while offset < rawBuffer.count {
                let pointer = baseAddress.advanced(by: offset)
                let written = write(fd, pointer, rawBuffer.count - offset)
                if written < 0 {
                    if errno == EINTR {
                        continue
                    }
                    return false
                }
                offset += written
            }
            return true
        }
    }
}
