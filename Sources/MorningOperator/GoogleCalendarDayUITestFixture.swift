import Foundation
import MorningApple
import MorningCore

/// Intercepted HTTP only. No live credential store, network fallback or provider write exists here.
@MainActor enum GoogleCalendarDayUITestFixture {
    #if DEBUG
    private(set) static var eventsReadCount = 0
    #else
    static var eventsReadCount: Int { 0 }
    #endif

    static var isRequested: Bool {
        #if DEBUG
        let flags = ProcessInfo.processInfo.arguments
        return flags.contains("--ui-testing") && flags.contains("--ui-testing-google-calendar-day")
        #else
        return false
        #endif
    }

    static func serviceIfRequested() -> ComposioService? {
        #if DEBUG
        guard isRequested else { return nil }
        eventsReadCount = 0
        let flags = ProcessInfo.processInfo.arguments
        let emptyAccount = flags.contains("--ui-testing-google-calendar-empty-account")
        let emptyDay = flags.contains("--ui-testing-google-calendar-empty-day")
        let partial = flags.contains("--ui-testing-google-calendar-partial")
        let unavailable = flags.contains("--ui-testing-google-calendar-unavailable")
        let connection = "ca_synthetic_google_calendar", cursor = "opaque-synthetic-calendar-page-two"
        let firstID = "synthetic-primary@calendar.invalid", secondID = "synthetic-second@group.calendar.invalid"
        let firstName = "SYNTHETIC calendrier personnel de préparation du matin avec un nom volontairement très long"
        let secondName = "SYNTHETIC deuxième page calendrier partagé de préparation du matin"
        return ComposioService(baseURL: URL(string: "https://synthetic-google-calendar.invalid")!,
            tokenStore: Tokens("synthetic-google-calendar-installation-token"), executionStore: Tokens(nil)) { request in
            guard let url = request.url, url.scheme == "https", url.host == "synthetic-google-calendar.invalid",
                  url.user == nil, url.password == nil, url.fragment == nil else { throw FixtureError.blocked }
            var payload: [String: Any]
            var status = 200
            switch (request.httpMethod, url.path) {
            case ("GET", "/v1/services"):
                guard url.query == nil else { throw FixtureError.blocked }
                payload = ["services": [["id": "googlecalendar", "name": "Google Calendar"]]]
            case ("GET", "/v1/connections"):
                guard url.query == nil else { throw FixtureError.blocked }
                payload = ["connections": emptyAccount ? [] : [["id": connection, "service": "googlecalendar", "name": "Google Calendar", "status": "ACTIVE",
                    "accountLabel": "SYNTHETIC compte Google de Camille pour la préparation du matin"]]]
            case ("GET", "/v1/tools"):
                let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                guard query.count == 1, query[0].name == "service", query[0].value == "googlecalendar" else { throw FixtureError.blocked }
                payload = ["tools": []]
            case ("POST", "/v1/execute"):
                guard url.query == nil, !emptyAccount, let body = request.httpBody, body.count <= 8_192,
                      let input = try JSONDecoder().decode(ComposioJSONValue.self, from: body).objectValue,
                      Set(input.keys) == Set(["connectionID", "tool", "requestID", "arguments"]),
                      input["connectionID"] == .string(connection), let requestID = input["requestID"]?.stringValue,
                      UUID(uuidString: requestID) != nil, let arguments = input["arguments"]?.objectValue else { throw FixtureError.blocked }
                let data: [String: Any]
                switch input["tool"]?.stringValue {
                case "GOOGLECALENDAR_LIST_CALENDARS":
                    guard Set(arguments.keys).isSubset(of: ["max_results", "min_access_role", "show_hidden", "show_deleted", "page_token"]),
                          arguments["max_results"] == .number(50), arguments["min_access_role"] == .string("reader"),
                          arguments["show_hidden"] == .bool(false), arguments["show_deleted"] == .bool(false) else { throw FixtureError.blocked }
                    if let page = arguments["page_token"] {
                        guard page == .string(cursor) else { throw FixtureError.blocked }
                        data = ["calendars": [calendar(secondID, secondName)], "next_page_token": ""]
                    } else {
                        data = ["calendars": [calendar(firstID, firstName, primary: true),
                            calendar("synthetic-freebusy@calendar.invalid", "SYNTHETIC disponibilités seules masquées", role: "freeBusyReader"),
                            calendar("synthetic-hidden@calendar.invalid", "SYNTHETIC calendrier masqué", hidden: true),
                            calendar("synthetic-deleted@calendar.invalid", "SYNTHETIC calendrier supprimé", deleted: true)], "next_page_token": cursor]
                    }
                case "GOOGLECALENDAR_EVENTS_LIST":
                    let fields = "kind,summary,timeZone,accessRole,nextPageToken,items(id,status,summary,start,end,location)"
                    guard Set(arguments.keys) == Set(["calendarId", "timeMin", "timeMax", "timeZone", "singleEvents", "orderBy", "showDeleted", "maxResults", "fields"]),
                          let id = arguments["calendarId"]?.stringValue, [firstID, secondID].contains(id),
                          let zoneID = arguments["timeZone"]?.stringValue, let zone = TimeZone(identifier: zoneID),
                          let from = arguments["timeMin"]?.stringValue, let to = arguments["timeMax"]?.stringValue,
                          let start = ISO8601DateFormatter().date(from: from),
                          let window = try? GoogleCalendarDayWindow(at: start, timeZone: zone),
                          window.timeMin == from, window.timeMax == to,
                          arguments["singleEvents"] == .bool(true), arguments["orderBy"] == .string("startTime"),
                          arguments["showDeleted"] == .bool(false), arguments["maxResults"] == .number(25), arguments["fields"] == .string(fields) else { throw FixtureError.blocked }
                    eventsReadCount += 1
                    if unavailable {
                        status = 503
                        payload = ["error": ["code": "provider_unavailable", "message": "SYNTHETIC calendar reading unavailable. No Google account is used."]]
                        let bytes = try JSONSerialization.data(withJSONObject: payload)
                        return (bytes, try response(url, status: status))
                    }
                    var result: [String: Any] = ["kind": "calendar#events", "summary": id == firstID ? firstName : secondName,
                        "timeZone": zoneID, "accessRole": "owner", "items": emptyDay ? [] : try events(window: window, zone: zone)]
                    if partial { result["nextPageToken"] = "opaque-synthetic-more-events-not-fetched" }
                    data = result
                default: throw FixtureError.blocked
                }
                payload = ["requestID": requestID, "successful": true, "data": data]
            default: throw FixtureError.blocked
            }
            return (try JSONSerialization.data(withJSONObject: payload), try response(url, status: status))
        }
        #else
        return nil
        #endif
    }

    #if DEBUG
    private enum FixtureError: Error { case blocked }
    private final class Tokens: ComposioTokenStoring {
        private var value: String?
        init(_ value: String?) { self.value = value }
        func load() throws -> String? { value }
        func save(_ token: String) throws { value = token }
        func clear() throws { value = nil }
    }
    private static func response(_ url: URL, status: Int) throws -> HTTPURLResponse {
        guard let value = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]) else { throw FixtureError.blocked }
        return value
    }
    private static func calendar(_ id: String, _ name: String, role: String = "owner", primary: Bool = false,
                                 hidden: Bool = false, deleted: Bool = false) -> [String: Any] {
        ["id": id, "kind": "calendar#calendarListEntry", "etag": "synthetic-etag", "summary": name,
         "accessRole": role, "primary": primary, "hidden": hidden, "deleted": deleted, "timeZone": "Europe/Paris"]
    }
    private static func events(window: GoogleCalendarDayWindow, zone: TimeZone) throws -> [[String: Any]] {
        let now = Date(), remaining = window.end.timeIntervalSince(now)
        guard now >= window.start, remaining > 60 else { throw FixtureError.blocked }
        let step = min(1_800, remaining / 6)
        let formatter = ISO8601DateFormatter()
        func timed(_ id: String, _ title: String, from: TimeInterval, to: TimeInterval) -> [String: Any] {
            ["id": id, "status": "confirmed", "summary": title, "location": "SYNTHETIC lieu de démonstration",
             "start": ["dateTime": formatter.string(from: now.addingTimeInterval(from))],
             "end": ["dateTime": formatter.string(from: now.addingTimeInterval(to))]]
        }
        let date = DateFormatter(); date.calendar = Calendar(identifier: .gregorian); date.locale = Locale(identifier: "en_US_POSIX")
        date.timeZone = zone; date.dateFormat = "yyyy-MM-dd"
        return [["id": "synthetic-all-day", "status": "confirmed", "summary": "SYNTHETIC journée de démonstration",
                 "start": ["date": date.string(from: window.start)], "end": ["date": date.string(from: window.end)]],
            timed("synthetic-event-one", "SYNTHETIC préparer les priorités du matin", from: step, to: step * 1.5),
            timed("synthetic-event-two", "SYNTHETIC échange de préparation de la journée", from: step * 3, to: step * 3.5)]
    }
    #endif
}
