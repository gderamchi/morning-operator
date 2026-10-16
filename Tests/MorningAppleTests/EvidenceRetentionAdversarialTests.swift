import Foundation
import MorningCore
import Testing
@testable import MorningApple

@Suite("Evidence retention — adversarial deletion boundaries")
struct EvidenceRetentionAdversarialTests {
    private let now = Date(timeIntervalSince1970: 1_791_417_600)
    private let day: TimeInterval = 86_400

    private func observation(_ text: String = "I review my calendar after breakfast.",
                             age: TimeInterval? = 40 * 86_400, observedDay: Int = 0) throws -> ObservationAcquisition {
        try ObservationAcquisition(importedAt: age.map { now.addingTimeInterval(-$0) },
            observedDate: ObservationObservedDate(date: now.addingTimeInterval(Double(observedDay - 60) * day),
                timeZoneIdentifier: "Europe/Paris", provenance: .userAssigned),
            origin: .human, sourceKind: .text, sourceLabel: "Synthetic adversarial probe", originalText: text)
    }

    private func moment(_ source: ObservationAcquisition) throws -> RoutineStep {
        let candidate = try #require(ObservationNarrationComposer.candidates(for: source).first)
        let prepared = try ObservationNarrationComposer.prepare(acquisition: source, candidate: candidate)
        return RoutineStep(title: "Synthetic saved moment", detail: prepared.spokenText, kind: .briefing,
            durationMinutes: 3, automation: .savedObservation, observationReference: prepared.reference)
    }

    private func routine(_ steps: [RoutineStep]) -> RoutineVersion {
        RoutineVersion(createdAt: now, sourceLabel: "Synthetic adversarial probe", steps: steps)
    }

    private func workspace(_ entries: [ObservationAcquisition], current: RoutineVersion? = nil,
                           previous: RoutineVersion? = nil, session: RoutineSession? = nil,
                           proposal: EvidenceRoutineProposal? = nil,
                           preferences: RoutinePreferenceJournal? = .init(),
                           runs: [MorningRunRecord] = []) throws -> EvidenceRetentionWorkspace {
        .init(archive: try ObservationArchive(entries: entries), currentRoutine: current,
            previousRoutine: previous, session: session, pendingProposal: proposal,
            preferences: preferences, history: MorningHistory(runs: runs))
    }

    private func proposal(_ sources: [ObservationAcquisition], base: RoutineVersion? = nil,
                          preferences: RoutinePreferenceJournal? = .init()) throws -> EvidenceRoutineProposal {
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: sources)
        return try LearningEvidencePreparation.assemble(evidence: evidence, steps: evidence.units.map {
            EvidenceRoutineStepInput(title: "Review calendar", detail: "Consider a short calendar review.",
                kind: .calendar, durationMinutes: 3, citations: [.init(unitID: $0.id, quote: $0.text)])
        }, preserving: base, preferences: preferences, at: now)
    }

    private func run(_ value: RoutineVersion, id: UUID = UUID()) throws -> MorningRunRecord {
        var session = RoutineSession(id: id, routine: value)
        // A stopped, unstarted run is a valid independent saved copy too.
        try session.stop(at: now)
        return try MorningRunRecord(session: session, timeZoneIdentifier: "Europe/Paris", recordedAt: now)
    }

    private func forgetting(_ source: ObservationAcquisition,
                            in value: EvidenceRetentionWorkspace) throws -> EvidenceRemovalReview {
        try #require(EvidenceRemovalReview.forgetting(source.id, in: value))
    }

    private func stripped(_ step: RoutineStep, clearDetail: Bool = true) -> RoutineStep {
        var next = step
        next.observationReference = nil
        if next.automation == .savedObservation { next.automation = nil }
        if clearDetail { next.detail = "" }
        return next
    }

    private func roundTrip<T: Codable>(_ value: T) throws -> T {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try JSONDecoder().decode(T.self, from: encoder.encode(value))
    }

    private func expectChanged(_ review: EvidenceRemovalReview,
                               in changed: EvidenceRetentionWorkspace) throws {
        let fresh = try #require(EvidenceRemovalReview.recomputed(review.scope, in: changed, now: now))
        #expect(fresh != review)
        #expect(fresh.fingerprint != review.fingerprint)
        #expect(throws: EvidenceRemovalError.planChanged(fresh)) {
            try review.applied(to: changed, now: now)
        }
        #expect(EvidenceRemovalMarker(review: review, confirmedAt: now).resumption(in: changed) == .abandon)
    }

    @Test func multipleQuotesAndSharedCurrentPreviousIDsChangeOnlyListedFields() throws {
        let source = try observation()
        let other = try observation("I water the plants before breakfast.", age: nil, observedDay: 1)
        let first = try moment(source)
        let second = try moment(source)
        var edited = try moment(source)
        edited.detail = "My own edited reminder."
        edited.automation = .spokenNote
        let unrelated = try moment(other)
        let draft = routine([first, unrelated, second, edited])
        let before = try workspace([source, other], current: draft, previous: draft,
            session: RoutineSession(routine: draft))
        let review = try forgetting(source, in: before)
        #expect(review.copies.count == 9)
        #expect(review.copies(.removed).count == 6)
        #expect(review.copies(.invalidated).count == 3)
        var expected = before
        try expected.archive.delete(id: source.id)
        var expectedRoutine = draft
        expectedRoutine.steps = [stripped(first), unrelated, stripped(second), stripped(edited, clearDetail: false)]
        expected.currentRoutine = expectedRoutine
        expected.previousRoutine = expectedRoutine
        expected.session = RoutineSession(id: try #require(before.session?.id), routine: expectedRoutine)
        #expect(try review.applied(to: before, now: now) == expected)
        #expect(before.archive.entry(id: source.id) == source)
    }

    @Test func duplicateStepIDsAcrossStoresDoNotCrossAcquisitionBoundaries() throws {
        let first = try observation()
        let second = try observation("I stretch before coffee.", observedDay: 1)
        let currentStep = try moment(first)
        let other = try moment(second)
        let previousStep = RoutineStep(id: currentStep.id, title: other.title, detail: other.detail,
            kind: other.kind, durationMinutes: other.durationMinutes, automation: other.automation,
            observationReference: other.observationReference)
        let before = try workspace([first, second], current: routine([currentStep]), previous: routine([previousStep]))
        let single = try forgetting(first, in: before)
        #expect(single.copies.map(\.store) == [.currentRoutine])
        let after = try single.applied(to: before, now: now)
        #expect(after.currentRoutine?.steps == [stripped(currentStep)])
        #expect(after.previousRoutine == before.previousRoutine)
        #expect(after.archive.entries == [second])
        let both = EvidenceRemovalReview.expiry(maximumAgeDays: 30, in: before, now: now)
        let emptied = try both.applied(to: before, now: now)
        #expect(emptied.currentRoutine?.steps == [stripped(currentStep)])
        #expect(emptied.previousRoutine?.steps == [stripped(previousStep)])
    }

    @Test func duplicateIDMustNotRedirectRemovalIntoRequiredCopy() throws {
        let source = try observation()
        let removable = try moment(source)
        var required = removable
        required.isRequired = true
        required.title = "Explicitly required copy"
        required.detail = "My own edited text that must survive."
        let before = try workspace([source], current: routine([required, removable]))
        let review = try forgetting(source, in: before)
        #expect(review.copies.map(\.reason) == [.markedRequired, .unapprovedDraftQuotation])
        do {
            let after = try review.applied(to: before, now: now)
            // Either disambiguate or refuse; selecting the first ID must never erase the kept row.
            #expect(after.currentRoutine?.steps.first == required)
            #expect(after.currentRoutine?.steps.last == stripped(removable))
        } catch let error as EvidenceRemovalError {
            #expect(error == .copyMoved || error == .wordsAlsoKept)
            #expect(before.currentRoutine?.steps == [required, removable])
        }
    }

    @Test func duplicateIDMustNotRedirectInvalidationIntoRequiredCopy() throws {
        let source = try observation()
        var required = try moment(source)
        required.isRequired = true
        var reworked = required
        reworked.isRequired = false
        reworked.detail = "My own edited draft reminder."
        let before = try workspace([source], current: routine([required, reworked]))
        let review = try forgetting(source, in: before)
        #expect(review.copies.map(\.reason) == [.markedRequired, .reworkedStep])
        do {
            let after = try review.applied(to: before, now: now)
            #expect(after.currentRoutine?.steps.first == required)
            #expect(after.currentRoutine?.steps.last == stripped(reworked, clearDetail: false))
        } catch let error as EvidenceRemovalError {
            #expect(error == .copyMoved || error == .wordsAlsoKept)
        }
    }

    @Test(arguments: ["approved", "kept", "required", "unreadableChoices"])
    func protectedCopiesSurviveAlongsideAnExpiredDraft(decision: String) throws {
        let source = try observation()
        let other = try observation("I stretch before coffee.", observedDay: 1)
        var protected = try moment(source)
        let removable = try moment(other)
        var preferences: RoutinePreferenceJournal? = .init()
        var previous: RoutineVersion?
        switch decision {
        case "approved": previous = routine([protected]).approved()
        case "kept": try preferences?.upsert(RoutinePreference(target: protected, presence: .keep))
        case "required": protected.isRequired = true
        default: preferences = nil
        }
        let current = routine([protected, removable])
        let before = try workspace([source, other], current: current, previous: previous,
            session: RoutineSession(routine: current), preferences: preferences,
            runs: [try run(routine([protected]))])
        let review = EvidenceRemovalReview.expiry(maximumAgeDays: 30, in: before, now: now)
        #expect(review.copies.filter { $0.acquisitionID == source.id }.allSatisfy { $0.disposition == .separatelyRetained })
        let after = try review.applied(to: before, now: now)
        #expect(after.archive.entries.isEmpty)
        #expect(after.currentRoutine?.steps[0] == protected)
        #expect(after.session?.routine.steps[0] == protected)
        #expect(after.previousRoutine == before.previousRoutine)
        #expect(after.history == before.history && after.preferences == before.preferences)
        #expect(after.currentRoutine?.steps[1] == (preferences == nil ? removable : stripped(removable)))
    }

    @Test func keptMomentCarriedByProposalSurvivesForgettingItsRawSource() throws {
        let keptSource = try observation("A quiet cup of tea.")
        let learned = try observation(observedDay: 1)
        let kept = try moment(keptSource)
        var choices = RoutinePreferenceJournal()
        try choices.upsert(RoutinePreference(target: kept, presence: .keep))
        let draft = routine([kept])
        let pending = try proposal([learned], base: draft, preferences: choices)
        let before = try workspace([keptSource, learned], current: draft, proposal: pending, preferences: choices)
        #expect(pending.isCurrent(archive: before.archive, baseRoutine: draft, preferences: choices))
        let review = try forgetting(keptSource, in: before)
        #expect(review.copies.filter { $0.store == .pendingProposal }.count == 2)
        #expect(review.copies.allSatisfy { $0.disposition == .separatelyRetained })
        #expect(!review.setsAsidePendingSuggestion)
        var expected = before
        try expected.archive.delete(id: keptSource.id)
        #expect(try review.applied(to: before, now: now) == expected)
    }

    @Test func discardingProposalPreservesKeptMomentInDraftAndJournal() throws {
        let keptSource = try observation("A quiet cup of tea.")
        let learned = try observation(observedDay: 1)
        let kept = try moment(keptSource)
        var choices = RoutinePreferenceJournal()
        try choices.upsert(RoutinePreference(target: kept, presence: .keep))
        let draft = routine([kept])
        let before = try workspace([keptSource, learned], current: draft,
            proposal: try proposal([learned], base: draft, preferences: choices), preferences: choices)
        let review = try forgetting(learned, in: before)
        #expect(review.setsAsidePendingSuggestion)
        var expected = before
        try expected.archive.delete(id: learned.id)
        expected.pendingProposal = nil
        #expect(try review.applied(to: before, now: now) == expected)
    }

    @Test(arguments: [30, 90, 365])
    func expiryBoundaryFutureAndUnknownAge(days: Int) throws {
        let age = Double(days) * day
        let old = try observation("Just beyond the limit.", age: age + 0.001)
        let edge = try observation("Exactly at the limit.", age: age, observedDay: 1)
        let younger = try observation("Just inside the limit.", age: age - 0.001, observedDay: 2)
        let future = try observation("Imported in the future.", age: -day, observedDay: 3)
        let unknown = try observation("No import date is saved.", age: nil, observedDay: 4)
        let before = try workspace([old, edge, younger, future, unknown])
        let review = EvidenceRemovalReview.expiry(maximumAgeDays: days, in: before, now: now)
        #expect(review.acquisitionIDs == [old.id])
        #expect(review.unknownAgeAcquisitionIDs == [unknown.id])
        #expect(try review.applied(to: before, now: now).archive.entries == [edge, younger, future, unknown])
        #expect(throws: EvidenceRemovalError.self) { try review.applied(to: before, now: now.addingTimeInterval(0.002)) }
    }

    @Test func invalidExpiryChoicesAndNonfiniteClockAreNoOps() throws {
        let source = try observation(age: 1_000 * day)
        let unknown = try observation("Undated observation.", age: nil, observedDay: 1)
        let before = try workspace([source, unknown], current: routine([try moment(source)]))
        for days in [Int.min, -1, 0, 1, 29, 31, 91, 366, Int.max] {
            let review = EvidenceRemovalReview.expiry(maximumAgeDays: days, in: before, now: now)
            #expect(review.isEmpty && review.unknownAgeAcquisitionIDs == [unknown.id])
            #expect(try review.applied(to: before, now: now) == before)
        }
        for instant in [Double.infinity, -Double.infinity, Double.nan] {
            let clock = Date(timeIntervalSince1970: instant)
            let review = EvidenceRemovalReview.expiry(maximumAgeDays: 30, in: before, now: clock)
            #expect(review.isEmpty)
            #expect(try review.applied(to: before, now: clock) == before)
        }
    }

    @Test func unknownAgeRequiresExplicitSingleScopeAndMissingSourceRefuses() throws {
        let source = try observation(age: nil)
        let before = try workspace([source])
        let review = try forgetting(source, in: before)
        #expect(review.scope == .single(source.id) && review.unknownAgeAcquisitionIDs.isEmpty)
        #expect(EvidenceRemovalReview.recomputed(review.scope, in: before, now: now) == review)
        let after = try review.applied(to: before, now: now)
        #expect(after.archive.entries.isEmpty)
        #expect(EvidenceRemovalReview.forgetting(source.id, in: after) == nil)
        #expect(EvidenceRemovalReview.recomputed(review.scope, in: after, now: now) == nil)
        #expect(throws: EvidenceRemovalError.observationGone) { try review.applied(to: after, now: now) }
    }

    @Test(arguments: ["archive", "currentRoutine", "previousRoutine", "session", "pendingProposal", "preferences", "history"])
    func changedRemovalImpactInEveryWorkspaceFieldRejectsOldReview(field: String) throws {
        let source = try observation()
        let step = try moment(source)
        let draft = routine([step])
        let before = try workspace([source], current: draft)
        let review = try forgetting(source, in: before)
        var changed = before
        switch field {
        case "archive": try changed.archive.correct(id: source.id, text: "I review my calendar after lunch.")
        case "currentRoutine": changed.currentRoutine?.steps[0].isRequired = true
        case "previousRoutine": changed.previousRoutine = draft.approved()
        case "session": changed.session = RoutineSession(routine: draft)
        case "pendingProposal": changed.pendingProposal = try proposal([source], base: draft)
        case "preferences": try changed.preferences?.upsert(RoutinePreference(target: step, presence: .keep))
        default: changed.history = MorningHistory(runs: [try run(draft)])
        }
        try expectChanged(review, in: changed)
    }

    @Test func changesOutsideRemovalImpactRemainExactlyAsEdited() throws {
        let source = try observation()
        let other = try observation("I stretch before coffee.", age: 2 * day, observedDay: 1)
        let step = try moment(source)
        let before = try workspace([source, other], current: routine([step]))
        let review = try forgetting(source, in: before)
        var changed = before
        try changed.archive.correct(id: other.id, text: "I stretch after coffee.")
        changed.currentRoutine?.sourceLabel = "My renamed draft"
        changed.currentRoutine?.number = 9
        changed.currentRoutine?.steps[0].title = "My new title"
        changed.currentRoutine?.steps[0].durationMinutes = 17
        changed.currentRoutine?.steps[0].kind = .wellbeing
        let unrelated = RoutineStep(title: "Unrelated note", detail: "My own words", automation: .spokenNote)
        changed.previousRoutine = routine([unrelated]).approved()
        changed.session = RoutineSession(routine: try #require(changed.previousRoutine))
        try changed.preferences?.upsert(RoutinePreference(target: unrelated, presence: .keep))
        changed.history = MorningHistory(runs: [try run(try #require(changed.previousRoutine))])
        #expect(try forgetting(source, in: changed) == review)
        var expected = changed
        try expected.archive.delete(id: source.id)
        expected.currentRoutine?.steps[0] = stripped(try #require(changed.currentRoutine?.steps[0]))
        #expect(try review.applied(to: changed, now: now) == expected)
    }

    @Test(arguments: ["correction", "observedDate", "importedAt", "sourceLabel"])
    func changedSourceWithoutDependentsRequiresFreshConfirmation(field: String) throws {
        let source = try observation()
        let before = try workspace([source])
        let review = try forgetting(source, in: before)
        var changed = before
        switch field {
        case "correction": try changed.archive.correct(id: source.id, text: "My newly corrected observation.")
        case "observedDate":
            try changed.archive.assignObservedDate(id: source.id, value: ObservationObservedDate(
                date: now, timeZoneIdentifier: "Europe/Paris", provenance: .userAssigned))
        default:
            let replacement = try ObservationAcquisition(id: source.id,
                importedAt: field == "importedAt" ? now.addingTimeInterval(-50 * day) : source.importedAt,
                observedDate: source.observedDate, origin: source.origin, sourceKind: source.sourceKind,
                sourceLabel: field == "sourceLabel" ? "A newly edited source label" : source.sourceLabel,
                originalText: source.originalText)
            changed.archive = try ObservationArchive(entries: [replacement])
        }
        try expectChanged(review, in: changed)
    }

    @Test func readySessionMustNotOverwriteUnlistedOrRetainedUnicodeBytes() throws {
        let source = try observation()
        let removable = try moment(source)
        for retained in [false, true] {
            var note = retained ? try moment(source) : RoutineStep(title: "Unlisted personal note")
            note.detail = "My caf\u{00E9} reminder."
            note.isRequired = retained
            let current = routine([removable, note])
            var pinned = current
            pinned.steps[1].detail = "My cafe\u{0301} reminder."
            #expect(pinned == current) // Swift's canonical String equality hides the byte edit.
            #expect(Array(pinned.steps[1].detail.utf8) != Array(current.steps[1].detail.utf8))
            let before = try workspace([source], current: current, session: RoutineSession(routine: pinned))
            let review = try forgetting(source, in: before)
            if retained {
                #expect(review.copies.filter { $0.stepID == note.id }.allSatisfy { $0.disposition == .separatelyRetained })
            } else {
                #expect(!review.copies.contains { $0.stepID == note.id })
            }
            do {
                let after = try review.applied(to: before, now: now)
                let actual = try #require(after.session?.routine.steps[1].detail)
                #expect(Array(actual.utf8) == Array(pinned.steps[1].detail.utf8))
            } catch let error as EvidenceRemovalError {
                #expect(error == .unsupportedCopy(.session))
            }
        }
    }

    @Test func byteChangedListedQuoteMustRejectOldReviewEvenWhenStringsAreEquivalent() throws {
        let composed = "I review my caf\u{00E9} calendar."
        let decomposed = "I review my cafe\u{0301} calendar."
        let source = try observation(composed + "\n" + decomposed)
        let step = RoutineStep(title: "My retained note", detail: composed)
        let before = try workspace([source], current: routine([step]))
        let review = try forgetting(source, in: before)
        #expect(review.copies.map(\.reason) == [.unlinkedMatchingText])
        var changed = before
        changed.currentRoutine?.steps[0].detail = decomposed
        let fresh = try forgetting(source, in: changed)
        #expect(fresh.fingerprint != review.fingerprint)
        #expect(EvidenceRemovalMarker(review: review, confirmedAt: now).resumption(in: changed) == .abandon)
        // Applying directly must enforce the same byte-sensitive confirmation as resumption.
        #expect(throws: EvidenceRemovalError.planChanged(fresh)) {
            try review.applied(to: changed, now: now)
        }
    }

    @Test func byteChangedProposalCitationMustNotBeDeletedByOldReview() throws {
        let composed = "I review my caf\u{00E9} calendar."
        let decomposed = "I review my cafe\u{0301} calendar."
        let source = try observation(composed + "\n" + decomposed)
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [source])
        let unit = try #require(evidence.units.first)
        let pending = try LearningEvidencePreparation.assemble(evidence: evidence, steps: [
            EvidenceRoutineStepInput(title: "Review calendar", detail: "A short calendar review.", kind: .calendar,
                durationMinutes: 3, citations: [.init(unitID: unit.id, quote: composed)])
        ], preserving: nil, preferences: .init(), at: now)

        // Preserve proposal/source/step identities, changing only the cited occurrence
        // and its exact evidence line through the production Codable validation boundary.
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(pending)) as? [String: Any])
        var support = try #require(object["support"] as? [[String: Any]])
        var citations = try #require(support[0]["citations"] as? [[String: Any]])
        citations[0]["quote"] = decomposed
        citations[0]["startCharacterOffset"] = composed.count + 1
        citations[0]["endCharacterOffset"] = composed.count + 1 + decomposed.count
        support[0]["citations"] = citations
        object["support"] = support
        var encodedRoutine = try #require(object["routine"] as? [String: Any])
        var steps = try #require(encodedRoutine["steps"] as? [[String: Any]])
        steps[0]["detail"] = try #require(steps[0]["detail"] as? String)
            .replacingOccurrences(of: composed, with: decomposed)
        encodedRoutine["steps"] = steps
        object["routine"] = encodedRoutine
        let edited = try JSONDecoder().decode(EvidenceRoutineProposal.self,
            from: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
        let before = try workspace([source], proposal: pending)
        var changed = before
        changed.pendingProposal = edited
        let pendingIsCurrent = pending.isCurrent(archive: before.archive, baseRoutine: nil, preferences: .init())
        let editedIsCurrent = edited.isCurrent(archive: changed.archive, baseRoutine: nil, preferences: .init())
        try #require(pendingIsCurrent && editedIsCurrent)
        let review = try forgetting(source, in: before)
        let fresh = try forgetting(source, in: changed)
        #expect(review.fingerprint != fresh.fingerprint)
        #expect(EvidenceRemovalMarker(review: review, confirmedAt: now).resumption(in: changed) == .abandon)
        #expect(throws: EvidenceRemovalError.planChanged(fresh)) { try review.applied(to: changed, now: now) }
    }

    @Test(arguments: ["currentRoutine", "previousRoutine", "session", "pendingProposal", "preferences", "history"])
    func fingerprintChangesWhenListedQuoteBytesChangeInEveryStore(store: String) throws {
        let composed = "I review my caf\u{00E9} calendar."
        let decomposed = "I review my cafe\u{0301} calendar."
        let source = try observation(composed + "\n" + decomposed)
        let learned = try observation(observedDay: 1)
        let step = RoutineStep(title: "My retained note", detail: composed)
        var alternate = step
        alternate.detail = decomposed
        let first = routine([step])
        var second = first
        second.steps = [alternate]
        var before = try workspace([source, learned])
        var changed = before
        switch store {
        case "currentRoutine": before.currentRoutine = first; changed.currentRoutine = second
        case "previousRoutine": before.previousRoutine = first; changed.previousRoutine = second
        case "session":
            let id = UUID()
            before.session = RoutineSession(id: id, routine: first)
            changed.session = RoutineSession(id: id, routine: second)
        case "history":
            let id = UUID()
            before.history = MorningHistory(runs: [try run(first, id: id)])
            changed.history = MorningHistory(runs: [try run(second, id: id)])
        case "preferences":
            try before.preferences?.upsert(RoutinePreference(target: step, presence: .keep))
            try changed.preferences?.upsert(RoutinePreference(target: alternate, presence: .keep))
        default:
            var choices = RoutinePreferenceJournal()
            try choices.upsert(RoutinePreference(target: step, presence: .keep))
            before.preferences = choices
            before.pendingProposal = try proposal([learned], preferences: choices)
            try choices.upsert(RoutinePreference(target: alternate, presence: .keep))
            changed.preferences = choices
            changed.pendingProposal = try proposal([learned], preferences: choices)
        }
        let a = try forgetting(source, in: before)
        let b = try forgetting(source, in: changed)
        #expect(!a.copies.isEmpty && a.copies.count == b.copies.count)
        #expect(a.fingerprint != b.fingerprint)
    }

    @Test func fingerprintIsStableAcrossPersistenceAndDoesNotStoreWords() throws {
        let source = try observation("SYNTHETIC_SECRET_MARKER I review my calendar.")
        let step = try moment(source)
        var choices = RoutinePreferenceJournal()
        try choices.upsert(RoutinePreference(target: step, presence: .keep))
        let draft = routine([step])
        let before = try workspace([source], current: draft, previous: draft,
            session: RoutineSession(routine: draft), preferences: choices, runs: [try run(draft)])
        let review = try forgetting(source, in: before)
        let restored = EvidenceRetentionWorkspace(archive: try roundTrip(before.archive),
            currentRoutine: try roundTrip(before.currentRoutine), previousRoutine: try roundTrip(before.previousRoutine),
            session: try roundTrip(before.session), pendingProposal: nil, preferences: try roundTrip(before.preferences),
            history: try roundTrip(before.history))
        #expect(try forgetting(source, in: restored).fingerprint == review.fingerprint)
        #expect(review.fingerprint.count == 64)
        #expect(review.fingerprint.allSatisfy { "0123456789abcdef".contains($0) })
        let marker = EvidenceRemovalMarker(review: review, confirmedAt: now)
        let encoded = try JSONEncoder().encode(marker)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("SYNTHETIC_SECRET_MARKER"))
        #expect(try roundTrip(marker) == marker)
        #expect(try roundTrip(marker).resumption(in: restored) == .apply(review))
    }

    @Test func fingerprintTracksScopeUnknownAgeAndCopyMultiplicity() throws {
        let source = try observation()
        let unknown = try observation("Unknown-age observation.", age: nil, observedDay: 1)
        let step = try moment(source)
        let before = try workspace([source], current: routine([step]))
        let single = try forgetting(source, in: before)
        let expiry = EvidenceRemovalReview.expiry(maximumAgeDays: 30, in: before, now: now)
        #expect(single.fingerprint != expiry.fingerprint)
        var additional = before
        additional.archive = try ObservationArchive(entries: [source, unknown])
        let withUnknown = EvidenceRemovalReview.expiry(maximumAgeDays: 30, in: additional, now: now)
        #expect(withUnknown.fingerprint != expiry.fingerprint)
        additional = before
        additional.previousRoutine = before.currentRoutine
        #expect(try forgetting(source, in: additional).fingerprint != single.fingerprint)
        additional = before
        additional.currentRoutine?.steps.append(try moment(source))
        #expect(try forgetting(source, in: additional).fingerprint != single.fingerprint)
    }

    @Test func markerAbandonsPartialArchiveOrDependentCopyRemoval() throws {
        let first = try observation()
        let second = try observation("I stretch before coffee.", observedDay: 1)
        let steps = [try moment(first), try moment(second)]
        let before = try workspace([first, second], current: routine(steps))
        let review = EvidenceRemovalReview.expiry(maximumAgeDays: 30, in: before, now: now)
        let marker = EvidenceRemovalMarker(review: review, confirmedAt: now)
        #expect(marker.resumption(in: before) == .apply(review))
        var partial = before
        try partial.archive.delete(id: first.id)
        #expect(marker.resumption(in: partial) == .abandon)
        partial = before
        partial.currentRoutine?.steps[0] = stripped(steps[0])
        #expect(marker.resumption(in: partial) == .abandon)
        let after = try review.applied(to: before, now: now)
        #expect(marker.resumption(in: after) == .finishCleanup)
    }

    @Test func resumptionUsesConfirmedTimeWithoutExpiringAdditionalSources() throws {
        let old = try observation()
        let edge = try observation("Exactly at the age boundary.", age: 30 * day, observedDay: 1)
        let unknown = try observation("Undated observation.", age: nil, observedDay: 2)
        let before = try workspace([old, edge, unknown])
        let review = EvidenceRemovalReview.expiry(maximumAgeDays: 30, in: before, now: now)
        let marker = EvidenceRemovalMarker(review: review, confirmedAt: now)
        #expect(marker.resumption(in: before) == .apply(review))
        #expect(throws: EvidenceRemovalError.self) { try review.applied(to: before, now: now.addingTimeInterval(day)) }
        #expect(try review.applied(to: before, now: marker.confirmedAt).archive.entries == [edge, unknown])
    }

    @Test func segmentedSessionRefusalIsAtomicRegardlessOfArchiveOrder() throws {
        let plain = try observation()
        let sessionID = UUID()
        let firstSegment = try ObservationAcquisition(importedAt: now.addingTimeInterval(-40 * day),
            origin: .human, sourceKind: .video, sourceLabel: "Synthetic segment zero", originalText: "Synthetic first segment.",
            sessionSegment: ObservationSessionSegmentReference(sessionID: sessionID, segmentIndex: 0, startSeconds: 0, endSeconds: 10))
        let unknownSegment = try ObservationAcquisition(importedAt: nil, origin: .human, sourceKind: .video,
            sourceLabel: "Synthetic segment one", originalText: "Synthetic second segment.",
            sessionSegment: ObservationSessionSegmentReference(sessionID: sessionID, segmentIndex: 1, startSeconds: 10, endSeconds: 20))
        for entries in [[plain, firstSegment, unknownSegment], [unknownSegment, firstSegment, plain]] {
            let before = try workspace(entries, current: routine([try moment(plain)]))
            let review = EvidenceRemovalReview.expiry(maximumAgeDays: 30, in: before, now: now)
            #expect(review.acquisitionIDs == entries.filter { $0.importedAt != nil }.map(\.id))
            #expect(review.unknownAgeAcquisitionIDs == [unknownSegment.id])
            #expect(throws: EvidenceRemovalError.segmentedSession) { try review.applied(to: before, now: now) }
            #expect(before.archive.entries == entries)
            #expect(throws: EvidenceRemovalError.segmentedSession) {
                try forgetting(unknownSegment, in: before).applied(to: before, now: now)
            }
            let plainReview = try forgetting(plain, in: before)
            let after = try plainReview.applied(to: before, now: now)
            #expect(after.archive.entries == entries.filter { $0.id != plain.id })
        }
    }

    @Test func mismatchedOrStoppedSessionFailsWithoutChangingWorkspace() throws {
        let source = try observation()
        let draft = routine([try moment(source)])
        var stopped = RoutineSession(routine: draft)
        try stopped.stop(at: now)
        let different = RoutineSession(routine: routine(draft.steps))
        for session in [stopped, different] {
            let before = try workspace([source], current: draft, session: session)
            let review = try forgetting(source, in: before)
            #expect(throws: EvidenceRemovalError.unsupportedCopy(.session)) { try review.applied(to: before, now: now) }
            #expect(before.archive.entry(id: source.id) == source)
            #expect(before.currentRoutine == draft && before.session == session)
        }
    }
}
