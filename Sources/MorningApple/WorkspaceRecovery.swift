import Foundation
import MorningCore

/// One saved element that is either read or kept verbatim. Decoding never fails for
/// valid JSON, so one damaged element cannot refuse the file that holds it.
/// The element's own decoder stays strict; this wrapper only decides what to do on failure.
public struct RecoverableElement<Value: Decodable & Sendable>: Decodable, Sendable {
    public let value: Value?
    /// The element as it was saved, when it could not be read.
    public let original: PreservedJSONValue?

    public init(from decoder: any Decoder) throws {
        if let read = try? Value(from: decoder) { value = read; original = nil }
        else { value = nil; original = try PreservedJSONValue(from: decoder) }
    }
}

/// Reads `MorningHistory` one record at a time: an unreadable past morning or day of app
/// usage is set aside alone. The keys are those `MorningHistory` writes.
struct RecoverableHistory: Decodable, Sendable {
    let value: MorningHistory
    let setAside: [(SetAsideWorkspacePart, PreservedJSONValue)]

    private enum CodingKeys: String, CodingKey { case runs, appObservations }
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let runs = try values.decodeIfPresent([RecoverableElement<MorningRunRecord>].self, forKey: .runs) ?? []
        let days = try values.decodeIfPresent([RecoverableElement<DailyAppObservation>].self, forKey: .appObservations) ?? []
        value = MorningHistory(runs: runs.compactMap(\.value), appObservations: days.compactMap(\.value))
        setAside = runs.compactMap { $0.original.map { (.historyRun, $0) } }
            + days.compactMap { $0.original.map { (.appObservation, $0) } }
    }
}

/// An element of the saved workspace that could not be read and was set aside on load.
public enum SetAsideWorkspacePart: String, Sendable, CaseIterable {
    case session, previousRoutine, historyRun, appObservation, capture

    /// Where the element is read in the snapshot, for naming a failure.
    var key: any CodingKey {
        switch self {
        case .session: AnyKey("session")
        case .previousRoutine: AnyKey("previousRoutine")
        case .historyRun, .appObservation: AnyKey("history")
        case .capture: AnyKey("captures")
        }
    }

    /// The saved form: the part's name and the element exactly as it was read.
    static func entry(part: SetAsideWorkspacePart, original: PreservedJSONValue) -> PreservedJSONValue {
        .object(["part": .string(part.rawValue), "original": original])
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

private struct AnyKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ value: String) { stringValue = value }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}
