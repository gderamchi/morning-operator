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
            await #expect(throws: SpeechPlaybackError.self) { try await speech.speakAndWait("SYNTHETIC_FAILED_TEXT") }
            #expect(speech.lastError == message.1)
            #expect(speech.state == .idle && speech.currentText == nil && speech.playbackID == nil)
            #expect(attempts == index + 1)
        }
    }

    @Test func providerFailureWaitsForReleaseAndThenWaitsForTheSameAppleReading() async throws {
        let release = SpeechRouteGate(), apple = SpeechRouteGate()
        var readings: [String] = []
        let speech = SpeechCoordinator(localSpeechOutput: { text, _ in readings.append(text); await apple.value() })
        speech.externalSpeech = { _ in throw MorningCloudVoiceError.unavailable }
        speech.externalSpeechFallback = { await release.value() }
        var completed = false
        let reading = Task { try await speech.speakAndWait("SYNTHETIC_APPROVED_READING"); completed = true }
        await release.waitUntilCalled()
        let requestID = speech.playbackID
        #expect(readings.isEmpty && !completed && speech.state == .preparing)
        release.release(); await apple.waitUntilCalled()
        #expect(readings == ["SYNTHETIC_APPROVED_READING"] && speech.playbackID == requestID && !completed)
        apple.release(); try await reading.value
        #expect(completed && speech.state == .idle && speech.playbackID == nil)
    }

    @Test(arguments: [false, true])
    func stopOrPauseDuringReleaseNeverStartsApple(pause: Bool) async {
        let release = SpeechRouteGate()
        var appleReads = 0
        let speech = SpeechCoordinator(localSpeechOutput: { _, _ in appleReads += 1 })
        speech.externalSpeech = { _ in throw MorningCloudVoiceError.unavailable }
        speech.externalSpeechFallback = { await release.value() }
        let reading = Task { try await speech.speakAndWait("SYNTHETIC_STOPPED_READING") }
        await release.waitUntilCalled()
        if pause { speech.pause() } else { speech.stop() }
        await #expect(throws: CancellationError.self) { try await reading.value }
        release.release()
        for _ in 0..<10 { await Task.yield() }
        #expect(appleReads == 0 && speech.state == .idle)
    }

    @Test func aRejectedAdmissionCannotFallBackOrCompleteSuccessfully() async {
        let release = SpeechRouteGate()
        var appleReads = 0, current = true
        let speech = SpeechCoordinator(localSpeechOutput: { _, _ in appleReads += 1 })
        speech.externalSpeech = { _ in throw MorningCloudVoiceError.unavailable }
        speech.externalSpeechFallback = {
            await release.value()
            guard current else { throw CancellationError() }
        }
        let reading = Task { try await speech.speakAndWait("SYNTHETIC_INVALIDATED_CONSENT") }
        await release.waitUntilCalled()
        current = false; release.release()
        await #expect(throws: CancellationError.self) { try await reading.value }
        #expect(appleReads == 0 && speech.lastError == nil)
    }

    @Test(arguments: [false, true])
    func taskCancellationOrChangedGenderInvalidatesPendingRecovery(changeGender: Bool) async {
        let release = SpeechRouteGate()
        var appleReads = 0
        let speech = SpeechCoordinator(localSpeechOutput: { _, _ in appleReads += 1 })
        speech.externalSpeech = { _ in throw MorningCloudVoiceError.unavailable }
        speech.externalSpeechFallback = { await release.value() }
        let reading = Task { try await speech.speakAndWait("SYNTHETIC_OLD_SELECTION") }
        await release.waitUntilCalled()
        if changeGender { speech.voiceGender = .male } else { reading.cancel() }
        await #expect(throws: CancellationError.self) { try await reading.value }
        release.release()
        for _ in 0..<10 { await Task.yield() }
        #expect(appleReads == 0 && speech.state == .idle)
    }

    @Test func aReplacementReadingSurvivesThePreviousReleaseFinishingLate() async throws {
        let release = SpeechRouteGate(), apple = SpeechRouteGate()
        var readings: [String] = []
        let speech = SpeechCoordinator(localSpeechOutput: { text, _ in readings.append(text); await apple.value() })
        speech.externalSpeech = { _ in throw MorningCloudVoiceError.unavailable }
        speech.externalSpeechFallback = { await release.value() }
        let old = Task { try await speech.speakAndWait("SYNTHETIC_OLD") }
        await release.waitUntilCalled()
        speech.externalSpeech = nil; speech.externalSpeechFallback = nil
        let new = Task { try await speech.speakAndWait("SYNTHETIC_NEW") }
        await apple.waitUntilCalled()
        let newID = speech.playbackID
        await #expect(throws: CancellationError.self) { try await old.value }
        release.release()
        for _ in 0..<10 { await Task.yield() }
        #expect(readings == ["SYNTHETIC_NEW"] && speech.playbackID == newID)
        apple.release(); try await new.value
    }

    @Test func directCancellationNeverCallsTheRecoveryBarrier() async {
        var appleReads = 0, recoveries = 0
        let speech = SpeechCoordinator(localSpeechOutput: { _, _ in appleReads += 1 })
        speech.externalSpeech = { _ in throw CancellationError() }
        speech.externalSpeechFallback = { recoveries += 1 }
        await #expect(throws: CancellationError.self) { try await speech.speakAndWait("SYNTHETIC_INTERRUPTED") }
        #expect(appleReads == 0 && recoveries == 0)
    }

    @Test func appleFailureDoesNotRetryCloudOrReportCompletion() async {
        var cloudReads = 0, appleReads = 0, recoveries = 0
        let speech = SpeechCoordinator(localSpeechOutput: { _, _ in appleReads += 1; throw MorningCloudVoiceError.unavailable })
        speech.externalSpeech = { _ in cloudReads += 1; throw MorningCloudVoiceError.unavailable }
        speech.externalSpeechFallback = { recoveries += 1 }
        await #expect(throws: SpeechPlaybackError.self) { try await speech.speakAndWait("SYNTHETIC_FAILURE") }
        #expect(cloudReads == 1 && appleReads == 1 && recoveries == 1 && speech.state == .idle)
    }

    @Test func textOnlyCloudAudioWaitsForPlaybackAndKeepsCaptionsShort() async throws {
        let drain = SpeechRouteGate()
        var syntheses = 0, appleReads = 0, completed = false
        let text = String(repeating: "SYNTHETIC_APPROVED_PASSAGE ", count: 20)
        let bytes = Data([1, 2, 3])
        let speech = SpeechCoordinator(localSpeechOutput: { _, _ in appleReads += 1 }, audioDataPlayback: { data in
            #expect(data == bytes); await drain.value()
        })
        speech.voiceGender = .male
        speech.cloudSpeech = { received, gender in
            #expect(received == text.trimmingCharacters(in: .whitespaces) && gender == .male)
            syntheses += 1; return bytes
        }
        let reading = Task { try await speech.speakAndWait(text); completed = true }
        await drain.waitUntilCalled()
        #expect(!completed && syntheses == 1 && appleReads == 0 && speech.state == .speaking)
        #expect((speech.currentCaption?.count ?? 0) <= 110 && speech.currentCaption != speech.currentText)
        drain.release(); try await reading.value
        #expect(completed && speech.state == .idle)
    }

    @Test func theExplicitSDKRouteHasPriorityOverTextOnlySynthesis() async throws {
        var sdk = 0, tts = 0, apple = 0
        let speech = SpeechCoordinator(localSpeechOutput: { _, _ in apple += 1 })
        speech.externalSpeech = { _ in sdk += 1 }
        speech.cloudSpeech = { _, _ in tts += 1; return Data() }
        try await speech.speakAndWait("SYNTHETIC_SDK_READING")
        #expect(sdk == 1 && tts == 0 && apple == 0)
    }

    @Test func textOnlySynthesisFailureFallsBackAfterReleaseWithoutRetryingTheProvider() async throws {
        let release = SpeechRouteGate()
        var tts = 0, apple = 0
        let speech = SpeechCoordinator(localSpeechOutput: { text, _ in
            #expect(text == "SYNTHETIC_TTS_FAILURE"); apple += 1
        })
        speech.cloudSpeech = { _, _ in tts += 1; throw MorningCloudVoiceError.unavailable }
        speech.externalSpeechFallback = { await release.value() }
        let reading = Task { try await speech.speakAndWait("SYNTHETIC_TTS_FAILURE") }
        await release.waitUntilCalled()
        #expect(apple == 0)
        release.release(); try await reading.value
        #expect(tts == 1 && apple == 1)
    }

    @Test func canceledTextOnlySynthesisNeverStartsEitherAudioOutput() async {
        let synthesis = SpeechRouteGate()
        var dataReads = 0, appleReads = 0, recoveries = 0
        let speech = SpeechCoordinator(localSpeechOutput: { _, _ in appleReads += 1 }, audioDataPlayback: { _ in dataReads += 1 })
        speech.cloudSpeech = { _, _ in await synthesis.value(); return Data([1]) }
        speech.externalSpeechFallback = { recoveries += 1 }
        let reading = Task { try await speech.speakAndWait("SYNTHETIC_CANCELED_TTS") }
        await synthesis.waitUntilCalled()
        speech.stop(); synthesis.release()
        await #expect(throws: CancellationError.self) { try await reading.value }
        for _ in 0..<10 { await Task.yield() }
        #expect(dataReads == 0 && appleReads == 0 && recoveries == 0)
    }

    @Test func asynchronousAudioFailureAlsoRecoversWithoutRepeatingSynthesis() async throws {
        let audio = SpeechRouteGate()
        var appleReads = 0, syntheses = 0, recoveries = 0
        let speech = SpeechCoordinator(localSpeechOutput: { _, _ in appleReads += 1 }, audioDataPlayback: { _ in
            await audio.value(); throw MorningCloudVoiceError.unavailable
        })
        speech.cloudSpeech = { _, _ in syntheses += 1; return Data([1]) }
        speech.externalSpeechFallback = { recoveries += 1 }
        let reading = Task { try await speech.speakAndWait("SYNTHETIC_AUDIO_FAILURE") }
        await audio.waitUntilCalled()
        #expect(appleReads == 0 && recoveries == 0)
        audio.release(); try await reading.value
        #expect(appleReads == 1 && recoveries == 1 && syntheses == 1)
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
