import Foundation
import MorningCore
import Testing
@testable import MorningApple

@Suite("Evidence retention — applying a confirmed plan, and nothing else")
struct EvidenceRetentionApplicationTests {
    private let now = Date(timeIntervalSince1970: 1_791_417_600) // A fixed synthetic instant.
    private let day: TimeInterval = 86_400

    private func morning(_ text: String = "I review my calendar after breakfast.", age: TimeInterval? = 0,
                         observed: Int = 0) throws -> ObservationAcquisition {
        try .init(importedAt: age.map { now.addingTimeInterval(-$0) },
            observedDate: ObservationObservedDate(date: now.addingTimeInterval(Double(observed - 60) * day),
                timeZoneIdentifier: "Europe/Paris", provenance: .userAssigned),
            origin: .human, sourceKind: .text, sourceLabel: "Synthetic test notes", originalText: text)
    }

    private func savedMoment(_ source: ObservationAcquisition) throws -> RoutineStep {
        let candidate = try #require(ObservationNarrationComposer.candidates(for: source).first)
        let prepared = try ObservationNarrationComposer.prepare(acquisition: source, candidate: candidate)
        return RoutineStep(title: "A saved moment", detail: prepared.spokenText, kind: .briefing,
            durationMinutes: 1, automation: .savedObservation, observationReference: prepared.reference)
    }

    private func proposal(from sources: [ObservationAcquisition], preserving base: RoutineVersion? = nil,
                          preferences: RoutinePreferenceJournal? = nil) throws -> EvidenceRoutineProposal {
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: sources)
        return try LearningEvidencePreparation.assemble(evidence: evidence, steps: evidence.units.map {
            EvidenceRoutineStepInput(title: "Review calendar", detail: "Consider a short calendar review.",
                kind: .calendar, durationMinutes: 3, citations: [.init(unitID: $0.id, quote: $0.text)])
        }, preserving: base, preferences: preferences, at: now)
    }

    private func workspace(_ entries: [ObservationAcquisition], current: RoutineVersion? = nil,
                           previous: RoutineVersion? = nil, session: RoutineSession? = nil,
                           proposal: EvidenceRoutineProposal? = nil, preferences: RoutinePreferenceJournal? = .init(),
                           runs: [MorningRunRecord] = []) throws -> EvidenceRetentionWorkspace {
        .init(archive: try ObservationArchive(entries: entries), currentRoutine: current, previousRoutine: previous,
              session: session, pendingProposal: proposal, preferences: preferences, history: MorningHistory(runs: runs))
    }

    private func run(_ routine: RoutineVersion) throws -> MorningRunRecord {
        var session = RoutineSession(routine: routine)
        try session.start(at: now)
        try session.stop(at: now.addingTimeInterval(60))
        return try MorningRunRecord(session: session, timeZoneIdentifier: "Europe/Paris", recordedAt: now)
    }

    // MARK: - Expiry

    @Test func expiryRemovesOnlyExpiredObservationsAndNeverAnUnknownAge() throws {
        let old = try morning("An old morning with tea.", age: 40 * day)
        let fresh = try morning("A fresh morning with coffee.", age: 2 * day, observed: 1)
        let undated = try morning("A morning imported before dates were saved.", age: nil, observed: 2)
        let before = try workspace([old, fresh, undated])
        let review = EvidenceRemovalReview.expiry(maximumAgeDays: 30, in: before, now: now)
        #expect(review.acquisitionIDs == [old.id])
        #expect(review.unknownAgeAcquisitionIDs == [undated.id])
        #expect(review.copies.isEmpty && !review.setsAsidePendingSuggestion)
        let after = try review.applied(to: before, now: now)
        #expect(after.archive.entries.map(\.id) == [fresh.id, undated.id])
        #expect(after.archive.entry(id: fresh.id) == fresh && after.archive.entry(id: undated.id) == undated)
        // Exactly at the limit is not expired; a setting that is not offered lists nothing.
        let edge = try morning("Exactly thirty days.", age: 30 * day)
        #expect(EvidenceRemovalReview.expiry(maximumAgeDays: 30, in: try workspace([edge]), now: now).isEmpty)
        #expect(EvidenceRemovalReview.expiry(maximumAgeDays: 1, in: before, now: now).isEmpty)
        #expect(EvidenceRemovalReview.expiry(maximumAgeDays: -30, in: before, now: now).isEmpty)
        #expect(EvidenceRemovalReview.maximumAgeChoices == [30, 90, 365])
    }

    // MARK: - Every disposition, applied exactly

    @Test func anUntouchedDraftQuotationGoesAndTheStepItselfStays() throws {
        let source = try morning(age: 40 * day)
        let moment = try savedMoment(source)
        let other = RoutineStep(title: "Stretch", detail: "Ten slow breaths.", kind: .wellbeing, durationMinutes: 4)
        let draft = RoutineVersion(sourceLabel: "Your morning", steps: [other, moment])
        let before = try workspace([source], current: draft)
        let review = try #require(EvidenceRemovalReview.forgetting(source.id, in: before))
        #expect(review.copies.map(\.disposition) == [.removed])
        let after = try review.applied(to: before, now: now)
        let routine = try #require(after.currentRoutine)
        // Same version: a draft stays a draft with the same identity and order.
        #expect(routine.id == draft.id && routine.number == draft.number && !routine.isApproved)
        #expect(routine.steps.map(\.id) == [other.id, moment.id])
        #expect(routine.steps[0] == other)
        let emptied = routine.steps[1]
        #expect(emptied.title == moment.title && emptied.kind == moment.kind)
        #expect(emptied.durationMinutes == moment.durationMinutes && emptied.isRequired == moment.isRequired)
        #expect(emptied.detail.isEmpty && emptied.observationReference == nil && emptied.automation == nil)
        #expect(after.archive.entries.isEmpty)
        // Nothing of the observation is left for a new plan to find.
        let again = after.plan(now: now, maximumAge: -1)
        #expect(again.dependentCopies.isEmpty)
    }

    @Test func approvedKeptAndRunCopiesAreLeftUntouched() throws {
        let approvedSource = try morning("A quiet cup of tea.", age: 40 * day)
        let keptSource = try morning("I water the plants by the window.", age: 40 * day, observed: 1)
        let approvedStep = try savedMoment(approvedSource)
        let keptStep = try savedMoment(keptSource)
        var journal = RoutinePreferenceJournal()
        try journal.upsert(RoutinePreference(target: keptStep, presence: .keep))
        let approved = RoutineVersion(sourceLabel: "Your morning", steps: [approvedStep]).approved()
        let draft = approved.revised(steps: [approvedStep, keptStep], at: now)
        let runs = [try run(approved)]
        let before = try workspace([approvedSource, keptSource], current: draft, previous: approved,
                                   preferences: journal, runs: runs)
        let review = EvidenceRemovalReview.expiry(maximumAgeDays: 30, in: before, now: now)
        #expect(review.acquisitionIDs == [approvedSource.id, keptSource.id])
        #expect(!review.copies.isEmpty && review.copies.allSatisfy { $0.disposition == .separatelyRetained })
        #expect(Set(review.copies.map(\.reason)) == [.approvedQuotation, .keptChoice])
        let after = try review.applied(to: before, now: now)
        #expect(after.archive.entries.isEmpty)
        #expect(after.currentRoutine == draft && after.previousRoutine == approved)
        #expect(after.preferences == journal && after.history == before.history)
    }

    @Test func aReworkedStepLosesOnlyItsLinkAndKeepsTheWording() throws {
        let source = try morning(age: 40 * day)
        var reworded = try savedMoment(source)
        reworded.detail = "My own reminder."
        var note = try savedMoment(source)
        note.automation = .spokenNote
        note.detail = "Call Mum before the school run."
        let draft = RoutineVersion(sourceLabel: "Your morning", steps: [reworded, note])
        let before = try workspace([source], current: draft)
        let review = try #require(EvidenceRemovalReview.forgetting(source.id, in: before))
        #expect(review.copies.map(\.disposition) == [.invalidated, .invalidated])
        let steps = try #require(try review.applied(to: before, now: now).currentRoutine?.steps)
        #expect(steps.map(\.detail) == ["My own reminder.", "Call Mum before the school run."])
        #expect(steps.allSatisfy { $0.observationReference == nil })
        #expect(steps.map(\.automation) == [nil, .spokenNote])
        #expect(steps.map(\.title) == [reworded.title, note.title])
    }

    @Test func nothingIsRemovedFromAStepWhileSavedChoicesCannotBeRead() throws {
        let source = try morning(age: 40 * day)
        let draft = RoutineVersion(sourceLabel: "Your morning", steps: [try savedMoment(source)])
        let before = try workspace([source], current: draft, preferences: nil)
        let review = try #require(EvidenceRemovalReview.forgetting(source.id, in: before))
        #expect(review.copies.map(\.reason) == [.choicesUnavailable])
        let after = try review.applied(to: before, now: now)
        #expect(after.currentRoutine == draft && after.archive.entries.isEmpty)
    }

    // MARK: - The pending suggestion

    @Test func aSuggestionBuiltFromTheObservationIsSetAsideAndAnotherIsKept() throws {
        let cited = try morning(age: 40 * day)
        let other = try morning("I stretch before coffee.", age: 2 * day, observed: 1)
        let pending = try proposal(from: [cited], preferences: .init())
        let before = try workspace([cited, other], proposal: pending)
        let review = try #require(EvidenceRemovalReview.forgetting(cited.id, in: before))
        #expect(review.setsAsidePendingSuggestion)
        #expect(review.copies.allSatisfy { $0.store == .pendingProposal && $0.disposition == .invalidated })
        #expect(try review.applied(to: before, now: now).pendingProposal == nil)

        let fromOther = try workspace([cited, other], proposal: try proposal(from: [other], preferences: .init()))
        let unrelated = try #require(EvidenceRemovalReview.forgetting(cited.id, in: fromOther))
        #expect(!unrelated.setsAsidePendingSuggestion && unrelated.copies.isEmpty)
        #expect(try unrelated.applied(to: fromOther, now: now).pendingProposal == fromOther.pendingProposal)
    }

    @Test func aSuggestionPreparedFromADraftThatChangesIsSetAsideAndSaysSo() throws {
        let quoted = try morning("A quiet cup of tea.", age: 40 * day)
        let learned = try morning(age: 2 * day, observed: 1)
        let draft = RoutineVersion(sourceLabel: "Your morning", steps: [try savedMoment(quoted)])
        let pending = try proposal(from: [learned], preserving: draft, preferences: .init())
        let before = try workspace([quoted, learned], current: draft, proposal: pending)
        #expect(pending.isCurrent(archive: before.archive, baseRoutine: draft, preferences: .init()))
        let review = try #require(EvidenceRemovalReview.forgetting(quoted.id, in: before))
        // The plan lists no suggestion copy for this observation, but its draft changes.
        #expect(!review.copies.contains { $0.store == .pendingProposal })
        #expect(review.copies.map(\.disposition) == [.removed])
        #expect(review.setsAsidePendingSuggestion)
        #expect(try review.applied(to: before, now: now).pendingProposal == nil)
    }

    // MARK: - Recompute and compare

    @Test func aReviewShownEarlierIsNeverAppliedToChangedData() throws {
        let source = try morning(age: 40 * day)
        let other = try morning("I stretch before coffee.", age: 2 * day, observed: 1)
        let draft = RoutineVersion(sourceLabel: "Your morning", steps: [try savedMoment(source)])
        let shown = try workspace([source, other], current: draft)
        let review = try #require(EvidenceRemovalReview.forgetting(source.id, in: shown))

        // The person approves the draft meanwhile: the quotation is now theirs to keep.
        let approved = try workspace([source, other], current: draft.approved())
        #expect(throws: EvidenceRemovalError.planChanged(try #require(EvidenceRemovalReview.forgetting(source.id, in: approved)))) {
            try review.applied(to: approved, now: now)
        }
        // A suggestion appears that cites it.
        let suggested = try workspace([source, other], current: draft, proposal: try proposal(from: [source], preserving: draft, preferences: .init()))
        do { _ = try review.applied(to: suggested, now: now); Issue.record("A changed plan was applied.") }
        catch EvidenceRemovalError.planChanged(let fresh) { #expect(fresh.setsAsidePendingSuggestion) }
        // The observation is already gone.
        #expect(throws: EvidenceRemovalError.observationGone) { try review.applied(to: try workspace([other], current: draft), now: now) }

        // Expiry: another observation crosses the limit between review and confirmation.
        let expiry = EvidenceRemovalReview.expiry(maximumAgeDays: 30, in: shown, now: now)
        #expect(expiry.acquisitionIDs == [source.id])
        #expect(throws: EvidenceRemovalError.self) { try expiry.applied(to: shown, now: now.addingTimeInterval(29 * day)) }
        #expect(try expiry.applied(to: shown, now: now).archive.entries.map(\.id) == [other.id])
    }

    // MARK: - Fail closed

    @Test func aSessionWithEventsOnTheDraftStopsTheWholeRemoval() throws {
        let source = try morning(age: 40 * day)
        let draft = RoutineVersion(sourceLabel: "Your morning", steps: [try savedMoment(source)])
        // A ready session on the same draft follows it, keeping its identity.
        let ready = RoutineSession(routine: draft)
        let before = try workspace([source], current: draft, session: ready)
        let review = try #require(EvidenceRemovalReview.forgetting(source.id, in: before))
        #expect(review.copies.map(\.store) == [.currentRoutine, .session])
        let after = try review.applied(to: before, now: now)
        #expect(after.session?.id == ready.id && after.session?.routine == after.currentRoutine)
        #expect(after.session?.routine.steps.first?.observationReference == nil)

        // A session stopped before it started holds events: it is a record, not a copy to edit.
        var stopped = RoutineSession(routine: draft)
        try stopped.stop(at: now)
        let running = try workspace([source], current: draft, session: stopped)
        let unsafe = try #require(EvidenceRemovalReview.forgetting(source.id, in: running))
        #expect(throws: EvidenceRemovalError.unsupportedCopy(.session)) { try unsafe.applied(to: running, now: now) }
    }

    @Test func anObservationFromARecordedSessionIsNotRemovedHere() throws {
        let segment = try ObservationSessionSegmentReference(sessionID: UUID(), segmentIndex: 0, startSeconds: 0, endSeconds: 10)
        let source = try ObservationAcquisition(importedAt: now.addingTimeInterval(-40 * day), origin: .human,
            sourceKind: .video, sourceLabel: "Synthetic segment", originalText: "Segment text for a test.",
            sessionSegment: segment)
        let before = try workspace([source])
        let review = EvidenceRemovalReview.expiry(maximumAgeDays: 30, in: before, now: now)
        #expect(review.acquisitionIDs == [source.id])
        #expect(throws: EvidenceRemovalError.segmentedSession) { try review.applied(to: before, now: now) }
    }

    // MARK: - The durable marker

    @Test func theMarkerHoldsNoWordsAndResumesOnlyTheConfirmedPlan() throws {
        let source = try morning("SYNTHETIC_PRIVATE_WORDS in my morning.", age: 40 * day)
        let other = try morning("I stretch before coffee.", age: 2 * day, observed: 1)
        let draft = RoutineVersion(sourceLabel: "Your morning", steps: [try savedMoment(source)])
        let before = try workspace([source, other], current: draft)
        let review = EvidenceRemovalReview.expiry(maximumAgeDays: 30, in: before, now: now)
        let marker = EvidenceRemovalMarker(review: review, confirmedAt: now)
        let encoded = try JSONEncoder().encode(marker)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("SYNTHETIC_PRIVATE_WORDS"))
        #expect(try JSONDecoder().decode(EvidenceRemovalMarker.self, from: encoded) == marker)

        // Relaunched much later with nothing changed: the confirmed instant is used again.
        #expect(marker.resumption(in: before) == .apply(review))
        // Already saved without the observation: only the cleanup is left.
        let after = try review.applied(to: before, now: now)
        #expect(marker.resumption(in: after) == .finishCleanup)
        // Anything changed meanwhile: nothing more is removed.
        let changed = try workspace([source, other], current: draft.approved())
        #expect(marker.resumption(in: changed) == .abandon)
        let single = EvidenceRemovalMarker(review: try #require(EvidenceRemovalReview.forgetting(source.id, in: before)), confirmedAt: now)
        #expect(single.resumption(in: before) != .abandon)
    }

    @Test func aDifferentReviewHasADifferentFingerprint() throws {
        let source = try morning(age: 40 * day)
        let draft = RoutineVersion(sourceLabel: "Your morning", steps: [try savedMoment(source)])
        let a = try #require(EvidenceRemovalReview.forgetting(source.id, in: try workspace([source], current: draft)))
        let b = try #require(EvidenceRemovalReview.forgetting(source.id, in: try workspace([source], current: draft.approved())))
        #expect(a.fingerprint != b.fingerprint)
        #expect(a.fingerprint == (try #require(EvidenceRemovalReview.forgetting(source.id, in: try workspace([source], current: draft)))).fingerprint)
    }

    // MARK: - Review findings

    @Test func aStepWhoseWordsAreAlsoKeptForAnotherObservationIsNeverCleared() throws {
        // Two observations share a whole line; an untouched draft step quotes the first.
        let first = try morning("Tea by the window.\nThen the news.", age: 40 * day)
        let second = try morning("Tea by the window.\nThen a walk.", age: 2 * day, observed: 1)
        let draft = RoutineVersion(sourceLabel: "Your morning", steps: [try savedMoment(first)])
        let before = try workspace([first, second], current: draft)
        let review = try #require(EvidenceRemovalReview.forgetting(first.id, in: before))
        let plan = before.plan(now: now, maximumAge: -1)
        #expect(plan.dependents(of: second.id).contains { $0.stepID == draft.steps[0].id && $0.disposition == .separatelyRetained })
        #expect(review.copies.map(\.disposition) == [.removed])
        #expect(review.removesKeptWords)
        #expect(throws: EvidenceRemovalError.wordsAlsoKept) { try review.applied(to: before, now: now) }
    }

    @Test func aCorrectionAfterTheReviewIsAChangedPlan() throws {
        let source = try morning(age: 40 * day)
        let before = try workspace([source])
        let review = try #require(EvidenceRemovalReview.forgetting(source.id, in: before))
        #expect(review.copies.isEmpty)
        var corrected = before
        try corrected.archive.correct(id: source.id, text: "I review my calendar after lunch.")
        #expect(throws: EvidenceRemovalError.self) { try review.applied(to: corrected, now: now) }
        let marker = EvidenceRemovalMarker(review: review, confirmedAt: now)
        #expect(marker.resumption(in: corrected) == .abandon)
        #expect(marker.resumption(in: before) == .apply(review))
    }
}
