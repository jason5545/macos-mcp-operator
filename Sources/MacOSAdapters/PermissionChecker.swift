import ApplicationServices
import Foundation

public struct PermissionChecker: PermissionChecking {
    public init() {}

    public func hasAccessibilityPermission(prompt: Bool) -> Bool {
        if prompt {
            let options = ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }
        return AXIsProcessTrusted()
    }

    public func hasScreenRecordingPermission(prompt: Bool) -> Bool {
        if prompt {
            return CGRequestScreenCaptureAccess()
        }
        return CGPreflightScreenCaptureAccess()
    }
}
