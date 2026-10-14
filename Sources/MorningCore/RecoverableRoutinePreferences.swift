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
/// Numbers are kept by value, never rounded: a 64-bit integer as it is, any other number
/// as a `Decimal` (or the `Double` it equals exactly), which writes back the same digits.
/// Refused, so that the caller refuses the whole file and leaves it unchanged rather than
/// keep an altered copy: a number outside `Decimal`'s range (such as 1e400 or 1e-200), a
/// number with 38 or more significant digits (where `Decimal` parsing drops digits), and
/// nesting deeper than `maximumDepth`. The app itself writes only 64-bit integers and
/// `Double`s in their shortest form (at most 17 digits). Known limit: a hand-written number
/// of more than 38 digits whose dropped digits leave fewer than 38 is not detected.
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
        else if let exact = try? container.decode(Decimal.self) {
            guard Self.significantDigits(exact) < 38 else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "A number too long to keep exactly.")
            }
            if let v = try? container.decode(Double.self), Decimal(v) == exact { self = .number(v) }
            else { self = .decimal(exact) }
        }
        else if (try? container.decode(Double.self)) != nil {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "A number outside the range kept exactly.")
        }
        else if let v = try? container.decode(String.self) { self = .string(v) }
        else if let v = try? container.decode([PreservedJSONValue].self) { self = .array(v) }
        else { self = .object(try container.decode([String: PreservedJSONValue].self)) }
    }

    /// How many levels of arrays and objects lie below this value; 0 for a scalar.
    public var height: Int {
        switch self {
        case .array(let items): 1 + (items.map(\.height).max() ?? 0)
        case .object(let fields): 1 + (fields.values.map(\.height).max() ?? 0)
        default: 0
        }
    }

    private static func significantDigits(_ value: Decimal) -> Int {
        let digits = value.description.filter(\.isNumber).drop { $0 == "0" }
        return digits.reversed().drop { $0 == "0" }.count
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
