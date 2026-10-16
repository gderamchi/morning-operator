#if DEBUG
import Foundation
import MorningCore
import MorningApple

/// Deliberate, isolated UI-test workspace for evidence retention (#8). Synthetic text
/// only: no capture, file, model call or personal observation is involved.
///
/// Two observations imported 40 days ago (one quoted by the approved routine, one the
/// source of a pending suggestion), one imported today and one with no import date.
@MainActor
enum EvidenceRetentionUITestFixture {
    static let argument = "--ui-testing-retention-fixture"
    static let expiredSuggestionID = UUID(uuidString: "8A000000-0000-4000-8000-000000000001")!
    static let expiredQuotedID = UUID(uuidString: "8A000000-0000-4000-8000-000000000002")!
    static let freshID = UUID(uuidString: "8A000000-0000-4000-8000-000000000003")!
    static let unknownAgeID = UUID(uuidString: "8A000000-0000-4000-8000-000000000004")!

    struct Workspace {
        let archive: ObservationArchive
        let routine: RoutineVersion
        let proposal: EvidenceRoutineProposal
    }

    static func workspace(arguments: [String] = ProcessInfo.processInfo.arguments) -> Workspace? {
        guard arguments.contains("--ui-testing"), arguments.contains(argument),
              arguments.contains(where: { $0.hasPrefix("--ui-testing-workspace=") }) else { return nil }
        let now = Date()
        let zone = TimeZone.current.identifier
        func observed(_ daysAgo: Int) throws -> ObservationObservedDate {
            try ObservationObservedDate(date: now.addingTimeInterval(Double(-daysAgo) * 86_400),
                                        timeZoneIdentifier: zone, provenance: .userAssigned)
        }
        do {
            let expiredSuggestion = try ObservationAcquisition(id: expiredSuggestionID,
                importedAt: now.addingTimeInterval(-40 * 86_400), observedDate: observed(41), origin: .synthetic,
                sourceKind: .text, sourceLabel: "Synthetic retention fixture · 40 days old",
                originalText: "I check the weather and water the plants.")
            let expiredQuoted = try ObservationAcquisition(id: expiredQuotedID,
                importedAt: now.addingTimeInterval(-40 * 86_400), observedDate: observed(40), origin: .synthetic,
                sourceKind: .text, sourceLabel: "Synthetic retention fixture · quoted in the routine",
                originalText: "Tea by the window with the radio on.")
            let fresh = try ObservationAcquisition(id: freshID, observedDate: observed(0), origin: .synthetic,
                sourceKind: .text, sourceLabel: "Synthetic retention fixture · today",
                originalText: "A short walk before breakfast.")
            let unknown = try ObservationAcquisition(id: unknownAgeID, importedAt: nil, observedDate: observed(3),
                origin: .synthetic, sourceKind: .text, sourceLabel: "Synthetic retention fixture · no import date",
                originalText: "Stretching on the balcony.")
            let archive = try ObservationArchive(entries: [expiredSuggestion, expiredQuoted, fresh, unknown])
            let candidate = try ObservationNarrationComposer.candidates(for: expiredQuoted).first
                .unwrapped()
            let prepared = try ObservationNarrationComposer.prepare(acquisition: expiredQuoted, candidate: candidate)
            let routine = RoutineVersion(sourceLabel: "Demo fixture — includes a synthetic saved observation", steps: [
                RoutineStep(title: "A saved moment", detail: prepared.spokenText, kind: .briefing, durationMinutes: 1,
                            automation: .savedObservation, observationReference: prepared.reference),
                RoutineStep(title: "Stretch", detail: "Synthetic layout example.", kind: .wellbeing, durationMinutes: 3)
            ]).approved()
            let evidence = try LearningEvidencePreparation.prepare(acquisitions: [expiredSuggestion])
            let citations = evidence.units.prefix(1).map { RoutineEvidenceCitationInput(unitID: $0.id, quote: String($0.text.prefix(220))) }
            let proposal = try LearningEvidencePreparation.assemble(evidence: evidence, steps: [
                EvidenceRoutineStepInput(title: "A morning to review",
                    detail: "Synthetic review fixture from the selected observations. No Apple model call.",
                    kind: .custom, durationMinutes: 3, citations: citations)
            ], preserving: routine, preferences: RoutinePreferenceJournal(), at: now)
            return Workspace(archive: archive, routine: routine, proposal: proposal)
        } catch {
            return nil
        }
    }
}

private struct MissingFixtureValue: Error {}

private extension Optional {
    func unwrapped() throws -> Wrapped {
        guard let self else { throw MissingFixtureValue() }
        return self
    }
}
#endif
