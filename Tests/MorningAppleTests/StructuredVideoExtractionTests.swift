import Foundation
import MorningCore
import Testing
@testable import MorningApple

@Suite("Single-pass video evidence assembly")
struct StructuredVideoExtractionTests {
    @Test func productionAssemblerRetainsOneResultPerRequestBeforeAnyDisplayDeduplication() throws {
        var builder = try VideoObservationBuilder(durationSeconds: 8)
        let ids = (0..<5).map { _ in UUID() }
        try builder.append(id: ids[0], requestedTimeSeconds: 0, actualTimeSeconds: 0, outcome: .observed, text: "Demo Inbox")
        try builder.append(id: ids[1], requestedTimeSeconds: 1, actualTimeSeconds: 1, outcome: .observed, text: "Demo Inbox")
        try builder.append(id: ids[2], requestedTimeSeconds: 2, actualTimeSeconds: nil, outcome: .decodeFailed)
        try builder.append(id: ids[3], requestedTimeSeconds: 3, actualTimeSeconds: 3, outcome: .ocrFailed)
        try builder.append(id: ids[4], requestedTimeSeconds: 4, actualTimeSeconds: 4, outcome: .blank)
        let result = try builder.finish()
        #expect(result.frames.map(\.id) == ids)
        #expect(result.frames.map(\.requestedTimeSeconds) == [0, 1, 2, 3, 4])
        #expect(result.frames.map(\.outcome) == [.observed, .observed, .decodeFailed, .ocrFailed, .blank])
        #expect(result.frames.count == 5)
        #expect(result.renderedText.components(separatedBy: "[Observed frame at ").count - 1 == 1)
        #expect(result.decodedFrameCount == 4)
        #expect(result.warnings.contains { $0.contains("2 of 5") })
    }

    @Test func textBudgetTruncationIsExplicitAndLaterRequestsAreStillRepresented() throws {
        var builder = try VideoObservationBuilder(durationSeconds: 10)
        try builder.append(id: UUID(), requestedTimeSeconds: 0, actualTimeSeconds: 0, outcome: .observed,
                           text: String(repeating: "x", count: ObservationVideoEvidence.maximumOCRCharacters + 1))
        try builder.append(id: UUID(), requestedTimeSeconds: 1, actualTimeSeconds: 1, outcome: .observed, text: "Later synthetic content")
        try builder.append(id: UUID(), requestedTimeSeconds: 2, actualTimeSeconds: nil, outcome: .decodeFailed)
        let result = try builder.finish()
        #expect(result.frames.count == 3)
        #expect(result.frames[0].text.count == ObservationVideoEvidence.maximumOCRCharacters)
        #expect(result.frames[0].textWasTruncated)
        #expect(result.frames[1].text.isEmpty && result.frames[1].textWasTruncated)
        #expect(result.frames[1].outcome == .observed, "Omitted OCR must not falsely label a screen blank.")
        #expect(result.frames[2].outcome == .decodeFailed)
        #expect(result.frames.allSatisfy { !$0.canSupportIdentity })
        #expect(result.renderedText.count <= ObservationVideoEvidence.maximumRenderedCharacters)
    }

    @Test func UTF8BudgetKeepsWholeCharactersAndInvalidActualTimesBecomeExplicitFallbacks() throws {
        var builder = try VideoObservationBuilder(durationSeconds: 10)
        let family = "👨‍👩‍👧‍👦"
        try builder.append(id: UUID(), requestedTimeSeconds: 0, actualTimeSeconds: .nan,
                           outcome: .observed, text: String(repeating: family, count: 20_000))
        let result = try builder.finish()
        let source = try #require(result.frames.first)
        #expect(source.textWasTruncated)
        #expect(source.text.utf8.count <= ObservationVideoEvidence.maximumOCRBytes)
        #expect(source.text.allSatisfy { String($0) == family })
        #expect(source.actualTimeSeconds == nil)
        #expect(source.timeBasis == .requestedSamplingTime)
        #expect(source.timeSeconds == 0)
        #expect(source.warnings.contains { $0.contains("fallback") })
    }

    @Test func frameCapRejectsAnExtraRequestWithoutDiscardingTheAcceptedTrace() throws {
        var builder = try VideoObservationBuilder(durationSeconds: 100)
        for index in 0..<ObservationVideoEvidence.maximumFrames {
            try builder.append(id: UUID(), requestedTimeSeconds: Double(index), actualTimeSeconds: Double(index), outcome: .blank)
        }
        #expect(throws: ObservationVideoEvidenceError.evidenceTooLarge) {
            try builder.append(id: UUID(), requestedTimeSeconds: 24, actualTimeSeconds: 24, outcome: .blank)
        }
        #expect(try builder.finish().frames.count == 24)
        #expect(try !builder.finish().hasRecognizedText)
    }
}
