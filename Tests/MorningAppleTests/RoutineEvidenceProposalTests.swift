import Foundation
import MorningCore
import Testing
@testable import MorningApple
#if canImport(FoundationModels)
import FoundationModels
#endif

@Suite("Saved-observation routine proposals")
struct RoutineEvidenceProposalTests {
    private let instant = Date(timeIntervalSince1970: 1_760_000_000)
    private let words = "I review my calendar after breakfast."

    private func source(id: UUID = UUID(), day: Int = 0, text: String? = nil,
                        correction: String? = nil, origin: ObservationAcquisitionOrigin = .human,
                        zone: String = "Europe/Paris", dated: Bool = true,
                        digest: String? = nil) throws -> ObservationAcquisition {
        try ObservationAcquisition(id: id, importedAt: instant, fileSHA256: digest,
            observedDate: dated ? ObservationObservedDate(date: instant.addingTimeInterval(Double(day) * 86_400),
                timeZoneIdentifier: zone, provenance: .userAssigned) : nil,
            origin: origin, sourceKind: .text, sourceLabel: "Synthetic test notes", originalText: text ?? words,
            correctedText: correction)
    }

    private func step(_ unit: PreparedLearningEvidenceUnit, quote: String? = nil,
                      title: String = "Review calendar") -> EvidenceRoutineStepInput {
        .init(title: title, detail: "Consider a short calendar review.", kind: .calendar, durationMinutes: 3,
              citations: [.init(unitID: unit.id, quote: quote ?? unit.text)])
    }

    @Test("Independent dates retain independent citations even with identical source text")
    func fourDatesAreNotGloballyDeduplicated() throws {
        let sources = try (0..<4).map { try source(day: $0) }
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: sources)
        #expect(evidence.units.count == 4)
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence,
            steps: evidence.units.map { step($0) }, preserving: nil, at: instant)
        #expect(proposal.routine.steps.count == 1)
        #expect(proposal.support[0].citations.count == 4)
        #expect(Set(proposal.sourceSnapshots.map { $0.observedDate.dayKey }).count == 4)
        #expect(!proposal.routine.isApproved)
        #expect(proposal.routine.steps.allSatisfy { !$0.isRequired && $0.automation == nil })
        #expect(proposal.isCurrent(archive: try ObservationArchive(entries: sources), baseRoutine: nil))
        #expect(evidence.modelRequestCount <= 6)
        #expect(evidence.submittedCharacterCount <= 8_000)
    }

    @Test("Two clips on one date keep source references without becoming two mornings")
    func sameDayAndDuplicateSelection() throws {
        let first = try source()
        let second = try source()
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [first, second])
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence,
            steps: evidence.units.map { step($0) }, preserving: nil)
        #expect(proposal.support[0].citations.count == 2)
        #expect(Set(proposal.sourceSnapshots.map { $0.observedDate.dayKey }).count == 1)
        #expect(throws: RoutineEvidenceProposalError.invalidSelection) {
            try LearningEvidencePreparation.prepare(acquisitions: [first, first])
        }
        let digest = String(repeating: "a", count: 64)
        #expect(throws: RoutineEvidenceProposalError.invalidSelection) {
            try LearningEvidencePreparation.prepare(acquisitions: [source(digest: digest), source(day: 1, digest: digest)])
        }
    }

    @Test("Dates, origin and original zone are explicit prerequisites")
    func rejectsUnassignedAndMixedSources() throws {
        #expect(throws: RoutineEvidenceProposalError.dateRequired) {
            try LearningEvidencePreparation.prepare(acquisitions: [source(dated: false)])
        }
        for origin in [ObservationAcquisitionOrigin.unknown, .automated] {
            #expect(throws: RoutineEvidenceProposalError.incompatibleSources) {
                try LearningEvidencePreparation.prepare(acquisitions: [source(origin: origin)])
            }
        }
        #expect(throws: RoutineEvidenceProposalError.incompatibleSources) {
            try LearningEvidencePreparation.prepare(acquisitions: [source(), source(day: 1, origin: .synthetic)])
        }
        #expect(throws: RoutineEvidenceProposalError.incompatibleSources) {
            try LearningEvidencePreparation.prepare(acquisitions: [source(), source(day: 1, zone: "UTC")])
        }
        #expect(throws: RoutineEvidenceProposalError.invalidSelection) {
            try LearningEvidencePreparation.prepare(acquisitions: [])
        }
        #expect(throws: RoutineEvidenceProposalError.invalidSelection) {
            try LearningEvidencePreparation.prepare(acquisitions: (0..<6).map { try source(day: $0) })
        }
    }

    @Test("Whole operation budget never silently truncates sources or selected acquisitions")
    func excessiveEvidenceFailsBeforeInference() throws {
        let long = String(repeating: "I review the calendar after breakfast. ", count: 220)
        #expect(throws: RoutineEvidenceProposalError.inputBudgetExceeded) {
            try LearningEvidencePreparation.prepare(acquisitions: [source(text: long)])
        }
        #expect(throws: RoutineEvidenceProposalError.insufficientEvidence) {
            try LearningEvidencePreparation.prepare(acquisitions: [source(), source(day: 1, correction: "")])
        }
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [source(text: String(repeating: words, count: 45))])
        #expect(evidence.units.map(\.text).joined() == String(repeating: words, count: 45))
        #expect(evidence.submittedCharacterCount == evidence.prompts.reduce(0) { $0 + $1.count })
    }

    @Test("Correction citations cannot borrow original source or video interpretation")
    func correctionTakesPrecedence() throws {
        let entry = try source(correction: "I enjoy a quiet cup of tea before breakfast.")
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        let unit = try #require(evidence.units.first)
        #expect(unit.sourceLayer == .correction)
        #expect(unit.text == entry.correctedText)
        #expect(throws: RoutineEvidenceProposalError.invalidCitation) {
            try LearningEvidencePreparation.assemble(evidence: evidence, steps: [step(unit, quote: words)], preserving: nil)
        }
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence, steps: [step(unit)], preserving: nil)
        #expect(proposal.support[0].citations[0].sourceLayer == .correction)
        #expect(proposal.isCurrent(archive: try ObservationArchive(entries: [entry]), baseRoutine: nil))
    }

    @Test("Exact submitted units reject quote borrowing, invented identifiers and Unicode substitutions")
    func citationsAreByteExactAndUnitScoped() throws {
        let decomposed = "I drink cafe\u{301} before reviewing my calendar."
        let sources = try [source(text: decomposed), source(day: 1, text: "I play chess after breakfast.")]
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: sources)
        let first = evidence.units[0]
        let second = evidence.units[1]
        #expect(throws: RoutineEvidenceProposalError.invalidCitation) {
            try LearningEvidencePreparation.assemble(evidence: evidence,
                steps: [step(first, quote: "I drink café before reviewing my calendar.")], preserving: nil)
        }
        #expect(throws: RoutineEvidenceProposalError.invalidCitation) {
            try LearningEvidencePreparation.assemble(evidence: evidence,
                steps: [step(first, quote: second.text)], preserving: nil)
        }
        #expect(throws: RoutineEvidenceProposalError.invalidCitation) {
            try LearningEvidencePreparation.assemble(evidence: evidence, steps: [EvidenceRoutineStepInput(
                title: "Review", detail: "", kind: .calendar, durationMinutes: 3,
                citations: [.init(unitID: UUID(), quote: first.text)])], preserving: nil)
        }
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence, steps: [step(first)], preserving: nil)
        let citation = proposal.support[0].citations[0]
        #expect(citation.quote.utf8.elementsEqual(decomposed.utf8))
        #expect(citation.startCharacterOffset == 0)
        #expect(citation.endCharacterOffset == decomposed.count)
        #expect(ProposalValidation.step(title: "Calendar", detail: "", kind: "calendar", durationMinutes: 3,
            evidenceQuote: "I drink café before reviewing my calendar.", source: decomposed) == nil)
    }

    @Test("Recorded frame IDs and offsets survive while unsupported frames are disclosed")
    func videoProvenanceAndOmissions() throws {
        let frame = try ObservationFrameEvidence(requestedTimeSeconds: 0, actualTimeSeconds: 0,
            outcome: .observed, text: "Calendar\n09:00 Project planning meeting")
        let blank = try ObservationFrameEvidence(requestedTimeSeconds: 1, actualTimeSeconds: 1, outcome: .blank)
        let setup = try ObservationFrameEvidence(requestedTimeSeconds: 2, actualTimeSeconds: 2,
            outcome: .observed, text: "Screen Sharing\nShare Screen\nCancel")
        let video = try ObservationVideoEvidence(durationSeconds: 3, frames: [frame, blank, setup])
        let entry = try ObservationAcquisition(observedDate: source().observedDate, origin: .human,
            sourceKind: .video, sourceLabel: "Generated fixture", originalText: video.renderedText, videoEvidence: video)
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        #expect(evidence.units.count == 1)
        #expect(evidence.omissions.count == 2)
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence,
            steps: [step(evidence.units[0], quote: "09:00 Project planning meeting")], preserving: nil)
        let citation = proposal.support[0].citations[0]
        #expect(citation.sampleID == frame.id)
        #expect(citation.startCharacterOffset == "Calendar\n".count)
        #expect(citation.sourceLayer == .videoFrame)
        #expect(proposal.isCurrent(archive: try ObservationArchive(entries: [entry]), baseRoutine: nil))
    }

    @Test("Same acquisition ID cannot hide corrections, source changes, date changes or deletion")
    func sourceChangesMakeProposalStale() throws {
        let entry = try source()
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence, steps: [step(evidence.units[0])], preserving: nil)
        var archive = try ObservationArchive(entries: [entry])
        try archive.correct(id: entry.id, text: "I skip calendar review today.")
        #expect(!proposal.isCurrent(archive: archive, baseRoutine: nil))
        archive = try ObservationArchive(entries: [entry])
        try archive.assignObservedDate(id: entry.id, value: source(day: 1).observedDate)
        #expect(!proposal.isCurrent(archive: archive, baseRoutine: nil))
        archive = try ObservationArchive(entries: [entry])
        try archive.assignObservedDate(id: entry.id, value: entry.observedDate, origin: .synthetic)
        #expect(!proposal.isCurrent(archive: archive, baseRoutine: nil))
        let changed = try source(id: entry.id, text: "I do not review the calendar today.")
        #expect(!proposal.isCurrent(archive: try ObservationArchive(entries: [changed]), baseRoutine: nil))
        #expect(!proposal.isCurrent(archive: ObservationArchive(), baseRoutine: nil))
    }

    @Test("Full base state catches same-ID approval and step edits")
    func baseRevisionIncludesApprovalAndAllFields() throws {
        let entry = try source()
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        let base = RoutineVersion(createdAt: instant, sourceLabel: "My routine",
            steps: [RoutineStep(title: "Tea", detail: "Quiet time", durationMinutes: 7)])
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence, steps: [step(evidence.units[0])], preserving: base)
        let archive = try ObservationArchive(entries: [entry])
        #expect(proposal.isCurrent(archive: archive, baseRoutine: base))
        #expect(!proposal.isCurrent(archive: archive, baseRoutine: base.approved()))
        var edited = base
        edited.steps[0].detail = "Changed without replacing the routine ID"
        #expect(!proposal.isCurrent(archive: archive, baseRoutine: edited))
        edited = base; edited.steps[0].automation = .spokenNote
        #expect(!proposal.isCurrent(archive: archive, baseRoutine: edited))
        edited = base; edited.number += 1
        #expect(!proposal.isCurrent(archive: archive, baseRoutine: edited))
        #expect(!proposal.isCurrent(archive: archive, baseRoutine: nil))
    }

    @Test("Kept rituals retain user values and do not borrow fresh model evidence")
    func requiredRitualReconciliationIsHonest() throws {
        let entry = try source()
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        let kept = RoutineStep(title: "Review calendar", detail: "My exact custom reminder", kind: .calendar,
            durationMinutes: 11, isRequired: true, automation: .spokenNote)
        let base = RoutineVersion(createdAt: instant, sourceLabel: "My approved morning", steps: [kept], isApproved: true)
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence, steps: [step(evidence.units[0])], preserving: base)
        #expect(proposal.routine.steps == [kept])
        #expect(!proposal.routine.isApproved)
        #expect(proposal.support[0].stepID == kept.id)
        #expect(proposal.support[0].reason == .preservedUserDecision)
        #expect(proposal.support[0].citations.isEmpty)
        #expect(proposal.isCurrent(archive: try ObservationArchive(entries: [entry]), baseRoutine: base))
    }

    @Test("Synthetic proposals stay synthetic and sample rituals do not become personal preferences")
    func syntheticOriginAndSampleExclusion() throws {
        let entry = try source(origin: .synthetic)
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence, steps: [step(evidence.units[0])], preserving: DemoFixtures.routine)
        #expect(proposal.routine.sourceLabel.localizedCaseInsensitiveContains("demo fixture"))
        #expect(proposal.routine.sourceLabel.contains("synthetic saved observations"))
        #expect(proposal.sourceSnapshots.allSatisfy { $0.origin == .synthetic })
        #expect(proposal.routine.steps.count == 1)
        #expect(proposal.support.allSatisfy { $0.reason == .inferredEvidence })
    }

    @Test("Validated restoration rejects approval and corrupted citation offsets")
    func codableRestorationIsValidated() throws {
        let entry = try source()
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence, steps: [step(evidence.units[0])], preserving: nil)
        let data = try JSONEncoder().encode(proposal)
        let restored = try JSONDecoder().decode(EvidenceRoutineProposal.self, from: data)
        #expect(restored == proposal)
        #expect(restored.isCurrent(archive: try ObservationArchive(entries: [entry]), baseRoutine: nil))
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var routine = try #require(object["routine"] as? [String: Any])
        routine["isApproved"] = true; object["routine"] = routine
        #expect(throws: RoutineEvidenceProposalError.invalidProposal) {
            try JSONDecoder().decode(EvidenceRoutineProposal.self, from: JSONSerialization.data(withJSONObject: object))
        }
        object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var support = try #require(object["support"] as? [[String: Any]])
        var citations = try #require(support[0]["citations"] as? [[String: Any]])
        citations[0]["startCharacterOffset"] = Int.max
        citations[0]["endCharacterOffset"] = Int.min
        support[0]["citations"] = citations; object["support"] = support
        #expect(throws: RoutineEvidenceProposalError.invalidProposal) {
            try JSONDecoder().decode(EvidenceRoutineProposal.self, from: JSONSerialization.data(withJSONObject: object))
        }
    }

    @Test("More than ten moments fails without silently removing kept rituals")
    func totalMomentLimitIncludesRequiredRituals() throws {
        let entry = try source()
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        let kept = (0..<10).map { RoutineStep(title: "Kept ritual \($0)", isRequired: true) }
        let base = RoutineVersion(sourceLabel: "My personal routine", steps: kept, isApproved: true)
        #expect(throws: RoutineEvidenceProposalError.tooManySteps) {
            try LearningEvidencePreparation.assemble(evidence: evidence, steps: [step(evidence.units[0])], preserving: base)
        }
        #expect(base.steps == kept)
        #expect(base.isApproved)
    }

    @Test("Approved routine retains bounded exact quotations after pending receipt removal")
    func routineRetainsEvidenceAfterApproval() throws {
        let sources = try [source(), source(day: 1), source(day: 2, text: "I review tomorrow’s appointments after breakfast.")]
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: sources)
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence,
            steps: evidence.units.map { step($0) }, preserving: nil)
        let approved = proposal.routine.approved()
        let detail = approved.steps[0].detail
        #expect(approved.isApproved)
        #expect(detail.contains("Evidence:"))
        #expect(Data(detail.utf8).range(of: Data(words.utf8)) != nil)
        #expect(Data(detail.utf8).range(of: Data(sources[2].originalText.utf8)) != nil)
        #expect(detail.components(separatedBy: "Evidence:").count == 3)
        #expect(detail.count <= 8_000)
    }

    @Test("Restored inferred values cannot overflow routine totals or bypass detail bounds")
    func restoredStepBoundsAndBaseOverflow() throws {
        let entry = try source()
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence, steps: [step(evidence.units[0])], preserving: nil)
        let data = try JSONEncoder().encode(proposal)
        for duration in [-1, Int.max, 61] {
            var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            var routine = try #require(object["routine"] as? [String: Any])
            var steps = try #require(routine["steps"] as? [[String: Any]])
            steps[0]["durationMinutes"] = duration
            routine["steps"] = steps; object["routine"] = routine
            #expect(throws: RoutineEvidenceProposalError.invalidProposal) {
                try JSONDecoder().decode(EvidenceRoutineProposal.self, from: JSONSerialization.data(withJSONObject: object))
            }
        }
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var routine = try #require(object["routine"] as? [String: Any])
        var steps = try #require(routine["steps"] as? [[String: Any]])
        steps[0]["detail"] = String(repeating: "x", count: 8_001)
        routine["steps"] = steps; object["routine"] = routine
        #expect(throws: RoutineEvidenceProposalError.invalidProposal) {
            try JSONDecoder().decode(EvidenceRoutineProposal.self, from: JSONSerialization.data(withJSONObject: object))
        }
        let extreme = RoutineVersion(number: Int.max, sourceLabel: "My routine", steps: [])
        #expect(throws: RoutineEvidenceProposalError.invalidProposal) {
            try LearningEvidencePreparation.assemble(evidence: evidence, steps: [step(evidence.units[0])], preserving: extreme)
        }
    }

    @Test("Restoration cannot discard or normalize the quotation retained after approval")
    func restoredDetailMustRetainExactEvidenceEntry() throws {
        let original = "I drink cafe\u{301} before reviewing my calendar."
        let entry = try source(text: original)
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence,
            steps: [step(evidence.units[0])], preserving: nil)
        let data = try JSONEncoder().encode(proposal)
        let alteredDetails = [
            "A tentative calendar review with no retained quotation.",
            original, // Bare prose is not the app-owned retained Evidence entry.
            "Evidence: “I drink café before reviewing my calendar.”" // Canonically equal, different bytes.
        ]
        for detail in alteredDetails {
            var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            var routine = try #require(object["routine"] as? [String: Any])
            var steps = try #require(routine["steps"] as? [[String: Any]])
            steps[0]["detail"] = detail
            routine["steps"] = steps; object["routine"] = routine
            // Typed citations and original source hashes remain intact in all cases.
            #expect(throws: RoutineEvidenceProposalError.invalidProposal) {
                try JSONDecoder().decode(EvidenceRoutineProposal.self,
                    from: JSONSerialization.data(withJSONObject: object))
            }
        }
        let restored = try JSONDecoder().decode(EvidenceRoutineProposal.self, from: data)
        #expect(restored.isCurrent(archive: try ObservationArchive(entries: [entry]), baseRoutine: nil))
    }

    @Test("Restored proposal version must follow the full current base or begin at one")
    func restoredVersionMustMatchBase() throws {
        let entry = try source()
        let archive = try ObservationArchive(entries: [entry])
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        let base = RoutineVersion(number: 4, createdAt: instant, sourceLabel: "My morning",
            steps: [RoutineStep(title: "Tea")], isApproved: true)
        for prior in [nil, base] as [RoutineVersion?] {
            let proposal = try LearningEvidencePreparation.assemble(evidence: evidence,
                steps: [step(evidence.units[0])], preserving: prior)
            #expect(proposal.routine.number == (prior?.number ?? 0) + 1)
            #expect(proposal.isCurrent(archive: archive, baseRoutine: prior))
            let data = try JSONEncoder().encode(proposal)
            for wrongNumber in [proposal.routine.number + 1, Int.max] {
                var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
                var routine = try #require(object["routine"] as? [String: Any])
                routine["number"] = wrongNumber; object["routine"] = routine
                let restored = try JSONDecoder().decode(EvidenceRoutineProposal.self,
                    from: JSONSerialization.data(withJSONObject: object))
                #expect(!restored.isCurrent(archive: archive, baseRoutine: prior))
            }
        }
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence,
            steps: [step(evidence.units[0])], preserving: base)
        var extreme = base; extreme.number = Int.max
        #expect(!proposal.isCurrent(archive: archive, baseRoutine: extreme))
    }

    #if canImport(FoundationModels)
    @Test("The cited guided schema resolves its exact supplied unit identifiers")
    func citedSchemaResolves() throws {
        let schema = try EvidenceRoutineGenerationSchema.make(unitIDs: [UUID(), UUID()])
        #expect(try JSONEncoder().encode(schema).count > 100)
    }
    #endif
}
