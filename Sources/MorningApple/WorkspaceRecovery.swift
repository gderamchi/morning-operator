import Foundation
import MorningCore

/// One saved element that is either read or kept as its exact saved text. Decoding never
/// fails because of the element itself, so one damaged element cannot refuse its file.
/// The element's own decoder stays strict; this wrapper only decides what to do on failure.
///
/// The text is cut from the bytes `AtomicJSONFile.load` decodes (`atomicJSONFileData`), so
/// numbers, escapes and spacing are kept byte for byte. Without those bytes, or if the
/// element cannot be found in them, the failure stands and the whole file is refused.
public struct RecoverableElement<Value: Decodable & Sendable>: Decodable, Sendable {
    public let value: Value?
    /// The element's exact saved JSON text, when it could not be read.
    public let raw: String?

    public init(from decoder: any Decoder) throws {
        if let read = try? Value(from: decoder) { value = read; raw = nil; return }
        guard let data = decoder.userInfo[.atomicJSONFileData] as? Data,
              let text = RawJSONText.find(in: data, at: decoder.codingPath) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "An unreadable element whose saved text could not be kept."))
        }
        value = nil
        raw = text
    }
}

/// Finds the exact text of one value in a JSON document by its coding path. It walks only
/// the objects and arrays on the path and skips every other value without recursion.
/// Returns nil for anything unexpected, including a key that appears twice.
enum RawJSONText {
    static func find(in data: Data, at path: [any CodingKey]) -> String? {
        let bytes = [UInt8](data)
        var index = 0
        skipSpace(bytes, &index)
        for key in path {
            guard index < bytes.count else { return nil }
            if let position = key.intValue {
                guard bytes[index] == UInt8(ascii: "[") else { return nil }
                index += 1
                for _ in 0..<position {
                    skipSpace(bytes, &index)
                    guard skipValue(bytes, &index) else { return nil }
                    skipSpace(bytes, &index)
                    guard index < bytes.count, bytes[index] == UInt8(ascii: ",") else { return nil }
                    index += 1
                }
                skipSpace(bytes, &index)
            } else {
                guard bytes[index] == UInt8(ascii: "{") else { return nil }
                index += 1
                var found: Int?
                while true {
                    skipSpace(bytes, &index)
                    guard index < bytes.count else { return nil }
                    if bytes[index] == UInt8(ascii: "}") { break }
                    let keyStart = index
                    guard bytes[index] == UInt8(ascii: "\""), skipValue(bytes, &index),
                          let name = try? JSONDecoder().decode(String.self, from: Data(bytes[keyStart..<index]))
                    else { return nil }
                    skipSpace(bytes, &index)
                    guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { return nil }
                    index += 1
                    skipSpace(bytes, &index)
                    if name == key.stringValue {
                        guard found == nil else { return nil }
                        found = index
                    }
                    guard skipValue(bytes, &index) else { return nil }
                    skipSpace(bytes, &index)
                    guard index < bytes.count else { return nil }
                    if bytes[index] == UInt8(ascii: ",") { index += 1 }
                    else if bytes[index] != UInt8(ascii: "}") { return nil }
                }
                guard let found else { return nil }
                index = found
            }
        }
        let start = index
        guard skipValue(bytes, &index) else { return nil }
        return String(bytes: bytes[start..<index], encoding: .utf8)
    }

    private static func skipSpace(_ bytes: [UInt8], _ index: inout Int) {
        while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
    }

    /// Moves past one value. Strings are skipped with their escapes; brackets are counted.
    private static func skipValue(_ bytes: [UInt8], _ index: inout Int) -> Bool {
        guard index < bytes.count else { return false }
        var depth = 0
        repeat {
            guard index < bytes.count else { return false }
            switch bytes[index] {
            case UInt8(ascii: "\""):
                index += 1
                while index < bytes.count, bytes[index] != UInt8(ascii: "\"") {
                    index += bytes[index] == UInt8(ascii: "\\") ? 2 : 1
                }
                guard index < bytes.count else { return false }
                index += 1
            case UInt8(ascii: "{"), UInt8(ascii: "["): depth += 1; index += 1
            case UInt8(ascii: "}"), UInt8(ascii: "]"):
                guard depth > 0 else { return false }
                depth -= 1; index += 1
            case UInt8(ascii: ","), 0x20, 0x09, 0x0A, 0x0D:
                guard depth > 0 else { return false }
                index += 1
            default:
                // A scalar: a number, true, false or null.
                index += 1
                if depth == 0 {
                    while index < bytes.count, !",]} \t\n\r".utf8.contains(bytes[index]) { index += 1 }
                }
            }
        } while depth > 0
        return true
    }
}

/// Reads `MorningHistory` one record at a time: an unreadable past morning or day of app
/// usage is set aside alone. The keys are those `MorningHistory` writes.
struct RecoverableHistory: Decodable, Sendable {
    let value: MorningHistory
    let setAside: [(SetAsideWorkspacePart, String)]

    private enum CodingKeys: String, CodingKey { case runs, appObservations }
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let runs = try values.decodeIfPresent([RecoverableElement<MorningRunRecord>].self, forKey: .runs) ?? []
        let days = try values.decodeIfPresent([RecoverableElement<DailyAppObservation>].self, forKey: .appObservations) ?? []
        value = MorningHistory(runs: runs.compactMap(\.value), appObservations: days.compactMap(\.value))
        setAside = runs.compactMap { $0.raw.map { (.historyRun, $0) } }
            + days.compactMap { $0.raw.map { (.appObservation, $0) } }
    }
}

/// One entry of the saved `setAside` list in its own form: exactly a part name and a text.
struct SetAsideEntry: Decodable, Sendable {
    let part: String
    let raw: String

    private enum CodingKeys: String, CodingKey { case part, raw }
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // Another key would be lost by writing back only these two: keep it as text instead.
        // Count every key present, not only the two this type names.
        guard try decoder.container(keyedBy: AnyKey.self).allKeys.count == 2 else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not an entry."))
        }
        part = try values.decode(String.self, forKey: .part)
        raw = try values.decode(String.self, forKey: .raw)
    }

    var saved: PreservedJSONValue { .object(["part": .string(part), "raw": .string(raw)]) }

    private struct AnyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    /// An earlier entry not in this form, kept as its exact saved text.
    static func unrecognized(_ raw: String) -> PreservedJSONValue {
        .object(["part": .string("unrecognized"), "raw": .string(raw)])
    }
}

/// An element of the saved workspace that could not be read and was set aside on load.
public enum SetAsideWorkspacePart: String, Sendable, CaseIterable {
    case session, previousRoutine, historyRun, appObservation, capture

    /// The saved form: the part's name and the element's exact saved JSON text.
    static func entry(part: SetAsideWorkspacePart, raw: String) -> PreservedJSONValue {
        .object(["part": .string(part.rawValue), "raw": .string(raw)])
    }

    /// The English sentence, which is also its key in the String Catalog.
    public var sentenceKey: String {
        switch self {
        case .session: "Your morning in progress couldn’t be read, so it was not resumed."
        case .previousRoutine: "Your previous routine couldn’t be read, so going back to it is not offered."
        case .historyRun: "Some past mornings couldn’t be read and are left out of your history."
        case .appObservation: "Some days of app use couldn’t be read and are left out of your history."
        case .capture: "Some saved thoughts and ideas couldn’t be read and are left out."
        }
    }

    public static let keptKey = "Everything else is restored. What couldn’t be read is kept in your saved file, not deleted."

    /// What the person reads after a load that set something aside, or nil when nothing was.
    public static func notice(for parts: [SetAsideWorkspacePart], bundle: Bundle? = nil) -> String? {
        guard !parts.isEmpty else { return nil }
        let sentences = allCases.filter(parts.contains).map(\.sentenceKey) + [keptKey]
        return sentences.map { (bundle ?? .module).localizedString(forKey: $0, value: nil, table: nil) }.joined(separator: " ")
    }
}

/// The part of the saved workspace that made the whole file unreadable, in plain words.
/// Read from the failure's coding path; the raw error text is never shown.
public enum UnreadableWorkspacePart: Sendable, Equatable, CaseIterable {
    case notOpened, newerFormat, file, routine, history, captures, observations, suggestion, appleItems
    case settings, startedMornings, other

    public init(error: any Error) {
        if case PersistenceError.unsupportedSchema? = error as? PersistenceError { self = .newerFormat; return }
        // Thrown after decoding, while moving a single legacy observation into the archive.
        if error is ObservationArchiveError { self = .observations; return }
        let path: [any CodingKey]
        switch error as? DecodingError {
        case .typeMismatch(_, let context)?, .valueNotFound(_, let context)?, .dataCorrupted(let context)?:
            path = context.codingPath
        case .keyNotFound(let key, let context)?:
            path = context.codingPath + [key]
        default:
            // Not a decoding failure: the file could not be opened or read at all.
            self = .notOpened
            return
        }
        // The file is an envelope: {"schemaVersion": 1, "value": {…the workspace…}}.
        guard path.count >= 2, path[0].stringValue == "value" else { self = .file; return }
        switch path[1].stringValue {
        case "schemaVersion": self = .file
        case "routine": self = .routine
        case "history": self = .history
        case "captures": self = .captures
        case "observationArchive", "observationNotes", "observationSource", "observationVideoEvidence",
             "observationContextClassification", "selectedObservationID": self = .observations
        case "pendingRoutineProposal", "routinePreferences": self = .suggestion
        case "receipts", "pendingCaptures": self = .appleItems
        case "automatic", "readAloud", "showMorningOnLockScreen", "voiceIdentifier",
             "sessionTimeZone", "sessionTimingInterrupted": self = .settings
        case "consumedMorningEntryIDs": self = .startedMornings
        default: self = .other
        }
    }

    /// The English sentence, which is also its key in the String Catalog.
    public var sentenceKey: String {
        switch self {
        case .notOpened: "The saved file couldn’t be opened."
        case .newerFormat: "The saved file was written by a newer version of MORE."
        case .file: "The saved file is damaged as a whole, so none of it could be read."
        case .routine: "Your approved routine couldn’t be read."
        case .history: "Your past mornings couldn’t be read."
        case .captures: "Your saved thoughts and ideas couldn’t be read."
        case .observations: "Your saved observations couldn’t be read."
        case .suggestion: "Your saved choices or a saved suggestion couldn’t be read."
        case .appleItems: "Your record of items sent to Calendar and Reminders couldn’t be read."
        case .settings: "Your settings couldn’t be read."
        case .startedMornings: "The list of mornings started from a shortcut couldn’t be read."
        case .other: "One part of your saved workspace couldn’t be read."
        }
    }

    public static let adviceKey = "Your file is kept unchanged and new changes are not saved. An update of MORE may be able to read it. To start again now, forget MORE’s local data in Privacy."

    public func sentence(bundle: Bundle? = nil) -> String {
        (bundle ?? .module).localizedString(forKey: sentenceKey, value: nil, table: nil)
    }

    public static func advice(bundle: Bundle? = nil) -> String {
        (bundle ?? .module).localizedString(forKey: adviceKey, value: nil, table: nil)
    }
}

