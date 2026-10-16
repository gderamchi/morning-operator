import Foundation
import MorningCore
import Testing
@testable import MorningApple

@Suite("Calendly personal day — injected HTTP only") @MainActor
struct CalendlyDayServiceTests {
    @Test func actualWhoAmIShapeCreatesAFreshNamedIdentityWithoutEmailOrDeprecatedResourceFallback() async throws {
        let f = Fixture(), service = f.reader()
        let identity = try await service.identity(connectionID: f.connection), expected = try f.target()
        #expect(identity.userURI == f.userURI && identity.userName == f.userName && identity.target == expected)
        #expect(identity.isCurrent(at: f.now) && !identity.isCurrent(at: f.now.addingTimeInterval(301)))
        #expect(f.reads.count == 1 && f.reads[0].tool == "CALENDLY_WHO_AM_I" && f.reads[0].arguments.isEmpty)
        #expect(!String(describing: identity).contains("PRIVATE_EMAIL"))
        f.profileOverride = ["resource": ["uri": f.userURI, "name": f.userName]]
        await #expect(throws: CalendlyDayError.invalidIdentity) { try await service.identity(connectionID: f.connection) }
        f.profileOverride = ["data": ["uri": f.userURI, "email": "PRIVATE_EMAIL"], "display_name": "PRIVATE_EMAIL"]
        await #expect(throws: CalendlyDayError.invalidIdentity) { try await service.identity(connectionID: f.connection) }
    }

    @Test func readUsesOnlyActualPersonalURIAndRechecksIdentityAfterItsPrunedResult() async throws {
        let f = Fixture(), service = f.reader()
        let document = try await service.read(target: f.target())
        #expect(f.reads.map(\.tool) == ["CALENDLY_WHO_AM_I", "CALENDLY_LIST_SCHEDULED_EVENTS", "CALENDLY_WHO_AM_I"])
        let args = f.reads[1].arguments
        #expect(args["user"] == .string(f.userURI) && args["count"] == .number(25) && args["status"] == .string("active"))
        #expect(args["sort"] == .string("start_time:asc") && args["min_start_time"] == .string("2026-03-28T22:59:59Z"))
        #expect(args["max_start_time"] == .string("2026-03-29T22:00:00Z"))
        #expect(args["organization"] == nil && args["group"] == nil && args["invitee_email"] == nil && args["page_token"] == nil)
        #expect(document.events.count == 1 && document.events[0].locationKind == .video)
        let visible = document.summary(french: false) + document.contextText(french: false)
        #expect(!visible.contains("PRIVATE_") && !visible.contains("https://meeting.invalid"))
        #expect(f.ledger.value == nil)
    }

    @Test func midnightAndLastBoundaryAreFilteredLocallyWithHonestCounts() async throws {
        let f = Fixture(), service = f.reader(), window = try CalendlyDayWindow(at: f.now, timeZone: f.zone)
        var cancelled = f.event("cancelled", start: window.start.addingTimeInterval(3_600)); cancelled["status"] = "canceled"
        let rows = [f.event("midnight", start: window.start), f.event("extra-lower-second", start: window.start.addingTimeInterval(-0.5)),
                    f.event("next-midnight", start: window.end), cancelled]
        f.eventsOverride = ["collection": rows, "pagination": ["count": rows.count]]
        let doc = try await service.read(target: f.target())
        #expect(doc.events.count == 1 && doc.events[0].start == window.start && doc.excludedCount == 2 && doc.cancelledCount == 1)
        #expect(doc.summary(french: true).contains("2 résultats hors journée") && doc.summary(french: false).contains("One cancelled appointment"))
    }

    @Test func longComposedNamesBecomeBoundedExcerptsInsteadOfLosingAValidReading() async throws {
        let f = Fixture(), service = f.reader()
        var row = f.event("long-event", start: f.now)
        row["name"] = String(repeating: "👨‍👩‍👧‍👦", count: 100)
        f.eventsOverride = ["collection": [row], "pagination": ["count": 1]]
        let doc = try await service.read(target: f.target())
        #expect(doc.events.count == 1 && doc.events[0].name.count <= 300 && doc.events[0].name.utf8.count <= 1_200)
        #expect(doc.events[0].name.hasSuffix("…") && doc.contextText().contains("excerpts"))
    }

    @Test func emptyPartialAndMalformedPagesNeverCollapseIntoTheSameResultOrFollowAURL() async throws {
        let f = Fixture(), service = f.reader()
        f.eventsOverride = ["collection": [], "pagination": ["count": 0]]
        let empty = try await service.read(target: f.target())
        #expect(empty.events.isEmpty && !empty.isPartial)
        for page: [String: Any] in [["count": 0, "next_page_token": "opaque"], ["count": 0, "next_page": "https://api.calendly.com/scheduled_events?page_token=opaque"]] {
            f.eventsOverride = ["collection": [], "pagination": page]
            let partial = try await service.read(target: f.target())
            #expect(partial.events.isEmpty && partial.isPartial && partial.summary(french: false).contains("More appointments may follow"))
        }
        for payload: [String: Any] in [[:], ["collection": []], ["collection": [], "pagination": ["count": 1]],
                                     ["collection": [], "pagination": ["count": 0, "next_page_token": 7]],
                                     ["collection": [], "pagination": ["count": 0, "next_page": "https://evil.invalid/appointments"]],
                                     ["collection": [], "pagination": ["count": 0], "error": "PRIVATE_PROVIDER_ERROR"]] {
            f.eventsOverride = payload
            await #expect(throws: (any Error).self) { try await service.read(target: f.target()) }
        }
        #expect(f.paths.allSatisfy { ["/v1/connections", "/v1/execute"].contains($0) })
    }

    @Test func staleOrChangedIdentityCannotReadAnotherUsersEventsOrPublishAnOldReading() async throws {
        for changeAfterRead in [false, true] {
            let f = Fixture(), service = f.reader(), approved = try f.target()
            if changeAfterRead { f.beforeEvents = { f.userURI = "https://api.calendly.com/users/other-user" } }
            else { f.userName = "Different current name" }
            await #expect(throws: CalendlyDayError.identityChanged) { try await service.read(target: approved) }
            #expect(f.reads.filter { $0.tool == CalendlyDayReadContract.eventsTool }.count == (changeAfterRead ? 1 : 0))
            f.beforeEvents = nil
        }
    }

    @Test func wrongMembershipUnknownStatusesDuplicatesAndUnboundedRowsAreRefused() async throws {
        let f = Fixture(), service = f.reader(), window = try CalendlyDayWindow(at: f.now, timeZone: f.zone)
        var wrongUser = f.event("wrong-user", start: window.start.addingTimeInterval(3_600))
        wrongUser["event_memberships"] = [["user": "https://api.calendly.com/users/other-user"]]
        var invalidTime = f.event("invalid-time", start: window.start.addingTimeInterval(3_600)); invalidTime["start_time"] = "2026-03-29T10:00:00"
        var invalidStatus = f.event("invalid-status", start: window.start.addingTimeInterval(3_600)); invalidStatus["status"] = "unknown"
        let one = f.event("one-event", start: window.start.addingTimeInterval(3_600))
        for rows in [[wrongUser], [invalidTime], [invalidStatus], [one, one], Array(repeating: one, count: 26)] {
            f.eventsOverride = ["collection": rows, "pagination": ["count": rows.count]]
            await #expect(throws: CalendlyDayError.invalidResponse) { try await service.read(target: f.target()) }
        }
    }

    @Test func aNewDayRecomputesUTCAndZoneBeforeAnyReadAndLateMidnightOrZoneChangeIsDiscarded() async throws {
        let f = Fixture(), service = f.reader()
        let first = try await service.read(target: f.target())
        f.now = calDate("2026-03-30T10:00:00Z")
        let next = try await service.read(target: f.target())
        #expect(next.window.start == first.window.end && f.reads.filter { $0.tool == CalendlyDayReadContract.eventsTool }.last?.arguments["min_start_time"] == .string("2026-03-29T21:59:59Z"))
        for change in ["midnight", "zone"] {
            let late = Fixture(), reader = late.reader()
            late.beforeEvents = {
                if change == "midnight" { late.now = calDate("2026-03-30T00:01:00+02:00") }
                else { late.zone = TimeZone(identifier: "Asia/Tokyo")! }
            }
            await #expect(throws: CalendlyDayError.invalidWindow) { try await reader.read(target: late.target()) }
            late.beforeEvents = nil
        }
    }

    @Test func cancellationDeadlineAndRevocationDoNotYieldASourceOrDispatchAnyWrite() async throws {
        let f = Fixture(), service = f.reader()
        var release: CheckedContinuation<Void, Never>?
        f.beforeEvents = { await withCheckedContinuation { release = $0 } }
        let task = Task { try await service.read(target: f.target()) }
        for _ in 0..<500 where release == nil { await Task.yield() }
        let continuation = try #require(release); task.cancel(); continuation.resume()
        await #expect(throws: (any Error).self) { try await task.value }
        f.beforeEvents = { try? await Task.sleep(for: .seconds(5)) }
        await #expect(throws: (any Error).self) { try await f.reader(timeout: .milliseconds(10)).read(target: f.target()) }
        f.beforeEvents = { f.active = false }
        await #expect(throws: CalendlyDayError.unavailable) { try await service.read(target: f.target()) }
        f.beforeEvents = nil
        #expect(f.reads.allSatisfy { [CalendlyDayReadContract.identityTool, CalendlyDayReadContract.eventsTool].contains($0.tool) })
    }

    @Test func failedReadRetryUsesFreshIDsWithoutReadingOrReleasingAnExistingWriteLedger() async throws {
        let f = Fixture(), service = f.reader(); f.ledger.value = "UNCHANGED_WRITE_RESERVATION"; f.failEvents = true
        await #expect(throws: (any Error).self) { try await service.read(target: f.target()) }
        f.failEvents = false
        _ = try await service.read(target: f.target())
        let events = f.reads.filter { $0.tool == CalendlyDayReadContract.eventsTool }
        #expect(events.count == 2 && events[0].id != events[1].id && f.ledger.value == "UNCHANGED_WRITE_RESERVATION")
        let calls = f.reads.count
        await #expect(throws: ComposioServiceError.invalidArguments) { try await f.client.readCalendly(tool: "CALENDLY_CANCEL_SCHEDULED_EVENT", arguments: [:], connectionID: f.connection) }
        await #expect(throws: ComposioServiceError.invalidArguments) { try await f.client.readCalendly(tool: "CALENDLY_GET_CURRENT_USER", arguments: [:], connectionID: f.connection) }
        let window = try CalendlyDayWindow(at: f.now, timeZone: f.zone)
        var args = CalendlyDayReadContract.arguments(target: try f.target(), window: window); args["organization"] = .string("https://api.calendly.com/organizations/other")
        await #expect(throws: ComposioServiceError.invalidArguments) { try await f.client.readCalendly(tool: CalendlyDayReadContract.eventsTool, arguments: args, connectionID: f.connection) }
        #expect(f.reads.count == calls)
    }

    @MainActor private final class Fixture {
        let connection = "ca_synthetic_calendly"
        var userURI = "https://api.calendly.com/users/actual-user", userName = "Owner SYNTHETIC"
        var now = calDate("2026-03-29T10:00:00Z"), zone = TimeZone(identifier: "Europe/Paris")!
        var active = true, failEvents = false
        var profileOverride: [String: Any]?, eventsOverride: [String: Any]?
        var beforeEvents: (@MainActor () async -> Void)?
        struct Read { let tool: String; let arguments: [String: ComposioJSONValue]; let id: UUID }
        var reads: [Read] = [], paths: [String] = []
        let ledger = Tokens(nil)
        lazy var client = ComposioService(baseURL: URL(string: "https://synthetic-calendly.invalid")!, tokenStore: Tokens(), executionStore: ledger) { [unowned self] request in
            self.paths.append(request.url!.path)
            if request.url?.path == "/v1/connections" {
                return calResponse(request, ["connections": [["id": self.connection, "service": "calendly", "name": "Calendly SYNTHETIC", "status": self.active ? "ACTIVE" : "EXPIRED"]]])
            }
            let input = try ComposioJSONValue.parseObject(String(decoding: request.httpBody!, as: UTF8.self))
            let tool = try #require(input["tool"]?.stringValue), args = try #require(input["arguments"]?.objectValue)
            let id = try #require(input["requestID"]?.stringValue.flatMap(UUID.init(uuidString:)))
            self.reads.append(.init(tool: tool, arguments: args, id: id))
            let data: [String: Any]
            if tool == CalendlyDayReadContract.identityTool {
                data = self.profileOverride ?? ["data": ["uri": self.userURI, "name": self.userName, "email": "PRIVATE_EMAIL", "scheduling_url": "https://calendly.com/PRIVATE_SCHEDULING_LINK"], "display_name": "PRIVATE_EMAIL"]
            } else {
                #expect(tool == CalendlyDayReadContract.eventsTool)
                let lower = try #require(args["min_start_time"]?.stringValue.flatMap(CalendlyDayReadContract.timestamp))
                let row = self.event("first-event", start: lower.addingTimeInterval(3_601))
                await self.beforeEvents?()
                if self.failEvents { throw URLError(.timedOut) }
                data = self.eventsOverride ?? ["collection": [row], "pagination": ["count": 1]]
            }
            return calResponse(request, ["requestID": id.uuidString, "successful": true, "data": ["successful": true, "data": data]])
        }
        func target() throws -> CalendlyDayTarget { try .init(connectionID: connection, userURI: userURI, userName: userName) }
        func reader(timeout: Duration = .seconds(40)) -> CalendlyDayService { .init(service: client, now: { self.now }, timeZone: { self.zone }, readTimeout: timeout) }
        func event(_ id: String, start: Date) -> [String: Any] {
            let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return ["uri": "https://api.calendly.com/scheduled_events/\(id)", "name": "Appointment SYNTHETIC", "status": "active",
                "start_time": f.string(from: start), "end_time": f.string(from: start.addingTimeInterval(1_800)),
                "event_memberships": [["user": userURI, "user_email": "PRIVATE_HOST_EMAIL"]],
                "location": ["type": "zoom_conference", "join_url": "https://meeting.invalid/PRIVATE_JOIN_URL", "location": "PRIVATE_LOCATION", "data": ["password": "PRIVATE_PASSWORD"]],
                "event_guests": [["email": "PRIVATE_GUEST_EMAIL"]], "meeting_notes_plain": "PRIVATE_NOTES"]
        }
    }
    private final class Tokens: ComposioTokenStoring {
        var value: String?
        init(_ value: String? = "SYNTHETIC_INSTALLATION_TOKEN") { self.value = value }
        func load() throws -> String? { value }
        func save(_ token: String) throws { value = token }
        func clear() throws { value = nil }
    }
}
private func calDate(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
private func calResponse(_ request: URLRequest, _ value: [String: Any]) -> (Data, HTTPURLResponse) {
    (try! JSONSerialization.data(withJSONObject: value), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
}
