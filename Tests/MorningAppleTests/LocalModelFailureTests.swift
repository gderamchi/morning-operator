import Foundation
import Testing
@testable import MorningApple

/// A model that does not answer is shown as a plain sentence, never a system error code (issue #89).
@Suite("A local model failure reads as a sentence") @MainActor
struct LocalModelFailureTests {
    private struct ModelManagerError: Error {}

    @Test func theSimulatorsMissingModelReadsAsNotReady() {
        let error = NSError(domain: "FoundationModels.ModelManagerError", code: 1019)
        #expect(LocalModelFailureReason.reason(for: error) == .notReady)
        let shown = AppleIntelligenceService.modelFailure(error).localizedDescription
        #expect(!shown.contains("1019") && !shown.contains("ModelManagerError"), "\(shown)")
        #expect(shown == LocalModelFailureReason.notReady.sentence)
    }

    @Test func anotherModelManagerCodeIsAFailureWithoutItsCode() {
        let error = NSError(domain: "FoundationModels.ModelManagerError", code: 1020)
        #expect(LocalModelFailureReason.reason(for: error) == .failed)
        let shown = AppleIntelligenceService.modelFailure(error).localizedDescription
        #expect(!shown.contains("1020") && !shown.contains("error"), "\(shown)")
    }

    @Test func everySentenceIsPlainAndHasFrench() throws {
        let path = try #require(Bundle.module.path(forResource: "fr", ofType: "lproj"))
        let french = try #require(Bundle(path: path))
        let reasons: [LocalModelFailureReason] = [.declined, .tooLong, .language, .busy, .notReady, .failed]
        for reason in reasons {
            let english = reason.sentence
            #expect(!english.isEmpty && english.rangeOfCharacter(from: .decimalDigits) == nil, "\(reason)")
            let translated = french.localizedString(forKey: english, value: nil, table: nil)
            #expect(translated != english && translated.contains("modèle local"), "\(reason) has no French: \(translated)")
        }
    }

    @Test func cancellationStaysCancellation() async {
        await #expect(throws: CancellationError.self) {
            _ = try await AppleIntelligenceService.answer { () async throws -> Int in throw CancellationError() }
        }
        await #expect(throws: AppleIntelligenceError.modelDidNotAnswer(.failed)) {
            _ = try await AppleIntelligenceService.answer { () async throws -> Int in throw ModelManagerError() }
        }
    }
}
