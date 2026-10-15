import Foundation
import MorningCore

public struct CalendlyIdentity: Equatable, Sendable {
    public let target: CalendlyDayTarget
    public let receivedAt: Date
    public var connectionID: String { target.connectionID }
    public var userURI: String { target.userURI }
    public var userName: String { target.userName }
    public init(target: CalendlyDayTarget, receivedAt: Date) throws {
        try target.validate()
        guard receivedAt.timeIntervalSinceReferenceDate.isFinite else { throw CalendlyDayError.invalidIdentity }
        self.target = target; self.receivedAt = receivedAt
    }
    public func isCurrent(at date: Date) -> Bool { (0...300).contains(date.timeIntervalSince(receivedAt)) }
}

/// The two non-deprecated read operations in Calendly pin 20260929_00.
/// No scheduling, cancellation, invitee lookup or arbitrary provider URL is used.
@MainActor public final class CalendlyDayService {
    private let service: ComposioService
    private let now: @MainActor () -> Date
    private let phoneTimeZone: @MainActor () -> TimeZone
    private let timeout: Duration
    public init(service: ComposioService, now: @escaping @MainActor () -> Date = { Date() },
                timeZone: @escaping @MainActor () -> TimeZone = { .current }, readTimeout: Duration = .seconds(40)) {
        self.service = service; self.now = now; phoneTimeZone = timeZone
        timeout = min(.seconds(45), max(.milliseconds(1), readTimeout))
    }
    public func identity(connectionID: String) async throws -> CalendlyIdentity {
        try await withThrowingTaskGroup(of: CalendlyIdentity.self) { group in
            group.addTask { try await self.readIdentity(connectionID) }
            group.addTask { [timeout] in try await Task.sleep(for: timeout); throw CalendlyDayError.unavailable }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw CalendlyDayError.unavailable }; return result
        }
    }
    public func read(target: CalendlyDayTarget, at date: Date? = nil, timeZone: TimeZone? = nil) async throws -> CalendlyDayDocument {
        try target.validate()
        let window = try CalendlyDayWindow(at: date ?? now(), timeZone: timeZone ?? phoneTimeZone())
        return try await withThrowingTaskGroup(of: CalendlyDayDocument.self) { group in
            group.addTask { try await self.readWindow(target, window: window) }
            group.addTask { [timeout] in try await Task.sleep(for: timeout); throw CalendlyDayError.unavailable }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw CalendlyDayError.unavailable }; return result
        }
    }
    private func readIdentity(_ connectionID: String) async throws -> CalendlyIdentity {
        try await checkConnection(connectionID)
        let result = try await service.readCalendly(tool: CalendlyDayReadContract.identityTool, arguments: [:], connectionID: connectionID)
        try Task.checkCancellation()
        // WHO_AM_I's provider payload has another typed `data` object. It is
        // intentionally different from the deprecated GET_CURRENT_USER resource.
        let p = try Self.payload(result)
        guard let identity = p["data"]?.objectValue, let uri = identity["uri"]?.stringValue,
              let name = identity["name"]?.stringValue else { throw CalendlyDayError.invalidIdentity }
        let target = try CalendlyDayTarget(connectionID: connectionID, userURI: uri, userName: name)
        try await checkConnection(connectionID)
        return try .init(target: target, receivedAt: now())
    }
    private func readWindow(_ target: CalendlyDayTarget, window: CalendlyDayWindow) async throws -> CalendlyDayDocument {
        let before = try await readIdentity(target.connectionID)
        guard before.target == target, before.isCurrent(at: now()) else { throw CalendlyDayError.identityChanged }
        let result = try await service.readCalendly(tool: CalendlyDayReadContract.eventsTool,
            arguments: CalendlyDayReadContract.arguments(target: target, window: window), connectionID: target.connectionID)
        try Task.checkCancellation()
        let p = try Self.payload(result)
        guard let rows = p["collection"]?.arrayValue, rows.count <= 25, let pagination = p["pagination"]?.objectValue,
              pagination["count"] == .number(Decimal(rows.count)) else { throw CalendlyDayError.invalidResponse }
        let partial = try Self.hasContinuation(pagination)
        var events: [CalendlyDayEvent] = [], seen: Set<String> = [], excluded = 0, cancelled = 0
        for row in rows {
            guard let event = row.objectValue, let uri = event["uri"]?.stringValue,
                  CalendlyDayTarget.validURI(uri, resource: "scheduled_events"), seen.insert(uri).inserted,
                  let memberships = event["event_memberships"]?.arrayValue, memberships.count <= 100,
                  memberships.contains(where: { $0.objectValue?["user"] == .string(target.userURI) }),
                  let status = event["status"]?.stringValue, ["active", "canceled"].contains(status),
                  let first = event["start_time"]?.stringValue, let last = event["end_time"]?.stringValue,
                  let start = CalendlyDayReadContract.timestamp(first), let end = CalendlyDayReadContract.timestamp(last), end > start,
                  start >= window.start.addingTimeInterval(-1), start <= window.end,
                  let name = event["name"]?.stringValue else { throw CalendlyDayError.invalidResponse }
            if status == "canceled" { cancelled += 1; continue }
            guard start >= window.start, start < window.end else { excluded += 1; continue }
            let location: CalendlyDayLocationKind
            if let raw = event["location"], raw != .null {
                guard let data = raw.objectValue else { throw CalendlyDayError.invalidResponse }
                if let type = data["type"], type.stringValue == nil { throw CalendlyDayError.invalidResponse }
                switch data["type"]?.stringValue {
                case "physical": location = .inPerson
                case "google_conference", "zoom_conference", "gotomeeting", "microsoft_teams_conference", "microsoft_teams", "webex_conference": location = .video
                case "inbound_call", "outbound_call": location = .phone
                default: location = .unspecified
                }
            } else { location = .unspecified }
            let excerpt = Self.nameExcerpt(name)
            events.append(try .init(uri: uri, name: excerpt, start: start, end: end, locationKind: location))
        }
        let after = try await readIdentity(target.connectionID)
        guard after.target == target else { throw CalendlyDayError.identityChanged }
        guard (try? CalendlyDayWindow(at: now(), timeZone: phoneTimeZone())) == window else { throw CalendlyDayError.invalidWindow }
        guard before.isCurrent(at: now()), after.isCurrent(at: now()) else { throw CalendlyDayError.unavailable }
        events.sort { $0.start != $1.start ? $0.start < $1.start : $0.uri < $1.uri }
        let document = try CalendlyDayDocument(target: target, window: window, receivedAt: now(), events: events, isPartial: partial,
                                             excludedCount: excluded, cancelledCount: cancelled)
        guard document.isCurrent(at: now(), timeZone: phoneTimeZone()) else { throw CalendlyDayError.invalidWindow }
        return document
    }
    private func checkConnection(_ id: String) async throws {
        try Task.checkCancellation()
        let list = try await service.connections()
        try Task.checkCancellation()
        let matching = list.filter { $0.id == id }
        guard matching.count == 1, matching[0].service == "calendly", matching[0].isActive else { throw CalendlyDayError.unavailable }
    }
    private static func payload(_ result: ComposioExecutionResult) throws -> [String: ComposioJSONValue] {
        guard result.successful, result.resultAvailable != false, var p = result.data?.objectValue else { throw CalendlyDayError.unavailable }
        for _ in 0..<3 {
            guard p["error"] == nil || p["error"] == .null || p["error"] == .string("") else { throw CalendlyDayError.unavailable }
            guard let successful = p["successful"] else { return p }
            guard successful == .bool(true), let nested = p["data"]?.objectValue else { throw CalendlyDayError.unavailable }; p = nested
        }
        guard p["successful"] == nil else { throw CalendlyDayError.invalidResponse }; return p
    }
    private static func hasContinuation(_ p: [String: ComposioJSONValue]) throws -> Bool {
        var partial = false
        if let value = p["next_page_token"], value != .null {
            guard let token = value.stringValue, token.utf8.count <= 2_048,
                  !token.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw CalendlyDayError.invalidResponse }
            partial = !token.isEmpty
        }
        if let value = p["next_page"], value != .null {
            guard let text = value.stringValue, text.utf8.count <= 4_096 else { throw CalendlyDayError.invalidResponse }
            if !text.isEmpty {
                guard let url = URL(string: text), url.scheme == "https", url.host == "api.calendly.com", url.port == nil,
                      url.user == nil, url.password == nil, url.fragment == nil, url.path == "/scheduled_events" else { throw CalendlyDayError.invalidResponse }
                partial = true // Never follow this URL or manufacture a page token.
            }
        }
        return partial
    }
    private static func nameExcerpt(_ name: String) -> String {
        let text = name.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? " " : String($0) }.joined()
        if text.count <= 300, text.utf8.count <= 1_200 { return text }
        var excerpt = "", bytes = 0, characters = 0
        for character in text {
            let piece = String(character)
            if characters >= 299 || bytes + piece.utf8.count > 1_197 { break }
            excerpt += piece; bytes += piece.utf8.count; characters += 1
        }
        return excerpt + "…"
    }
}

enum CalendlyDayReadContract {
    static let identityTool = "CALENDLY_WHO_AM_I", eventsTool = "CALENDLY_LIST_SCHEDULED_EVENTS"
    static func arguments(target: CalendlyDayTarget, window: CalendlyDayWindow) -> [String: ComposioJSONValue] {
        ["user": .string(target.userURI), "status": .string("active"), "count": .number(25), "sort": .string("start_time:asc"),
         "min_start_time": .string(window.minStartTime), "max_start_time": .string(window.maxStartTime)]
    }
    static func validRead(_ tool: String, _ args: [String: ComposioJSONValue]) -> Bool {
        if tool == identityTool { return args.isEmpty }
        guard tool == eventsTool, Set(args.keys) == Set(["user", "status", "count", "sort", "min_start_time", "max_start_time"]),
              let user = args["user"]?.stringValue, CalendlyDayTarget.validURI(user, resource: "users"),
              args["status"] == .string("active"), args["count"] == .number(25), args["sort"] == .string("start_time:asc"),
              let lower = args["min_start_time"]?.stringValue, lower.hasSuffix("Z"), let first = timestamp(lower),
              let upper = args["max_start_time"]?.stringValue, upper.hasSuffix("Z"), let last = timestamp(upper) else { return false }
        return (23 * 3_600 + 1...25 * 3_600 + 1).contains(last.timeIntervalSince(first))
    }
    static func timestamp(_ text: String) -> Date? {
        guard text.utf8.count <= 100, text.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$"#, options: .regularExpression) != nil else { return nil }
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = f.date(from: text) { return date }
        f.formatOptions = [.withInternetDateTime]; return f.date(from: text)
    }
}
