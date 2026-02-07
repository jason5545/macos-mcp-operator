import AppKit
import CoreGraphics
import CoreTypes
import Foundation

open class SystemInputAdapter: InputAdapting, @unchecked Sendable {
    public init() {}

    public func moveMouse(x: Double, y: Double, durationMS: Int) async throws {
        let point = CGPoint(x: x, y: y)
        if durationMS <= 0 {
            try postMouseEvent(type: .mouseMoved, point: point, button: .left)
            return
        }

        let start = NSEvent.mouseLocation
        let steps = max(durationMS / 16, 1)

        for index in 1...steps {
            try Task.checkCancellation()
            let progress = Double(index) / Double(steps)
            let interpolated = CGPoint(
                x: start.x + (point.x - start.x) * progress,
                y: start.y + (point.y - start.y) * progress
            )
            try postMouseEvent(type: .mouseMoved, point: interpolated, button: .left)
            try await Task.sleep(nanoseconds: 16_000_000)
        }
    }

    public func clickMouse(x: Double, y: Double, button: MouseButton, clickCount: Int) async throws {
        let point = CGPoint(x: x, y: y)
        let cgButton = toCGMouseButton(button)
        let downType = mouseDownType(for: button)
        let upType = mouseUpType(for: button)

        for _ in 0..<max(clickCount, 1) {
            try Task.checkCancellation()
            try postMouseEvent(type: downType, point: point, button: cgButton)
            try postMouseEvent(type: upType, point: point, button: cgButton)
            try await Task.sleep(nanoseconds: 25_000_000)
        }
    }

    public func dragMouse(fromX: Double, fromY: Double, toX: Double, toY: Double, durationMS: Int) async throws {
        let from = CGPoint(x: fromX, y: fromY)
        let to = CGPoint(x: toX, y: toY)
        try postMouseEvent(type: .leftMouseDown, point: from, button: .left)

        let steps = max(durationMS / 16, 1)
        for index in 1...steps {
            try Task.checkCancellation()
            let progress = Double(index) / Double(steps)
            let point = CGPoint(
                x: from.x + (to.x - from.x) * progress,
                y: from.y + (to.y - from.y) * progress
            )
            try postMouseEvent(type: .leftMouseDragged, point: point, button: .left)
            try await Task.sleep(nanoseconds: 16_000_000)
        }

        try postMouseEvent(type: .leftMouseUp, point: to, button: .left)
    }

    public func scroll(deltaX: Double, deltaY: Double) async throws {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(deltaY),
            wheel2: Int32(deltaX),
            wheel3: 0
        ) else {
            throw OperatorError("Failed to create scroll event")
        }

        event.post(tap: .cghidEventTap)
    }

    public func textInput(_ text: String, mode: TextInputMode) async throws {
        switch mode {
        case .paste:
            try await pasteText(text)
        case .keystroke:
            try await typeText(text)
        case .auto:
            do {
                try await pasteText(text)
            } catch {
                try await typeText(text)
            }
        }
    }

    public func keyChord(keys: [String], repeatCount: Int) async throws {
        guard !keys.isEmpty else {
            throw OperatorError("keys cannot be empty")
        }

        let parsed = try parseKeyChord(keys)
        for _ in 0..<max(repeatCount, 1) {
            try Task.checkCancellation()
            try postKeyChord(parsed)
            try await Task.sleep(nanoseconds: 30_000_000)
        }
    }

    private func postMouseEvent(type: CGEventType, point: CGPoint, button: CGMouseButton) throws {
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: button) else {
            throw OperatorError("Failed to create mouse event")
        }
        event.post(tap: .cghidEventTap)
    }

    open func pasteText(_ text: String) async throws {
        let success = await MainActor.run { () -> Bool in
            let board = NSPasteboard.general
            board.clearContents()
            return board.setString(text, forType: .string)
        }

        guard success else {
            throw OperatorError("Unable to write text into pasteboard")
        }

        try await keyChord(keys: ["cmd", "v"], repeatCount: 1)
    }

    open func typeText(_ text: String) async throws {
        for scalar in text.unicodeScalars {
            try Task.checkCancellation()
            guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
            else {
                throw OperatorError("Failed to build keyboard event")
            }

            var characters: [UniChar] = [UniChar(scalar.value)]
            keyDown.keyboardSetUnicodeString(stringLength: 1, unicodeString: &characters)
            keyUp.keyboardSetUnicodeString(stringLength: 1, unicodeString: &characters)
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
            try await Task.sleep(nanoseconds: 12_000_000)
        }
    }

    private func toCGMouseButton(_ button: MouseButton) -> CGMouseButton {
        switch button {
        case .left:
            return .left
        case .right:
            return .right
        case .center:
            return .center
        }
    }

    private func mouseDownType(for button: MouseButton) -> CGEventType {
        switch button {
        case .left:
            return .leftMouseDown
        case .right:
            return .rightMouseDown
        case .center:
            return .otherMouseDown
        }
    }

    private func mouseUpType(for button: MouseButton) -> CGEventType {
        switch button {
        case .left:
            return .leftMouseUp
        case .right:
            return .rightMouseUp
        case .center:
            return .otherMouseUp
        }
    }

    private struct ParsedKeyChord {
        let modifiers: CGEventFlags
        let modifierKeys: [CGKeyCode]
        let primaryKey: CGKeyCode?
    }

    private func parseKeyChord(_ keys: [String]) throws -> ParsedKeyChord {
        var modifiers: CGEventFlags = []
        var modifierKeys: [CGKeyCode] = []
        var primaryKey: CGKeyCode?

        for rawKey in keys {
            let key = rawKey.lowercased()
            switch key {
            case "cmd", "command":
                modifiers.insert(.maskCommand)
                modifierKeys.append(55)
            case "shift":
                modifiers.insert(.maskShift)
                modifierKeys.append(56)
            case "opt", "option", "alt":
                modifiers.insert(.maskAlternate)
                modifierKeys.append(58)
            case "ctrl", "control":
                modifiers.insert(.maskControl)
                modifierKeys.append(59)
            default:
                guard let keyCode = keyCodeForString(key) else {
                    throw OperatorError("Unsupported key: \(rawKey)")
                }
                primaryKey = keyCode
            }
        }

        return ParsedKeyChord(modifiers: modifiers, modifierKeys: modifierKeys, primaryKey: primaryKey)
    }

    private func postKeyChord(_ parsed: ParsedKeyChord) throws {
        for keyCode in parsed.modifierKeys {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) else {
                throw OperatorError("Failed to create modifier keyDown")
            }
            event.flags = parsed.modifiers
            event.post(tap: .cghidEventTap)
        }

        if let primaryKey = parsed.primaryKey {
            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: primaryKey, keyDown: true),
                  let up = CGEvent(keyboardEventSource: nil, virtualKey: primaryKey, keyDown: false)
            else {
                throw OperatorError("Failed to create key event")
            }
            down.flags = parsed.modifiers
            up.flags = parsed.modifiers
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }

        for keyCode in parsed.modifierKeys.reversed() {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
                throw OperatorError("Failed to create modifier keyUp")
            }
            event.flags = []
            event.post(tap: .cghidEventTap)
        }
    }

    private func keyCodeForString(_ key: String) -> CGKeyCode? {
        let mapping: [String: CGKeyCode] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
            "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
            "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
            "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
            "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
            "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42,
            ",": 43, "/": 44, "n": 45, "m": 46, ".": 47,
            "tab": 48, "space": 49, "return": 36, "enter": 36, "escape": 53,
            "delete": 51, "backspace": 51,
            "left": 123, "right": 124, "down": 125, "up": 126,
        ]

        return mapping[key]
    }
}
