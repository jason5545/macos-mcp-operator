import Foundation

public enum SchemaType: String, Sendable {
    case object
    case string
    case number
    case integer
    case boolean
    case array
}

public struct ToolSchema: Sendable {
    public var type: SchemaType
    public var required: Set<String>
    public var properties: [String: SchemaProperty]

    public init(type: SchemaType = .object, required: Set<String> = [], properties: [String: SchemaProperty] = [:]) {
        self.type = type
        self.required = required
        self.properties = properties
    }

    public func asJSONValue() -> JSONValue {
        var propertiesJSON: [String: JSONValue] = [:]
        for (key, property) in properties {
            propertiesJSON[key] = property.asJSONValue()
        }

        let requiredArray = required.sorted().map(JSONValue.string)
        return .object([
            "type": .string(type.rawValue),
            "required": .array(requiredArray),
            "properties": .object(propertiesJSON),
            "additionalProperties": .bool(false),
        ])
    }

    public func validate(arguments: JSONValue?) -> [String] {
        let object = arguments?.objectValue ?? [:]
        var errors: [String] = []

        for key in required where object[key] == nil {
            errors.append("missing required field: \(key)")
        }

        for key in object.keys where properties[key] == nil {
            errors.append("unknown field: \(key)")
        }

        for (key, property) in properties {
            guard let value = object[key] else { continue }
            if !property.matches(value: value) {
                errors.append("field '\(key)' expected \(property.description)")
            }
        }

        return errors
    }
}

public indirect enum SchemaProperty: Sendable {
    case scalar(SchemaType)
    case enumString([String])
    case array(of: SchemaProperty)
    case object(required: Set<String>, properties: [String: SchemaProperty])
    case nullable(SchemaProperty)

    var description: String {
        switch self {
        case .scalar(let type):
            return type.rawValue
        case .enumString(let values):
            return "one of [\(values.joined(separator: ", "))]"
        case .array(let item):
            return "array of \(item.description)"
        case .object:
            return "object"
        case .nullable(let value):
            return "\(value.description) or null"
        }
    }

    func asJSONValue() -> JSONValue {
        switch self {
        case .scalar(let type):
            return .object(["type": .string(type.rawValue)])
        case .enumString(let values):
            return .object([
                "type": .string("string"),
                "enum": .array(values.map(JSONValue.string)),
            ])
        case .array(let item):
            return .object([
                "type": .string("array"),
                "items": item.asJSONValue(),
            ])
        case .object(let required, let properties):
            var mapped: [String: JSONValue] = [:]
            for (key, value) in properties {
                mapped[key] = value.asJSONValue()
            }
            return .object([
                "type": .string("object"),
                "required": .array(required.sorted().map(JSONValue.string)),
                "properties": .object(mapped),
                "additionalProperties": .bool(false),
            ])
        case .nullable(let value):
            return .object([
                "anyOf": .array([value.asJSONValue(), .object(["type": .string("null")])]),
            ])
        }
    }

    func matches(value: JSONValue) -> Bool {
        switch self {
        case .scalar(let type):
            switch type {
            case .string:
                if case .string = value { return true }
                return false
            case .number:
                if case .number = value { return true }
                return false
            case .integer:
                guard case .number(let number) = value else { return false }
                return floor(number) == number
            case .boolean:
                if case .bool = value { return true }
                return false
            case .array:
                if case .array = value { return true }
                return false
            case .object:
                if case .object = value { return true }
                return false
            }
        case .enumString(let values):
            guard case .string(let string) = value else { return false }
            return values.contains(string)
        case .array(let item):
            guard case .array(let values) = value else { return false }
            return values.allSatisfy { item.matches(value: $0) }
        case .object(let required, let properties):
            guard case .object(let object) = value else { return false }
            for key in required where object[key] == nil {
                return false
            }
            for (key, itemValue) in object {
                guard let property = properties[key], property.matches(value: itemValue) else {
                    return false
                }
            }
            return true
        case .nullable(let wrapped):
            if case .null = value { return true }
            return wrapped.matches(value: value)
        }
    }
}
