import XCTest
@testable import MCPCore

private actor TestWriter: MCPResponseWriter {
    private(set) var responses: [JSONRPCResponse] = []

    func write(response: JSONRPCResponse) async {
        responses.append(response)
    }

    func drain() -> [JSONRPCResponse] {
        let copy = responses
        responses = []
        return copy
    }
}

private actor EmptyExecutor: ToolExecutorProtocol {
    func listTools() async -> [ToolDefinition] { [] }
    func callTool(name: String, arguments: JSONValue?) async throws -> ToolCallResult {
        ToolCallResult(structuredContent: .object([:]), text: "ok")
    }
}

private actor ImageExecutor: ToolExecutorProtocol {
    func listTools() async -> [ToolDefinition] { [] }
    func callTool(name: String, arguments: JSONValue?) async throws -> ToolCallResult {
        _ = name
        _ = arguments
        return ToolCallResult(
            structuredContent: .object([:]),
            text: "ok",
            imageBase64: Data("hello".utf8).base64EncodedString(),
            imageMimeType: "image/png"
        )
    }
}

final class MCPServerTests: XCTestCase {
    func testInitializeNegotiatesToLatestWhenUnsupported() async throws {
        let writer = TestWriter()
        let server = MCPServer(name: "test", version: "1.0", writer: writer, toolExecutor: EmptyExecutor())

        let line = #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2099-01-01"}}"#
        await server.receive(line: line)

        try await Task.sleep(nanoseconds: 30_000_000)
        let responses = await writer.drain()

        XCTAssertEqual(responses.count, 1)
        XCTAssertNil(responses[0].error)
        XCTAssertEqual(responses[0].result?.objectValue?["protocolVersion"]?.stringValue, "2025-11-25")
    }

    func testToolsCallUsesInlineImageForCodexClient() async throws {
        let writer = TestWriter()
        let server = MCPServer(name: "test", version: "1.0", writer: writer, toolExecutor: ImageExecutor())

        await server.receive(
            line: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","clientInfo":{"name":"Codex Desktop","version":"1.0"}}}"#
        )
        await server.receive(line: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        await server.receive(
            line: #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"screen_capture","arguments":{}}}"#
        )

        try await Task.sleep(nanoseconds: 30_000_000)
        let responses = await writer.drain()
        let toolResponse = try XCTUnwrap(responses.first(where: { $0.id == .int(2) }))
        let content = try XCTUnwrap(toolResponse.result?.objectValue?["content"]?.arrayValue)
        let hasImageBlock = content.contains(where: { $0.objectValue?["type"]?.stringValue == "image" })
        XCTAssertTrue(hasImageBlock)
    }

    func testToolsCallUsesImagePathForClaudeClient() async throws {
        let writer = TestWriter()
        let server = MCPServer(name: "test", version: "1.0", writer: writer, toolExecutor: ImageExecutor())

        await server.receive(
            line: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","clientInfo":{"name":"Claude Code","version":"1.0"}}}"#
        )
        await server.receive(line: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        await server.receive(
            line: #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"screen_capture","arguments":{}}}"#
        )

        try await Task.sleep(nanoseconds: 30_000_000)
        let responses = await writer.drain()
        let toolResponse = try XCTUnwrap(responses.first(where: { $0.id == .int(2) }))
        let content = try XCTUnwrap(toolResponse.result?.objectValue?["content"]?.arrayValue)

        let hasImageBlock = content.contains(where: { $0.objectValue?["type"]?.stringValue == "image" })
        XCTAssertFalse(hasImageBlock)

        let structured = try XCTUnwrap(toolResponse.result?.objectValue?["structuredContent"]?.objectValue)
        let imagePath = try XCTUnwrap(structured["imagePath"]?.stringValue)
        XCTAssertTrue(FileManager.default.fileExists(atPath: imagePath))
    }
}
