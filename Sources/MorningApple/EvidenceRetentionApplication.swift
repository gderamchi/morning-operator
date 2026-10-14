import CryptoKit
import Foundation
import MorningCore

/// The saved workspace parts a retention plan reads, and the only parts applying
/// it may change: the archive, the current and previous routine, the saved session
/// and the pending suggestion. Saved choices and run history are read, never changed.
public struct EvidenceRetentionWorkspace: Sendable, Equatable {
    public var archive: ObservationArchive
    public var currentRoutine: RoutineVersion?
    public var previousRoutine: RoutineVersion?
    public var session: RoutineSession?
    public var pendingProposal: EvidenceRoutineProposal?
    /// Nil when the saved choices could not be read: nothing is then listed for removal.
    public var preferences: RoutinePreferenceJournal?
    public var history: MorningHistory

    public init(archive: ObservationArchive, currentRoutine: RoutineVersion?, previousRoutine: RoutineVersion?,
                session: RoutineSession?, pendingProposal: EvidenceRoutineProposal?,
                preferences: RoutinePreferenceJournal?, history: MorningHistory) {
        self.archive = archive; self.currentRoutine = currentRoutine; self.previousRoutine = previousRoutine
        self.session = session; self.pendingProposal = pendingProposal
        self.preferences = preferences; self.history = history
    }

    func plan(now: Date, maximumAge: TimeInterval) -> EvidenceRetentionPlan {
        EvidenceRetentionPlan(archive: archive, currentRoutine: currentRoutine, previousRoutine: previousRoutine,
            session: session, pendingProposal: pendingProposal, preferences: preferences, history: history,
            now: now, maximumAge: maximumAge)
    }
}

/// What a removal covers, chosen by the person. Fixed identifiers only: nothing
/// translated is stored or compared.
public enum EvidenceRemovalScope: Sendable, Equatable, Codable {
    /// Every observation imported more than this many days before the review.
    case expiry(maximumAgeDays: Int)
    /// One observation the person chose to forget.
    case single(UUID)
}

public enum EvidenceRemovalError: Error, Sendable, Equatable {
    /// The saved data no longer gives the plan the person confirmed. Show this one instead.
    case planChanged(EvidenceRemovalReview)
    /// The plan lists a change in a copy this version cannot edit safely. Nothing is changed.
    case unsupportedCopy(EvidenceRetentionStore)
    /// The observation is part of a recorded session, which removal does not handle yet (#88).
    case segmentedSession
    /// The listed step is no longer where the plan found it.
    case copyMoved
    /// The observation to forget is no longer saved.
    case observationGone
    /// A quotation to remove sits in a step whose words are also listed as kept for
    /// another reason. Clearing it would remove what the person keeps; nothing is changed.
    case wordsAlsoKept
}

/// One removal as the person reviews and confirms it: the observations that go,
/// every copy the plan lists for them with its disposition, and whether the pending
/// suggestion is set aside. Derived, never saved; its fingerprint is.
///
/// Applying it never trusts a review shown earlier: `applied(to:now:)` works the
/// review out again from the workspace it is given and refuses when the two differ.
public struct EvidenceRemovalReview: Sendable, Equatable {
    public let scope: EvidenceRemovalScope
    /// Archive order.
    public let acquisitionIDs: [UUID]
    /// Expiry only: observations with no saved import date. Listed, never removed.
    public let unknownAgeAcquisitionIDs: [UUID]
    /// Every copy the plan lists for `acquisitionIDs`, in plan order.
    public let copies: [EvidenceDependentCopy]
    /// True when the pending suggestion is listed as invalidated, or when a listed
    /// change to the draft it was prepared from leaves it no longer current.
    public let setsAsidePendingSuggestion: Bool
    /// A digest of each removed observation as saved, in archive order. A correction,
    /// new date or new screen label after the review makes it a different review.
    let acquisitionRevisions: [String]
    /// Steps (by store) that any copy, of any observation, lists as kept. A listed
    /// removal inside one of them would also remove kept words.
    let keptSteps: Set<String>
    /// True when applying would remove words listed as kept: nothing can be applied.
    public var removesKeptWords: Bool {
        copies.contains { $0.disposition == .removed && Self.keptKey($0).map(keptSteps.contains) == true }
    }

    /// The choices offered for "Keep raw evidence for…". Off (nil) is the default.
    public static let maximumAgeChoices = [30, 90, 365]

    /// Expiry by import date. A maximum age that is not one of the offered choices
    /// lists nothing, so a damaged or future setting never removes more.
    public static func expiry(maximumAgeDays: Int, in workspace: EvidenceRetentionWorkspace,
                              now: Date) -> EvidenceRemovalReview {
        let plan = workspace.plan(now: now, maximumAge: maximumAgeChoices.contains(maximumAgeDays)
                                  ? Double(maximumAgeDays) * 86_400 : -1)
        return .init(scope: .expiry(maximumAgeDays: maximumAgeDays), ids: plan.expiredAcquisitionIDs,
                     unknown: plan.unknownAgeAcquisitionIDs, plan: plan, workspace: workspace)
    }

    /// Forgetting one observation. Nil when it is no longer in the archive.
    public static func forgetting(_ acquisitionID: UUID, in workspace: EvidenceRetentionWorkspace) -> EvidenceRemovalReview? {
        guard workspace.archive.entry(id: acquisitionID) != nil else { return nil }
        // A negative age expires nothing; the dependent copies do not depend on age.
        let plan = workspace.plan(now: Date(timeIntervalSince1970: 0), maximumAge: -1)
        return .init(scope: .single(acquisitionID), ids: [acquisitionID], unknown: [], plan: plan, workspace: workspace)
    }

    /// The same scope worked out again from the given workspace at `now`.
    public static func recomputed(_ scope: EvidenceRemovalScope, in workspace: EvidenceRetentionWorkspace,
                                  now: Date) -> EvidenceRemovalReview? {
        switch scope {
        case .expiry(let days): expiry(maximumAgeDays: days, in: workspace, now: now)
        case .single(let id): forgetting(id, in: workspace)
        }
    }

    private init(scope: EvidenceRemovalScope, ids: [UUID], unknown: [UUID],
                 plan: EvidenceRetentionPlan, workspace: EvidenceRetentionWorkspace) {
        self.scope = scope
        acquisitionIDs = ids
        unknownAgeAcquisitionIDs = unknown
        let wanted = Set(ids)
        let copies = plan.dependentCopies.filter { wanted.contains($0.acquisitionID) }
        self.copies = copies
        acquisitionRevisions = ids.map { id in
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = workspace.archive.entry(id: id).flatMap { try? encoder.encode($0) } ?? Data()
            return Self.hex(SHA256.hash(data: data))
        }
        let kept = Set(plan.dependentCopies.filter { $0.disposition == .separatelyRetained }.compactMap(Self.keptKey))
        keptSteps = kept
        if let proposal = workspace.pendingProposal, !ids.isEmpty {
            let listed = copies.contains { $0.store == .pendingProposal && $0.disposition != .separatelyRetained }
            // The suggestion is checked against the workspace this removal would leave.
            let after = try? Self.change(workspace, ids: ids, copies: copies, keptSteps: kept, dropProposal: false)
            setsAsidePendingSuggestion = listed || after.map {
                !proposal.isCurrent(archive: $0.archive, baseRoutine: $0.currentRoutine, preferences: $0.preferences)
            } ?? true
        } else {
            setsAsidePendingSuggestion = false
        }
    }

    public var isEmpty: Bool { acquisitionIDs.isEmpty }

    private static func keptKey(_ copy: EvidenceDependentCopy) -> String? {
        copy.stepID.map { "\(copy.store.rawValue) \($0.uuidString)" }
    }

    public func copies(_ disposition: EvidenceDependentDisposition) -> [EvidenceDependentCopy] {
        copies.filter { $0.disposition == disposition }
    }

    /// A content-free digest for the durable removal marker: identifiers, fixed
    /// identifiers and a hash of each quotation, never the words themselves.
    public var fingerprint: String {
        var lines: [String] = []
        switch scope {
        case .expiry(let days): lines.append("expiry \(days)")
        case .single(let id): lines.append("single \(id.uuidString)")
        }
        lines += acquisitionIDs.map { "remove \($0.uuidString)" }
        lines += unknownAgeAcquisitionIDs.map { "unknown \($0.uuidString)" }
        lines += acquisitionRevisions.map { "revision \($0)" }
        lines += keptSteps.sorted().map { "kept \($0)" }
        for copy in copies {
            let quote = copy.quote.map { Self.hex(SHA256.hash(data: Data($0.utf8))) } ?? "-"
            lines.append([copy.acquisitionID.uuidString, copy.store.rawValue, copy.kind.rawValue,
                          copy.stepID?.uuidString ?? "-", quote, copy.reason.rawValue].joined(separator: " "))
        }
        lines.append(setsAsidePendingSuggestion ? "suggestion set aside" : "suggestion kept")
        return Self.hex(SHA256.hash(data: Data(lines.joined(separator: "\n").utf8)))
    }

    private static func hex(_ digest: SHA256.Digest) -> String { digest.map { String(format: "%02x", $0) }.joined() }

    /// The workspace without this removal's observations, with exactly the listed
    /// changes made. It works the review out again from `workspace` at `now` first
    /// and throws `planChanged` with the new review when it differs from this one.
    /// Copies listed as separately retained, saved choices and run history are never changed.
    public func applied(to workspace: EvidenceRetentionWorkspace, now: Date) throws -> EvidenceRetentionWorkspace {
        guard let current = Self.recomputed(scope, in: workspace, now: now) else {
            throw EvidenceRemovalError.observationGone
        }
        // Byte-exact: two spellings of the same letters are two different quotations.
        guard current == self, current.fingerprint == fingerprint else { throw EvidenceRemovalError.planChanged(current) }
        return try Self.change(workspace, ids: acquisitionIDs, copies: copies, keptSteps: keptSteps,
                               dropProposal: setsAsidePendingSuggestion)
    }

    private static func change(_ workspace: EvidenceRetentionWorkspace, ids: [UUID], copies: [EvidenceDependentCopy],
                               keptSteps: Set<String>, dropProposal: Bool) throws -> EvidenceRetentionWorkspace {
        // Fail closed before anything: a step can hold words of two observations.
        guard !copies.contains(where: { $0.disposition == .removed && keptKey($0).map(keptSteps.contains) == true }) else {
            throw EvidenceRemovalError.wordsAlsoKept
        }
        var next = workspace
        for id in ids {
            guard let entry = next.archive.entry(id: id) else { throw EvidenceRemovalError.copyMoved }
            guard entry.sessionSegment == nil else { throw EvidenceRemovalError.segmentedSession }
            try next.archive.delete(id: id)
        }
        let changed = copies.filter { $0.disposition != .separatelyRetained }
        func edit(_ routine: RoutineVersion?, in store: EvidenceRetentionStore) throws -> RoutineVersion? {
            let mine = changed.filter { $0.store == store }
            guard var routine, !mine.isEmpty else { return routine }
            for copy in mine {
                // A step identity that appears twice cannot say which step the plan meant.
                guard let stepID = copy.stepID, routine.steps.filter({ $0.id == stepID }).count == 1,
                      let index = routine.steps.firstIndex(where: { $0.id == stepID }),
                      let reference = routine.steps[index].observationReference,
                      reference.acquisitionID == copy.acquisitionID,
                      copy.quote.map({ Array($0.utf8) }) == Array(reference.quote.utf8) else {
                    throw EvidenceRemovalError.copyMoved
                }
                // The step's name, category, timing and place stay. The link to the
                // observation goes, and with it the quotation the reference holds.
                var step = routine.steps[index]
                step.observationReference = nil
                if step.automation == .savedObservation { step.automation = nil }
                switch copy.disposition {
                case .removed:
                    // Proven untouched: the whole detail is the excerpt as composed.
                    guard copy.reason == .unapprovedDraftQuotation else { throw EvidenceRemovalError.copyMoved }
                    step.detail = ""
                case .invalidated:
                    // Reworked: the wording is the person's own and stays.
                    guard copy.reason == .reworkedStep else { throw EvidenceRemovalError.copyMoved }
                case .separatelyRetained:
                    continue
                }
                routine.steps[index] = step
            }
            return routine
        }
        for copy in changed {
            switch copy.store {
            case .currentRoutine, .previousRoutine, .session, .pendingProposal: continue
            // A run record and a kept choice are never listed for a change. If one ever
            // is, nothing is applied rather than editing history or a decision.
            case .runHistory, .preferenceJournal: throw EvidenceRemovalError.unsupportedCopy(copy.store)
            }
        }
        let editedCurrent = try edit(next.currentRoutine, in: .currentRoutine)
        next.previousRoutine = try edit(next.previousRoutine, in: .previousRoutine)
        if changed.contains(where: { $0.store == .session }), let session = next.session {
            // The saved session pins its own copy. Only a session not yet started, made
            // from this same draft, can follow the draft; anything else is left alone.
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            guard session.status == .ready, session.events.isEmpty, let editedCurrent,
                  let pinned = try? encoder.encode(session.routine),
                  let draft = try? encoder.encode(workspace.currentRoutine), pinned == draft else {
                throw EvidenceRemovalError.unsupportedCopy(.session)
            }
            let sessionCopies = changed.filter { $0.store == .session }
            let currentCopies = changed.filter { $0.store == .currentRoutine }
            guard sessionCopies.map(\.stepID) == currentCopies.map(\.stepID),
                  sessionCopies.map(\.reason) == currentCopies.map(\.reason) else {
                throw EvidenceRemovalError.unsupportedCopy(.session)
            }
            next.session = RoutineSession(id: session.id, routine: editedCurrent)
        }
        next.currentRoutine = editedCurrent
        if dropProposal { next.pendingProposal = nil }
        return next
    }
}

/// The durable record written before a confirmed removal changes anything, and
/// removed only once every step has finished. It holds identifiers, the confirmed
/// instant and a digest, never observation words.
public struct EvidenceRemovalMarker: Codable, Sendable, Equatable {
    public static let fileName = "evidence-removal.json"
    public let scope: EvidenceRemovalScope
    public let acquisitionIDs: [UUID]
    public let confirmedAt: Date
    public let fingerprint: String

    public init(review: EvidenceRemovalReview, confirmedAt: Date) {
        scope = review.scope; acquisitionIDs = review.acquisitionIDs
        self.confirmedAt = confirmedAt; fingerprint = review.fingerprint
    }

    public enum Resumption: Sendable, Equatable {
        /// Every listed observation is already gone: only the final cleanup remains.
        case finishCleanup
        /// Nothing changed since the confirmation: apply this review, which equals it.
        case apply(EvidenceRemovalReview)
        /// The data changed, or only part of it is gone: nothing more is removed.
        /// The person reviews it again.
        case abandon
    }

    /// What to do with this marker in the given workspace. Works the review out
    /// again at the confirmed instant and applies only an identical one.
    public func resumption(in workspace: EvidenceRetentionWorkspace) -> Resumption {
        let present = acquisitionIDs.filter { workspace.archive.entry(id: $0) != nil }
        if present.isEmpty { return .finishCleanup }
        guard present.count == acquisitionIDs.count,
              let review = EvidenceRemovalReview.recomputed(scope, in: workspace, now: confirmedAt),
              review.acquisitionIDs == acquisitionIDs, review.fingerprint == fingerprint else { return .abandon }
        return .apply(review)
    }
}
