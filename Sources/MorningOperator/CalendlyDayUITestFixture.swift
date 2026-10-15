import Foundation
import MorningApple
import MorningCore

/// Intercepted HTTP only, without live credentials, network fallback or writes.
@MainActor enum CalendlyDayUITestFixture {
    #if DEBUG
    private(set) static var eventsReadCount = 0
    #else
    static var eventsReadCount: Int { 0 }
    #endif

    static var isRequested: Bool {
        #if DEBUG
        let flags = ProcessInfo.processInfo.arguments
        return flags.contains("--ui-testing") && flags.contains("--ui-testing-calendly-day")
        #else
        return false
        #endif
    }

    static func serviceIfRequested() -> ComposioService? {
        #if DEBUG
        guard isRequested else { return nil }
        eventsReadCount = 0
        let flags = ProcessInfo.processInfo.arguments
        let emptyAccount = flags.contains("--ui-testing-calendly-empty-account")
        let emptyDay = flags.contains("--ui-testing-calendly-empty-day")
        let partial = flags.contains("--ui-testing-calendly-partial")
        let unavailable = flags.contains("--ui-testing-calendly-unavailable")
        let connection = "ca_synthetic_calendly"
        let userURI = "https://api.calendly.com/users/synthetic-local-owner"
        let userName = "SYNTHETIC Camille, compte de préparation du matin avec un nom volontairement très long"
        return ComposioService(baseURL: URL(string: "https://synthetic-calendly.invalid")!,
            tokenStore: Tokens("synthetic-calendly-installation-token"), executionStore: Tokens(nil)) { request in
            guard let url = request.url, url.scheme == "https", url.host == "synthetic-calendly.invalid", url.port == nil,
                  url.user == nil, url.password == nil, url.fragment == nil else { throw FixtureError.blocked }
            var payload: [String: Any]
            var status = 200
            switch (request.httpMethod, url.path) {
            case ("GET", "/v1/services"):
                guard url.query == nil else { throw FixtureError.blocked }
                payload = ["services": [["id": "calendly", "name": "Calendly"]]]
            case ("GET", "/v1/connections"):
                guard url.query == nil else { throw FixtureError.blocked }
                payload = ["connections": emptyAccount ? [] : [["id": connection, "service": "calendly", "name": "Calendly", "status": "ACTIVE",
                    "accountLabel": "SYNTHETIC compte Calendly de préparation du matin"]]]
            case ("GET", "/v1/tools"):
                let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                guard query.count == 1, query[0].name == "service", query[0].value == "calendly" else { throw FixtureError.blocked }
                payload = ["tools": []]
            case ("POST", "/v1/execute"):
                guard url.query == nil, !emptyAccount, let body = request.httpBody, body.count <= 8_192,
                      let input = try JSONDecoder().decode(ComposioJSONValue.self, from: body).objectValue,
                      Set(input.keys) == Set(["connectionID", "tool", "requestID", "arguments"]),
                      input["connectionID"] == .string(connection), let requestID = input["requestID"]?.stringValue,
                      UUID(uuidString: requestID) != nil, let arguments = input["arguments"]?.objectValue else { throw FixtureError.blocked }
                let data: [String: Any]
                switch input["tool"]?.stringValue {
                case "CALENDLY_WHO_AM_I":
                    guard arguments.isEmpty else { throw FixtureError.blocked }
                    data = ["data": ["uri": userURI, "name": userName], "display_name": userName]
                case "CALENDLY_LIST_SCHEDULED_EVENTS":
                    guard Set(arguments.keys) == Set(["user", "status", "count", "sort", "min_start_time", "max_start_time"]),
                          arguments["user"] == .string(userURI), arguments["status"] == .string("active"),
                          arguments["count"] == .number(25), arguments["sort"] == .string("start_time:asc"),
                          let lower = arguments["min_start_time"]?.stringValue, lower.hasSuffix("Z"),
                          let start = ISO8601DateFormatter().date(from: lower),
                          let upper = arguments["max_start_time"]?.stringValue, upper.hasSuffix("Z"),
                          let window = try? CalendlyDayWindow(at: start.addingTimeInterval(1), timeZone: .current),
                          window.minStartTime == lower, window.maxStartTime == upper else { throw FixtureError.blocked }
                    eventsReadCount += 1
                    if unavailable {
                        status = 503
                        payload = ["error": ["code": "provider_unavailable", "message": "SYNTHETIC Calendly reading unavailable. No Calendly account is used."]]
                        return (try JSONSerialization.data(withJSONObject: payload), try response(url, status: status))
                    }
                    let collection = emptyDay ? [] : events(window: window, userURI: userURI)
                    var pagination: [String: Any] = ["count": collection.count]
                    if partial { pagination["next_page_token"] = "opaque-synthetic-more-appointments-not-fetched" }
                    data = ["collection": collection, "pagination": pagination]
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
    private static func events(window: CalendlyDayWindow, userURI: String) -> [[String: Any]] {
        func event(_ id: String, name: String, start: Date, end: Date, location: String) -> [String: Any] {
            ["uri": "https://api.calendly.com/scheduled_events/\(id)", "name": name, "status": "active",
             "start_time": start.ISO8601Format(), "end_time": end.ISO8601Format(),
             "event_memberships": [["user": userURI]], "location": ["type": location]]
        }
        let span = window.end.timeIntervalSince(window.start)
        return [
            event("synthetic-midnight", name: "SYNTHETIC début de journée", start: window.start,
                  end: window.start.addingTimeInterval(1_800), location: "physical"),
            event("synthetic-preparation", name: "SYNTHETIC préparer les priorités du matin", start: window.start.addingTimeInterval(span / 3),
                  end: window.start.addingTimeInterval(span / 3 + 1_800), location: "zoom_conference"),
            event("synthetic-overnight", name: "SYNTHETIC échange de fin de journée", start: window.end.addingTimeInterval(-1_800),
                  end: window.end.addingTimeInterval(1_800), location: "outbound_call")
        ]
    }
    #endif
}
