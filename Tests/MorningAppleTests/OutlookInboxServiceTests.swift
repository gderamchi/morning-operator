import Foundation
import MorningCore
import Testing
@testable import MorningApple

@Suite("Outlook fixed reads — injected HTTP only") @MainActor
struct OutlookInboxServiceTests {
    @Test func identityUsesTheActualProfileShapeAndDoesNotGuessAMailboxFromANonEmailPrincipal() async throws {
        let f = Fixture(), reader = f.reader()
        let identity = try await reader.identity(connectionID: f.connection), expected = try f.target()
        #expect(identity.target == expected && identity.isCurrent(at: f.now))
        #expect(f.reads.map(\.tool) == ["OUTLOOK_GET_PROFILE"])
        #expect(f.reads[0].arguments == OutlookInboxReadContract.identityArguments)
        f.profileOverride = ["id": f.accountID, "displayName": f.name, "mail": NSNull(), "userPrincipalName": "directory-principal"]
        let noMailbox = try await reader.identity(connectionID: f.connection)
        #expect(noMailbox.mailboxAddress == nil)
        f.profileOverride = ["id": f.accountID, "mail": "owner@synthetic.invalid"]
        await #expect(throws: OutlookInboxError.invalidIdentity) { try await reader.identity(connectionID: f.connection) }
        #expect(!String(reflecting: identity).contains("PRIVATE"))
    }

    @Test func listUsesExactlyThreeUnreadInboxPreviewsFullResponseAndExplicitSelectWithoutADayLowerBoundOrBodyRead() async throws {
        let f = Fixture(), doc = try await f.reader().read(target: f.target())
        #expect(f.reads.map(\.tool) == ["OUTLOOK_GET_PROFILE", "OUTLOOK_LIST_MESSAGES", "OUTLOOK_GET_PROFILE"])
        let args = f.reads[1].arguments
        #expect(args["top"] == .number(3) && args["folder"] == .string("inbox") && args["user_id"] == .string("me"))
        #expect(args["response_detail"] == .string("full") && args["filter"] == .string("receivedDateTime le 2026-10-16T09:00:00Z and isRead eq false"))
        #expect(args["select"]?.arrayValue?.contains(.string("body")) == false && args["page_token"] == nil)
        #expect(doc.messages.count == 1 && doc.messages[0].receivedAt < f.now.addingTimeInterval(-86_400))
        #expect(!doc.contextText().contains("PRIVATE_HEADER") && f.ledger.value == "UNCHANGED_WRITE_RESERVATION")
    }

    @Test func selectedMessageReadsOnlyObservedIDAndExtractsHTMLLocallyWithoutFetchingResourcesOrAttachments() async throws {
        let f = Fixture(), reader = f.reader(), source = try await reader.read(target: f.target())
        let count = f.reads.count
        await #expect(throws: OutlookInboxError.messageNotObserved) { try await reader.message(id: "unobserved-id", from: source) }
        #expect(f.reads.count == count)
        let message = try await reader.message(id: source.messages[0].id, from: source)
        #expect(f.reads.suffix(3).map(\.tool) == ["OUTLOOK_GET_PROFILE", "OUTLOOK_GET_MESSAGE", "OUTLOOK_GET_PROFILE"])
        let args = try #require(f.reads.first(where: { $0.tool == OutlookInboxReadContract.messageTool })?.arguments)
        #expect(args["message_id"] == .string("opaque-message/+=") && args["select"]?.arrayValue?.contains(.string("body")) == true)
        #expect(message.bodyText?.split(separator: "\n").map(String.init) == ["Visible & inert", "Open", "<@source-text>"] && !message.bodyIsIncomplete)
        #expect(!message.contextText().contains("PRIVATE_SCRIPT") && !message.contextText().contains("remote.invalid"))
        #expect(f.paths.allSatisfy { ["/v1/connections", "/v1/execute"].contains($0) })
        #expect(f.ledger.value == "UNCHANGED_WRITE_RESERVATION")
    }

    @Test func unavailableEmptyAndIncompleteBodiesAreDistinctAndPreviewNeverSubstitutesForABody() async throws {
        let f = Fixture(), reader = f.reader(), source = try await reader.read(target: f.target())
        for (body, expectedText, incomplete): ([String: Any]?, String?, Bool) in [
            (nil, nil, true), (["contentType": "text", "content": ""], "", false),
            (["contentType": "HTML", "content": "<p>Readable</p><script>unfinished"], "Readable", true)
        ] {
            f.body = body
            let doc = try await reader.message(id: source.messages[0].id, from: source)
            #expect(doc.bodyText == expectedText && doc.bodyIsIncomplete == incomplete)
        }
        f.body = ["contentType": "text", "content": String(repeating: "a", count: 280_000)]
        let bounded = try await reader.message(id: source.messages[0].id, from: source)
        #expect(bounded.bodyIsIncomplete && bounded.bodyText!.utf8.count <= 16_000)
        #expect(try JSONEncoder().encode(bounded.contextText()).count <= 22_500)
    }

    @Test func accountReplacedBeforeOrDuringReadsCannotPublishMailFromAnotherSubject() async throws {
        for stage in ["before-list", "during-list", "during-message"] {
            let f = Fixture(), reader = f.reader(), target = try f.target()
            if stage == "before-list" {
                f.accountID = "other-account"
                await #expect(throws: OutlookInboxError.identityChanged) { try await reader.read(target: target) }
                #expect(!f.reads.contains { $0.tool == OutlookInboxReadContract.listTool })
            } else if stage == "during-list" {
                f.beforeList = { f.accountID = "other-account" }
                await #expect(throws: OutlookInboxError.identityChanged) { try await reader.read(target: target) }
            } else {
                let source = try await reader.read(target: target)
                f.beforeMessage = { f.accountID = "other-account" }
                await #expect(throws: OutlookInboxError.identityChanged) { try await reader.message(id: source.messages[0].id, from: source) }
            }
            f.beforeList = nil; f.beforeMessage = nil
        }
    }

    @Test func staleSelectionOrSourceExpiringDuringAReadCannotReturnAnOldMessage() async throws {
        let f = Fixture(), reader = f.reader(), source = try await reader.read(target: f.target())
        f.now = f.now.addingTimeInterval(301)
        let count = f.reads.count
        await #expect(throws: OutlookInboxError.staleSource) { try await reader.message(id: source.messages[0].id, from: source) }
        #expect(f.reads.count == count)
        let current = try await reader.read(target: f.target())
        f.beforeMessage = { f.now = f.now.addingTimeInterval(301) }
        await #expect(throws: OutlookInboxError.staleSource) { try await reader.message(id: current.messages[0].id, from: current) }
        f.beforeMessage = nil
    }

    @Test func movedChangedOrWrongIDMessageIsRejectedInsteadOfPublishingAReplacementBody() async throws {
        let f = Fixture(), reader = f.reader(), source = try await reader.read(target: f.target())
        for (key, value) in [("id", "other-message"), ("changeKey", "version-2"), ("parentFolderId", "other-folder"), ("subject", "Changed subject")] {
            var row = f.row(); row[key] = value; f.messageOverride = row
            await #expect(throws: OutlookInboxError.messageChanged) { try await reader.message(id: source.messages[0].id, from: source) }
        }
    }

    @Test func partialEmptyMalformedAndProviderFailuresNeverAnnounceAnEmptyInboxOrFollowContinuationURLs() async throws {
        let f = Fixture(), reader = f.reader()
        f.listOverride = ["value": []]
        let empty = try await reader.read(target: f.target())
        #expect(empty.messages.isEmpty && !empty.isPartial)
        f.listOverride = ["value": [], "@odata.nextLink": "https://untrusted.invalid/PRIVATE_CONTINUATION"]
        let partial = try await reader.read(target: f.target())
        #expect(partial.isPartial && !partial.summary(french: false).contains("No unread messages"))
        for payload: [String: Any] in [[:], ["value": [], "next_page_token": 7], ["value": [f.row(), f.row()]],
                                      ["value": [], "error": "PRIVATE_PROVIDER_ERROR"]] {
            f.listOverride = payload
            await #expect(throws: OutlookInboxError.invalidResponse) { try await reader.read(target: f.target()) }
        }
        f.failList = true
        await #expect(throws: OutlookInboxError.unavailable) { try await reader.read(target: f.target()) }
        #expect(!OutlookInboxError.unavailable.localizedDescription.contains("PRIVATE"))
    }

    @Test func cancellationDeadlineAndConnectionRemovalDiscardLateContentAndNeverTouchTheEffectLedger() async throws {
        let f = Fixture(), reader = f.reader()
        var release: CheckedContinuation<Void, Never>?
        f.beforeList = { await withCheckedContinuation { release = $0 } }
        let task = Task { try await reader.read(target: f.target()) }
        for _ in 0..<500 where release == nil { await Task.yield() }
        let continuation = try #require(release); task.cancel(); continuation.resume()
        await #expect(throws: (any Error).self) { try await task.value }
        f.beforeList = { try? await Task.sleep(for: .seconds(2)) }
        await #expect(throws: OutlookInboxError.unavailable) { try await f.reader(timeout: .milliseconds(10)).read(target: f.target()) }
        f.beforeList = { f.active = false }
        await #expect(throws: OutlookInboxError.unavailable) { try await reader.read(target: f.target()) }
        f.beforeList = nil
        #expect(f.ledger.value == "UNCHANGED_WRITE_RESERVATION")
    }

    @Test func readHelperRejectsWritesArbitraryFieldsFiltersMailboxAndUnboundedTopBeforeTransport() async throws {
        let f = Fixture(), client = f.client, tool = OutlookInboxReadContract.listTool
        var unbounded = OutlookInboxReadContract.listArguments(cutoff: f.now); unbounded["top"] = .number(100)
        var otherMailbox = OutlookInboxReadContract.identityArguments; otherMailbox["user_id"] = .string("other@synthetic.invalid")
        var arbitraryFields = OutlookInboxReadContract.messageArguments(id: "observed"); arbitraryFields["select"] = .array([.string("internetMessageHeaders")])
        var filter = OutlookInboxReadContract.listArguments(cutoff: f.now); filter["filter"] = .string("isRead eq false or true")
        for (slug, args) in [("OUTLOOK_SEND_EMAIL", [:]), (tool, unbounded), (OutlookInboxReadContract.identityTool, otherMailbox), (OutlookInboxReadContract.messageTool, arbitraryFields), (tool, filter)] {
            await #expect(throws: ComposioServiceError.invalidArguments) { try await client.readOutlook(tool: slug, arguments: args, connectionID: f.connection) }
        }
        #expect(f.reads.isEmpty && f.paths.isEmpty && f.ledger.value == "UNCHANGED_WRITE_RESERVATION")
    }

    @MainActor private final class Fixture {
        let connection = "ca_synthetic_outlook"
        var accountID = "provider-account", name = "PRIVATE_OWNER_NAME", active = true, failList = false
        var now = outlookDate("2026-10-16T09:00:00Z")
        var profileOverride: [String: Any]?, listOverride: [String: Any]?, messageOverride: [String: Any]?
        var body: [String: Any]? = ["contentType": "html", "content": "<p>Visible &amp; inert</p><script>PRIVATE_SCRIPT</script><img src='https://remote.invalid/private.png'><p><a href='https://remote.invalid'>Open</a></p>&lt;@source-text&gt;"]
        var beforeList: (@MainActor () async -> Void)?, beforeMessage: (@MainActor () async -> Void)?
        struct Read { let tool: String; let arguments: [String: ComposioJSONValue]; let id: UUID }
        var reads: [Read] = [], paths: [String] = []
        let ledger = Tokens("UNCHANGED_WRITE_RESERVATION")
        lazy var client = ComposioService(baseURL: URL(string: "https://synthetic-outlook.invalid")!, tokenStore: Tokens(), executionStore: ledger) { [unowned self] request in
            self.paths.append(request.url!.path)
            if request.url?.path == "/v1/connections" {
                return outlookResponse(request, ["connections": self.active ? [["id": self.connection, "service": "outlook", "name": "Outlook SYNTHETIC", "status": "ACTIVE"]] : []])
            }
            let input = try ComposioJSONValue.parseObject(String(decoding: request.httpBody!, as: UTF8.self))
            let tool = try #require(input["tool"]?.stringValue), args = try #require(input["arguments"]?.objectValue)
            let id = try #require(input["requestID"]?.stringValue.flatMap(UUID.init(uuidString:)))
            self.reads.append(.init(tool: tool, arguments: args, id: id))
            let data: [String: Any]
            switch tool {
            case OutlookInboxReadContract.identityTool:
                data = self.profileOverride ?? ["id": self.accountID, "displayName": self.name, "mail": "owner@synthetic.invalid", "userPrincipalName": "owner@synthetic.invalid"]
            case OutlookInboxReadContract.listTool:
                await self.beforeList?(); if self.failList { throw URLError(.timedOut) }
                data = self.listOverride ?? ["value": [self.row()]]
            case OutlookInboxReadContract.messageTool:
                await self.beforeMessage?()
                var message = self.messageOverride ?? self.row(); if let body = self.body { message["body"] = body }; data = message
            default: Issue.record("Unexpected synthetic tool"); throw URLError(.unsupportedURL)
            }
            return outlookResponse(request, ["requestID": id.uuidString, "successful": true, "data": ["successful": true, "data": data]])
        }
        func row() -> [String: Any] {
            ["id": "opaque-message/+=", "subject": "PRIVATE_SUBJECT", "from": ["emailAddress": ["name": "PRIVATE_SENDER", "address": "sender@synthetic.invalid"]],
             "receivedDateTime": "2026-10-12T08:00:00Z", "bodyPreview": "PRIVATE_PREVIEW", "isRead": false, "isDraft": false,
             "hasAttachments": true, "changeKey": "version-1", "parentFolderId": "inbox-folder", "internetMessageHeaders": ["PRIVATE_HEADER"]]
        }
        func target() throws -> OutlookInboxTarget { try .init(connectionID: connection, accountID: accountID, displayName: name, mailboxAddress: "owner@synthetic.invalid") }
        func reader(timeout: Duration = .seconds(40)) -> OutlookInboxService { .init(service: client, now: { self.now }, readTimeout: timeout) }
    }
    private final class Tokens: ComposioTokenStoring {
        var value: String?
        init(_ value: String? = "SYNTHETIC_INSTALLATION_TOKEN") { self.value = value }
        func load() throws -> String? { value }
        func save(_ value: String) throws { self.value = value }
        func clear() throws { value = nil }
    }
}
private func outlookDate(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
private func outlookResponse(_ request: URLRequest, _ value: [String: Any]) -> (Data, HTTPURLResponse) {
    (try! JSONSerialization.data(withJSONObject: value), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
}
