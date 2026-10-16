import Foundation
import Testing
@testable import MorningApple

@Suite("External speech output — fixture closure, no audio provider", .timeLimit(.minutes(1)))
@MainActor
struct SpeechCloudOutputTests {
    @Test func externalPlaybackCompletionIsAwaitedInsteadOfStartingSystemSpeech() async throws {
        let speech = SpeechCoordinator(), gate = SpeechRouteGate()
        var received: String?
        speech.externalSpeech = { text in received = text; await gate.value() }
        var completed = false
        let reading = Task { try await speech.speakAndWait("SYNTHETIC_APPROVED_TEXT"); completed = true }
        await gate.waitUntilCalled()
        #expect(received == "SYNTHETIC_APPROVED_TEXT" && !completed)
        #expect(speech.state == .speaking && speech.currentText == received)
        gate.release(); try await reading.value
        #expect(completed && speech.state == .idle && speech.currentText == nil)
        speech.externalSpeech = nil
    }

    @Test(arguments: [false, true]) func stopOrPauseCancelsTheWaitAndLateCloudCompletionCannotReportSuccess(pause: Bool) async {
        let speech = SpeechCoordinator(), gate = SpeechRouteGate()
        var cancels = 0
        speech.externalSpeech = { _ in await gate.value() }
        speech.cancelExternalSpeech = { cancels += 1 }
        let reading = Task { try await speech.speakAndWait("SYNTHETIC_CANCELLED_TEXT") }
        await gate.waitUntilCalled()
        if pause { speech.pause() } else { speech.stop() }
        await #expect(throws: CancellationError.self) { try await reading.value }
        gate.release()
        for _ in 0..<10 { await Task.yield() }
        #expect(cancels >= 1 && speech.state == .idle && speech.currentText == nil)
        speech.externalSpeech = nil; speech.cancelExternalSpeech = nil
    }

    @Test func providerFailureRemainsAnErrorWithoutAnAppleSpeechFallback() async {
        struct SyntheticFailure: Error {}
        let speech = SpeechCoordinator()
        speech.externalSpeech = { _ in throw SyntheticFailure() }
        await #expect(throws: SpeechPlaybackError.self) { try await speech.speakAndWait("SYNTHETIC_FAILED_TEXT") }
        #expect(speech.state == .idle && speech.lastError != nil && speech.currentText == nil)
        speech.externalSpeech = nil
    }

    @Test func externalFailureFollowsFrenchThenEnglishWithoutChangingGlobalLanguage() async {
        struct SyntheticFailure: Error {}
        var locale = Locale(identifier: "fr_FR"), attempts = 0
        let speech = SpeechCoordinator(externalSpeechLocale: { locale })
        speech.externalSpeech = { _ in attempts += 1; throw SyntheticFailure() }
        defer { speech.externalSpeech = nil }
        let messages = [
            ("fr_FR", "La lecture en ligne n’a pas pu se terminer. Réessayez ou continuez avec les commandes."),
            ("en_US", "Cloud speech could not finish. Try again or continue with the controls.")
        ]
        for (index, message) in messages.enumerated() {
            locale = Locale(identifier: message.0)
            await #expect(throws: SpeechPlaybackError.self) {
                try await speech.speakAndWait("SYNTHETIC_FAILED_TEXT")
            }
            #expect(speech.lastError == message.1)
            #expect(speech.state == .idle && speech.currentText == nil && speech.playbackID == nil)
            #expect(attempts == index + 1)
        }
    }
}

@MainActor
private final class SpeechRouteGate {
    private var waiting: CheckedContinuation<Void, Never>?
    private var observers: [CheckedContinuation<Void, Never>] = []
    func value() async {
        await withCheckedContinuation { continuation in
            waiting = continuation
            let current = observers; observers = []
            for observer in current { observer.resume() }
        }
    }
    func waitUntilCalled() async {
        guard waiting == nil else { return }
        await withCheckedContinuation { observers.append($0) }
    }
    func release() { let current = waiting; waiting = nil; current?.resume() }
}
