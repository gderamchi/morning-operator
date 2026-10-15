import Foundation
import Testing
import MorningCore
@testable import MorningApple

@Suite("Explicit voice permission preparation") @MainActor
struct MorningVoiceAccessTests {
    typealias Snapshot = MorningVoiceAccessSnapshot

    @Test("Reading status never requests grants; preparation requests only missing grants in order")
    func explicitRequestsOnly() async throws {
        let fake = Permissions(.init(speech: .notDetermined, microphone: .undetermined, localRecognition: .available))
        let access = fake.access()
        #expect(!access.refresh(language: .french).isReady)
        #expect(fake.requests.isEmpty)
        let result = try await access.requestAccess(language: .french)
        #expect(result.isReady)
        #expect(fake.requests == ["speech", "microphone"])
        #expect(fake.languages.last == .french)
        _ = try await access.requestAccess(language: .french)
        _ = access.refresh(language: .french)
        #expect(fake.requests == ["speech", "microphone"], "Granted status and foreground refresh never repeat system prompts.")
    }

    @Test("Denied, restricted and unsupported access stays honest without requesting another grant")
    func deniedAndUnsupported() async throws {
        for snapshot in [Snapshot(speech: .denied, microphone: .undetermined, localRecognition: .available),
                         .init(speech: .restricted, microphone: .undetermined, localRecognition: .available),
                         .init(speech: .authorized, microphone: .denied, localRecognition: .available),
                         .init(speech: .notDetermined, microphone: .undetermined, localRecognition: .unsupported)] {
            let fake = Permissions(snapshot), access = fake.access()
            let result = try await access.requestAccess(language: .english)
            #expect(result == snapshot)
            #expect(!result.isReady)
            #expect(fake.requests.isEmpty)
            #expect(!result.description(french: true).isEmpty)
        }
    }

    @Test("A speech denial does not unnecessarily request the microphone")
    func denialStopsSequence() async throws {
        let fake = Permissions(.init(speech: .notDetermined, microphone: .undetermined, localRecognition: .available))
        fake.speechResult = .denied
        let access = fake.access(), result = try await access.requestAccess(language: .french)
        #expect(result.speech == .denied && result.microphone == .undetermined)
        #expect(fake.requests == ["speech"])
    }

    @Test("Already prepared grants are skipped and a microphone denial is not treated as ready")
    func missingGrantOnly() async throws {
        let speechOnly = Permissions(.init(speech: .notDetermined, microphone: .granted, localRecognition: .available))
        let preparedSpeech = try await speechOnly.access().requestAccess(language: .french)
        #expect(preparedSpeech.isReady && speechOnly.requests == ["speech"])
        let microphoneOnly = Permissions(.init(speech: .authorized, microphone: .undetermined, localRecognition: .available))
        microphoneOnly.microphoneResult = .denied
        let denied = try await microphoneOnly.access().requestAccess(language: .english)
        #expect(!denied.isReady && denied.canOpenSettings && !denied.canRequest)
        #expect(microphoneOnly.requests == ["microphone"])
    }

    @Test("Local capability is checked after speech permission; unsupported does not request a microphone")
    func permissionBeforeCapability() async throws {
        var authorized = false
        var requests: [String] = []
        let access = MorningVoiceAccess(probe: { _ in
            .init(speech: authorized ? .authorized : .notDetermined, microphone: .undetermined,
                  localRecognition: authorized ? .unsupported : .notChecked)
        }, speechRequest: { requests.append("speech"); authorized = true }, microphoneRequest: { requests.append("microphone") })
        #expect(access.snapshot.localRecognition == .notChecked && access.snapshot.canRequest)
        #expect(requests.isEmpty)
        let result = try await access.requestAccess(language: .french)
        #expect(result.localRecognition == .unsupported && !result.isReady)
        #expect(requests == ["speech"])
        #expect(result.microphone == .undetermined)
    }

    @Test("A cancelled screen ignores the late grant and never opens the next dialog")
    func cancelledLateGrant() async throws {
        var snapshot = Snapshot(speech: .notDetermined, microphone: .undetermined, localRecognition: .available)
        var completion: CheckedContinuation<Void, Never>?
        var microphoneRequests = 0
        let access = MorningVoiceAccess(probe: { _ in snapshot }, speechRequest: {
            await withCheckedContinuation { completion = $0 }
            snapshot = .init(speech: .authorized, microphone: .undetermined, localRecognition: .available)
        }, microphoneRequest: { microphoneRequests += 1 })
        let request = Task { try await access.requestAccess(language: .english) }
        while completion == nil { await Task.yield() }
        access.cancel()
        #expect(access.isRequesting, "The uncancellable system dialog remains owned until its callback.")
        do { _ = try await access.requestAccess(language: .english); Issue.record("An overlapping permission request was accepted.") }
        catch is CancellationError { }
        completion?.resume()
        do { _ = try await request.value; Issue.record("A late grant restored a cancelled preparation.") }
        catch is CancellationError { }
        #expect(microphoneRequests == 0 && !access.isRequesting)
        #expect(access.snapshot.speech == .notDetermined, "A cancelled result is not published as prepared.")
        #expect(access.refresh(language: .english).speech == .authorized, "A deliberate later refresh reads the actual system state.")
    }

    @Test("Temporary recognizer loss and language changes do not fabricate readiness")
    func availabilityAndLanguage() async throws {
        let access = MorningVoiceAccess(probe: { language in
            .init(speech: .authorized, microphone: .granted,
                  localRecognition: language == .french ? .available : .temporarilyUnavailable)
        }, speechRequest: { Issue.record("Unexpected speech request") }, microphoneRequest: { Issue.record("Unexpected microphone request") })
        #expect(access.refresh(language: .french).isReady)
        let unavailable = try await access.requestAccess(language: .english)
        #expect(!unavailable.isReady && !unavailable.canRequest)
        #expect(unavailable.description(french: false).contains("temporarily unavailable"))
        #expect(access.refresh(language: .french).isReady)
    }

    @MainActor private final class Permissions {
        var snapshot: Snapshot
        var speechResult = Snapshot.Speech.authorized
        var microphoneResult = Snapshot.Microphone.granted
        var requests: [String] = []
        var languages: [MorningVoiceCommandLanguage] = []
        init(_ snapshot: Snapshot) { self.snapshot = snapshot }
        func access() -> MorningVoiceAccess {
            MorningVoiceAccess(probe: { language in self.languages.append(language); return self.snapshot }, speechRequest: {
                self.requests.append("speech")
                self.snapshot = .init(speech: self.speechResult, microphone: self.snapshot.microphone, localRecognition: self.snapshot.localRecognition)
            }, microphoneRequest: {
                self.requests.append("microphone")
                self.snapshot = .init(speech: self.snapshot.speech, microphone: self.microphoneResult, localRecognition: self.snapshot.localRecognition)
            })
        }
    }
}
