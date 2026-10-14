import Foundation

/// Keeps an unreadable preference payload through unrelated workspace saves.
/// A caller must explicitly replace it after the user chooses to reset choices.
/// For optional legacy fields, distinguish an absent key from a present null:
/// use contains(_:) followed by decode(_:forKey:), not decodeIfPresent.
public struct RecoverableRoutinePreferences: Codable, Sendable {
    public let value: RoutinePreferenceJournal?
    private let original: PreservedJSONValue?

    public init(_ value: RoutinePreferenceJournal) { self.value = value; original = nil }

    /// A durable recovery marker when legacy choices could not be migrated.
    public init(unreadable message: String) { value = nil; original = .string(message) }

    public init(from decoder: any Decoder) throws {
        if let journal = try? RoutinePreferenceJournal(from: decoder) {
            value = journal
            original = nil
        } else {
            value = nil
            original = try PreservedJSONValue(from: decoder)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        if let value { try value.encode(to: encoder) }
        else { try (original ?? .null).encode(to: encoder) }
    }
}

/// Preserves JSON values and unknown fields, not whitespace, key order or a
/// numeric token's spelling. Nothing from a recovery payload drives learning.
/// Used for unreadable saved choices and for workspace elements set aside on load.
///
/// A number a `Double` cannot hold exactly (an integer beyond 64 bits, or a decimal
/// fraction) is kept as a `Decimal`, which writes back the same digits. A number beyond
/// both (such as 1e400) and nesting deeper than `maximumDepth` are refused: the caller
/// then refuses the whole file, which is left unchanged, rather than keeping an altered copy.
public indirect enum PreservedJSONValue: Codable, Sendable, Equatable {
    case null, bool(Bool), integer(Int64), unsigned(UInt64), number(Double), decimal(Decimal), string(String)
    case array([PreservedJSONValue]), object([String: PreservedJSONValue])

    /// Counted from the root of the decoded document. Real saved data is far shallower.
    public static let maximumDepth = 96

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard decoder.codingPath.count <= Self.maximumDepth else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Nested too deeply to keep.")
        }
        if container.decodeNil() { self = .null }
        else if let v = try? container.decode(Bool.self) { self = .bool(v) }
        else if let v = try? container.decode(Int64.self) { self = .integer(v) }
        else if let v = try? container.decode(UInt64.self) { self = .unsigned(v) }
        else if let exact = try? container.decode(Decimal.self),
                (try? container.decode(Double.self)).map({ Decimal($0) != exact }) ?? true { self = .decimal(exact) }
        else if let v = try? container.decode(Double.self) { self = .number(v) }
        else if let v = try? container.decode(String.self) { self = .string(v) }
        else if let v = try? container.decode([PreservedJSONValue].self) { self = .array(v) }
        else { self = .object(try container.decode([String: PreservedJSONValue].self)) }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let v): try container.encode(v)
        case .integer(let v): try container.encode(v)
        case .unsigned(let v): try container.encode(v)
        case .number(let v): try container.encode(v)
        case .decimal(let v): try container.encode(v)
        case .string(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        }
    }
}
