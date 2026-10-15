import Foundation
import MorningCore

public struct GoogleCalendarChoice: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let timeZoneIdentifier: String?
    public let isPrimary: Bool
    public init(id: String, name: String, timeZoneIdentifier: String? = nil, isPrimary: Bool = false) throws {
        _ = try GoogleCalendarDayTarget(connectionID: "calendar_selection", calendarID: id, calendarName: name)
        guard timeZoneIdentifier == nil || timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) != nil else { throw GoogleCalendarDayError.invalidResponse }
        self.id = id; self.name = name; self.timeZoneIdentifier = timeZoneIdentifier; self.isPrimary = isPrimary
    }
    public func target(connectionID: String) throws -> GoogleCalendarDayTarget {
        try .init(connectionID: connectionID, calendarID: id, calendarName: name)
    }
}

public struct GoogleCalendarChoicesPage: Equatable, Sendable {
    public let choices: [GoogleCalendarChoice]
    public let nextCursor: String?
    public init(choices: [GoogleCalendarChoice], nextCursor: String? = nil) throws {
        guard choices.count <= 50, Set(choices.map(\.id)).count == choices.count,
              nextCursor == nil || nextCursor.map(GoogleCalendarReadContract.validCursor) == true else { throw GoogleCalendarDayError.invalidResponse }
        self.choices = choices; self.nextCursor = nextCursor
    }
}

/// Fixed read-only Google Calendar operations, pinned by the server catalog.
/// This service neither requests authorization nor creates or edits an event.
@MainActor public final class GoogleCalendarDayService {
    private let service: ComposioService
    private let now: @MainActor () -> Date
    private let phoneTimeZone: @MainActor () -> TimeZone
    private let readTimeout: Duration

    public init(service: ComposioService, now: @escaping @MainActor () -> Date = { Date() },
                timeZone: @escaping @MainActor () -> TimeZone = { .current }, readTimeout: Duration = .seconds(40)) {
        self.service = service; self.now = now; phoneTimeZone = timeZone
        self.readTimeout = min(.seconds(45), max(.milliseconds(1), readTimeout))
    }

    public func calendars(connectionID: String, cursor: String? = nil) async throws -> GoogleCalendarChoicesPage {
        try await checkConnection(connectionID)
        var args = GoogleCalendarReadContract.calendarArguments
        if let cursor { guard GoogleCalendarReadContract.validCursor(cursor) else { throw GoogleCalendarDayError.invalidResponse }; args["page_token"] = .string(cursor) }
        let result = try await service.readGoogleCalendar(tool: GoogleCalendarReadContract.listTool, arguments: args, connectionID: connectionID)
        try Task.checkCancellation()
        let payload = try Self.payload(result)
        guard payload["nextPageToken"] == nil, let rows = payload["calendars"]?.arrayValue, rows.count <= 50 else { throw GoogleCalendarDayError.invalidResponse }
        var choices: [GoogleCalendarChoice] = [], ids: Set<String> = []
        for row in rows {
            guard let item = row.objectValue,
                  let id = item["id"]?.stringValue, GoogleCalendarDayTarget.validCalendarID(id), ids.insert(id).inserted,
                  let role = item["accessRole"]?.stringValue,
                  Self.optionalBool(item["deleted"]) != nil, Self.optionalBool(item["hidden"]) != nil,
                  Self.optionalBool(item["primary"]) != nil else { throw GoogleCalendarDayError.invalidResponse }
            if Self.optionalBool(item["deleted"]) == true || Self.optionalBool(item["hidden"]) == true || role == "freeBusyReader" { continue }
            guard ["reader", "writerWithoutPrivateAccess", "writer", "owner"].contains(role) else { throw GoogleCalendarDayError.invalidResponse }
            let name: String
            if let override = item["summaryOverride"], override != .null {
                guard let text = override.stringValue else { throw GoogleCalendarDayError.invalidResponse }; name = text
            } else {
                guard let text = item["summary"]?.stringValue else { throw GoogleCalendarDayError.invalidResponse }; name = text
            }
            // A nameless row cannot become a destination labelled with an internal ID.
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            _ = try GoogleCalendarDayTarget(connectionID: connectionID, calendarID: id, calendarName: name)
            let zone: String?
            if let value = item["timeZone"], value != .null {
                guard let text = value.stringValue, TimeZone(identifier: text) != nil else { throw GoogleCalendarDayError.invalidResponse }; zone = text
            } else { zone = nil }
            choices.append(try .init(id: id, name: name, timeZoneIdentifier: zone, isPrimary: Self.optionalBool(item["primary"]) == true))
        }
        let next = try Self.cursor(payload["next_page_token"])
        try await checkConnection(connectionID)
        return try .init(choices: choices, nextCursor: next)
    }

    public func read(target: GoogleCalendarDayTarget, at date: Date? = nil, timeZone: TimeZone? = nil) async throws -> GoogleCalendarDayDocument {
        try target.validate()
        // Resolve once before any suspension. A late result cannot move to tomorrow.
        let window = try GoogleCalendarDayWindow(at: date ?? now(), timeZone: timeZone ?? phoneTimeZone())
        return try await withThrowingTaskGroup(of: GoogleCalendarDayDocument.self) { group in
            group.addTask { try await self.readWindow(target: target, window: window) }
            group.addTask { [readTimeout] in try await Task.sleep(for: readTimeout); throw GoogleCalendarDayError.unavailable }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw GoogleCalendarDayError.unavailable }
            return result
        }
    }

    private func readWindow(target: GoogleCalendarDayTarget, window: GoogleCalendarDayWindow) async throws -> GoogleCalendarDayDocument {
        try Task.checkCancellation()
        // Re-validate the saved ID/name against real current calendar choices. A bounded
        // scan supports later pages without broadening a missing ID to "primary".
        var cursor: String?, seen: Set<String> = [], selected: GoogleCalendarChoice?
        for _ in 0..<10 {
            let page = try await calendars(connectionID: target.connectionID, cursor: cursor)
            if let choice = page.choices.first(where: { $0.id == target.calendarID }) {
                guard choice.name == target.calendarName else { throw GoogleCalendarDayError.selectionChanged }
                selected = choice; break
            }
            guard let next = page.nextCursor else { break }
            guard seen.insert(next).inserted else { throw GoogleCalendarDayError.invalidResponse }; cursor = next
        }
        guard let selected else { throw GoogleCalendarDayError.selectionChanged }
        let result = try await service.readGoogleCalendar(tool: GoogleCalendarReadContract.eventsTool,
            arguments: GoogleCalendarReadContract.eventArguments(target: target, window: window), connectionID: target.connectionID)
        try Task.checkCancellation()
        let p = try Self.payload(result)
        if let kind = p["kind"], kind != .string("calendar#events") { throw GoogleCalendarDayError.invalidResponse }
        if let role = p["accessRole"] {
            guard let text = role.stringValue, ["reader", "writerWithoutPrivateAccess", "writer", "owner"].contains(text) else { throw GoogleCalendarDayError.unavailable }
        }
        guard p["next_page_token"] == nil, let rows = p["items"]?.arrayValue, rows.count <= GoogleCalendarDayDocument.maximumEvents else { throw GoogleCalendarDayError.invalidResponse }
        let partial = try Self.cursor(p["nextPageToken"]) != nil
        var events: [GoogleCalendarDayEvent] = [], cancelled = 0, ids: Set<String> = []
        for row in rows {
            guard let item = row.objectValue, let status = item["status"]?.stringValue,
                  ["confirmed", "tentative", "cancelled"].contains(status) else { throw GoogleCalendarDayError.invalidResponse }
            if status == "cancelled" { cancelled += 1; continue }
            guard let id = item["id"]?.stringValue, ids.insert(id).inserted,
                  let start = item["start"]?.objectValue, let end = item["end"]?.objectValue else { throw GoogleCalendarDayError.invalidResponse }
            let schedule: GoogleCalendarEventSchedule
            if let first = start["date"]?.stringValue, let last = end["date"]?.stringValue,
               start["dateTime"] == nil, end["dateTime"] == nil {
                guard let sourceZoneID = selected.timeZoneIdentifier, let sourceZone = TimeZone(identifier: sourceZoneID),
                      Self.allDayOverlaps(first, last, sourceZone: sourceZone, window: window) else { throw GoogleCalendarDayError.invalidResponse }
                schedule = .allDay(startDate: first, endDate: last)
            } else if start["date"] == nil, end["date"] == nil,
                      let first = start["dateTime"]?.stringValue, let last = end["dateTime"]?.stringValue,
                      let from = Self.timestamp(first), let to = Self.timestamp(last), to > window.start, from < window.end {
                schedule = .timed(start: from, end: to)
            } else { throw GoogleCalendarDayError.invalidResponse }
            let title = try Self.text(item["summary"], maximum: 300) ?? ""
            let place = try Self.text(item["location"], maximum: 300)
            events.append(try .init(id: id, title: title, schedule: schedule, location: place, isTentative: status == "tentative"))
        }
        try await checkConnection(target.connectionID)
        let document = try GoogleCalendarDayDocument(target: target, window: window, receivedAt: now(), events: events, isPartial: partial, cancelledCount: cancelled)
        guard document.isCurrent(at: now(), timeZone: phoneTimeZone()) else { throw GoogleCalendarDayError.invalidWindow }
        return document
    }

    private func checkConnection(_ id: String) async throws {
        try Task.checkCancellation()
        let rows = try await service.connections()
        try Task.checkCancellation()
        guard rows.contains(where: { $0.id == id && $0.service == "googlecalendar" && $0.isActive }) else { throw GoogleCalendarDayError.unavailable }
    }
    private static func payload(_ result: ComposioExecutionResult) throws -> [String: ComposioJSONValue] {
        guard result.successful, result.resultAvailable != false, var p = result.data?.objectValue else { throw GoogleCalendarDayError.unavailable }
        for _ in 0..<3 {
            guard p["error"] == nil || p["error"] == .null || p["error"] == .string("") else { throw GoogleCalendarDayError.unavailable }
            guard let success = p["successful"] else { return p }
            guard success == .bool(true), p["error"] == nil || p["error"] == .null || p["error"] == .string(""),
                  let data = p["data"]?.objectValue else { throw GoogleCalendarDayError.unavailable }; p = data
        }
        guard p["successful"] == nil else { throw GoogleCalendarDayError.invalidResponse }
        return p
    }
    private static func optionalBool(_ value: ComposioJSONValue?) -> Bool? { value == nil || value == .null ? false : value?.boolValue }
    private static func cursor(_ value: ComposioJSONValue?) throws -> String? {
        guard let value, value != .null else { return nil }
        guard let text = value.stringValue, text.isEmpty || GoogleCalendarReadContract.validCursor(text) else { throw GoogleCalendarDayError.invalidResponse }
        return text.isEmpty ? nil : text
    }
    private static func text(_ value: ComposioJSONValue?, maximum: Int) throws -> String? {
        guard let value, value != .null else { return nil }
        guard let text = value.stringValue else { throw GoogleCalendarDayError.invalidResponse }
        // Keep a disclosed source excerpt, never a provider description or attendees.
        return text.count > maximum ? String(text.prefix(maximum - 1)) + "…" : text
    }
    private static func allDayOverlaps(_ start: String, _ end: String, sourceZone: TimeZone, window: GoogleCalendarDayWindow) -> Bool {
        guard GoogleCalendarDayEvent.dateOnly(start) != nil, GoogleCalendarDayEvent.dateOnly(end) != nil, start < end else { return false }
        var c = Calendar(identifier: .gregorian); c.timeZone = sourceZone
        func boundary(_ text: String) -> Date? {
            let parts = text.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3 else { return nil }
            return c.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        }
        guard let first = boundary(start), let last = boundary(end) else { return false }
        return first < window.end && last > window.start
    }
    private static func timestamp(_ text: String) -> Date? {
        guard text.utf8.count <= 100, text.range(of: #"T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$"#, options: .regularExpression) != nil else { return nil }
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = f.date(from: text) { return date }
        f.formatOptions = [.withInternetDateTime]; return f.date(from: text)
    }
}

enum GoogleCalendarReadContract {
    static let listTool = "GOOGLECALENDAR_LIST_CALENDARS", eventsTool = "GOOGLECALENDAR_EVENTS_LIST"
    static let fields = "kind,summary,timeZone,accessRole,nextPageToken,items(id,status,summary,start,end,location)"
    static let calendarArguments: [String: ComposioJSONValue] = ["max_results": .number(50), "min_access_role": .string("reader"), "show_hidden": .bool(false), "show_deleted": .bool(false)]
    static func validCursor(_ text: String) -> Bool { !text.isEmpty && text.utf8.count <= 2_048 && !text.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) }
    static func eventArguments(target: GoogleCalendarDayTarget, window: GoogleCalendarDayWindow) -> [String: ComposioJSONValue] {
        ["calendarId": .string(target.calendarID), "timeMin": .string(window.timeMin), "timeMax": .string(window.timeMax),
         "timeZone": .string(window.timeZoneIdentifier), "singleEvents": .bool(true), "orderBy": .string("startTime"),
         "showDeleted": .bool(false), "maxResults": .number(25), "fields": .string(fields)]
    }
    static func validRead(_ tool: String, _ args: [String: ComposioJSONValue]) -> Bool {
        if tool == listTool {
            let allowed = Set(calendarArguments.keys).union(["page_token"])
            guard Set(args.keys).isSubset(of: allowed), calendarArguments.allSatisfy({ args[$0.key] == $0.value }) else { return false }
            return args["page_token"] == nil || args["page_token"]?.stringValue.map(validCursor) == true
        }
        guard tool == eventsTool, Set(args.keys) == Set(["calendarId", "timeMin", "timeMax", "timeZone", "singleEvents", "orderBy", "showDeleted", "maxResults", "fields"]),
              let id = args["calendarId"]?.stringValue, GoogleCalendarDayTarget.validCalendarID(id),
              let from = args["timeMin"]?.stringValue, let to = args["timeMax"]?.stringValue,
              let zoneID = args["timeZone"]?.stringValue, let zone = TimeZone(identifier: zoneID),
              args["singleEvents"] == .bool(true), args["orderBy"] == .string("startTime"), args["showDeleted"] == .bool(false),
              args["maxResults"] == .number(25), args["fields"] == .string(fields) else { return false }
        let f = ISO8601DateFormatter()
        guard let start = f.date(from: from), let end = f.date(from: to), let window = try? GoogleCalendarDayWindow(at: start, timeZone: zone) else { return false }
        return window.start == start && window.end == end && window.timeMin == from && window.timeMax == to
    }
}
