import AppKit
import CoreGraphics
import CoreTypes
import Foundation

public final class SystemWindowAdapter: WindowAdapting, @unchecked Sendable {
    public init() {}

    public func listWindows(includeMinimized: Bool) async -> [WindowDescriptor] {
        let options: CGWindowListOption = includeMinimized
            ? [.optionAll]
            : [.optionOnScreenOnly, .excludeDesktopElements]

        guard let windowInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        return windowInfo.compactMap { info in
            guard
                let windowID = info[kCGWindowNumber as String] as? UInt32,
                let ownerName = info[kCGWindowOwnerName as String] as? String,
                let bounds = info[kCGWindowBounds as String] as? [String: Any],
                let x = bounds["X"] as? Double,
                let y = bounds["Y"] as? Double,
                let width = bounds["Width"] as? Double,
                let height = bounds["Height"] as? Double
            else {
                return nil
            }

            let title = (info[kCGWindowName as String] as? String) ?? ""
            let pid = (info[kCGWindowOwnerPID as String] as? pid_t) ?? 0
            let app = NSRunningApplication(processIdentifier: pid)
            let bundleID = app?.bundleIdentifier
            let isFocused = frontmostPID == pid

            return WindowDescriptor(
                windowID: windowID,
                bundleID: bundleID,
                appName: ownerName,
                title: title,
                frame: WindowFrame(x: x, y: y, width: width, height: height),
                isFocused: isFocused
            )
        }
    }

    public func focusWindow(
        windowID: UInt32?,
        bundleID: String?,
        launchIfNeeded: Bool,
        activateAllWindows: Bool
    ) async throws -> String? {
        if let bundleID {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                return activate(app: app, activateAllWindows: activateAllWindows) ? bundleID : nil
            }

            guard launchIfNeeded else {
                throw OperatorError("App \(bundleID) is not running")
            }

            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                throw OperatorError("Cannot resolve app URL for \(bundleID)")
            }

            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)

            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                return activate(app: app, activateAllWindows: activateAllWindows) ? bundleID : nil
            }

            return bundleID
        }

        guard let windowID else {
            throw OperatorError("Either window_id or bundle_id is required")
        }

        let windows = await listWindows(includeMinimized: true)
        guard let match = windows.first(where: { $0.windowID == windowID }) else {
            throw OperatorError("Window \(windowID) was not found")
        }

        guard let bundleID = match.bundleID else {
            throw OperatorError("Bundle ID unavailable for window \(windowID)")
        }

        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            throw OperatorError("Application \(bundleID) is not running")
        }

        _ = activate(app: app, activateAllWindows: activateAllWindows)
        return bundleID
    }

    public func frontmostBundleID() async -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    private func activate(app: NSRunningApplication, activateAllWindows: Bool) -> Bool {
        let options: NSApplication.ActivationOptions = activateAllWindows ? [.activateAllWindows] : []
        return app.activate(options: options)
    }
}
