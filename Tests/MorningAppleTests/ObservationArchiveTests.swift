import Foundation
import MorningCore
import Testing
@testable import MorningApple

@Suite("Dated observation archive")
struct ObservationArchiveTests {
    private let imported = Date(timeIntervalSince1970: 1_792_000_000)

    private func written(_ text: String = "A synthetic morning note", id: UUID = UUID(), digest: String? = nil,
                         observed: ObservationObservedDate? = nil,
                         origin: ObservationAcquisitionOrigin = .unknown) throws -> ObservationAcquisition {
        try .init(id: id, importedAt: imported, fileSHA256: digest, observedDate: observed,
                  origin: origin, sourceKind: .text, sourceLabel: "Selected synthetic notes", originalText: text)
    }
    private func video(_ text: String = "Synthetic heading") throws -> ObservationVideoEvidence {
        try .init(durationSeconds: 2, frames: [
            ObservationFrameEvidence(requestedTimeSeconds: 0, actualTimeSeconds: 0, outcome: .observed, text: text)
        ])
    }
    private func movie(_ evidence: ObservationVideoEvidence, id: UUID = UUID(),
                       classification: ObservationContextClassification? = nil) throws -> ObservationAcquisition {
        try .init(id: id, importedAt: imported, sourceKind: .video, sourceLabel: "Synthetic movie",
                  originalText: evidence.renderedText, videoEvidence: evidence, classification: classification)
    }
    /// Supplied test result; these tests invoke no model or Apple framework.
    private func interpretation(_ evidence: ObservationVideoEvidence, quote: String? = nil) -> ObservationContextClassification {
        let decisions = evidence.frames.map { frame in
            ObservationFrameIdentityDecision(sampleID: frame.id, timeSeconds: frame.timeSeconds, timeBasis: frame.timeBasis,
                evidence: .identified(app: .init(key: "visual-context:synthetic", displayName: "Synthetic"), reference: frame.evidenceReference),
                evidenceQuote: quote ?? frame.text)
        }
        return .init(decisions: decisions, status: .completed, attemptedBatchCount: 1,
                     respondedBatchCount: 1, failedBatchCount: 0, diagnostics: [], modelAvailability: "Synthetic test result")
    }

    @Test func twoExplicitDaysAndOriginsSurviveSuccessiveImportsAndRelaunch() throws {
        let firstDate = try ObservationObservedDate(date: imported, timeZoneIdentifier: "Europe/Paris", provenance: .recordingSession)
        let secondDate = try ObservationObservedDate(date: imported.addingTimeInterval(86_400), timeZoneIdentifier: "Europe/Paris", provenance: .userAssigned)
        let first = try written(observed: firstDate, origin: .human)
        let second = try written("Another independent synthetic observation", observed: secondDate, origin: .synthetic)
        var archive = ObservationArchive()
        try archive.insert(first)
        try archive.insert(second)
        let restored = try JSONDecoder().decode(ObservationArchive.self, from: JSONEncoder().encode(archive))
        #expect(restored.entries == [first, second])
        #expect(restored.entries.map(\.origin) == [.human, .synthetic])
        #expect(firstDate.dayKey != secondDate.dayKey)
        #expect(restored.entries.map(\.observedDate?.provenance) == [.recordingSession, .userAssigned])
    }

    @Test func digestReimportPreservesIDCorrectionDateImportTimeAndOriginalSource() throws {
        let digest = String(repeating: "a", count: 64)
        let original = try written(digest: digest)
        var archive = ObservationArchive()
        try archive.insert(original)
        let assigned = try ObservationObservedDate(date: imported, timeZoneIdentifier: "UTC", provenance: .userAssigned)
        try archive.assignObservedDate(id: original.id, value: assigned, origin: .human)
        try archive.correct(id: original.id, text: "My correction")
        let before = archive
        let reimport = try ObservationAcquisition(importedAt: imported.addingTimeInterval(1_000), fileSHA256: digest.uppercased(),
            origin: .synthetic, sourceKind: .text, sourceLabel: "New filename", originalText: "A different OCR pass")
        let selected = try archive.insert(reimport)
        #expect(selected == original.id)
        #expect(archive == before)
        #expect(archive.entry(id: selected)?.effectiveText == "My correction")
        #expect(archive.entry(id: selected)?.originalText == original.originalText)
        #expect(archive.entry(id: selected)?.observedDate == assigned)
        #expect(archive.entry(id: selected)?.importedAt == imported)
    }

    @Test func stableAcquisitionRetryDeduplicatesButMatchingTextAloneDoesNot() throws {
        let original = try written()
        var archive = try ObservationArchive(entries: [original])
        #expect(try archive.insert(original) == original.id)
        #expect(archive.entries.count == 1)
        let separate = try written(original.originalText)
        try archive.insert(separate)
        #expect(archive.entries.count == 2)
        let conflicting = try written("Changed original", id: original.id)
        let before = archive
        #expect(throws: ObservationArchiveError.duplicateAcquisition) { try archive.insert(conflicting) }
        #expect(archive == before)
    }

    @Test func correctionsRetainOriginalVideoAndInvalidateAnalysisWithoutChangingAcquisition() throws {
        let evidence = try video()
        let result = interpretation(evidence)
        let source = try movie(evidence, classification: result)
        var archive = try ObservationArchive(entries: [source])
        try archive.correct(id: source.id, text: "I was planning, not reading a message")
        let corrected = try #require(archive.entry(id: source.id))
        #expect(corrected.originalText == source.originalText)
        #expect(corrected.videoEvidence == evidence)
        #expect(corrected.classification == nil)
        #expect(corrected.warnings.isEmpty)
        let before = archive
        #expect(throws: ObservationArchiveError.correctedObservation) { try archive.classify(id: source.id, result: result) }
        #expect(archive == before)
        try archive.correct(id: source.id, text: nil)
        #expect(archive.entry(id: source.id)?.effectiveText == source.originalText)
        #expect(archive.entry(id: source.id)?.classification == nil)
        try archive.classify(id: source.id, result: result)
        #expect(archive.entries.count == 1)
        #expect(archive.entry(id: source.id)?.classification == result)
    }

    @Test func unsupportedInterpretationIsRemovedWithoutLosingValidSourceOnRestoration() throws {
        let evidence = try video()
        let source = try movie(evidence, classification: interpretation(evidence))
        let encoded = try JSONEncoder().encode(ObservationArchive(entries: [source]))
        let json = try JSONSerialization.jsonObject(with: encoded)
        let original = try #require(json as? [String: Any])
        let originalEntries = try #require(original["entries"] as? [[String: Any]])
        var object = original
        var entries = originalEntries
        var classification = try #require(entries[0]["classification"] as? [String: Any])
        var decisions = try #require(classification["decisions"] as? [[String: Any]])
        decisions[0]["evidenceQuote"] = "Text absent from this source"
        classification["decisions"] = decisions
        entries[0]["classification"] = classification
        object["entries"] = entries
        let restored = try JSONDecoder().decode(ObservationArchive.self, from: JSONSerialization.data(withJSONObject: object))
        let retained = try #require(restored.entry(id: source.id))
        #expect(retained.videoEvidence == evidence)
        #expect(retained.originalText == source.originalText)
        #expect(retained.classification == nil)
        #expect(retained.warnings == [.invalidClassificationRemoved])
        entries = originalEntries
        entries[0]["classification"] = "Malformed derived payload"
        object["entries"] = entries
        let malformed = try JSONDecoder().decode(ObservationArchive.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(malformed.entry(id: source.id)?.warnings == [.invalidClassificationRemoved])
        #expect(malformed.entry(id: source.id)?.videoEvidence == evidence)
    }

    @Test func explicitBadClassificationIsTransactionalAndConstructorDowngradesDerivedOnly() throws {
        let evidence = try video("Caf\u{00E9}")
        let original = try movie(evidence, classification: interpretation(evidence))
        var archive = try ObservationArchive(entries: [original])
        let unsupported = interpretation(evidence, quote: "Cafe\u{0301}")
        let before = archive
        #expect(throws: ObservationArchiveError.invalidClassification) { try archive.classify(id: original.id, result: unsupported) }
        #expect(archive == before)
        let restored = try movie(evidence, classification: unsupported)
        #expect(restored.classification == nil)
        #expect(restored.videoEvidence == evidence)
        #expect(restored.warnings == [.invalidClassificationRemoved])
    }

    @Test func quoteFromOmittedBodyCannotBorrowPreparedHeaderProvenance() throws {
        let evidence = try video("Synthetic heading\n" + String(repeating: "q", count: 340))
        let input = try ObservationContextValidation.prepare(frames: evidence.frames, catalog: [])
        let unsupported = interpretation(evidence, quote: "qqq")
        let derived = ObservationContextClassification(decisions: unsupported.decisions, status: .completed,
            attemptedBatchCount: 1, respondedBatchCount: 1, failedBatchCount: 0,
            diagnostics: [], modelAvailability: "Synthetic test result", inputSelection: input.inputSelection)
        let restored = try movie(evidence, classification: derived)
        #expect(restored.videoEvidence == evidence)
        #expect(restored.classification == nil)
        #expect(restored.warnings == [.invalidClassificationRemoved])
        let supported = interpretation(evidence, quote: "Synthetic heading")
        let valid = ObservationContextClassification(decisions: supported.decisions, status: .completed,
            attemptedBatchCount: 1, respondedBatchCount: 1, failedBatchCount: 0,
            diagnostics: [], modelAvailability: "Synthetic test result", inputSelection: input.inputSelection)
        #expect(try movie(evidence, classification: valid).classification == valid)
    }

    @Test func explicitObservedZoneControlsDayAndUnknownLegacyDatesStayUnknown() throws {
        let instant = try #require(ISO8601DateFormatter().date(from: "2026-10-10T00:30:00Z"))
        let paris = try ObservationObservedDate(date: instant, timeZoneIdentifier: "Europe/Paris", provenance: .recordingSession)
        let newYork = try ObservationObservedDate(date: instant, timeZoneIdentifier: "America/New_York", provenance: .userAssigned)
        #expect(paris.dayKey == "2026-10-10")
        #expect(newYork.dayKey == "2026-10-09")
        #expect(paris.date == newYork.date)
        #expect(paris.dayStart != newYork.dayStart)
        let legacy = try ObservationAcquisition(importedAt: nil, sourceKind: .unknown,
                                               sourceLabel: "Legacy observation", originalText: "Previously saved note")
        let restored = try JSONDecoder().decode(ObservationAcquisition.self, from: JSONEncoder().encode(legacy))
        #expect(restored.importedAt == nil)
        #expect(restored.observedDate == nil)
        #expect(restored.origin == .unknown)
        #expect(restored.fileSHA256 == nil)
        #expect(throws: ObservationArchiveError.invalidDate) {
            try ObservationObservedDate(date: instant, timeZoneIdentifier: "Not/A_Zone", provenance: .userAssigned)
        }
        #expect(throws: ObservationArchiveError.invalidDate) {
            try ObservationObservedDate(date: Date(timeIntervalSince1970: .infinity), timeZoneIdentifier: "UTC", provenance: .userAssigned)
        }
        var archive = try ObservationArchive(entries: [legacy])
        try archive.assignObservedDate(id: legacy.id, value: paris, origin: .automated)
        #expect(archive.entry(id: legacy.id)?.origin == .automated)
        try archive.assignObservedDate(id: legacy.id, value: nil)
        #expect(archive.entry(id: legacy.id)?.observedDate == nil)
        #expect(archive.entry(id: legacy.id)?.origin == .automated)
        #expect(archive.entry(id: legacy.id)?.importedAt == nil)
    }

    @Test func deleteRemovesOnlyChosenAcquisitionAndClearRemovesAll() throws {
        let first = try written("First day")
        let second = try written("Second day")
        var archive = try ObservationArchive(entries: [first, second])
        try archive.delete(id: first.id)
        #expect(archive.entries == [second])
        let before = archive
        #expect(throws: ObservationArchiveError.unknownAcquisition) { try archive.delete(id: first.id) }
        #expect(archive == before)
        archive.clear()
        #expect(archive == ObservationArchive())
    }

    @Test func entryAndTextBudgetsRejectAdditionsWithoutEviction() throws {
        let entries = try (0..<ObservationArchive.maximumEntries).map { try written("Observation \($0)") }
        var archive = try ObservationArchive(entries: entries)
        let before = archive
        let extra = try written("One more")
        #expect(throws: ObservationArchiveError.archiveFull) { try archive.insert(extra) }
        #expect(archive == before)
        let text = String(repeating: "🧪", count: ObservationArchive.maximumTextCharacters)
        let large = try (0..<33).map { _ in
            try ObservationAcquisition(sourceKind: .manual, sourceLabel: "Synthetic budget fixture",
                                       originalText: text, correctedText: text)
        }
        #expect(throws: ObservationArchiveError.archiveTooLarge) { try ObservationArchive(entries: large) }
    }

    @Test func aggregateLayoutBudgetRejectsOversizedArchive() throws {
        let count = ObservationFrameEvidence.maximumOCRLines
        let text = Array(repeating: "A", count: count).joined(separator: "\n")
        let bounds = try ObservationNormalizedBounds(x: 0, y: 0, width: 1, height: 0.1)
        let lines = try (0..<count).map { index in
            try ObservationOCRLine(text: "A", startCharacterOffset: index * 2, endCharacterOffset: index * 2 + 1,
                                   bounds: bounds, confidence: 1)
        }
        let frames = try (0..<ObservationVideoEvidence.maximumFrames).map { index in
            try ObservationFrameEvidence(requestedTimeSeconds: Double(index), outcome: .observed, text: text, ocrLines: lines)
        }
        let evidence = try ObservationVideoEvidence(durationSeconds: 25, frames: frames)
        let entries = try (0..<4).map { _ in try movie(evidence) }
        #expect(4 * frames.count * lines.count > ObservationArchive.maximumOCRLines)
        #expect(throws: ObservationArchiveError.archiveTooLarge) { try ObservationArchive(entries: entries) }
    }

    @Test func malformedSourceAndConflictingFingerprintsDoNotMasqueradeAsValidHistory() throws {
        let evidence = try video()
        #expect(throws: ObservationArchiveError.invalidSource) {
            try ObservationAcquisition(sourceKind: .image, sourceLabel: "Wrong type", originalText: evidence.renderedText, videoEvidence: evidence)
        }
        #expect(throws: ObservationArchiveError.invalidSource) {
            try ObservationAcquisition(sourceKind: .video, sourceLabel: "Altered body", originalText: "Different OCR", videoEvidence: evidence)
        }
        let coverage = "[Recording coverage: This is an interrupted synthetic recording.]\n\n" + evidence.renderedText
        let withNote = try ObservationAcquisition(sourceKind: .video, sourceLabel: "Partial synthetic movie",
            originalText: coverage, videoEvidence: evidence)
        #expect(withNote.originalText == coverage)
        #expect(throws: ObservationArchiveError.invalidDigest) { try written(digest: String(repeating: "z", count: 64)) }
        let first = try written(digest: String(repeating: "b", count: 64))
        let duplicate = try written(digest: first.fileSHA256)
        #expect(throws: ObservationArchiveError.duplicateDigest) { try ObservationArchive(entries: [first, duplicate]) }
        #expect(throws: ObservationArchiveError.duplicateAcquisition) { try ObservationArchive(entries: [first, first]) }
        #expect(throws: ObservationArchiveError.invalidSource) { try written(String(repeating: "A", count: 33_001)) }
        #expect(throws: ObservationArchiveError.invalidSource) {
            try ObservationAcquisition(sourceKind: .manual, sourceLabel: "Correction limit", originalText: "Original",
                                       correctedText: String(repeating: "A", count: 32_001))
        }
        let source = try movie(evidence)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(source))
        var object = try #require(json as? [String: Any])
        var videoObject = try #require(object["videoEvidence"] as? [String: Any])
        videoObject["durationSeconds"] = 0
        object["videoEvidence"] = videoObject
        #expect(throws: ObservationVideoEvidenceError.invalidDuration) {
            try JSONDecoder().decode(ObservationAcquisition.self, from: JSONSerialization.data(withJSONObject: object))
        }
    }
}
