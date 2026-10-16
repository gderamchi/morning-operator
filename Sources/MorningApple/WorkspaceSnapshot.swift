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
/// One unreadable morning in progress, previous routine, past morning, day of app usage,
/// saved note, time target, accepted longer plan or run feedback is set aside on load instead of refusing the file: it is left out,
/// named in `newlySetAside`, and kept as its exact saved text in `setAside` (one
/// {"part", "raw"} object per element), which the app writes back
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
    public var handsFreeListeningSuppressedSessionID: UUID?
    public var showMorningOnLockScreen: Bool?
    public var sessionTimingInterrupted: Bool?
    /// The time target, an accepted longer plan and run feedback (#10).
    public var budgetAndFeedback: RoutineBudgetAndFeedback?
    public var pendingCaptures: [String: String]?
    public var voiceIdentifier: String?
    public var voiceGender: String?
    public var observationNotes: String?
    public var observationSource: String?
    public var observationVideoEvidence: ObservationVideoEvidence?
    public var observationContextClassification: RecoverableObservationClassification?
    public var observationArchive: ObservationArchive?
    public var selectedObservationID: UUID?
    public var pendingRoutineProposal: RecoverableRoutineProposal?
    public var pendingScreenTimeProposal: ScreenTimeRoutineProposal?
    public var consumedMorningEntryIDs: [UUID]?
    public var routinePreferences: RecoverableRoutinePreferences?
    /// Which morning sessions were already greeted (issue #28). Session identifiers only.
    public var greeting: MorningGreetingState?
    public var executionRecords: [RoutineExecutionRecord]?
    public var evidenceRetentionDays: Int?
    /// Elements set aside on this or an earlier load, verbatim. See `SetAsideWorkspacePart`.
    public var setAside: [PreservedJSONValue]?
    /// What this load set aside. Never saved.
    public private(set) var newlySetAside: [SetAsideWorkspacePart] = []

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, routine, session, previousRoutine, history, captures, receipts, sessionTimeZone
        case automatic, readAloud, handsFreeListeningSuppressedSessionID, showMorningOnLockScreen, sessionTimingInterrupted, budgetAndFeedback, pendingCaptures
        case voiceIdentifier, voiceGender, observationNotes, observationSource, observationVideoEvidence
        case observationContextClassification, observationArchive, selectedObservationID
        case pendingRoutineProposal, pendingScreenTimeProposal, consumedMorningEntryIDs, routinePreferences, greeting, executionRecords, evidenceRetentionDays, setAside
    }

    public init(routine: RoutineVersion? = nil, session: RoutineSession? = nil, previousRoutine: RoutineVersion? = nil,
                history: MorningHistory? = nil, captures: [QuickCapture]? = nil, receipts: [String: String]? = nil,
                sessionTimeZone: String? = nil, automatic: Bool? = nil, readAloud: Bool? = nil,
                handsFreeListeningSuppressedSessionID: UUID? = nil,
                showMorningOnLockScreen: Bool? = nil, sessionTimingInterrupted: Bool? = nil,
                budgetAndFeedback: RoutineBudgetAndFeedback? = nil,
                pendingCaptures: [String: String]? = nil, voiceIdentifier: String? = nil, voiceGender: String? = nil,
                observationNotes: String? = nil, observationSource: String? = nil,
                observationVideoEvidence: ObservationVideoEvidence? = nil,
                observationContextClassification: RecoverableObservationClassification? = nil,
                observationArchive: ObservationArchive? = nil, selectedObservationID: UUID? = nil,
                pendingRoutineProposal: RecoverableRoutineProposal? = nil, pendingScreenTimeProposal: ScreenTimeRoutineProposal? = nil,
                consumedMorningEntryIDs: [UUID]? = nil,
                routinePreferences: RecoverableRoutinePreferences? = nil, greeting: MorningGreetingState? = nil,
                executionRecords: [RoutineExecutionRecord]? = nil, evidenceRetentionDays: Int? = nil, setAside: [PreservedJSONValue]? = nil) {
        self.routine = routine; self.session = session; self.previousRoutine = previousRoutine
        self.history = history; self.captures = captures; self.receipts = receipts
        self.sessionTimeZone = sessionTimeZone; self.automatic = automatic; self.readAloud = readAloud
        self.handsFreeListeningSuppressedSessionID = handsFreeListeningSuppressedSessionID
        self.showMorningOnLockScreen = showMorningOnLockScreen; self.sessionTimingInterrupted = sessionTimingInterrupted
        self.budgetAndFeedback = budgetAndFeedback
        self.pendingCaptures = pendingCaptures; self.voiceIdentifier = voiceIdentifier; self.voiceGender = voiceGender
        self.observationNotes = observationNotes; self.observationSource = observationSource
        self.observationVideoEvidence = observationVideoEvidence
        self.observationContextClassification = observationContextClassification
        self.observationArchive = observationArchive; self.selectedObservationID = selectedObservationID
        self.pendingRoutineProposal = pendingRoutineProposal; self.pendingScreenTimeProposal = pendingScreenTimeProposal
        self.consumedMorningEntryIDs = consumedMorningEntryIDs
        self.routinePreferences = routinePreferences; self.greeting = greeting
        self.executionRecords = executionRecords
        self.evidenceRetentionDays = evidenceRetentionDays
        self.setAside = setAside?.isEmpty == true ? nil : setAside
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        var setAsideNow: [(SetAsideWorkspacePart, String)] = []
        func element<Value: Decodable & Sendable>(_ type: Value.Type, _ key: CodingKeys,
                                                    _ part: SetAsideWorkspacePart) throws -> Value? {
            // Missing and null are both "none", as before; only a present value can be set aside.
            guard let read = try values.decodeIfPresent(RecoverableElement<Value>.self, forKey: key) else { return nil }
            if let raw = read.raw { setAsideNow.append((part, raw)) }
            return read.value
        }
        // A type that validates its content may throw its own error, which carries no
        // coding path. Give it the key, so the person is told which part failed.
        func strict<Value: Decodable>(_ type: Value.Type, _ key: CodingKeys) throws -> Value? {
            do { return try values.decodeIfPresent(type, forKey: key) }
            catch let error as DecodingError { throw error }
            catch {
                throw DecodingError.dataCorrupted(.init(codingPath: values.codingPath + [key],
                    debugDescription: "The saved value was refused.", underlyingError: error))
            }
        }
        // The decoder keeps only one value of a repeated key, so the other would be lost on
        // the next save, even when the kept one is null. The app never writes one: refuse the
        // file unchanged. Keys this scan cannot count could hide a repeat too.
        if let data = decoder.userInfo[.atomicJSONFileData] as? Data {
            let keys = RawJSONText.keys(in: data, at: values.codingPath)
            guard let keys, Set(keys).count == keys.count else {
                throw DecodingError.dataCorrupted(.init(codingPath: values.codingPath,
                    debugDescription: "A repeated key, or keys that could not be counted."))
            }
        }
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        routine = try strict(RoutineVersion.self, .routine)
        session = try element(RoutineSession.self, .session, .session)
        previousRoutine = try element(RoutineVersion.self, .previousRoutine, .previousRoutine)
        if let read = try values.decodeIfPresent(RecoverableHistory.self, forKey: .history) {
            history = read.value
            setAsideNow += read.setAside
        }
        if let read = try values.decodeIfPresent([RecoverableElement<QuickCapture>].self, forKey: .captures) {
            captures = read.compactMap(\.value)
            setAsideNow += read.compactMap { $0.raw.map { (.capture, $0) } }
        }
        receipts = try values.decodeIfPresent([String: String].self, forKey: .receipts)
        sessionTimeZone = try values.decodeIfPresent(String.self, forKey: .sessionTimeZone)
        automatic = try values.decodeIfPresent(Bool.self, forKey: .automatic)
        readAloud = try values.decodeIfPresent(Bool.self, forKey: .readAloud)
        handsFreeListeningSuppressedSessionID = try values.decodeIfPresent(UUID.self, forKey: .handsFreeListeningSuppressedSessionID)
        executionRecords = try values.decodeIfPresent([RoutineExecutionRecord].self, forKey: .executionRecords)
        evidenceRetentionDays = (try? values.decodeIfPresent(Int.self, forKey: .evidenceRetentionDays)) ?? nil
        showMorningOnLockScreen = try values.decodeIfPresent(Bool.self, forKey: .showMorningOnLockScreen)
        sessionTimingInterrupted = try values.decodeIfPresent(Bool.self, forKey: .sessionTimingInterrupted)
        if let read = try values.decodeIfPresent(RecoverableBudgetAndFeedback.self, forKey: .budgetAndFeedback) {
            budgetAndFeedback = read.value
            setAsideNow += read.setAside
        }
        pendingCaptures = try values.decodeIfPresent([String: String].self, forKey: .pendingCaptures)
        voiceIdentifier = try values.decodeIfPresent(String.self, forKey: .voiceIdentifier)
        voiceGender = try? values.decodeIfPresent(String.self, forKey: .voiceGender)
        observationNotes = try values.decodeIfPresent(String.self, forKey: .observationNotes)
        observationSource = try values.decodeIfPresent(String.self, forKey: .observationSource)
        observationVideoEvidence = try strict(ObservationVideoEvidence.self, .observationVideoEvidence)
        observationContextClassification = try values.decodeIfPresent(RecoverableObservationClassification.self, forKey: .observationContextClassification)
        observationArchive = try strict(ObservationArchive.self, .observationArchive)
        selectedObservationID = try values.decodeIfPresent(UUID.self, forKey: .selectedObservationID)
        pendingRoutineProposal = try values.decodeIfPresent(RecoverableRoutineProposal.self, forKey: .pendingRoutineProposal)
        pendingScreenTimeProposal = try? values.decodeIfPresent(ScreenTimeRoutineProposal.self, forKey: .pendingScreenTimeProposal)
        consumedMorningEntryIDs = try values.decodeIfPresent([UUID].self, forKey: .consumedMorningEntryIDs)
        // Missing is an older workspace. Present-but-null is damaged saved data;
        // keep it unreadable until the user explicitly resets their choices.
        routinePreferences = values.contains(.routinePreferences)
            ? try values.decode(RecoverableRoutinePreferences.self, forKey: .routinePreferences) : nil
        // Missing is an older workspace. An unreadable value must not close the whole
        // workspace: at worst a morning in progress is treated as not greeted yet.
        greeting = (try? values.decodeIfPresent(MorningGreetingState.self, forKey: .greeting)) ?? nil
        // Earlier set-aside elements are kept, whatever their shape: this list is never
        // interpreted. An entry in this type's own form stays as it is; anything else is
        // kept as its exact saved text, so no number is rounded and nothing can refuse the file.
        var kept: [PreservedJSONValue] = []
        if let earlier = try values.decodeIfPresent(RecoverableElement<[RecoverableElement<SetAsideEntry>]>.self,
                                                     forKey: .setAside) {
            if let items = earlier.value {
                kept = items.compactMap { $0.value?.saved ?? $0.raw.map(SetAsideEntry.unrecognized) }
            } else if let raw = earlier.raw {
                kept = [SetAsideEntry.unrecognized(raw)]
            }
        }
        kept += setAsideNow.map { SetAsideWorkspacePart.entry(part: $0.0, raw: $0.1) }
        setAside = kept.isEmpty ? nil : kept
        newlySetAside = setAsideNow.map(\.0)
    }
}
