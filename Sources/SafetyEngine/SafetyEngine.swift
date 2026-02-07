import CoreTypes
import CryptoKit
import Foundation

public enum SafetyDecision: Sendable {
    case allow
    case reject(message: String)
}

public actor SafetyEngine {
    private var mode: SafetyMode
    private var whitelist: Set<String>

    public init(mode: SafetyMode, appWhitelist: [String]) {
        self.mode = mode
        self.whitelist = Set(appWhitelist)
    }

    public func currentMode() -> SafetyMode {
        mode
    }

    public func setMode(_ mode: SafetyMode) {
        self.mode = mode
    }

    public func currentWhitelist() -> [String] {
        whitelist.sorted()
    }

    public func setWhitelist(_ bundleIDs: [String]) {
        whitelist = Set(bundleIDs)
    }

    public func addWhitelist(_ bundleIDs: [String]) {
        whitelist.formUnion(bundleIDs)
    }

    public func removeWhitelist(_ bundleIDs: [String]) {
        whitelist.subtract(bundleIDs)
    }

    public func evaluate(
        toolName: String,
        riskClass: RiskClass,
        targetBundleID: String?,
        confirmationToken: String?,
        argumentsFingerprint: String
    ) -> SafetyDecision {
        _ = toolName
        _ = riskClass
        _ = targetBundleID
        _ = confirmationToken
        _ = argumentsFingerprint
        // v1.1 disables interactive approval/token workflow for single-user local automation.
        return .allow
    }

    public func makeFingerprint(toolName: String, arguments: [String: String]) -> String {
        let sortedArguments = arguments.keys.sorted().map { "\($0)=\(arguments[$0] ?? "")" }.joined(separator: "&")
        let value = "\(toolName)|\(sortedArguments)"
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
