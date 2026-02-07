import Foundation

public enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.typeMismatch(
                JSONValue.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON value")
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    public static func from(any value: Any) -> JSONValue {
        switch value {
        case let value as String:
            return .string(value)
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                return .bool(value.boolValue)
            }
            return .number(value.doubleValue)
        case let value as Bool:
            return .bool(value)
        case let value as Double:
            return .number(value)
        case let value as Float:
            return .number(Double(value))
        case let value as Int:
            return .number(Double(value))
        case let value as [Any]:
            return .array(value.map(JSONValue.from(any:)))
        case let value as [String: Any]:
            var mapped: [String: JSONValue] = [:]
            for (key, val) in value {
                mapped[key] = JSONValue.from(any: val)
            }
            return .object(mapped)
        default:
            return .null
        }
    }

    public var objectValue: [String: JSONValue]? {
        guard case .object(let obj) = self else { return nil }
        return obj
    }

    public var arrayValue: [JSONValue]? {
        guard case .array(let array) = self else { return nil }
        return array
    }

    public var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    public var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    public var doubleValue: Double? {
        guard case .number(let value) = self else { return nil }
        return value
    }

    public var intValue: Int? {
        guard case .number(let value) = self else { return nil }
        return Int(value)
    }

    public func prettyPrinted() -> String {
        guard
            let data = try? JSONEncoder().encode(self),
            let object = try? JSONSerialization.jsonObject(with: data),
            let formatted = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]),
            let string = String(data: formatted, encoding: .utf8)
        else {
            return "{}"
        }
        return string
    }
}

public extension Dictionary where Key == String, Value == JSONValue {
    func value<T: LosslessStringConvertible>(for key: String) -> T? {
        guard let raw = self[key] else { return nil }
        switch raw {
        case .string(let value):
            return T(value)
        case .number(let value):
            return T(String(value))
        default:
            return nil
        }
    }
}
