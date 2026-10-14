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
        guard var index = locate(data, path) else { return nil }
        let start = index
        guard skipValue(data, &index) else { return nil }
        return String(bytes: data[start..<index], encoding: .utf8)
    }

    /// Every key of the object at `path`, in order and with repeats, or nil.
    static func keys(in data: Data, at path: [any CodingKey]) -> [String]? {
        guard var index = locate(data, path) else { return nil }
        return members(data, &index)?.map(\.name)
    }

    /// Where the value at `path` starts.
    private static func locate(_ bytes: Data, _ path: [any CodingKey]) -> Int? {
        var index = bytes.startIndex
        // JSONDecoder accepts a UTF-8 byte order mark before the document.
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { index += 3 }
        skipSpace(bytes, &index)
        for key in path {
            guard index < bytes.endIndex else { return nil }
            if let position = key.intValue {
                guard position >= 0, bytes[index] == UInt8(ascii: "[") else { return nil }
                index += 1
                for _ in 0..<position {
                    skipSpace(bytes, &index)
                    guard skipValue(bytes, &index) else { return nil }
                    skipSpace(bytes, &index)
                    guard index < bytes.endIndex, bytes[index] == UInt8(ascii: ",") else { return nil }
                    index += 1
                }
                skipSpace(bytes, &index)
                guard index < bytes.endIndex, bytes[index] != UInt8(ascii: "]") else { return nil }
            } else {
                guard let found = members(bytes, &index)?.filter({ $0.name == key.stringValue }),
                      found.count == 1 else { return nil }
                index = found[0].valueStart
            }
        }
        return index
    }

    /// Walks the object starting at `index` and leaves `index` after its closing brace.
    private static func members(_ bytes: Data, _ index: inout Int) -> [(name: String, valueStart: Int)]? {
        guard index < bytes.endIndex, bytes[index] == UInt8(ascii: "{") else { return nil }
        index += 1
        var result: [(name: String, valueStart: Int)] = []
        while true {
            skipSpace(bytes, &index)
            guard index < bytes.endIndex else { return nil }
            if bytes[index] == UInt8(ascii: "}"), result.isEmpty { index += 1; return result }
            let keyStart = index
            guard bytes[index] == UInt8(ascii: "\""), skipValue(bytes, &index),
                  let name = try? JSONDecoder().decode(String.self, from: Data(bytes[keyStart..<index]))
            else { return nil }
            skipSpace(bytes, &index)
            guard index < bytes.endIndex, bytes[index] == UInt8(ascii: ":") else { return nil }
            index += 1
            skipSpace(bytes, &index)
            result.append((name, index))
            guard skipValue(bytes, &index) else { return nil }
            skipSpace(bytes, &index)
            guard index < bytes.endIndex else { return nil }
            if bytes[index] == UInt8(ascii: ",") { index += 1 }
            else if bytes[index] == UInt8(ascii: "}") { index += 1; return result }
            else { return nil }
        }
    }

    private static func skipSpace(_ bytes: Data, _ index: inout Int) {
        while index < bytes.endIndex, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
    }

    /// Moves past one value. Strings are skipped with their escapes; brackets are counted.
    private static func skipValue(_ bytes: Data, _ index: inout Int) -> Bool {
        guard index < bytes.endIndex else { return false }
        var depth = 0
        repeat {
            guard index < bytes.endIndex else { return false }
            switch bytes[index] {
            case UInt8(ascii: "\""):
                index += 1
                while index < bytes.endIndex, bytes[index] != UInt8(ascii: "\"") {
                    index += bytes[index] == UInt8(ascii: "\\") ? 2 : 1
                }
                guard index < bytes.endIndex else { return false }
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
                guard depth > 0 || "-0123456789tfn".utf8.contains(bytes[index]) else { return false }
                index += 1
                if depth == 0 {
                    while index < bytes.endIndex, !",]} \t\n\r".utf8.contains(bytes[index]) { index += 1 }
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

/// Reads `RoutineBudgetAndFeedback` with its own decoder, which never fails and leaves out
/// what it cannot use, then sets aside as exact saved text every saved part that the result
/// left out: an unreadable or out-of-range target, an acceptance it does not keep, a feedback
/// record it does not keep, or the whole value when it is not an object. Nothing that was
/// saved is dropped without being kept and named. Null or missing parts are "none", as before.
/// A key repeated in the value, its acceptance or a feedback record would be collapsed by the
/// decoder, so such a value is set aside whole and none of it is used. The app never writes one.
struct RecoverableBudgetAndFeedback: Decodable, Sendable {
    let value: RoutineBudgetAndFeedback
    let setAside: [(SetAsideWorkspacePart, String)]

    private enum CodingKeys: String, CodingKey { case targetMinutes, acceptedLongerPlan, feedback }
    private struct Index: CodingKey {
        let intValue: Int?
        var stringValue: String { String(intValue ?? 0) }
        init(_ index: Int) { intValue = index }
        init?(intValue: Int) { self.intValue = intValue }
        init?(stringValue: String) { nil }
    }
    /// Always decodes, so the list advances past an unreadable record.
    private struct Probe: Decodable {
        let record: RoutineSessionFeedback?
        init(from decoder: any Decoder) throws { record = try? RoutineSessionFeedback(from: decoder) }
    }

    init(from decoder: any Decoder) throws {
        let value = try RoutineBudgetAndFeedback(from: decoder)
        let data = decoder.userInfo[.atomicJSONFileData] as? Data
        func raw(_ path: [any CodingKey]) throws -> String {
            guard let data,
                  let text = RawJSONText.find(in: data, at: decoder.codingPath + path) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath + path,
                    debugDescription: "An unreadable element whose saved text could not be kept."))
            }
            return text
        }
        guard let values = try? decoder.container(keyedBy: CodingKeys.self) else {
            self.value = value
            setAside = [(.timeBudgetAndFeedback, try raw([]))]
            return
        }
        // True for an object with a repeated key, and for one whose keys cannot be counted (for
        // example a trailing comma the decoder accepts but this scan does not): either may hide a
        // value. Without the saved bytes (never the case for the workspace file) keys cannot be counted.
        func repeats(_ path: [any CodingKey]) -> Bool {
            guard let data else { return false }
            if let keys = RawJSONText.keys(in: data, at: decoder.codingPath + path) { return Set(keys).count != keys.count }
            guard let text = RawJSONText.find(in: data, at: decoder.codingPath + path) else { return true }
            return text.hasPrefix("{")
        }
        let acceptanceSaved = values.contains(.acceptedLongerPlan) && (try? values.decodeNil(forKey: .acceptedLongerPlan)) == false
        let count = (try? values.nestedUnkeyedContainer(forKey: .feedback))?.count ?? 0
        if repeats([]) || (acceptanceSaved && repeats([CodingKeys.acceptedLongerPlan]))
            || (0..<count).contains(where: { repeats([CodingKeys.feedback, Index($0)]) }) {
            self.value = RoutineBudgetAndFeedback()
            setAside = [(.timeBudgetAndFeedback, try raw([]))]
            return
        }
        self.value = value
        func saved(_ key: CodingKeys) -> Bool { values.contains(key) && (try? values.decodeNil(forKey: key)) == false }
        var parts: [(SetAsideWorkspacePart, String)] = []
        if saved(.targetMinutes), value.targetMinutes == nil {
            parts.append((.timeTarget, try raw([CodingKeys.targetMinutes])))
        }
        if saved(.acceptedLongerPlan), value.acceptedLongerPlan == nil {
            parts.append((.longerPlanAcceptance, try raw([CodingKeys.acceptedLongerPlan])))
        }
        if saved(.feedback) {
            if var list = try? values.nestedUnkeyedContainer(forKey: .feedback) {
                while !list.isAtEnd {
                    let index = list.currentIndex
                    let probe = try list.decode(Probe.self)
                    // An exact repeat of a kept record loses nothing.
                    if let record = probe.record, value.feedback.contains(record) { continue }
                    parts.append((.runFeedback, try raw([CodingKeys.feedback, Index(index)])))
                }
            } else {
                parts.append((.runFeedback, try raw([CodingKeys.feedback])))
            }
        }
        setAside = parts
    }
}

/// One entry of the saved `setAside` list in its own form: exactly a part name and a text.
struct SetAsideEntry: Decodable, Sendable {
    let part: String
    let raw: String

    private enum CodingKeys: String, CodingKey { case part, raw }
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // Another key, or a repeated one (which the decoder silently collapses), would be lost
        // by writing back only these two: keep the entry as text instead. Read from the bytes.
        guard let data = decoder.userInfo[.atomicJSONFileData] as? Data,
              RawJSONText.keys(in: data, at: decoder.codingPath)?.sorted() == ["part", "raw"] else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not an entry."))
        }
        part = try values.decode(String.self, forKey: .part)
        raw = try values.decode(String.self, forKey: .raw)
    }

    var saved: PreservedJSONValue { .object(["part": .string(part), "raw": .string(raw)]) }

    /// An earlier entry not in this form, kept as its exact saved text.
    static func unrecognized(_ raw: String) -> PreservedJSONValue {
        .object(["part": .string("unrecognized"), "raw": .string(raw)])
    }
}

/// An element of the saved workspace that could not be read and was set aside on load.
public enum SetAsideWorkspacePart: String, Sendable, CaseIterable {
    case session, previousRoutine, historyRun, appObservation, capture
    case timeTarget, longerPlanAcceptance, runFeedback, timeBudgetAndFeedback

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
        case .timeTarget: "Your time target couldn’t be read, so no target is set."
        case .longerPlanAcceptance: "Your choice to keep a longer plan couldn’t be read, so it is not applied."
        case .runFeedback: "Some feedback on past mornings couldn’t be read and is left out."
        case .timeBudgetAndFeedback: "Your time target and feedback on past mornings couldn’t be read and are left out."
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

