import CoreTypes
import Foundation

public struct PermissionProbeResult: Sendable {
    public let status: PermissionProbeStatus
    public let errorCode: PermissionErrorCode?
    public let message: String
    public let remediation: [String]

    public init(
        status: PermissionProbeStatus,
        errorCode: PermissionErrorCode?,
        message: String,
        remediation: [String] = []
    ) {
        self.status = status
        self.errorCode = errorCode
        self.message = message
        self.remediation = remediation
    }
}

public enum PermissionProbeMapper {
    public static func mapFromAppleScriptFailure(_ text: String) -> PermissionProbeResult {
        let lowered = text.lowercased()

        if lowered.contains("(-1743)") || lowered.contains("not authorized to send apple events") {
            return PermissionProbeResult(
                status: .denied,
                errorCode: .automationNotAllowed,
                message: "Automation permission is not granted for the target app.",
                remediation: [
                    "Open System Settings > Privacy & Security > Automation.",
                    "Grant automation access for the broker host app.",
                ]
            )
        }

        if lowered.contains("(-128)") || lowered.contains("user canceled") {
            return PermissionProbeResult(
                status: .notDetermined,
                errorCode: nil,
                message: "Automation permission has not been finalized yet.",
                remediation: [
                    "Retry the action and approve the permission prompt if shown.",
                    "Or grant access in System Settings > Privacy & Security > Automation.",
                ]
            )
        }

        return PermissionProbeResult(
            status: .error,
            errorCode: .execFailed,
            message: text.isEmpty ? "Automation probe failed." : text,
            remediation: [
                "Verify target app exists and can be scripted.",
                "Check broker logs and rerun probe.",
            ]
        )
    }
}

public final class PermissionProbeExecutor: @unchecked Sendable {
    private let appleScriptExecutor: AppleScriptExecutor

    public init(appleScriptExecutor: AppleScriptExecutor) {
        self.appleScriptExecutor = appleScriptExecutor
    }

    public func probe(bundleID: String?, appName: String?) -> PermissionProbeResult {
        guard bundleID != nil || appName != nil else {
            return PermissionProbeResult(
                status: .error,
                errorCode: .execFailed,
                message: "bundle_id or app_name is required",
                remediation: ["Provide a valid target bundle_id or app_name."]
            )
        }

        let targetSpecifier: String
        if let bundleID {
            targetSpecifier = "application id \"\(escapeAppleScriptString(bundleID))\""
        } else if let appName {
            targetSpecifier = "application \"\(escapeAppleScriptString(appName))\""
        } else {
            targetSpecifier = "application \"Finder\""
        }

        let script = """
        with timeout of 5 seconds
            tell \(targetSpecifier)
                id
            end tell
        end timeout
        """

        do {
            _ = try appleScriptExecutor.run(script: script)
            return PermissionProbeResult(
                status: .granted,
                errorCode: nil,
                message: "Automation permission probe succeeded."
            )
        } catch let error as BrokerExecutionError {
            let text = error.stderr.isEmpty ? error.message : error.stderr
            return PermissionProbeMapper.mapFromAppleScriptFailure(text)
        } catch {
            return PermissionProbeResult(
                status: .error,
                errorCode: .execFailed,
                message: error.localizedDescription
            )
        }
    }

    private func escapeAppleScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
