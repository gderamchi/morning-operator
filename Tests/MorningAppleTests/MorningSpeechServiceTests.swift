import Foundation
import Testing
@testable import MorningApple

@Suite("Online speech boundary — synthetic HTTP, no provider or microphone")
@MainActor
struct MorningSpeechServiceTests {
    private let baseURL = URL(string: "https://speech.example.invalid")!
    private let mp3 = Data([0x49, 0x44, 0x33, 4, 0, 0])

    @Test func sendsOnlySelectedTextLanguageAndGenderWithInstallationBearer() async throws {
        var requests: [URLRequest] = []
        let service = ComposioService(baseURL: baseURL, tokenStore: SpeechTokenStore(), executionStore: SpeechTokenStore()) { request in
            requests.append(request)
            return (mp3, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "audio/mpeg"])!)
        }
        for language in ["fr", "en"] {
            for gender in MorningVoiceGender.allCases {
                #expect(try await service.morningSpeech("Synthetic selected text.", language: language, voiceGender: gender) == mp3)
                let request = try #require(requests.last)
                let body = try JSONDecoder().decode([String: String].self, from: #require(request.httpBody))
                #expect(body == ["text": "Synthetic selected text.", "language": language, "voiceGender": gender.rawValue])
                #expect(request.url?.path == "/v1/voice/speech" && request.httpMethod == "POST")
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-installation-token")
                #expect(request.value(forHTTPHeaderField: "Accept") == "audio/mpeg")
                #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
                #expect(request.value(forHTTPHeaderField: "xi-api-key") == nil)
                #expect(request.timeoutInterval == 25)
            }
        }
        #expect(requests.count == 4)
    }

    @Test func rejectsInvalidTextAndLanguageBeforeDispatch() async throws {
        var calls = 0
        let service = ComposioService(baseURL: baseURL, tokenStore: SpeechTokenStore(), executionStore: SpeechTokenStore()) { _ in
            calls += 1; throw URLError(.badServerResponse)
        }
        for (text, language) in [("", "fr"), (" \n", "fr"), ("\u{0}", "en"), (String(repeating: "é", count: 16_385), "fr"), ("Synthetic", "de")] {
            await #expect(throws: ComposioServiceError.invalidArguments) {
                try await service.morningSpeech(text, language: language, voiceGender: .female)
            }
        }
        #expect(calls == 0)
    }

    @Test func refusesInvalidAudioAndNeverRetries() async throws {
        for (data, mime) in [(Data(), "audio/mpeg"), (Data("private-provider-json".utf8), "audio/mpeg"), (mp3, "application/json"), (Data(repeating: 0, count: 8_388_609), "audio/mpeg")] {
            var calls = 0
            let service = ComposioService(baseURL: baseURL, tokenStore: SpeechTokenStore(), executionStore: SpeechTokenStore()) { request in
                calls += 1
                return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": mime])!)
            }
            await #expect(throws: ComposioServiceError.invalidResponse) {
                try await service.morningSpeech("Synthetic.", language: "en", voiceGender: .male)
            }
            #expect(calls == 1)
        }
    }

    @Test func preservesSanitizedActivationFailureWithoutRetry() async throws {
        var calls = 0
        let service = ComposioService(baseURL: baseURL, tokenStore: SpeechTokenStore(), executionStore: SpeechTokenStore()) { request in
            calls += 1
            let data = Data(#"{"error":{"code":"voice_not_configured","message":"Online speech is unavailable."}}"#.utf8)
            return (data, HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        }
        do {
            _ = try await service.morningSpeech("Synthetic.", language: "fr", voiceGender: .female)
            Issue.record("Expected activation failure")
        } catch ComposioServiceError.backend(let failure) {
            #expect(failure.code == "voice_not_configured")
        }
        #expect(calls == 1)
    }

    @Test func credentialWithdrawalRejectsLateAudioEvenWhenTransportIgnoresCancellation() async throws {
        let gate = SpeechResponseGate()
        let store = SpeechTokenStore()
        let service = ComposioService(baseURL: baseURL, tokenStore: store, executionStore: SpeechTokenStore()) { request in
            await gate.pause()
            return (mp3, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "audio/mpeg"])!)
        }
        let pending = Task { try await service.morningSpeech("Synthetic.", language: "fr", voiceGender: .female) }
        await gate.waitUntilPaused()
        try service.clearLocalCredentials()
        gate.resume()
        await #expect(throws: CancellationError.self) { try await pending.value }
        #expect(store.token == nil)
    }
}

@MainActor
private final class SpeechTokenStore: ComposioTokenStoring {
    var token: String? = "synthetic-installation-token"
    func load() throws -> String? { token }
    func save(_ token: String) throws { self.token = token }
    func clear() throws { token = nil }
}

@MainActor
private final class SpeechResponseGate {
    private var continuation: CheckedContinuation<Void, Never>?
    func pause() async { await withCheckedContinuation { continuation = $0 } }
    func waitUntilPaused() async { while continuation == nil { await Task.yield() } }
    func resume() { continuation?.resume(); continuation = nil }
}
