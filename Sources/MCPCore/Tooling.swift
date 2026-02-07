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

public enum ToolImageDeliveryMode: Sendable {
    case inlineBase64
    case filePath
    case both
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

    public func asJSONValue(imageDeliveryMode: ToolImageDeliveryMode = .inlineBase64) -> JSONValue {
        var contentBlocks: [JSONValue] = []
        var effectiveStructuredContent = structuredContent

        if let imageBase64, let imageMimeType {
            switch imageDeliveryMode {
            case .inlineBase64:
                contentBlocks.append(Self.inlineImageBlock(base64: imageBase64, mimeType: imageMimeType))
            case .filePath:
                if let imagePath = Self.materializeImageFile(base64: imageBase64, mimeType: imageMimeType) {
                    effectiveStructuredContent = Self.mergeImagePath(
                        imagePath,
                        mimeType: imageMimeType,
                        into: effectiveStructuredContent
                    )
                    contentBlocks.append(Self.imagePathTextBlock(path: imagePath))
                } else {
                    contentBlocks.append(Self.inlineImageBlock(base64: imageBase64, mimeType: imageMimeType))
                }
            case .both:
                contentBlocks.append(Self.inlineImageBlock(base64: imageBase64, mimeType: imageMimeType))
                if let imagePath = Self.materializeImageFile(base64: imageBase64, mimeType: imageMimeType) {
                    effectiveStructuredContent = Self.mergeImagePath(
                        imagePath,
                        mimeType: imageMimeType,
                        into: effectiveStructuredContent
                    )
                    contentBlocks.append(Self.imagePathTextBlock(path: imagePath))
                }
            }
        }

        contentBlocks.append(.object([
            "type": .string("text"),
            "text": .string(text),
        ]))

        var result: [String: JSONValue] = [
            "content": .array(contentBlocks),
            "isError": .bool(isError),
        ]
        result["structuredContent"] = effectiveStructuredContent
        return .object(result)
    }

    private static func inlineImageBlock(base64: String, mimeType: String) -> JSONValue {
        .object([
            "type": .string("image"),
            "data": .string(base64),
            "mimeType": .string(mimeType),
        ])
    }

    private static func imagePathTextBlock(path: String) -> JSONValue {
        .object([
            "type": .string("text"),
            "text": .string("Image saved to \(path)"),
        ])
    }

    private static func mergeImagePath(_ path: String, mimeType: String, into structuredContent: JSONValue) -> JSONValue {
        if var object = structuredContent.objectValue {
            object["imagePath"] = .string(path)
            object["imageMimeType"] = .string(mimeType)
            return .object(object)
        }
        return .object([
            "payload": structuredContent,
            "imagePath": .string(path),
            "imageMimeType": .string(mimeType),
        ])
    }

    private static func materializeImageFile(base64: String, mimeType: String) -> String? {
        guard let data = Data(base64Encoded: base64) else {
            return nil
        }

        let fileManager = FileManager.default
        let directoryURL = fileManager.temporaryDirectory.appendingPathComponent("macos-mcp-operator-images", isDirectory: true)
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let fileExtension = mimeType == "image/jpeg" ? "jpg" : "png"
            let fileURL = directoryURL.appendingPathComponent(UUID().uuidString).appendingPathExtension(fileExtension)
            try data.write(to: fileURL, options: .atomic)
            return fileURL.path
        } catch {
            return nil
        }
    }
}

public protocol ToolExecutorProtocol: Sendable {
    func listTools() async -> [ToolDefinition]
    func callTool(name: String, arguments: JSONValue?) async throws -> ToolCallResult
}
