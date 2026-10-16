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
