import Foundation

public protocol MCPResponseWriter: Sendable {
    func write(response: JSONRPCResponse) async
}

public actor StdioResponseWriter: MCPResponseWriter {
    private let encoder: JSONEncoder

    public init() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    public func write(response: JSONRPCResponse) async {
        guard let data = try? encoder.encode(response) else {
            return
        }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}

public actor MCPServer {
    private let name: String
    private let version: String
    private let writer: MCPResponseWriter
    private let toolExecutor: ToolExecutorProtocol

    private var initialized = false
    private var negotiatedVersion = MCPVersioning.latest
    private var inFlight: [JSONRPCID: Task<Void, Never>] = [:]

    public init(name: String, version: String, writer: MCPResponseWriter, toolExecutor: ToolExecutorProtocol) {
        self.name = name
        self.version = version
        self.writer = writer
        self.toolExecutor = toolExecutor
    }

    public func receive(line: String) async {
        let decoder = JSONDecoder()
        guard let lineData = line.data(using: .utf8) else {
            return
        }

        let request: JSONRPCRequest
        do {
            request = try decoder.decode(JSONRPCRequest.self, from: lineData)
        } catch {
            if let id = extractID(from: lineData) {
                let response = JSONRPCResponse(
                    id: id,
                    error: JSONRPCErrorObject(code: JSONRPCErrorCode.parseError, message: "Invalid JSON-RPC payload")
                )
                await writer.write(response: response)
            }
            return
        }

        guard request.jsonrpc == "2.0" else {
            if let id = request.id {
                let response = JSONRPCResponse(
                    id: id,
                    error: JSONRPCErrorObject(code: JSONRPCErrorCode.invalidRequest, message: "jsonrpc must be 2.0")
                )
                await writer.write(response: response)
            }
            return
        }

        if request.method == "notifications/cancelled" {
            await handleCancelledNotification(request)
            return
        }

        guard let id = request.id else {
            if request.method == "notifications/initialized" {
                initialized = true
            }
            return
        }

        let task = Task {
            let response = await self.processRequest(request)
            await self.writer.write(response: response)
            self.removeInFlight(id: id)
        }
        inFlight[id] = task
    }

    private func removeInFlight(id: JSONRPCID) {
        inFlight[id] = nil
    }

    private func processRequest(_ request: JSONRPCRequest) async -> JSONRPCResponse {
        guard let id = request.id else {
            return JSONRPCResponse(
                id: .string("missing-id"),
                error: JSONRPCErrorObject(code: JSONRPCErrorCode.invalidRequest, message: "id is required for requests")
            )
        }

        do {
            switch request.method {
            case "initialize":
                return try handleInitialize(id: id, params: request.params)
            case "ping":
                return JSONRPCResponse(id: id, result: .object([:]))
            case "tools/list":
                let tools = await toolExecutor.listTools().map { $0.asJSONValue() }
                let result: JSONValue = .object([
                    "tools": .array(tools),
                ])
                return JSONRPCResponse(id: id, result: result)
            case "tools/call":
                if !initialized {
                    return JSONRPCResponse(
                        id: id,
                        error: JSONRPCErrorObject(code: JSONRPCErrorCode.invalidRequest, message: "Server not initialized")
                    )
                }
                let (name, arguments) = try decodeToolCallParams(request.params)
                let result = try await toolExecutor.callTool(name: name, arguments: arguments)
                return JSONRPCResponse(id: id, result: result.asJSONValue())
            default:
                return JSONRPCResponse(
                    id: id,
                    error: JSONRPCErrorObject(code: JSONRPCErrorCode.methodNotFound, message: "Method not found: \(request.method)")
                )
            }
        } catch let error as MCPServerError {
            return JSONRPCResponse(
                id: id,
                error: JSONRPCErrorObject(code: error.code, message: error.message)
            )
        } catch let error as MCPToolError {
            return JSONRPCResponse(
                id: id,
                error: JSONRPCErrorObject(code: error.code, message: error.message)
            )
        } catch {
            return JSONRPCResponse(
                id: id,
                error: JSONRPCErrorObject(code: JSONRPCErrorCode.internalError, message: error.localizedDescription)
            )
        }
    }

    private func handleInitialize(id: JSONRPCID, params: JSONValue?) throws -> JSONRPCResponse {
        guard
            let object = params?.objectValue,
            let requestedVersion = object["protocolVersion"]?.stringValue
        else {
            throw MCPServerError.invalidParams("initialize.params.protocolVersion is required")
        }

        negotiatedVersion = MCPVersioning.negotiate(clientRequestedVersion: requestedVersion)
        let result: JSONValue = .object([
            "protocolVersion": .string(negotiatedVersion),
            "capabilities": .object([
                "tools": .object([
                    "listChanged": .bool(false),
                ]),
            ]),
            "serverInfo": .object([
                "name": .string(name),
                "version": .string(version),
            ]),
        ])
        return JSONRPCResponse(id: id, result: result)
    }

    private func decodeToolCallParams(_ params: JSONValue?) throws -> (String, JSONValue?) {
        guard
            let object = params?.objectValue,
            let name = object["name"]?.stringValue
        else {
            throw MCPServerError.invalidParams("tools/call requires name")
        }
        let arguments = object["arguments"]
        return (name, arguments)
    }

    private func handleCancelledNotification(_ request: JSONRPCRequest) async {
        guard
            let params = request.params?.objectValue,
            let requestIDValue = params["requestId"]
        else {
            return
        }

        let requestID: JSONRPCID?
        switch requestIDValue {
        case .string(let value):
            requestID = .string(value)
        case .number(let value):
            requestID = .int(Int(value))
        default:
            requestID = nil
        }

        guard let requestID else { return }
        inFlight[requestID]?.cancel()
        inFlight[requestID] = nil
    }

    private func extractID(from data: Data) -> JSONRPCID? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rawID = object["id"]
        else {
            return nil
        }

        if let stringID = rawID as? String {
            return .string(stringID)
        }
        if let numberID = rawID as? Int {
            return .int(numberID)
        }
        if let numberID = rawID as? NSNumber {
            return .int(numberID.intValue)
        }
        return nil
    }

    public func waitForInFlightRequests() async {
        let tasks = Array(inFlight.values)
        for task in tasks {
            await task.value
        }
    }
}

private struct MCPServerError: Error, Sendable {
    let code: Int
    let message: String

    static func invalidParams(_ message: String) -> MCPServerError {
        MCPServerError(code: JSONRPCErrorCode.invalidParams, message: message)
    }
}
