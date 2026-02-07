import CoreTypes
import Foundation

public struct BrokerConfig: Codable, Sendable {
    public var bundleID: String
    public var appPath: String
    public var socketPath: String
    public var launchAgentLabel: String

    public init(
        bundleID: String = "com.jianruicheng.macos-mcp-operator.host",
        appPath: String = "~/Applications/macos-mcp-operator-host.app",
        socketPath: String = "~/.local/share/macos-mcp-operator/broker.sock",
        launchAgentLabel: String = "com.jianruicheng.macos-mcp-operator.host"
    ) {
        self.bundleID = bundleID
        self.appPath = appPath
        self.socketPath = socketPath
        self.launchAgentLabel = launchAgentLabel
    }

    private struct AnyCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil

        init(_ string: String) {
            self.stringValue = string
        }

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            return nil
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)

        func decodeValue<T: Decodable>(_ type: T.Type, snake: String, camel: String, default fallback: T) -> T {
            if let value = try? container.decode(type, forKey: AnyCodingKey(snake)) {
                return value
            }
            if let value = try? container.decode(type, forKey: AnyCodingKey(camel)) {
                return value
            }
            return fallback
        }

        bundleID = decodeValue(String.self, snake: "bundle_id", camel: "bundleID", default: "com.jianruicheng.macos-mcp-operator.host")
        appPath = decodeValue(String.self, snake: "app_path", camel: "appPath", default: "~/Applications/macos-mcp-operator-host.app")
        socketPath = decodeValue(String.self, snake: "socket_path", camel: "socketPath", default: "~/.local/share/macos-mcp-operator/broker.sock")
        launchAgentLabel = decodeValue(String.self, snake: "launch_agent_label", camel: "launchAgentLabel", default: "com.jianruicheng.macos-mcp-operator.host")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AnyCodingKey.self)
        try container.encode(bundleID, forKey: AnyCodingKey("bundle_id"))
        try container.encode(appPath, forKey: AnyCodingKey("app_path"))
        try container.encode(socketPath, forKey: AnyCodingKey("socket_path"))
        try container.encode(launchAgentLabel, forKey: AnyCodingKey("launch_agent_label"))
    }
}

public struct AppConfig: Codable, Sendable {
    public var defaultMode: SafetyMode
    public var appWhitelist: [String]
    public var sensitiveBundleIDs: [String]
    public var dangerousKeyChords: [[String]]
    public var auditEnabled: Bool
    public var killSwitchHotkey: String
    public var approvalEnabled: Bool
    public var executionBackend: ExecutionBackend
    public var broker: BrokerConfig

    public init(
        defaultMode: SafetyMode = .restricted,
        appWhitelist: [String] = ["com.apple.Notes"],
        sensitiveBundleIDs: [String] = ["com.apple.systempreferences"],
        dangerousKeyChords: [[String]] = [["cmd", "q"], ["cmd", "w"], ["cmd", "delete"]],
        auditEnabled: Bool = true,
        killSwitchHotkey: String = "ctrl+opt+cmd+.",
        approvalEnabled: Bool = false,
        executionBackend: ExecutionBackend = .broker,
        broker: BrokerConfig = BrokerConfig()
    ) {
        self.defaultMode = defaultMode
        self.appWhitelist = appWhitelist
        self.sensitiveBundleIDs = sensitiveBundleIDs
        self.dangerousKeyChords = dangerousKeyChords
        self.auditEnabled = auditEnabled
        self.killSwitchHotkey = killSwitchHotkey
        self.approvalEnabled = approvalEnabled
        self.executionBackend = executionBackend
        self.broker = broker
    }

    private struct AnyCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil

        init(_ string: String) {
            self.stringValue = string
        }

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            return nil
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)

        func decodeValue<T: Decodable>(_ type: T.Type, snake: String, camel: String, default fallback: T) -> T {
            if let value = try? container.decode(type, forKey: AnyCodingKey(snake)) {
                return value
            }
            if let value = try? container.decode(type, forKey: AnyCodingKey(camel)) {
                return value
            }
            return fallback
        }

        defaultMode = decodeValue(SafetyMode.self, snake: "default_mode", camel: "defaultMode", default: .restricted)
        appWhitelist = decodeValue([String].self, snake: "app_whitelist", camel: "appWhitelist", default: ["com.apple.Notes"])
        sensitiveBundleIDs = decodeValue([String].self, snake: "sensitive_bundle_ids", camel: "sensitiveBundleIDs", default: ["com.apple.systempreferences"])
        dangerousKeyChords = decodeValue([[String]].self, snake: "dangerous_key_chords", camel: "dangerousKeyChords", default: [["cmd", "q"], ["cmd", "w"], ["cmd", "delete"]])
        auditEnabled = decodeValue(Bool.self, snake: "audit_enabled", camel: "auditEnabled", default: true)
        killSwitchHotkey = decodeValue(String.self, snake: "kill_switch_hotkey", camel: "killSwitchHotkey", default: "ctrl+opt+cmd+.")
        approvalEnabled = decodeValue(Bool.self, snake: "approval_enabled", camel: "approvalEnabled", default: false)
        executionBackend = decodeValue(ExecutionBackend.self, snake: "execution_backend", camel: "executionBackend", default: .broker)
        broker = decodeValue(BrokerConfig.self, snake: "broker", camel: "broker", default: BrokerConfig())
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AnyCodingKey.self)
        try container.encode(defaultMode, forKey: AnyCodingKey("default_mode"))
        try container.encode(appWhitelist, forKey: AnyCodingKey("app_whitelist"))
        try container.encode(sensitiveBundleIDs, forKey: AnyCodingKey("sensitive_bundle_ids"))
        try container.encode(dangerousKeyChords, forKey: AnyCodingKey("dangerous_key_chords"))
        try container.encode(auditEnabled, forKey: AnyCodingKey("audit_enabled"))
        try container.encode(killSwitchHotkey, forKey: AnyCodingKey("kill_switch_hotkey"))
        try container.encode(approvalEnabled, forKey: AnyCodingKey("approval_enabled"))
        try container.encode(executionBackend, forKey: AnyCodingKey("execution_backend"))
        try container.encode(broker, forKey: AnyCodingKey("broker"))
    }
}

public actor ConfigStore {
    private let configURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var cachedConfig: AppConfig?

    public init(configURL: URL? = nil) {
        if let configURL {
            self.configURL = configURL
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            self.configURL = home
                .appendingPathComponent(".config", isDirectory: true)
                .appendingPathComponent("macos-mcp-operator", isDirectory: true)
                .appendingPathComponent("config.json")
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        self.decoder = JSONDecoder()
    }

    public func load() async throws -> AppConfig {
        if let cachedConfig {
            return cachedConfig
        }

        if FileManager.default.fileExists(atPath: configURL.path) {
            let data = try Data(contentsOf: configURL)
            let config = try decoder.decode(AppConfig.self, from: data)
            cachedConfig = config
            return config
        }

        let config = AppConfig()
        try persist(config: config)
        cachedConfig = config
        return config
    }

    public func save(_ config: AppConfig) async throws {
        try persist(config: config)
        cachedConfig = config
    }

    public func update(_ mutate: (inout AppConfig) -> Void) async throws -> AppConfig {
        var config = try await load()
        mutate(&config)
        try persist(config: config)
        cachedConfig = config
        return config
    }

    private func persist(config: AppConfig) throws {
        let directory = configURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(config)
        try data.write(to: configURL, options: .atomic)
    }
}
