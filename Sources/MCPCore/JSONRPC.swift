import Foundation

public enum JSONRPCID: Codable, Hashable, Sendable, CustomStringConvertible {
    case string(String)
    case int(Int)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
            return
        }
        if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
            return
        }
        throw DecodingError.typeMismatch(
            JSONRPCID.self,
            DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "id must be string or int")
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        }
    }

    public var description: String {
        switch self {
        case .string(let value):
            return value
        case .int(let value):
            return String(value)
        }
    }
}

public struct JSONRPCRequest: Codable, Sendable {
    public var jsonrpc: String
    public var id: JSONRPCID?
    public var method: String
    public var params: JSONValue?

    public init(jsonrpc: String = "2.0", id: JSONRPCID? = nil, method: String, params: JSONValue? = nil) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.method = method
        self.params = params
    }
}

public struct JSONRPCErrorObject: Codable, Sendable {
    public var code: Int
    public var message: String
    public var data: JSONValue?

    public init(code: Int, message: String, data: JSONValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }
}

public struct JSONRPCResponse: Codable, Sendable {
    public var jsonrpc: String
    public var id: JSONRPCID
    public var result: JSONValue?
    public var error: JSONRPCErrorObject?

    public init(id: JSONRPCID, result: JSONValue) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = result
        self.error = nil
    }

    public init(id: JSONRPCID, error: JSONRPCErrorObject) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = nil
        self.error = error
    }
}

public enum JSONRPCErrorCode {
    public static let parseError = -32700
    public static let invalidRequest = -32600
    public static let methodNotFound = -32601
    public static let invalidParams = -32602
    public static let internalError = -32603

    public static let toolExecutionFailed = -32000
}
