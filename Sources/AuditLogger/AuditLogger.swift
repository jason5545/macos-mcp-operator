import CoreTypes
import Foundation

public struct AuditEvent: Codable, Sendable {
    public var timestamp: Date
    public var tool: String
    public var targetBundleID: String?
    public var status: ActionStatus
    public var message: String
    public var metadata: [String: String]

    public init(
        timestamp: Date = Date(),
        tool: String,
        targetBundleID: String?,
        status: ActionStatus,
        message: String,
        metadata: [String: String] = [:]
    ) {
        self.timestamp = timestamp
        self.tool = tool
        self.targetBundleID = targetBundleID
        self.status = status
        self.message = message
        self.metadata = metadata
    }
}

public actor AuditLogger {
    private let enabled: Bool
    private let logURL: URL
    private let encoder: JSONEncoder
    private let sensitiveKeys: Set<String> = ["text", "imageBase64", "image", "password", "token"]

    public init(enabled: Bool, logURL: URL? = nil) {
        self.enabled = enabled
        if let logURL {
            self.logURL = logURL
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            self.logURL = home
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Logs", isDirectory: true)
                .appendingPathComponent("macos-mcp-operator", isDirectory: true)
                .appendingPathComponent("audit.jsonl")
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    public func log(_ event: AuditEvent) async {
        guard enabled else {
            return
        }

        do {
            let redactedEvent = redact(event)
            let directory = logURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let data = try encoder.encode(redactedEvent)
            guard let line = String(data: data, encoding: .utf8) else {
                return
            }
            let payload = line + "\n"

            if FileManager.default.fileExists(atPath: logURL.path) {
                let handle = try FileHandle(forWritingTo: logURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                handle.write(Data(payload.utf8))
            } else {
                try Data(payload.utf8).write(to: logURL, options: .atomic)
            }
        } catch {
            // Logging failures should never break tool execution.
        }
    }

    private func redact(_ event: AuditEvent) -> AuditEvent {
        var redacted = event
        var metadata = redacted.metadata
        for key in metadata.keys where sensitiveKeys.contains(key) {
            metadata[key] = "[REDACTED]"
        }
        redacted.metadata = metadata
        return redacted
    }
}
