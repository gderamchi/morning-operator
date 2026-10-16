import Foundation
import Testing
@testable import MorningApple

@Suite("Online account boundary — injected HTTP transport, no provider calls")
@MainActor
struct ComposioServiceTests {
    private let baseURL = URL(string: "https://connections.example.invalid")!
    private let token = "synthetic-installation-token"

    @Test func constructionIsOfflineAndMissingConfigurationStaysUnavailable() async throws {
        var calls = 0
        let service = ComposioService(baseURL: nil, tokenStore: MemoryTokenStore(), executionStore: MemoryTokenStore()) { request in
            calls += 1; return reply(request, #"{}"#)
        }
        #expect(!service.isConfigured && calls == 0)
        await #expect(throws: ComposioServiceError.notConfigured) { try await service.services() }
        #expect(calls == 0)
    }

    @Test func supportCodeIdentifiesOnlyTheExistingTokenWithoutNetworking() throws {
        var calls = 0
        let store = MemoryTokenStore(token: token)
        let service = ComposioService(baseURL: baseURL, tokenStore: store, executionStore: MemoryTokenStore()) { request in
            calls += 1; return reply(request, #"{}"#)
        }
        let code = try #require(try service.existingInstallationSupportCode())
        #expect(code == "52537b5bfd28338f7c9c934a")
        #expect(code.count == 24 && code.allSatisfy { $0.isHexDigit })
        #expect(try service.existingInstallationSupportCode() == code)
        #expect(code != token && store.token == token && store.saveCount == 0 && calls == 0)
    }

    @Test func missingSupportTokenDoesNotEnrollAnInstallation() throws {
        var calls = 0
        let store = MemoryTokenStore()
        let service = ComposioService(baseURL: baseURL, tokenStore: store, executionStore: MemoryTokenStore()) { request in
            calls += 1; return reply(request, #"{}"#)
        }
        #expect(try service.existingInstallationSupportCode() == nil)
        #expect(store.token == nil && store.saveCount == 0 && calls == 0)
    }

    @Test func supportCodeStorageErrorNeverExposesTheBearer() throws {
        var calls = 0
        let store = MemoryTokenStore(token: token)
        store.readError = NSError(domain: "Synthetic private credential", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: token])
        let service = ComposioService(baseURL: baseURL, tokenStore: store, executionStore: MemoryTokenStore()) { request in
            calls += 1; return reply(request, #"{}"#)
        }
        do {
            _ = try service.existingInstallationSupportCode()
            Issue.record("A failed secure-store read must not produce a support code.")
        } catch {
            #expect(error as? ComposioServiceError == .credentialsUnavailable)
            #expect(!error.localizedDescription.contains(token))
        }
        #expect(store.saveCount == 0 && calls == 0)
    }

    @Test func installationIsAnonymousThenRequestsUseOnlyPerInstallationBearer() async throws {
        var requests: [URLRequest] = []
        let store = MemoryTokenStore()
        let service = ComposioService(baseURL: baseURL, tokenStore: store, executionStore: MemoryTokenStore()) { request in
            requests.append(request)
            if request.url?.path == "/v1/installations" { return reply(request, #"{"token":"synthetic-installation-token"}"#) }
            if request.url?.path == "/v1/services" { return reply(request, #"{"services":[{"id":"gmail","name":"Gmail"}]}"#) }
            return reply(request, #"{"connections":[{"id":"ca_fixture","service":"gmail","name":"Gmail","status":"ACTIVE","accountLabel":"Synthetic account"}]}"#)
        }
        #expect(requests.isEmpty)
        let services = try await service.services()
        let accounts = try await service.connections()
        #expect(services.first?.id == "gmail" && accounts.first?.isActive == true)
        #expect(requests.count == 3 && store.token == token)
        #expect(requests[0].httpMethod == "POST" && requests[0].value(forHTTPHeaderField: "Authorization") == nil)
        #expect(requests[0].value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(try body(requests[0]).isEmpty)
        #expect(requests.dropFirst().allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer " + token })
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "x-api-key") == nil && $0.timeoutInterval > 0 })
    }

    @Test func oauthLinkDoesNotMarkAccountActiveAndCompletionCarriesSessionWithBearer() async throws {
        var requests: [URLRequest] = []
        let service = ComposioService(baseURL: baseURL, tokenStore: MemoryTokenStore(token: token), executionStore: MemoryTokenStore()) { request in
            requests.append(request)
            if request.url?.path == "/v1/connections/complete" { return reply(request, #"{"id":"ca_fixture","service":"gmail","status":"ACTIVE"}"#) }
            return reply(request, #"{"authorizationURL":"https://connections.example.invalid/v1/oauth/start?ticket=fixture"}"#)
        }
        let authorization = try await service.startConnection(service: "gmail", callbackURL: URL(string: "more://composio/callback")!)
        #expect(authorization.authorizationURL.scheme == "https")
        let start = try body(requests[0])
        #expect(start["service"] == .string("gmail") && start["callbackURL"] == .string("more://composio/callback"))
        try await service.completeConnection(sessionURI: "fixture-session-uri")
        #expect(requests[1].httpMethod == "POST")
        #expect(try body(requests[1])["sessionURI"] == .string("fixture-session-uri"))
        #expect(requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer " + token)
        await #expect(throws: ComposioServiceError.invalidArguments) {
            try await service.startConnection(service: "gmail", callbackURL: URL(string: "other://composio/callback")!)
        }
        #expect(requests.count == 2)
    }

    @Test func toolsDisconnectAndExecutionMatchContractWithoutRetry() async throws {
        let requestID = UUID()
        var requests: [URLRequest] = []
        let service = ComposioService(baseURL: baseURL, tokenStore: MemoryTokenStore(token: token), executionStore: MemoryTokenStore()) { request in
            requests.append(request)
            switch request.url?.path {
            case "/v1/tools": return reply(request, #"{"tools":[{"slug":"GMAIL_LIST_MESSAGES","name":"Find mail","description":"Find matching messages","inputSchema":{"type":"object","properties":{"query":{"type":"string"}}}}]}"#)
            case "/v1/execute": return reply(request, "{\"requestID\":\"\(requestID.uuidString)\",\"successful\":true,\"data\":{\"count\":1}}")
            default: return reply(request, "", status: 204)
            }
        }
        let tools = try await service.tools(service: "gmail")
        #expect(tools.first?.slug == "GMAIL_LIST_MESSAGES")
        #expect(URLComponents(url: requests[0].url!, resolvingAgainstBaseURL: false)?.queryItems == [URLQueryItem(name: "service", value: "gmail")])
        let result = try await service.execute(tool: "GMAIL_LIST_MESSAGES", arguments: ["query": .string("fixture")], connectionID: "ca_fixture", requestID: requestID)
        #expect(result.successful && result.requestID == requestID)
        let execution = try body(requests[1])
        #expect(execution["arguments"] == .object(["query": .string("fixture")]))
        #expect(execution["connectionID"] == .string("ca_fixture") && execution["requestID"] == .string(requestID.uuidString))
        #expect(requests[1].timeoutInterval == 60)
        try await service.disconnect(connectionID: "ca_fixture")
        #expect(requests[2].httpMethod == "DELETE" && requests[2].url?.path == "/v1/connections/ca_fixture")
        #expect(requests.count == 3)
    }

    @Test(arguments: ["timeout", "malformed", "wrongID", "uncertain", "pending", "mismatch", "unknown", "server"])
    func uncertainExecutionCannotBecomeSuccessOrAutomaticRetry(_ failure: String) async throws {
        let requestID = UUID()
        var calls = 0
        let service = ComposioService(baseURL: baseURL, tokenStore: MemoryTokenStore(token: token), executionStore: MemoryTokenStore()) { request in
            calls += 1
            switch failure {
            case "timeout": throw URLError(.timedOut)
            case "malformed": return reply(request, #"{"successful":true}"#)
            case "wrongID": return reply(request, "{\"requestID\":\"\(UUID().uuidString)\",\"successful\":true}")
            case "uncertain": return reply(request, #"{"error":{"code":"execution_uncertain","message":"Check the account"}}"#, status: 409)
            case "pending": return reply(request, #"{"error":{"code":"execution_pending","message":"Check the account"}}"#, status: 409)
            case "mismatch": return reply(request, #"{"error":{"code":"request_mismatch","message":"Check the account"}}"#, status: 409)
            case "unknown": return reply(request, #"{"error":{"code":"new_error","message":"Unknown state"}}"#, status: 400)
            default: return reply(request, #"{"error":{"code":"internal","message":"Unavailable"}}"#, status: 503)
            }
        }
        await #expect(throws: ComposioServiceError.executionUncertain(requestID)) {
            try await service.execute(tool: "GMAIL_SEND_EMAIL", arguments: [:], connectionID: "ca_fixture", requestID: requestID)
        }
        #expect(calls == 1)
    }

    @Test func deniedAndRejectedRequestsRemainFailures() async throws {
        let unauthorized = ComposioService(baseURL: baseURL, tokenStore: MemoryTokenStore(token: token), executionStore: MemoryTokenStore()) { request in
            reply(request, #"{"error":{"code":"unauthorized","message":"No access"}}"#, status: 401)
        }
        await #expect(throws: ComposioServiceError.notAuthorized) { try await unauthorized.connections() }
        let rejected = ComposioService(baseURL: baseURL, tokenStore: MemoryTokenStore(token: token), executionStore: MemoryTokenStore()) { request in
            reply(request, #"{"error":{"code":"invalid_arguments","message":"Missing recipient"}}"#, status: 400)
        }
        await #expect(throws: ComposioServiceError.backend(ComposioFailure(code: "invalid_arguments", message: "Missing recipient"))) {
            try await rejected.execute(tool: "GMAIL_SEND_EMAIL", arguments: [:], connectionID: "ca_fixture")
        }
    }

    @Test func unresolvedIntentBlocksNewUUIDAcrossRecreationUntilExplicitReconciliation() async throws {
        let requestID = UUID()
        let installation = MemoryTokenStore(token: token)
        let ledger = MemoryTokenStore()
        var calls = 0
        let first = ComposioService(baseURL: baseURL, tokenStore: installation, executionStore: ledger) { request in
            calls += 1; throw URLError(.timedOut)
        }
        await #expect(throws: ComposioServiceError.executionUncertain(requestID)) {
            try await first.execute(tool: "GMAIL_SEND_EMAIL", arguments: ["body": .string("PRIVATE_FIXTURE_CONTENT")], connectionID: "ca_fixture", requestID: requestID)
        }
        #expect(ledger.token?.contains("PRIVATE_FIXTURE_CONTENT") == false)
        let newID = UUID()
        let recreated = ComposioService(baseURL: baseURL, tokenStore: installation, executionStore: ledger) { request in
            calls += 1
            return reply(request, "{\"requestID\":\"\(newID.uuidString)\",\"successful\":true,\"data\":{\"status\":\"queued\"}}")
        }
        await #expect(throws: ComposioServiceError.executionUncertain(requestID)) {
            try await recreated.execute(tool: "GMAIL_SEND_EMAIL", arguments: ["body": .string("PRIVATE_FIXTURE_CONTENT")], connectionID: "ca_fixture", requestID: newID)
        }
        #expect(calls == 1)
        try recreated.reconcileExecution(requestID: requestID)
        let receipt = try await recreated.execute(tool: "GMAIL_SEND_EMAIL", arguments: ["body": .string("PRIVATE_FIXTURE_CONTENT")], connectionID: "ca_fixture", requestID: newID)
        #expect(receipt.successful && calls == 2)
    }

    @Test func clearRejectsLateInstallationAndDoesNotRestoreToken() async throws {
        let gate = ComposioHTTPGate()
        let store = MemoryTokenStore()
        let service = ComposioService(baseURL: baseURL, tokenStore: store, executionStore: MemoryTokenStore()) { request in
            await gate.pause()
            return reply(request, #"{"token":"synthetic-installation-token"}"#)
        }
        let pending = Task { try await service.services() }
        await gate.waitUntilPaused()
        try service.clearLocalCredentials()
        gate.resume()
        await #expect(throws: CancellationError.self) { try await pending.value }
        #expect(store.token == nil && store.clearCount == 1)
    }

    @Test func unsafeEndpointsAndPathInjectionNeverContactTransport() async throws {
        var calls = 0
        let unsafe = ComposioService(baseURL: URL(string: "http://remote.example.invalid")!, tokenStore: MemoryTokenStore(token: token), executionStore: MemoryTokenStore()) { request in
            calls += 1; return reply(request, #"{}"#)
        }
        await #expect(throws: ComposioServiceError.insecureURL) { try await unsafe.connections() }
        let service = ComposioService(baseURL: baseURL, tokenStore: MemoryTokenStore(token: token), executionStore: MemoryTokenStore()) { request in
            calls += 1; return reply(request, #"{}"#)
        }
        await #expect(throws: ComposioServiceError.invalidArguments) { try await service.disconnect(connectionID: "../other") }
        await #expect(throws: ComposioServiceError.invalidArguments) { try await service.disconnect(connectionID: "..") }
        #expect(calls == 0)
    }

    @Test func parametersRequireObjectAndPreserveDecimalNumbers() throws {
        #expect(throws: ComposioServiceError.invalidArguments) { try ComposioJSONValue.parseObject("[1,2]") }
        #expect(throws: ComposioServiceError.invalidArguments) { try ComposioJSONValue.parseObject("bad") }
        let json = #"{"recipient":"fixture","count":9007199254740993,"send":false,"nested":{"a":[null,1.25]}}"#
        let value = try ComposioJSONValue.parseObject(json)
        let roundTrip = try ComposioJSONValue.object(value).prettyPrintedJSON()
        #expect(roundTrip.contains("9007199254740993"))
        #expect(try ComposioJSONValue.parseObject(roundTrip) == value)
    }

    private func body(_ request: URLRequest) throws -> [String: ComposioJSONValue] {
        try ComposioJSONValue.parseObject(String(decoding: request.httpBody ?? Data(), as: UTF8.self))
    }
    private func reply(_ request: URLRequest, _ text: String, status: Int = 200) -> (Data, HTTPURLResponse) {
        (Data(text.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
    }
}

@MainActor
private final class MemoryTokenStore: ComposioTokenStoring {
    var token: String?
    var clearCount = 0
    var saveCount = 0
    var readError: (any Error)?
    init(token: String? = nil) { self.token = token }
    func load() throws -> String? {
        if let readError { throw readError }
        return token
    }
    func save(_ token: String) throws { self.token = token; saveCount += 1 }
    func clear() throws { token = nil; clearCount += 1 }
}

@MainActor
private final class ComposioHTTPGate {
    private var continuation: CheckedContinuation<Void, Never>?
    func pause() async { await withCheckedContinuation { continuation = $0 } }
    func waitUntilPaused() async { while continuation == nil { await Task.yield() } }
    func resume() { continuation?.resume(); continuation = nil }
}
