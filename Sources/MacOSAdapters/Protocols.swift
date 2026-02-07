import CoreTypes
import Foundation

public protocol PermissionChecking: Sendable {
    func hasAccessibilityPermission(prompt: Bool) -> Bool
    func hasScreenRecordingPermission(prompt: Bool) -> Bool
}

public protocol InputAdapting: Sendable {
    func moveMouse(x: Double, y: Double, durationMS: Int) async throws
    func clickMouse(x: Double, y: Double, button: MouseButton, clickCount: Int) async throws
    func dragMouse(fromX: Double, fromY: Double, toX: Double, toY: Double, durationMS: Int) async throws
    func scroll(deltaX: Double, deltaY: Double) async throws
    func textInput(_ text: String, mode: TextInputMode) async throws
    func keyChord(keys: [String], repeatCount: Int) async throws
}

public protocol WindowAdapting: Sendable {
    func listWindows(includeMinimized: Bool) async -> [WindowDescriptor]
    func focusWindow(windowID: UInt32?, bundleID: String?, launchIfNeeded: Bool) async throws -> String?
    func frontmostBundleID() async -> String?
}

public protocol CaptureAdapting: Sendable {
    func capture(region: CaptureRegion?, quality: Double?) async throws -> CaptureResult
}
