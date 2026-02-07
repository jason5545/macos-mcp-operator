import Foundation

public struct ToolDefinition: Sendable {
    public let name: String
    public let description: String
    public let inputSchema: ToolSchema

    public init(name: String, description: String, inputSchema: ToolSchema) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }

    public func asJSONValue() -> JSONValue {
        .object([
            "name": .string(name),
            "description": .string(description),
            "inputSchema": inputSchema.asJSONValue(),
        ])
    }
}

public struct ToolCallResult: Sendable {
    public let structuredContent: JSONValue
    public let text: String
    public let isError: Bool
    public let imageBase64: String?
    public let imageMimeType: String?

    public init(structuredContent: JSONValue, text: String, isError: Bool = false, imageBase64: String? = nil, imageMimeType: String? = nil) {
        self.structuredContent = structuredContent
        self.text = text
        self.isError = isError
        self.imageBase64 = imageBase64
        self.imageMimeType = imageMimeType
    }

    public func asJSONValue() -> JSONValue {
        var contentBlocks: [JSONValue] = []

        if let imageBase64, let imageMimeType {
            contentBlocks.append(.object([
                "type": .string("image"),
                "data": .string(imageBase64),
                "mimeType": .string(imageMimeType),
            ]))
        }

        contentBlocks.append(.object([
            "type": .string("text"),
            "text": .string(text),
        ]))

        var result: [String: JSONValue] = [
            "content": .array(contentBlocks),
            "isError": .bool(isError),
        ]
        result["structuredContent"] = structuredContent
        return .object(result)
    }
}

public protocol ToolExecutorProtocol: Sendable {
    func listTools() async -> [ToolDefinition]
    func callTool(name: String, arguments: JSONValue?) async throws -> ToolCallResult
}
