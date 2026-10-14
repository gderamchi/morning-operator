import Foundation
import MorningCore

/// Legacy derived output is optional. An unsupported model payload must not make
/// the person's valid routine and original observation impossible to restore.
public struct RecoverableObservationClassification: Codable, Sendable {
    public let value: ObservationContextClassification?
    public let wasInvalid: Bool
    public init(_ value: ObservationContextClassification) { self.value = value; wasInvalid = false }
    public init(from decoder: any Decoder) throws {
        do { value = try ObservationContextClassification(from: decoder); wasInvalid = false }
        catch { value = nil; wasInvalid = true }
    }
    public func encode(to encoder: any Encoder) throws {
        if let value { try value.encode(to: encoder) }
        else { var container = encoder.singleValueContainer(); try container.encodeNil() }
    }
}

/// A damaged derived suggestion must not strand the current routine or original
/// observations. Restored proposals are also checked against live source revisions.
public struct RecoverableRoutineProposal: Codable, Sendable {
    public let value: EvidenceRoutineProposal?
    public let wasInvalid: Bool
    public init(_ value: EvidenceRoutineProposal) { self.value = value; wasInvalid = false }
    public init(from decoder: any Decoder) throws {
        do { value = try EvidenceRoutineProposal(from: decoder); wasInvalid = false }
        catch { value = nil; wasInvalid = true }
    }
    public func encode(to encoder: any Encoder) throws {
        if let value { try value.encode(to: encoder) }
        else { var container = encoder.singleValueContainer(); try container.encodeNil() }
    }
}

/// The app's whole saved workspace, `workspace.json`. The app is its only writer.
///
/// It lives in this package, not in the app, so the package tests decode a real earlier
/// file through the exact type and path the app uses (`AtomicJSONFile.load`).
///
/// One unreadable morning in progress, previous routine, past morning, day of app usage
/// or saved note is set aside on load instead of refusing the file: it is left out,
/// named in `newlySetAside`, and kept verbatim in `setAside`, which the app writes back
/// on every save. Only forgetting all local data removes it. Any other unreadable part
/// still refuses the whole file; `UnreadableWorkspacePart` names it for the person.
public struct WorkspaceSnapshot: Codable, Sendable {
    public var schemaVersion = 1
    public var routine: RoutineVersion?
    public var session: RoutineSession?
    public var previousRoutine: RoutineVersion?
    public var history: MorningHistory?
    public var captures: [QuickCapture]?
    public var receipts: [String: String]?
    public var sessionTimeZone: String?
    public var automatic: Bool?
    public var readAloud: Bool?
    public var showMorningOnLockScreen: Bool?
    public var sessionTimingInterrupted: Bool?
    public var pendingCaptures: [String: String]?
    public var voiceIdentifier: String?
    public var observationNotes: String?
    public var observationSource: String?
    public var observationVideoEvidence: ObservationVideoEvidence?
    public var observationContextClassification: RecoverableObservationClassification?
    public var observationArchive: ObservationArchive?
    public var selectedObservationID: UUID?
    public var pendingRoutineProposal: RecoverableRoutineProposal?
    public var consumedMorningEntryIDs: [UUID]?
    public var routinePreferences: RecoverableRoutinePreferences?
    /// Which morning sessions were already greeted (issue #28). Session identifiers only.
    public var greeting: MorningGreetingState?
    /// Elements set aside on this or an earlier load, verbatim. See `SetAsideWorkspacePart`.
    public var setAside: [PreservedJSONValue]?
    /// What this load set aside. Never saved.
    public private(set) var newlySetAside: [SetAsideWorkspacePart] = []

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, routine, session, previousRoutine, history, captures, receipts, sessionTimeZone
        case automatic, readAloud, showMorningOnLockScreen, sessionTimingInterrupted, pendingCaptures
        case voiceIdentifier, observationNotes, observationSource, observationVideoEvidence
        case observationContextClassification, observationArchive, selectedObservationID
        case pendingRoutineProposal, consumedMorningEntryIDs, routinePreferences, greeting, setAside
    }

    public init(routine: RoutineVersion? = nil, session: RoutineSession? = nil, previousRoutine: RoutineVersion? = nil,
                history: MorningHistory? = nil, captures: [QuickCapture]? = nil, receipts: [String: String]? = nil,
                sessionTimeZone: String? = nil, automatic: Bool? = nil, readAloud: Bool? = nil,
                showMorningOnLockScreen: Bool? = nil, sessionTimingInterrupted: Bool? = nil,
                pendingCaptures: [String: String]? = nil, voiceIdentifier: String? = nil,
                observationNotes: String? = nil, observationSource: String? = nil,
                observationVideoEvidence: ObservationVideoEvidence? = nil,
                observationContextClassification: RecoverableObservationClassification? = nil,
                observationArchive: ObservationArchive? = nil, selectedObservationID: UUID? = nil,
                pendingRoutineProposal: RecoverableRoutineProposal? = nil, consumedMorningEntryIDs: [UUID]? = nil,
                routinePreferences: RecoverableRoutinePreferences? = nil, greeting: MorningGreetingState? = nil,
                setAside: [PreservedJSONValue]? = nil) {
        self.routine = routine; self.session = session; self.previousRoutine = previousRoutine
        self.history = history; self.captures = captures; self.receipts = receipts
        self.sessionTimeZone = sessionTimeZone; self.automatic = automatic; self.readAloud = readAloud
        self.showMorningOnLockScreen = showMorningOnLockScreen; self.sessionTimingInterrupted = sessionTimingInterrupted
        self.pendingCaptures = pendingCaptures; self.voiceIdentifier = voiceIdentifier
        self.observationNotes = observationNotes; self.observationSource = observationSource
        self.observationVideoEvidence = observationVideoEvidence
        self.observationContextClassification = observationContextClassification
        self.observationArchive = observationArchive; self.selectedObservationID = selectedObservationID
        self.pendingRoutineProposal = pendingRoutineProposal; self.consumedMorningEntryIDs = consumedMorningEntryIDs
        self.routinePreferences = routinePreferences; self.greeting = greeting
        self.setAside = setAside?.isEmpty == true ? nil : setAside
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        var setAsideNow: [(SetAsideWorkspacePart, PreservedJSONValue)] = []
        func element<Value: Decodable & Sendable>(_ type: Value.Type, _ key: CodingKeys,
                                                    _ part: SetAsideWorkspacePart) throws -> Value? {
            // Missing and null are both "none", as before; only a present value can be set aside.
            guard let read = try values.decodeIfPresent(RecoverableElement<Value>.self, forKey: key) else { return nil }
            if let original = read.original { setAsideNow.append((part, original)) }
            return read.value
        }
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        routine = try values.decodeIfPresent(RoutineVersion.self, forKey: .routine)
        session = try element(RoutineSession.self, .session, .session)
        previousRoutine = try element(RoutineVersion.self, .previousRoutine, .previousRoutine)
        if let read = try values.decodeIfPresent(RecoverableHistory.self, forKey: .history) {
            history = read.value
            setAsideNow += read.setAside
        }
        if let read = try values.decodeIfPresent([RecoverableElement<QuickCapture>].self, forKey: .captures) {
            captures = read.compactMap(\.value)
            setAsideNow += read.compactMap { $0.original.map { (.capture, $0) } }
        }
        receipts = try values.decodeIfPresent([String: String].self, forKey: .receipts)
        sessionTimeZone = try values.decodeIfPresent(String.self, forKey: .sessionTimeZone)
        automatic = try values.decodeIfPresent(Bool.self, forKey: .automatic)
        readAloud = try values.decodeIfPresent(Bool.self, forKey: .readAloud)
        showMorningOnLockScreen = try values.decodeIfPresent(Bool.self, forKey: .showMorningOnLockScreen)
        sessionTimingInterrupted = try values.decodeIfPresent(Bool.self, forKey: .sessionTimingInterrupted)
        pendingCaptures = try values.decodeIfPresent([String: String].self, forKey: .pendingCaptures)
        voiceIdentifier = try values.decodeIfPresent(String.self, forKey: .voiceIdentifier)
        observationNotes = try values.decodeIfPresent(String.self, forKey: .observationNotes)
        observationSource = try values.decodeIfPresent(String.self, forKey: .observationSource)
        observationVideoEvidence = try values.decodeIfPresent(ObservationVideoEvidence.self, forKey: .observationVideoEvidence)
        observationContextClassification = try values.decodeIfPresent(RecoverableObservationClassification.self, forKey: .observationContextClassification)
        observationArchive = try values.decodeIfPresent(ObservationArchive.self, forKey: .observationArchive)
        selectedObservationID = try values.decodeIfPresent(UUID.self, forKey: .selectedObservationID)
        pendingRoutineProposal = try values.decodeIfPresent(RecoverableRoutineProposal.self, forKey: .pendingRoutineProposal)
        consumedMorningEntryIDs = try values.decodeIfPresent([UUID].self, forKey: .consumedMorningEntryIDs)
        // Missing is an older workspace. Present-but-null is damaged saved data;
        // keep it unreadable until the user explicitly resets their choices.
        routinePreferences = values.contains(.routinePreferences)
            ? try values.decode(RecoverableRoutinePreferences.self, forKey: .routinePreferences) : nil
        // Missing is an older workspace. An unreadable value must not close the whole
        // workspace: at worst a morning in progress is treated as not greeted yet.
        greeting = (try? values.decodeIfPresent(MorningGreetingState.self, forKey: .greeting)) ?? nil
        // Earlier set-aside elements are kept as they are, whatever their shape: this
        // list is never interpreted, so nothing in it can refuse the file.
        var kept: [PreservedJSONValue] = []
        switch try values.decodeIfPresent(PreservedJSONValue.self, forKey: .setAside) {
        case .array(let earlier): kept = earlier
        case .some(.null), nil: break
        case .some(let other): kept = [other]
        }
        kept += setAsideNow.map { SetAsideWorkspacePart.entry(part: $0.0, original: $0.1) }
        setAside = kept.isEmpty ? nil : kept
        newlySetAside = setAsideNow.map(\.0)
    }
}
