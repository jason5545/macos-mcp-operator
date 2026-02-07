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
}
