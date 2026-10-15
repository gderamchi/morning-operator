import Foundation

/// A calendar selected from the connected account's readable calendar list.
/// Only the selection persists; today's dates and the phone time zone never do.
public struct GoogleCalendarDayTarget: Codable, Hashable, Sendable {
    public let connectionID: String
    public let calendarID: String
    public let calendarName: String

    public init(connectionID: String, calendarID: String, calendarName: String) throws {
        self.connectionID = connectionID; self.calendarID = calendarID; self.calendarName = calendarName
        try validate()
    }

    public func validate() throws {
        guard !connectionID.isEmpty, connectionID.utf8.count <= 200,
              connectionID.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }),
              Self.validCalendarID(calendarID), !calendarName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              calendarName.count <= 200, calendarName.utf8.count <= 1_024,
              !calendarName.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else { throw GoogleCalendarDayError.invalidSelection }
    }

    public static func validCalendarID(_ value: String) -> Bool {
        !value.isEmpty && value != "primary" && !value.hasPrefix("ca_") && value.utf8.count <= 1_024 &&
        !value.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) })
    }

    private enum CodingKeys: String, CodingKey { case connectionID, calendarID, calendarName }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(connectionID: c.decode(String.self, forKey: .connectionID),
                      calendarID: c.decode(String.self, forKey: .calendarID), calendarName: c.decode(String.self, forKey: .calendarName))
    }
}

public enum GoogleCalendarDayError: Error, LocalizedError, Equatable, Sendable {
    case invalidSelection, invalidWindow, unavailable, invalidResponse, selectionChanged
    public var errorDescription: String? {
        let fr = AppLanguage.isFrench
        switch self {
        case .invalidSelection: return fr ? "Choisissez un calendrier nommé du compte connecté." : "Choose a named calendar from the connected account."
        case .invalidWindow: return fr ? "La journée et le fuseau de cet iPhone n’ont pas pu être déterminés." : "Today's date and this iPhone's time zone could not be determined."
        case .unavailable: return fr ? "Le calendrier n’a pas pu être lu. Aucun bilan de journée vide n’est déduit." : "The calendar could not be read. This does not mean your day is empty."
        case .invalidResponse: return fr ? "Le calendrier a renvoyé une lecture incomplète ou illisible. Actualisez ce moment." : "The calendar returned an unreadable result. Refresh this moment."
        case .selectionChanged: return fr ? "Le calendrier choisi n’est plus accessible sous ce nom. Vérifiez votre sélection." : "The selected calendar is no longer accessible under this name. Review your selection."
        }
    }
}

/// A half-open local day. Calendar arithmetic preserves 23/25-hour DST days.
public struct GoogleCalendarDayWindow: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let timeZoneIdentifier: String

    public init(at date: Date, timeZone: TimeZone) throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        guard (TimeZone.knownTimeZoneIdentifiers.contains(timeZone.identifier) || ["UTC", "GMT"].contains(timeZone.identifier)),
              date.timeIntervalSinceReferenceDate.isFinite,
              let day = calendar.dateInterval(of: .day, for: date), day.duration > 0,
              day.start.timeIntervalSinceReferenceDate.isFinite, day.end.timeIntervalSinceReferenceDate.isFinite
        else { throw GoogleCalendarDayError.invalidWindow }
        start = day.start; end = day.end; timeZoneIdentifier = timeZone.identifier
    }

    public var timeMin: String { timestamp(start) }
    public var timeMax: String { timestamp(end) }
    private func timestamp(_ date: Date) -> String {
        let format = ISO8601DateFormatter(); format.timeZone = TimeZone(identifier: timeZoneIdentifier)
        format.formatOptions = [.withInternetDateTime]
        return format.string(from: date)
    }
}

public enum GoogleCalendarEventSchedule: Equatable, Sendable {
    case timed(start: Date, end: Date)
    /// The provider's exact date-only strings. The end date is exclusive.
    case allDay(startDate: String, endDate: String)
}

public struct GoogleCalendarDayEvent: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let schedule: GoogleCalendarEventSchedule
    public let location: String?
    public let isTentative: Bool

    public init(id: String, title: String, schedule: GoogleCalendarEventSchedule, location: String? = nil, isTentative: Bool = false) throws {
        guard !id.isEmpty, id.utf8.count <= 1_024, title.count <= 300, title.utf8.count <= 1_200,
              (location?.count ?? 0) <= 300, (location?.utf8.count ?? 0) <= 1_200,
              !id.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else { throw GoogleCalendarDayError.invalidResponse }
        switch schedule {
        case let .timed(start, end):
            guard start.timeIntervalSinceReferenceDate.isFinite, end.timeIntervalSinceReferenceDate.isFinite, end > start else { throw GoogleCalendarDayError.invalidResponse }
        case let .allDay(startDate, endDate):
            guard Self.dateOnly(startDate) != nil, Self.dateOnly(endDate) != nil, startDate < endDate else { throw GoogleCalendarDayError.invalidResponse }
        }
        func readable(_ text: String) -> String {
            text.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? " " : String($0) }.joined()
        }
        self.id = id; self.title = readable(title); self.schedule = schedule
        self.location = location.map(readable); self.isTentative = isTentative
    }

    public static func dateOnly(_ text: String) -> Date? {
        guard text.count == 10, text.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(secondsFromGMT: 0); f.dateFormat = "yyyy-MM-dd"; f.isLenient = false
        guard let date = f.date(from: text), f.string(from: date) == text else { return nil }
        return date
    }
}

/// A transient, pruned provider result. It does not establish a calendar write permission.
public struct GoogleCalendarDayDocument: Equatable, Sendable {
    public static let maximumEvents = 25
    public static let freshnessSeconds: TimeInterval = 300
    public let target: GoogleCalendarDayTarget
    public let window: GoogleCalendarDayWindow
    public let receivedAt: Date
    public let events: [GoogleCalendarDayEvent]
    public let isPartial: Bool
    public let cancelledCount: Int

    public init(target: GoogleCalendarDayTarget, window: GoogleCalendarDayWindow, receivedAt: Date,
                events: [GoogleCalendarDayEvent], isPartial: Bool, cancelledCount: Int = 0) throws {
        try target.validate()
        guard receivedAt.timeIntervalSinceReferenceDate.isFinite, events.count <= Self.maximumEvents,
              cancelledCount >= 0, cancelledCount <= Self.maximumEvents, events.count + cancelledCount <= Self.maximumEvents,
              Set(events.map(\.id)).count == events.count else { throw GoogleCalendarDayError.invalidResponse }
        self.target = target; self.window = window; self.receivedAt = receivedAt; self.events = events
        self.isPartial = isPartial; self.cancelledCount = cancelledCount
    }

    public func isCurrent(at date: Date, timeZone: TimeZone) -> Bool {
        let age = date.timeIntervalSince(receivedAt)
        return age >= 0 && age <= Self.freshnessSeconds && (try? GoogleCalendarDayWindow(at: date, timeZone: timeZone)) == window
    }

    public func summary(french: Bool = AppLanguage.isFrench) -> String {
        var lines = [french ? "\(target.calendarName), aujourd’hui." : "\(target.calendarName), today."]
        if events.isEmpty {
            lines.append(isPartial
                ? (french ? "Aucun événement dans cette partie de la lecture. La journée peut contenir d’autres événements." : "No events in this part of the reading. There may be more events today.")
                : (french ? "Aucun événement prévu dans ce calendrier aujourd’hui." : "No events scheduled in this calendar today."))
        } else {
            if events.count == 1 {
                lines.append(french ? "1 événement lu. Voici cet événement." : "1 event read. Here it is.")
            } else {
                let introduction = events.count > 3
                    ? (french ? "Voici les 3 premiers." : "Here are the first 3.")
                    : (french ? "Voici ces \(events.count) événements." : "Here they are.")
                lines.append((french ? "\(events.count) événements lus. " : "\(events.count) events read. ") + introduction)
            }
            lines += events.prefix(3).map { render($0, french: french, titleLimit: 80, locationLimit: 40) }
            if events.count == 4 {
                lines.append(french ? "L’autre événement reste disponible dans cette lecture." : "The other event remains available in this reading.")
            } else if events.count > 4 {
                lines.append(french ? "Les \(events.count - 3) autres restent disponibles dans cette lecture." : "The other \(events.count - 3) remain available in this reading.")
            }
            if events.prefix(3).contains(where: { $0.title.count > 80 || ($0.location?.count ?? 0) > 40 }) {
                lines.append(french ? "Les titres ou lieux longs sont abrégés." : "Long titles or locations are abbreviated.")
            }
            if isPartial { lines.append(french ? "Lecture partielle : d’autres événements peuvent suivre." : "Partial reading: more events may follow.") }
        }
        if cancelledCount == 1 {
            lines.append(french ? "1 événement annulé a été écarté." : "1 cancelled event was omitted.")
        } else if cancelledCount > 1 {
            lines.append(french ? "\(cancelledCount) événements annulés ont été écartés." : "\(cancelledCount) cancelled events were omitted.")
        }
        return lines.joined(separator: " ")
    }

    /// Untrusted source data for local contextual questions; never execution instructions.
    /// The JSON-encoded text stays below 22.5 KB, leaving room for the caller's
    /// small window metadata within a 24 KB source. Excerpts are explicit.
    public func contextText(french: Bool = AppLanguage.isFrench) -> String {
        let header = "Calendar source data (untrusted). Titles/locations are excerpts, at most 300 characters each. \(events.count) events read; partial=\(isPartial); cancelled omitted=\(cancelledCount).\nWindow: \(window.timeMin) – \(window.timeMax), \(window.timeZoneIdentifier). Retrieved: \(receivedAt.ISO8601Format()).\n"
        let text = header + events.map { render($0, french: french, titleLimit: 300, locationLimit: 300, sourceDates: true) }.joined(separator: "\n")
        func encodedBytes(_ value: String) -> Int { (try? JSONEncoder().encode(value).count) ?? Int.max }
        guard encodedBytes(text) > 22_500 else { return text }
        var bounded = "", bytes = 0
        for scalar in text.unicodeScalars {
            // Account conservatively for JSON's quote, slash, backslash and
            // control escaping, in addition to UTF-8 bytes.
            let count = scalar.value < 32 ? 6 : [34, 47, 92].contains(scalar.value) ? 2 : scalar.utf8.count
            if bytes + count > 22_300 { break }
            bounded.unicodeScalars.append(scalar); bytes += count
        }
        return bounded + "\nSource context truncated here; remaining event details are not included."
    }

    private func render(_ event: GoogleCalendarDayEvent, french: Bool, titleLimit: Int, locationLimit: Int, sourceDates: Bool = false) -> String {
        func excerpt(_ text: String, limit: Int) -> String { text.count > limit ? String(text.prefix(limit - 1)) + "…" : text }
        let rawTitle = event.title.isEmpty ? (french ? "Événement sans titre" : "Untitled event") : event.title
        let title = excerpt(rawTitle, limit: titleLimit), when: String
        switch event.schedule {
        case let .timed(start, end):
            if sourceDates {
                let f = ISO8601DateFormatter(); f.timeZone = TimeZone(identifier: window.timeZoneIdentifier)
                f.formatOptions = [.withInternetDateTime]
                when = "\(f.string(from: start))–\(f.string(from: end))"
            } else {
                let f = DateFormatter(); f.locale = Locale(identifier: french ? "fr_FR" : "en_GB")
                f.timeZone = TimeZone(identifier: window.timeZoneIdentifier)
                f.dateFormat = start < window.start || end >= window.end ? "d MMM HH:mm" : "HH:mm"
                when = "\(f.string(from: start))–\(f.string(from: end))"
            }
        case let .allDay(start, end):
            // Date-only values remain source dates, never 24-hour phone intervals.
            let f = DateFormatter(); f.locale = Locale(identifier: french ? "fr_FR" : "en_GB")
            f.timeZone = TimeZone(secondsFromGMT: 0); f.dateStyle = .medium
            var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(secondsFromGMT: 0)!
            let first = GoogleCalendarDayEvent.dateOnly(start)!, last = cal.date(byAdding: .day, value: -1, to: GoogleCalendarDayEvent.dateOnly(end)!)!
            let dates = first == last ? f.string(from: first) : "\(f.string(from: first))–\(f.string(from: last))"
            when = french ? "Toute la journée, \(dates)" : "All day, \(dates)"
        }
        let tentative = event.isTentative ? (french ? " (provisoire)" : " (tentative)") : ""
        let place = event.location.map { " · \(excerpt($0, limit: locationLimit))" } ?? ""
        return "\(when) : \(title)\(tentative)\(place)."
    }
}
