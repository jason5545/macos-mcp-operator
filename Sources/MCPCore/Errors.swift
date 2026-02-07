import Foundation

public struct MCPToolError: Error, Sendable {
    public let code: Int
    public let message: String

    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }

    public static func invalidParams(_ message: String) -> MCPToolError {
        MCPToolError(code: JSONRPCErrorCode.invalidParams, message: message)
    }

    public static func executionFailed(_ message: String) -> MCPToolError {
        MCPToolError(code: JSONRPCErrorCode.toolExecutionFailed, message: message)
    }
}
