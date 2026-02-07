import CoreTypes
import Foundation

public enum BrokerMethod: String, Codable, Sendable {
    case health = "health"
    case stop = "stop"
    case applescriptRun = "applescript_run"
    case applescriptAppCommand = "applescript_app_command"
    case probeAutomation = "probe_automation"
}

public struct BrokerRequest: Codable, Sendable {
    public var id: String
    public var method: BrokerMethod
    public var script: String?
    public var targetBundleID: String?
    public var bundleID: String?
    public var appName: String?
    public var command: String?
    public var activate: Bool?

    public init(
        id: String = UUID().uuidString,
        method: BrokerMethod,
        script: String? = nil,
        targetBundleID: String? = nil,
        bundleID: String? = nil,
        appName: String? = nil,
        command: String? = nil,
        activate: Bool? = nil
    ) {
        self.id = id
        self.method = method
        self.script = script
        self.targetBundleID = targetBundleID
        self.bundleID = bundleID
        self.appName = appName
        self.command = command
        self.activate = activate
    }
}

public struct BrokerResponse: Codable, Sendable {
    public var id: String
    public var ok: Bool
    public var message: String
    public var code: String?
    public var stdout: String?
    public var stderr: String?
    public var cancelledActions: Int?
    public var probeStatus: PermissionProbeStatus?
    public var probeErrorCode: PermissionErrorCode?
    public var remediation: [String]?

    public init(
        id: String,
        ok: Bool,
        message: String,
        code: String? = nil,
        stdout: String? = nil,
        stderr: String? = nil,
        cancelledActions: Int? = nil,
        probeStatus: PermissionProbeStatus? = nil,
        probeErrorCode: PermissionErrorCode? = nil,
        remediation: [String]? = nil
    ) {
        self.id = id
        self.ok = ok
        self.message = message
        self.code = code
        self.stdout = stdout
        self.stderr = stderr
        self.cancelledActions = cancelledActions
        self.probeStatus = probeStatus
        self.probeErrorCode = probeErrorCode
        self.remediation = remediation
    }

    public static func success(
        id: String,
        message: String,
        stdout: String? = nil,
        stderr: String? = nil
    ) -> BrokerResponse {
        BrokerResponse(
            id: id,
            ok: true,
            message: message,
            stdout: stdout,
            stderr: stderr
        )
    }

    public static func failure(
        id: String,
        code: String,
        message: String,
        stderr: String? = nil
    ) -> BrokerResponse {
        BrokerResponse(
            id: id,
            ok: false,
            message: message,
            code: code,
            stderr: stderr
        )
    }
}
