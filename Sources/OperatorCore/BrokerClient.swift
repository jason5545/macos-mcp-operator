import BrokerCore
import ConfigStore
import CoreTypes
import Darwin
import Foundation

public struct BrokerIdentity: Sendable {
    public let bundleID: String
    public let path: String
    public let signed: Bool
}

public protocol BrokerClientProtocol: Sendable {
    func runAppleScript(script: String, targetBundleID: String?) async throws -> BrokerResponse
    func runAppleScriptAppCommand(bundleID: String?, appName: String?, command: String, activate: Bool) async throws -> BrokerResponse
    func probeAutomation(bundleID: String?, appName: String?) async throws -> PermissionProbeResult
    func health(autostart: Bool) async -> Bool
    func stopActive() async -> Int
    func identity() async throws -> BrokerIdentity
}

public struct BrokerClientError: LocalizedError, Sendable {
    public let code: PermissionErrorCode
    public let message: String

    public init(code: PermissionErrorCode, message: String) {
        self.code = code
        self.message = message
    }

    public var errorDescription: String? {
        "\(code.rawValue): \(message)"
    }
}

public actor BrokerClient: BrokerClientProtocol {
    private let configStore: ConfigStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(configStore: ConfigStore) {
        self.configStore = configStore
    }

    public func runAppleScript(script: String, targetBundleID: String?) async throws -> BrokerResponse {
        let response = try await send(
            request: BrokerRequest(method: .applescriptRun, script: script, targetBundleID: targetBundleID),
            autostart: true
        )
        guard response.ok else {
            throw BrokerClientError(
                code: .execFailed,
                message: response.message
            )
        }
        return response
    }

    public func runAppleScriptAppCommand(bundleID: String?, appName: String?, command: String, activate: Bool) async throws -> BrokerResponse {
        let response = try await send(
            request: BrokerRequest(
                method: .applescriptAppCommand,
                bundleID: bundleID,
                appName: appName,
                command: command,
                activate: activate
            ),
            autostart: true
        )
        guard response.ok else {
            throw BrokerClientError(
                code: .execFailed,
                message: response.message
            )
        }
        return response
    }

    public func probeAutomation(bundleID: String?, appName: String?) async throws -> PermissionProbeResult {
        let response = try await send(
            request: BrokerRequest(method: .probeAutomation, bundleID: bundleID, appName: appName),
            autostart: true
        )

        return PermissionProbeResult(
            status: response.probeStatus ?? .error,
            errorCode: response.probeErrorCode,
            message: response.message,
            remediation: response.remediation ?? []
        )
    }

    public func health(autostart: Bool) async -> Bool {
        do {
            let response = try await send(
                request: BrokerRequest(method: .health),
                autostart: autostart
            )
            return response.ok
        } catch {
            return false
        }
    }

    public func stopActive() async -> Int {
        do {
            let response = try await send(
                request: BrokerRequest(method: .stop),
                autostart: false
            )
            return response.cancelledActions ?? 0
        } catch {
            return 0
        }
    }

    public func identity() async throws -> BrokerIdentity {
        let config = try await configStore.load()
        let appPath = expandedPath(config.broker.appPath)
        return BrokerIdentity(
            bundleID: config.broker.bundleID,
            path: appPath,
            signed: isCodeSigned(path: appPath)
        )
    }

    private func send(request: BrokerRequest, autostart: Bool) async throws -> BrokerResponse {
        let config = try await configStore.load()
        let socketPath = expandedPath(config.broker.socketPath)

        do {
            return try sendRaw(request: request, socketPath: socketPath)
        } catch {
            guard autostart else { throw error }
            try launchBroker(config: config.broker)
            do {
                return try sendRaw(request: request, socketPath: socketPath)
            } catch {
                throw BrokerClientError(
                    code: .brokerUnavailable,
                    message: "Broker is unavailable at \(socketPath). Start \(expandedPath(config.broker.appPath)) and retry."
                )
            }
        }
    }

    private func launchBroker(config: BrokerConfig) throws {
        let launchAgentLabel = config.launchAgentLabel
        let uid = getuid()
        let guiDomain = "gui/\(uid)"
        let plistPath = "\(NSHomeDirectory())/Library/LaunchAgents/\(launchAgentLabel).plist"

        _ = runCommand(
            executable: "/bin/launchctl",
            arguments: ["kickstart", "-k", "\(guiDomain)/\(launchAgentLabel)"]
        )

        if FileManager.default.fileExists(atPath: plistPath) {
            _ = runCommand(
                executable: "/bin/launchctl",
                arguments: ["bootstrap", guiDomain, plistPath]
            )
            _ = runCommand(
                executable: "/bin/launchctl",
                arguments: ["kickstart", "-k", "\(guiDomain)/\(launchAgentLabel)"]
            )
        }

        _ = runCommand(
            executable: "/usr/bin/open",
            arguments: ["-g", expandedPath(config.appPath)]
        )

        usleep(500_000)
    }

    private func sendRaw(request: BrokerRequest, socketPath: String) throws -> BrokerResponse {
        let socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFD >= 0 else {
            throw BrokerClientError(code: .brokerUnavailable, message: "Failed to create socket: \(String(cString: strerror(errno)))")
        }
        defer { close(socketFD) }

        var timeout = timeval(tv_sec: 20, tv_usec: 0)
        withUnsafePointer(to: &timeout) { ptr in
            _ = setsockopt(socketFD, SOL_SOCKET, SO_RCVTIMEO, ptr, socklen_t(MemoryLayout<timeval>.size))
            _ = setsockopt(socketFD, SOL_SOCKET, SO_SNDTIMEO, ptr, socklen_t(MemoryLayout<timeval>.size))
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
#if os(macOS)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
#endif

        let pathBytes = socketPath.utf8CString
        let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)
        guard pathBytes.count <= pathCapacity else {
            throw BrokerClientError(code: .brokerUnavailable, message: "Socket path too long: \(socketPath)")
        }

        withUnsafeMutableBytes(of: &address.sun_path) { rawBuffer in
            rawBuffer.initializeMemory(as: UInt8.self, repeating: 0)
            pathBytes.withUnsafeBytes { source in
                if let sourceBase = source.baseAddress, let targetBase = rawBuffer.baseAddress {
                    memcpy(targetBase, sourceBase, min(source.count, rawBuffer.count))
                }
            }
        }

        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(socketFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            throw BrokerClientError(code: .brokerUnavailable, message: "Unable to connect broker socket: \(String(cString: strerror(errno)))")
        }

        let payload = try encoder.encode(request) + Data([0x0A])
        guard writeAll(payload, to: socketFD) else {
            throw BrokerClientError(code: .brokerUnavailable, message: "Failed to send broker request")
        }

        guard let line = readLine(from: socketFD), !line.isEmpty else {
            throw BrokerClientError(code: .brokerUnavailable, message: "Broker returned empty response")
        }

        return try decoder.decode(BrokerResponse.self, from: line)
    }

    private func writeAll(_ data: Data, to fd: Int32) -> Bool {
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

    private func expandedPath(_ path: String) -> String {
        NSString(string: path).expandingTildeInPath
    }

    private func isCodeSigned(path: String) -> Bool {
        guard FileManager.default.fileExists(atPath: path) else { return false }
        let output = runCommand(
            executable: "/usr/bin/codesign",
            arguments: ["--verify", "--deep", "--strict", path]
        )
        return output.status == 0
    }

    @discardableResult
    private func runCommand(executable: String, arguments: [String]) -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return (1, "", error.localizedDescription)
        }

        process.waitUntilExit()
        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, stdout, stderr)
    }
}
