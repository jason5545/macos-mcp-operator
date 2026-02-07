import Foundation

public enum SafetyMode: String, Codable, Sendable {
    case restricted
    case full_auto
}

public enum RiskClass: String, Codable, Sendable {
    case low
    case high
}

public enum ActionStatus: String, Codable, Sendable {
    case executed
    case pending_confirmation
    case rejected
    case cancelled
}

public struct ActionReceipt: Codable, Sendable {
    public var actionID: String
    public var status: ActionStatus
    public var message: String
    public var confirmationToken: String?
    public var expiresAt: Date?
    public var data: [String: String]?

    public init(
        actionID: String,
        status: ActionStatus,
        message: String,
        confirmationToken: String? = nil,
        expiresAt: Date? = nil,
        data: [String: String]? = nil
    ) {
        self.actionID = actionID
        self.status = status
        self.message = message
        self.confirmationToken = confirmationToken
        self.expiresAt = expiresAt
        self.data = data
    }
}

public struct WindowFrame: Codable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct WindowDescriptor: Codable, Sendable {
    public var windowID: UInt32
    public var bundleID: String?
    public var appName: String
    public var title: String
    public var frame: WindowFrame
    public var isFocused: Bool

    public init(
        windowID: UInt32,
        bundleID: String?,
        appName: String,
        title: String,
        frame: WindowFrame,
        isFocused: Bool
    ) {
        self.windowID = windowID
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.frame = frame
        self.isFocused = isFocused
    }
}

public enum MouseButton: String, Codable, Sendable {
    case left
    case right
    case center
}

public enum TextInputMode: String, Codable, Sendable {
    case auto
    case paste
    case keystroke
}

public enum ExecutionBackend: String, Codable, Sendable {
    case broker
}

public enum PermissionProbeStatus: String, Codable, Sendable {
    case granted
    case denied
    case notDetermined = "not_determined"
    case error
}

public enum PermissionErrorCode: String, Codable, Sendable {
    case automationNotAllowed = "AUTOMATION_NOT_ALLOWED"
    case accessibilityMissing = "ACCESSIBILITY_MISSING"
    case screenRecordingMissing = "SCREEN_RECORDING_MISSING"
    case brokerUnavailable = "BROKER_UNAVAILABLE"
    case execFailed = "EXEC_FAILED"
}

public struct CaptureRegion: Codable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct CaptureResult: Codable, Sendable {
    public var imageBase64: String
    public var format: String
    public var width: Int
    public var height: Int

    public init(imageBase64: String, format: String, width: Int, height: Int) {
        self.imageBase64 = imageBase64
        self.format = format
        self.width = width
        self.height = height
    }
}

public struct OperatorError: LocalizedError, Sendable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? {
        message
    }
}
