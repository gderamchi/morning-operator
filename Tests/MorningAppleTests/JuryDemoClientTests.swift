import Foundation
import Testing
@testable import MorningApple
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@Suite("Isolated jury demo transport")
struct JuryDemoClientTests {
    @Test("Local HTTP is limited to the development LAN and credentials never enter URLs")
    func configurationBoundary() throws {
        for url in ["https://more.company.fr", "http://localhost:8788", "http://127.0.0.1:8788",
                    "http://192.168.1.3:8788", "http://10.0.0.5", "http://172.16.2.3", "http://mac.local:8788"] {
            _ = try JuryDemoConfiguration(baseURL: #require(URL(string: url)), token: "local-secret")
        }
        for url in ["http://company.fr", "http://172.32.2.3", "ftp://localhost", "https://user:secret@company.fr",
                    "https://company.fr?token=secret", "https://company.fr#secret"] {
            #expect(throws: JuryDemoError.configuration) {
                try JuryDemoConfiguration(baseURL: #require(URL(string: url)), token: "local-secret")
            }
        }
        #expect(throws: JuryDemoError.configuration) {
            try JuryDemoConfiguration(baseURL: #require(URL(string: "https://company.fr")), token: "bad\nheader")
        }
    }

    @Test("The same authorized request identity reaches the server exactly once")
    func authorizedTurn() async throws {
        let probe = JuryDemoTransportProbe(body: Self.response)
        let client = try makeClient(probe)
        let requestID = UUID()
        let result = try await client.turn(sessionID: "known-session", requestID: requestID, text: "Oui, envoie.")
        #expect(result.stage == "mail")
        #expect(result.receipt?.status == "sent")
        let requests = await probe.requests
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/v1/jury/turn")
        #expect(request.url?.query == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer local-secret")
        let body = try JSONDecoder().decode([String: String].self, from: #require(request.httpBody))
        #expect(body == ["sessionID": "known-session", "requestID": requestID.uuidString, "text": "Oui, envoie."])
    }

    @Test("An uncertain external effect is never automatically retried")
    func noEffectRetry() async throws {
        let probe = JuryDemoTransportProbe(body: Data(), status: 502)
        let client = try makeClient(probe)
        await #expect(throws: JuryDemoError.serviceUnavailable) {
            try await client.turn(sessionID: "known-session", requestID: UUID(), text: "Envoie.")
        }
        #expect(await probe.requests.count == 1)
    }

    @Test("An oversized instruction is rejected whole rather than truncated into an authorization")
    func oversizedTurn() async throws {
        let probe = JuryDemoTransportProbe(body: Self.response)
        let client = try makeClient(probe)
        await #expect(throws: JuryDemoError.invalidResponse) {
            try await client.turn(sessionID: "known-session", requestID: UUID(), text: String(repeating: "a", count: 4_001))
        }
        #expect(await probe.requests.isEmpty)
    }

    @Test("A response from another session cannot advance the current morning")
    func rejectsWrongSession() async throws {
        let probe = JuryDemoTransportProbe(body: Self.response)
        let client = try makeClient(probe)
        await #expect(throws: JuryDemoError.invalidResponse) {
            try await client.turn(sessionID: "different-session", requestID: UUID(), text: "Suivant.")
        }
    }

    @Test("An unrecognized stage cannot advance the client")
    func rejectsUnknownStage() async throws {
        let body = Data("{\"sessionID\":\"known-session\",\"stage\":\"unexpected\",\"text\":\"Bonjour\",\"completed\":false}".utf8)
        let client = try makeClient(JuryDemoTransportProbe(body: body))
        await #expect(throws: JuryDemoError.invalidResponse) { try await client.start() }
    }

    @Test("Missing voice audio fails explicitly and never substitutes native synthesis")
    func requiresAudio() async throws {
        let probe = JuryDemoTransportProbe(body: Self.response)
        let client = try makeClient(probe)
        await #expect(throws: JuryDemoError.speechUnavailable) { try await client.speech(text: "Bonjour.") }
        #expect(await probe.requests.count == 1)
    }

    @Test("Stop addresses only the current remote session")
    func deleteSession() async throws {
        let probe = JuryDemoTransportProbe(body: Data(), status: 204)
        let client = try makeClient(probe)
        try await client.stop(sessionID: "known-session")
        let request = try #require(await probe.requests.first)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path == "/v1/jury/session/known-session")
        #expect(request.httpBody == nil)
    }

    @Test("Reopening reconciles the exact retained session with a read-only request")
    func reconcileSession() async throws {
        let probe = JuryDemoTransportProbe(body: Self.response)
        let client = try makeClient(probe)
        let result = try await client.resume(sessionID: "known-session")
        #expect(result.receipt?.status == "sent")
        let request = try #require(await probe.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/v1/jury/session/known-session")
        #expect(request.httpBody == nil)
    }

    @Test("An expired retained session fails instead of creating another one")
    func expiredSession() async throws {
        let probe = JuryDemoTransportProbe(body: Data(), status: 404)
        let client = try makeClient(probe)
        await #expect(throws: JuryDemoError.sessionUnavailable) { try await client.resume(sessionID: "expired-session") }
        let requests = await probe.requests
        #expect(requests.count == 1)
        #expect(requests.first?.httpMethod == "GET")
    }

    @Test("Native reminder intent is typed and cannot be confirmed without a real receipt")
    func nativeReminderContract() async throws {
        let requestID = UUID().uuidString
        let body = Data("""
            {"sessionID":"known-session","stage":"mail","text":"Je prépare votre rappel.","completed":false,
            "action":{"type":"createReminder","requestID":"\(requestID)","title":"Point produit","minutesBefore":20,"meetingHour":15,"meetingMinute":0}}
            """.utf8)
        let probe = JuryDemoTransportProbe(body: body)
        let client = try makeClient(probe)
        let response = try await client.start()
        #expect(response.action?.url == nil)
        #expect(response.action?.requestID == requestID)
        #expect(response.action?.meetingHour == 15)
        await #expect(throws: JuryDemoError.invalidResponse) {
            try await client.actionResult(sessionID: "known-session", requestID: requestID, status: "confirmed")
        }
        #expect(await probe.requests.count == 1)
    }

    @Test("A verified native result is acknowledged once without executing another effect")
    func nativeReminderAcknowledgement() async throws {
        let probe = JuryDemoTransportProbe(body: Self.response)
        let client = try makeClient(probe)
        let requestID = UUID().uuidString
        _ = try await client.actionResult(sessionID: "known-session", requestID: requestID, status: "confirmed", receiptID: "eventkit-verified-id")
        let requests = await probe.requests
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.url?.path == "/v1/jury/action-result")
        let body = try JSONDecoder().decode([String: String].self, from: #require(request.httpBody))
        #expect(body == ["sessionID": "known-session", "requestID": requestID, "status": "confirmed", "receiptID": "eventkit-verified-id"])
    }

    @Test("Captions stay short even for a long word and preserve every non-whitespace character")
    func shortCaptions() {
        let text = "Votre rendez-vous est confirmé. " + String(repeating: "a", count: 380) + " À tout à l’heure !"
        let passages = JuryDemoCaptionTiming.passages(text)
        #expect(passages.count >= 4)
        #expect(passages.allSatisfy { !$0.isEmpty && $0.count <= 150 })
        #expect(passages.joined().filter { !$0.isWhitespace } == text.filter { !$0.isWhitespace })
    }

    @Test("Only a backend ID is restored and an explicit stop forgets it")
    @MainActor func retainedSession() throws {
        let suiteName = "JuryDemoClientTests-\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: suiteName))
        defer { preferences.removePersistentDomain(forName: suiteName) }
        let configuration = try JuryDemoConfiguration(baseURL: #require(URL(string: "http://127.0.0.1:8788")), token: "local-secret")
        let key = "MorningJuryDemoSession:\(Bundle.main.bundleIdentifier ?? "MORE"):\(configuration.baseURL.absoluteString)"
        preferences.set("known-session", forKey: key)
        let client = try makeClient(JuryDemoTransportProbe(body: Data(), status: 204))
        let session = JuryDemoVoiceSession(configuration: configuration, preferences: preferences, client: client)
        #expect(session.sessionID == "known-session")
        #expect(session.transcript.isEmpty)
        session.stop()
        #expect(preferences.string(forKey: key) == nil)
    }

    @Test("Voice failure retains reconciliation and a stopped backend never completes the routine")
    @MainActor func failedAndStoppedLifecycle() async throws {
        let suiteName = "JuryDemoClientTests-\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: suiteName))
        defer { preferences.removePersistentDomain(forName: suiteName) }
        let configuration = try JuryDemoConfiguration(baseURL: #require(URL(string: "http://127.0.0.1:8788")), token: "local-secret")
        let key = "MorningJuryDemoSession:\(Bundle.main.bundleIdentifier ?? "MORE"):\(configuration.baseURL.absoluteString)"
        preferences.set("known-session", forKey: key)
        let probe = JuryDemoTransportProbe(body: Data(), status: 204)
        let session = JuryDemoVoiceSession(configuration: configuration, preferences: preferences, client: try makeClient(probe))
        var completed = false
        session.onCompleted = { completed = true }
        session.fail(JuryDemoError.speechUnavailable)
        await Task.yield()
        #expect(session.state == .failed)
        #expect(session.sessionID == "known-session")
        #expect(await probe.requests.isEmpty)
        let stopped = try JSONDecoder().decode(JuryDemoResponse.self, from: Data("""
            {"sessionID":"known-session","stage":"stopped","text":"Votre matin est arrêté.","completed":true}
            """.utf8)).validated()
        session.receiveStoppedSession(stopped)
        #expect(session.state == .idle)
        #expect(!completed)
        #expect(session.sessionID == "known-session")
        #expect(preferences.string(forKey: key) == "known-session")
    }

    @Test("Startup failure and stop synchronize the existing session controls exactly once")
    @MainActor func stateCallbacks() {
        let session = JuryDemoVoiceSession(configuration: nil)
        var changes: [JuryDemoVoiceState] = []
        session.onStateChange = { changes.append($0) }
        session.start()
        #expect(session.state == .failed)
        #expect(!session.isActive)
        session.stop(); session.stop()
        #expect(changes == [.failed, .idle])
    }

    private func makeClient(_ probe: JuryDemoTransportProbe) throws -> JuryDemoClient {
        let configuration = try JuryDemoConfiguration(baseURL: #require(URL(string: "http://127.0.0.1:8788")), token: "local-secret")
        return JuryDemoClient(configuration: configuration, transport: { try await probe.load($0) })
    }

    private static let response = Data("""
        {"sessionID":"known-session","stage":"mail","text":"Le message est envoyé.","completed":false,
        "receipt":{"type":"email","id":"provider-message-id","status":"sent"}}
        """.utf8)
}

private actor JuryDemoTransportProbe {
    var requests: [URLRequest] = []
    let body: Data
    let status: Int
    init(body: Data, status: Int = 200) { self.body = body; self.status = status }
    func load(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        return (body, try #require(HTTPURLResponse(url: #require(request.url), statusCode: status,
                                                  httpVersion: nil, headerFields: ["Content-Type": "application/json"])))
    }
}
