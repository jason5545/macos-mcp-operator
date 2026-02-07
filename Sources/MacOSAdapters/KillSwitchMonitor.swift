import AppKit
import Foundation

public final class KillSwitchMonitor: @unchecked Sendable {
    public typealias TriggerHandler = @Sendable () -> Void

    private var monitorToken: Any?
    private let handler: TriggerHandler

    public init(handler: @escaping TriggerHandler) {
        self.handler = handler
    }

    @discardableResult
    public func start() -> Bool {
        monitorToken = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [handler] event in
            let requiredFlags: NSEvent.ModifierFlags = [.control, .option, .command]
            let containsRequiredFlags = event.modifierFlags.intersection(requiredFlags) == requiredFlags
            if containsRequiredFlags, event.charactersIgnoringModifiers == "." {
                handler()
            }
        }

        return monitorToken != nil
    }

    public func stop() {
        if let monitorToken {
            NSEvent.removeMonitor(monitorToken)
            self.monitorToken = nil
        }
    }
}
