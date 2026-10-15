import Foundation
import MorningCore
import Testing
@testable import MorningApple

@Suite("Google Calendar day — injected provider HTTP only") @MainActor
struct GoogleCalendarDayServiceTests {
    @Test func namedCalendarPagesUsePinnedSnakeCaseAndActualProviderNames() async throws {
        let f = Fixture()
        f.listPages[""] = ["calendars": [f.calendar(name: "Original", override: "Owner-chosen label"),
            f.calendar(id: "busy@example.invalid", name: "Busy only", role: "freeBusyReader")], "next_page_token": "opaque-cursor"]
        f.listPages["opaque-cursor"] = ["calendars": [f.calendar(id: "other@example.invalid", name: "Other calendar")]]
        let service = f.reader()
        let first = try await service.calendars(connectionID: f.connection)
        #expect(first.choices.count == 1 && first.choices[0].name == "Owner-chosen label" && first.nextCursor == "opaque-cursor")
        let next = try await service.calendars(connectionID: f.connection, cursor: first.nextCursor)
        #expect(next.choices[0].id == "other@example.invalid" && next.nextCursor == nil)
        let reads = f.reads
        #expect(reads[0].tool == "GOOGLECALENDAR_LIST_CALENDARS")
        #expect(reads[0].arguments["max_results"] == .number(50) && reads[0].arguments["min_access_role"] == .string("reader"))
        #expect(reads[1].arguments["page_token"] == .string("opaque-cursor") && reads[1].arguments["pageToken"] == nil)
        #expect(f.ledger.value == nil)
        let selectedLaterPage = try GoogleCalendarDayTarget(connectionID: f.connection, calendarID: "other@example.invalid", calendarName: "Other calendar")
        let doc = try await service.read(target: selectedLaterPage)
        #expect(doc.target == selectedLaterPage && doc.events.isEmpty)
    }

    @Test func primaryLabelsDistinguishChoicesAndLaterPageHomonymsInvalidateTheEarlierChoice() throws {
        let primary = try GoogleCalendarChoice(id: "main@example.invalid", name: "Morning", isPrimary: true)
        let first = try GoogleCalendarChoice(id: "first@example.invalid", name: "Morning")
        let later = try GoogleCalendarChoice(id: "later@example.invalid", name: "Morning")
        #expect(primary.sourceLabel(french: false) == "Morning (primary calendar)")
        #expect(primary.sourceLabel(french: true) == "Morning (calendrier principal)")
        #expect(try primary.target(connectionID: "ca_synthetic").isPrimary == true)
        #expect(try first.target(connectionID: "ca_synthetic").isPrimary == false)
        #expect(!primary.isAmbiguous(in: [primary, first]) && !first.isAmbiguous(in: [primary, first]))
        let all = [primary, first, later]
        #expect(!primary.isAmbiguous(in: all) && first.isAmbiguous(in: all) && later.isAmbiguous(in: all))
        for french in [false, true] {
            #expect(try primary.target(connectionID: "ca_synthetic").sourceLabel(french: french) == primary.sourceLabel(french: french))
        }
        // A source name that looks like our suffix must not become a second identical label.
        let suffixName = try GoogleCalendarChoice(id: "suffix@example.invalid", name: primary.sourceLabel(french: false))
        #expect(primary.isAmbiguous(in: [primary, suffixName], french: false))
    }

    @Test func reviewedPrimaryStatusIsRecheckedWithoutRewritingLegacySelections() async throws {
        let f = Fixture(), service = f.reader()
        let primary = try #require(try await service.calendars(connectionID: f.connection).choices.first)
        let approved = try primary.target(connectionID: f.connection)
        #expect(approved.isPrimary == true)
        let initial = try await service.read(target: approved)
        #expect(initial.target == approved && initial.summary(french: false).contains("primary calendar"))
        f.listPages[""] = ["calendars": [f.calendar(primary: false)]]
        let eventReads = f.reads.filter { $0.tool == GoogleCalendarReadContract.eventsTool }.count
        await #expect(throws: GoogleCalendarDayError.selectionChanged) { try await service.read(target: approved) }
        #expect(f.reads.filter { $0.tool == GoogleCalendarReadContract.eventsTool }.count == eventReads)
        let legacy = try await service.read(target: f.target())
        #expect(legacy.target.isPrimary == nil && !legacy.summary(french: false).contains("primary calendar"))
    }

    @Test func runtimeWindowIsRebuiltOnEachReadAndEventsUseOnlyFixedCamelCaseArguments() async throws {
        let f = Fixture(), service = f.reader()
        f.eventPayload = ["kind": "calendar#events", "items": [f.event()], "nextPageToken": "more-events"]
        let first = try await service.read(target: f.target())
        #expect(first.events.count == 1 && first.isPartial && first.events[0].title == "Morning meeting")
        #expect(!first.contextText().contains("OMITTED_PRIVATE"))
        let initial = try #require(f.reads.last(where: { $0.tool == "GOOGLECALENDAR_EVENTS_LIST" }))
        #expect(initial.arguments["calendarId"] == .string(f.calendarID) && initial.arguments["maxResults"] == .number(25))
        #expect(initial.arguments["timeMin"] == .string("2026-03-29T00:00:00+01:00"))
        #expect(initial.arguments["timeMax"] == .string("2026-03-30T00:00:00+02:00"))
        #expect(initial.arguments["timeZone"] == .string("Europe/Paris") && initial.arguments["singleEvents"] == .bool(true))
        #expect(initial.arguments["fields"] == .string(GoogleCalendarReadContract.fields))
        #expect(initial.arguments["syncToken"] == nil && initial.arguments["q"] == nil && initial.arguments["pageToken"] == nil)
        f.now = date("2026-03-30T10:00:00Z"); f.eventPayload = ["kind": "calendar#events", "items": []]
        let next = try await service.read(target: f.target())
        #expect(next.window.start == first.window.end && !next.isPartial && next.events.isEmpty)
        #expect(f.reads.last?.arguments["timeMin"] == .string("2026-03-30T00:00:00+02:00"))
    }

    @Test func realEmptyPartialEmptyAbsentAndProviderFailureRemainDifferent() async throws {
        let f = Fixture(), service = f.reader()
        f.eventPayload = ["items": []]
        let empty = try await service.read(target: f.target())
        #expect(empty.events.isEmpty && !empty.isPartial && empty.summary(french: false).contains("No events scheduled"))
        f.eventPayload = ["items": [], "nextPageToken": "another-page"]
        let partial = try await service.read(target: f.target())
        #expect(partial.events.isEmpty && partial.isPartial && partial.summary(french: false).contains("There may be more"))
        for payload: [String: Any] in [[:], ["items": NSNull()], ["items": [], "nextPageToken": 17], ["items": [], "error": ["message": "Provider failure"]], ["items": [], "accessRole": "freeBusyReader"]] {
            f.eventPayload = payload
            await #expect(throws: (any Error).self) { try await service.read(target: f.target()) }
        }
        f.failEvents = true
        await #expect(throws: (any Error).self) { try await service.read(target: f.target()) }
    }

    @Test func allDayDatesUseCalendarZoneAndExclusiveEndWithoutTwentyFourHourConversion() async throws {
        let f = Fixture(), service = f.reader()
        let allDay: [String: Any] = ["id": "trip", "status": "tentative", "summary": "Source trip", "start": ["date": "2026-03-29"], "end": ["date": "2026-03-31"]]
        f.eventPayload = ["items": [allDay, ["id": "tombstone", "status": "cancelled"]]]
        let doc = try await service.read(target: f.target())
        #expect(doc.events[0].schedule == .allDay(startDate: "2026-03-29", endDate: "2026-03-31"))
        #expect(doc.cancelledCount == 1 && doc.summary(french: false).contains("cancelled"))
        var outside = allDay; outside["start"] = ["date": "2026-03-26"]; outside["end"] = ["date": "2026-03-27"]
        f.eventPayload = ["items": [outside]]
        await #expect(throws: GoogleCalendarDayError.invalidResponse) { try await service.read(target: f.target()) }
        f.listPages[""] = ["calendars": [f.calendar(zone: "America/Los_Angeles")]]
        // March 28 in Los Angeles overlaps the phone's March 29 local window.
        var previousSourceDay = allDay; previousSourceDay["start"] = ["date": "2026-03-28"]; previousSourceDay["end"] = ["date": "2026-03-29"]
        f.eventPayload = ["items": [previousSourceDay]]
        let overlap = try await service.read(target: f.target())
        #expect(overlap.events[0].schedule == .allDay(startDate: "2026-03-28", endDate: "2026-03-29"))
    }

    @Test func malformedTimesOverflowAndWrongPaginationCannotTurnIntoEmptySuccess() async throws {
        let f = Fixture(), service = f.reader()
        var missingOffset = f.event(); missingOffset["start"] = ["dateTime": "2026-03-29T11:00:00"]
        var reversed = f.event(); reversed["end"] = ["dateTime": "2026-03-29T08:00:00+02:00"]
        for payload: [String: Any] in [["items": [missingOffset]], ["items": [reversed]], ["items": Array(repeating: f.event(), count: 26)],
                                     ["items": [], "next_page_token": "wrong-shape"]] {
            f.eventPayload = payload
            await #expect(throws: (any Error).self) { try await service.read(target: f.target()) }
        }
        for payload: [String: Any] in [["items": []], ["calendars": [], "next_page_token": 1], ["calendars": [], "nextPageToken": "wrong-shape"]] {
            f.listPages[""] = payload
            await #expect(throws: (any Error).self) { try await service.calendars(connectionID: f.connection) }
        }
    }

    @Test func selectionMustStillBeNamedReadableAndOnTheSameActiveService() async throws {
        let f = Fixture(), service = f.reader()
        f.listPages[""] = ["calendars": [f.calendar(name: "Renamed")]]
        await #expect(throws: GoogleCalendarDayError.selectionChanged) { try await service.read(target: f.target()) }
        #expect(!f.reads.contains { $0.tool == GoogleCalendarReadContract.eventsTool })
        f.active = false
        await #expect(throws: GoogleCalendarDayError.unavailable) { try await service.calendars(connectionID: f.connection) }
        f.active = true; f.connectionService = "slack"
        await #expect(throws: GoogleCalendarDayError.unavailable) { try await service.calendars(connectionID: f.connection) }
        f.connectionService = "googlecalendar"; f.listPages = [:]
        f.beforeEvents = { f.active = false }
        await #expect(throws: GoogleCalendarDayError.unavailable) { try await service.read(target: f.target()) }
        f.beforeEvents = nil
    }

    @Test func readOnlyRetriesUseFreshUUIDsWithoutTouchingExistingEffectLedgerAndRejectOtherTools() async throws {
        let f = Fixture(); f.ledger.value = "UNCHANGED_EFFECT_RESERVATION"
        f.failEvents = true
        let service = f.reader()
        await #expect(throws: (any Error).self) { try await service.read(target: f.target()) }
        f.failEvents = false
        _ = try await service.read(target: f.target())
        let requests = f.reads.filter { $0.tool == GoogleCalendarReadContract.eventsTool }
        #expect(requests.count == 2 && requests[0].id != requests[1].id && f.ledger.value == "UNCHANGED_EFFECT_RESERVATION")
        let calls = f.reads.count
        await #expect(throws: ComposioServiceError.invalidArguments) { try await f.client.readGoogleCalendar(tool: "GOOGLECALENDAR_CREATE_EVENT", arguments: [:], connectionID: f.connection) }
        let window = try GoogleCalendarDayWindow(at: f.now, timeZone: f.zone)
        var args = GoogleCalendarReadContract.eventArguments(target: try f.target(), window: window); args["syncToken"] = .string("must-not-widen-window")
        await #expect(throws: ComposioServiceError.invalidArguments) { try await f.client.readGoogleCalendar(tool: GoogleCalendarReadContract.eventsTool, arguments: args, connectionID: f.connection) }
        #expect(f.reads.count == calls)
    }

    @Test func midnightZoneChangeAndCancellationRejectLateReadRatherThanReassigningIt() async throws {
        for change in ["midnight", "zone", "cancel"] {
            let f = Fixture(), service = f.reader()
            var release: CheckedContinuation<Void, Never>?
            f.beforeEvents = { await withCheckedContinuation { release = $0 } }
            let read = Task { try await service.read(target: f.target()) }
            for _ in 0..<500 where release == nil { await Task.yield() }
            let continuation = try #require(release)
            if change == "midnight" { f.now = date("2026-03-30T00:01:00+02:00") }
            if change == "zone" { f.zone = TimeZone(identifier: "Asia/Tokyo")! }
            if change == "cancel" { read.cancel() }
            continuation.resume()
            await #expect(throws: (any Error).self) { try await read.value }
        }
    }

    @Test func wholeReadHasOneDeadlineAndLargeValidResultKeepsSpokenSummaryShort() async throws {
        let f = Fixture()
        f.beforeEvents = { try? await Task.sleep(for: .seconds(5)) }
        let shortDeadline = f.reader(timeout: .milliseconds(10))
        await #expect(throws: (any Error).self) { try await shortDeadline.read(target: f.target()) }
        f.beforeEvents = nil
        f.eventPayload = ["items": (0..<25).map { i -> [String: Any] in
            var row = f.event(); row["id"] = "event-\(i)"; row["summary"] = String(repeating: "🌱", count: 400); row["location"] = String(repeating: "🏡", count: 400); return row
        }]
        let doc = try await f.reader().read(target: f.target())
        #expect(doc.events.count == 25 && doc.summary(french: false).count <= 1_800)
        #expect(doc.summary(french: false).contains("22 remain") && doc.summary(french: false).contains("abbreviated"))
        #expect(doc.contextText(french: false).utf8.count < 24_000 && doc.contextText(french: false).contains("truncated"))
    }

    @MainActor private final class Fixture {
        let connection = "ca_synthetic_calendar", calendarID = "calendar@example.invalid"
        var now = date("2026-03-29T10:00:00Z"), zone = TimeZone(identifier: "Europe/Paris")!
        var active = true, connectionService = "googlecalendar", failEvents = false
        var listPages: [String: [String: Any]] = [:], eventPayload: [String: Any] = ["items": []]
        var beforeEvents: (@MainActor () async -> Void)?
        struct Read { let tool: String; let arguments: [String: ComposioJSONValue]; let id: UUID }
        var reads: [Read] = []
        let ledger = Tokens(nil)
        lazy var client = ComposioService(baseURL: URL(string: "https://synthetic.example.invalid")!, tokenStore: Tokens(), executionStore: ledger) { [unowned self] request in
            if request.url?.path == "/v1/connections" {
                return response(request, ["connections": [["id": self.connection, "service": self.connectionService, "name": "Calendar SYNTHETIC", "status": self.active ? "ACTIVE" : "EXPIRED"]]])
            }
            let input = try ComposioJSONValue.parseObject(String(decoding: request.httpBody!, as: UTF8.self))
            let tool = try #require(input["tool"]?.stringValue), args = try #require(input["arguments"]?.objectValue)
            let id = try #require(input["requestID"]?.stringValue.flatMap(UUID.init(uuidString:)))
            self.reads.append(.init(tool: tool, arguments: args, id: id))
            let payload: [String: Any]
            if tool == GoogleCalendarReadContract.listTool {
                payload = self.listPages[args["page_token"]?.stringValue ?? ""] ?? ["calendars": [self.calendar()]]
            } else {
                #expect(tool == GoogleCalendarReadContract.eventsTool)
                await self.beforeEvents?()
                if self.failEvents { throw URLError(.timedOut) }
                payload = self.eventPayload
            }
            return response(request, ["requestID": id.uuidString, "successful": true, "data": ["successful": true, "data": payload]])
        }
        func reader(timeout: Duration = .seconds(40)) -> GoogleCalendarDayService { .init(service: client, now: { self.now }, timeZone: { self.zone }, readTimeout: timeout) }
        func target() throws -> GoogleCalendarDayTarget { try .init(connectionID: connection, calendarID: calendarID, calendarName: "Personal calendar") }
        func calendar(id: String? = nil, name: String = "Personal calendar", override: String? = nil, role: String = "owner", zone: String = "Europe/Paris", primary: Bool = true) -> [String: Any] {
            var row: [String: Any] = ["id": id ?? calendarID, "summary": name, "timeZone": zone, "accessRole": role, "primary": primary]
            if let override { row["summaryOverride"] = override }; return row
        }
        func event() -> [String: Any] { ["id": "meeting", "status": "confirmed", "summary": "Morning meeting", "start": ["dateTime": "2026-03-29T11:00:00+02:00"], "end": ["dateTime": "2026-03-29T12:00:00+02:00"], "description": "OMITTED_PRIVATE_DESCRIPTION", "attendees": [["email": "OMITTED_PRIVATE_ATTENDEE"]]] }
    }
    private final class Tokens: ComposioTokenStoring {
        var value: String?
        init(_ value: String? = "SYNTHETIC_INSTALLATION_TOKEN") { self.value = value }
        func load() throws -> String? { value }
        func save(_ token: String) throws { value = token }
        func clear() throws { value = nil }
    }
}

private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
private func response(_ request: URLRequest, _ value: [String: Any]) -> (Data, HTTPURLResponse) {
    (try! JSONSerialization.data(withJSONObject: value), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
}
