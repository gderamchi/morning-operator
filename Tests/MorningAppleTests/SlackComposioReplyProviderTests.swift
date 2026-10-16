import Foundation
import MorningCore
import Testing
@testable import MorningApple

@Suite("Slack dedicated server contract — injected HTTP only") @MainActor
struct SlackComposioReplyProviderTests {
    @Test func credentialsFailureAndCancellationBeforePostReleaseOnlyTheirOwnClaim() async throws {
        for cancelBeforePost in [false, true] {
            let fixture = try Fixture(), directory = FileManager.default.temporaryDirectory.appendingPathComponent("SlackPreflight-SYNTHETIC-\(UUID())")
            defer { try? FileManager.default.removeItem(at: directory) }
            var posts = 0, release: CheckedContinuation<Void, Never>?
            let tokens = Tokens(); tokens.failLoad = !cancelBeforePost
            let service = ComposioService(baseURL: URL(string: "https://synthetic.example.invalid")!, tokenStore: tokens, executionStore: Tokens(nil)) { request in
                posts += 1; return response(request, [:])
            }
            let identity = try SlackReplyIdentity(connectionID: "ca_synthetic", revision: String(repeating: "a", count: 64), teamID: "T12345678", userID: "U12345678", teamName: "Actual workspace", userName: "owner")
            let provider = ClientProvider(service: service, destination: try .init(identity: identity, channelID: fixture.channel, channelName: "morning"))
            if cancelBeforePost { provider.beforeSend = { await withCheckedContinuation { release = $0 } } }
            let conversation = SlackThreadReplyConversation(provider: provider, drafts: SlackReplyDraftService(generator: { _ in "Exact body" }),
                directory: directory, now: { fixture.time }, speak: { _ in })
            await conversation.prepare(intention: "Reply", source: fixture.source, context: fixture.source.executionID)
            let send = Task { await conversation.respond("send it", context: fixture.source.executionID) }
            if cancelBeforePost {
                for _ in 0..<200 where release == nil { await Task.yield() }
                let continuation = try #require(release)
                conversation.cancel(); continuation.resume()
            }
            _ = await send.value
            let entries = try AtomicJSONFile<[SlackReplyJournal.Entry]>(url: directory.appendingPathComponent("slack-reply-journal.json"), maximumBytes: 262_144).load()
            #expect(posts == 0 && entries.isEmpty && conversation.phase == .reviewing && !conversation.canConfirm)
        }
    }

    @Test func cancellationAfterPostKeepsPendingClaimEvenWhenCallbackArrives() async throws {
        let fixture = try Fixture(), directory = FileManager.default.temporaryDirectory.appendingPathComponent("SlackPost-SYNTHETIC-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        var posts = 0, release: CheckedContinuation<Void, Never>?
        let service = ComposioService(baseURL: URL(string: "https://synthetic.example.invalid")!, tokenStore: Tokens(), executionStore: Tokens(nil)) { request in
            posts += 1; await withCheckedContinuation { release = $0 }
            throw URLError(.timedOut)
        }
        let identity = try SlackReplyIdentity(connectionID: "ca_synthetic", revision: String(repeating: "a", count: 64), teamID: "T12345678", userID: "U12345678", teamName: "Actual workspace", userName: "owner")
        let provider = ClientProvider(service: service, destination: try .init(identity: identity, channelID: fixture.channel, channelName: "morning"))
        let conversation = SlackThreadReplyConversation(provider: provider, drafts: SlackReplyDraftService(generator: { _ in "Exact body" }),
            directory: directory, now: { fixture.time }, speak: { _ in })
        await conversation.prepare(intention: "Reply", source: fixture.source, context: fixture.source.executionID)
        let send = Task { await conversation.respond("send it", context: fixture.source.executionID) }
        for _ in 0..<200 where release == nil { await Task.yield() }
        let continuation = try #require(release)
        conversation.cancel(); continuation.resume(); _ = await send.value
        let entries = try AtomicJSONFile<[SlackReplyJournal.Entry]>(url: directory.appendingPathComponent("slack-reply-journal.json"), maximumBytes: 262_144).load()
        #expect(posts == 1 && entries.count == 1 && entries[0].receipt == nil && conversation.phase == .uncertain)
    }

    @Test func boundedReadRetryDoesNotCreateOrReleaseAnEffectReservation() async throws {
        var calls = 0
        let ledger = Tokens(nil)
        let service = ComposioService(baseURL: URL(string: "https://synthetic.example.invalid")!, tokenStore: Tokens(), executionStore: ledger) { request in
            calls += 1
            if calls == 1 { throw URLError(.timedOut) }
            let input = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            return response(request, ["requestID": input["requestID"]!, "successful": true, "data": ["ok": true, "channels": []]])
        }
        let args: [String: ComposioJSONValue] = ["limit": .number(50), "types": .string("public_channel,private_channel"), "exclude_archived": .bool(true)]
        await #expect(throws: (any Error).self) { try await service.readSlack(tool: "SLACK_LIST_ALL_CHANNELS", arguments: args, connectionID: "ca_synthetic") }
        let result = try await service.readSlack(tool: "SLACK_LIST_ALL_CHANNELS", arguments: args, connectionID: "ca_synthetic")
        #expect(result.successful && calls == 2 && ledger.value == nil)
        await #expect(throws: ComposioServiceError.invalidArguments) { try await service.readSlack(tool: "SLACK_SEND_MESSAGE", arguments: [:], connectionID: "ca_synthetic") }
        await #expect(throws: ComposioServiceError.invalidArguments) { try await service.readSlack(tool: "SLACK_LIST_ALL_CHANNELS", arguments: args.merging(["team_id": .string("T99999999")]) { _, new in new }, connectionID: "ca_synthetic") }
        #expect(calls == 2)
    }

    @Test func namedDestinationAndSendUseBoundServerIdentityWithoutGenericWriteFallback() async throws {
        let fixture = try Fixture()
        var requests: [URLRequest] = []
        let service = ComposioService(baseURL: URL(string: "https://synthetic.example.invalid")!, tokenStore: Tokens(), executionStore: Tokens(nil)) { request in
            requests.append(request)
            if request.url?.path == "/v1/slack/reply-identity" { return response(request, fixture.identityJSON) }
            if request.url?.path == "/v1/connections" { return response(request, ["connections": [["id": "ca_synthetic", "service": "slack", "name": "Slack", "status": "ACTIVE"]]]) }
            let input = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as! [String: Any]
            if request.url?.path == "/v1/execute" {
                let tool = input["tool"] as? String
                let payload: [String: Any] = tool == "SLACK_RETRIEVE_CONVERSATION_INFORMATION"
                    ? ["ok": true, "channel": ["id": fixture.channel, "name": "morning", "is_archived": false, "is_member": true]]
                    : ["ok": true, "messages": [["type": "message", "ts": fixture.parent, "user": "U33333333", "text": "Source text"]]]
                return response(request, ["requestID": input["requestID"]!, "successful": true, "data": ["successful": true, "data": payload]])
            }
            #expect(request.url?.path == "/v1/slack/replies")
            #expect(input["tool"] == nil && input["blocks"] == nil)
            #expect(input["channelID"] as? String == fixture.channel && input["threadTS"] as? String == fixture.parent)
            let identity = try #require(input["expectedIdentity"] as? [String: String])
            #expect(identity["revision"] == String(repeating: "a", count: 64) && identity["teamID"] == "T12345678" && identity["userID"] == "U12345678")
            let id = try #require(input["requestID"] as? String)
            return response(request, ["requestID": id, "successful": true, "data": ["successful": true, "data": ["ok": true,
                "channel": fixture.channel, "ts": "1800000001.000002", "message": ["ts": "1800000001.000002", "user": "U12345678", "thread_ts": fixture.parent,
                    "blocks": [["type": "section", "block_id": "more-reply-v1-" + id.lowercased(), "text": ["type": "plain_text", "text": input["body"]!]]]]]]])
        }
        let provider = SlackComposioReplyProvider(service: service, now: { fixture.time })
        let destination = try await provider.destination(for: fixture.source)
        #expect(destination.channelName == "morning" && destination.teamName == "Actual workspace")
        let prepared = try SlackPreparedReply(source: fixture.source, destination: destination, body: "Exact reply")
        let receipt = try await provider.send(prepared, operationID: UUID())
        #expect(receipt.channelID == fixture.channel)
        let genericTools = try requests.filter { $0.url?.path == "/v1/execute" }.map {
            try ComposioJSONValue.parseObject(String(decoding: $0.httpBody!, as: UTF8.self))["tool"]?.stringValue
        }
        #expect(!genericTools.contains("SLACK_SEND_MESSAGE"))
        #expect(requests.filter { $0.url?.path == "/v1/slack/replies" }.count == 1)
    }

    @Test func oldServerOrUnsupportedIdentityProtocolCannotEnableSending() async throws {
        for oldRoute in [false, true] {
            let fixture = try Fixture()
            var paths: [String] = []
            let service = ComposioService(baseURL: URL(string: "https://synthetic.example.invalid")!, tokenStore: Tokens(), executionStore: Tokens(nil)) { request in
                paths.append(request.url!.path)
                if oldRoute { return response(request, ["error": ["code": "not_found", "message": "Route not found"]], status: 404) }
                var identity = fixture.identityJSON; identity["protocolVersion"] = 999
                return response(request, identity)
            }
            let provider = SlackComposioReplyProvider(service: service, now: { fixture.time })
            await #expect(throws: (any Error).self) { try await provider.destination(for: fixture.source) }
            #expect(paths == ["/v1/slack/reply-identity"])
        }
    }

    @Test func changedSubjectBeforeSendCannotReachDedicatedWriteRoute() async throws {
        let fixture = try Fixture()
        var writes = 0
        let service = ComposioService(baseURL: URL(string: "https://synthetic.example.invalid")!, tokenStore: Tokens(), executionStore: Tokens(nil)) { request in
            if request.url?.path == "/v1/slack/reply-identity" {
                var identity = fixture.identityJSON; identity["userID"] = "U99999999"
                return response(request, identity)
            }
            if request.url?.path == "/v1/connections" { return response(request, ["connections": [["id": "ca_synthetic", "service": "slack", "name": "Slack", "status": "ACTIVE"]]]) }
            if request.url?.path == "/v1/slack/replies" { writes += 1 }
            let input = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as! [String: Any]
            return response(request, ["requestID": input["requestID"]!, "successful": true, "data": ["ok": true,
                "channel": ["id": fixture.channel, "name": "morning", "is_archived": false, "is_member": true]]])
        }
        let identity = try SlackReplyIdentity(connectionID: "ca_synthetic", revision: String(repeating: "a", count: 64), teamID: "T12345678", userID: "U12345678", teamName: "Actual workspace", userName: "owner")
        let prepared = try SlackPreparedReply(source: fixture.source, destination: .init(identity: identity, channelID: fixture.channel, channelName: "morning"), body: "Exact reply")
        let provider = SlackComposioReplyProvider(service: service, now: { fixture.time })
        await #expect(throws: (any Error).self) { try await provider.send(prepared, operationID: UUID()) }
        #expect(writes == 0)
    }

    private struct Fixture {
        let time = Date(timeIntervalSince1970: 1_800_000_000)
        let channel = "C12345678", parent = "1800000000.000001"
        let source: SlackReplySource
        init() throws {
            let result: ComposioJSONValue = .object(["ok": .bool(true), "messages": .array([.object(["type": .string("message"),
                "ts": .string(parent), "user": .string("U33333333"), "text": .string("Source text")])])])
            let document = try ConnectedMomentDocument(executionID: .init(sessionID: UUID(), routineVersionID: UUID(), stepID: UUID()), service: "slack", result: result,
                receivedAt: time, origin: .init(tool: "SLACK_FETCH_CONVERSATION_HISTORY", connectionID: "ca_synthetic", arguments: ["channel": .string(channel)]))
            source = try #require(SlackReplySource.sources(in: document, at: time).first)
        }
        var identityJSON: [String: Any] { ["protocolVersion": 1, "connectionID": "ca_synthetic", "revision": String(repeating: "a", count: 64), "teamID": "T12345678", "userID": "U12345678", "teamName": "Actual workspace", "userName": "owner"] }
    }
    private final class Tokens: ComposioTokenStoring {
        var value: String?
        var failLoad = false
        init(_ value: String? = "SYNTHETIC_INSTALLATION_TOKEN") { self.value = value }
        func load() throws -> String? { if failLoad { throw ComposioServiceError.credentialsUnavailable }; return value }
        func save(_ token: String) throws { value = token }
        func clear() throws { value = nil }
    }
    private final class ClientProvider: SlackThreadReplyProviding {
        let service: ComposioService, result: SlackReplyDestination
        var beforeSend: (@MainActor () async -> Void)?
        init(service: ComposioService, destination: SlackReplyDestination) { self.service = service; result = destination }
        func destination(for source: SlackReplySource) async throws -> SlackReplyDestination { result }
        func validate(_ reply: SlackPreparedReply) async throws {}
        func send(_ reply: SlackPreparedReply, operationID: UUID) async throws -> SlackReplyReceipt {
            await beforeSend?()
            return try SlackReplyReceipt.verified(result: await service.sendSlackReply(reply, operationID: operationID), reply: reply, operationID: operationID)
        }
    }
    private func response(_ request: URLRequest, _ body: [String: Any], status: Int = 200) -> (Data, HTTPURLResponse) {
        (try! JSONSerialization.data(withJSONObject: body), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
    }
}
