import Foundation

/// The provider identity reviewed with a connected Calendly account. No date or
/// time zone is saved: every reading resolves today's phone day again.
public struct CalendlyDayTarget: Codable, Hashable, Sendable {
    public let connectionID: String
    public let userURI: String
    public let userName: String

    public init(connectionID: String, userURI: String, userName: String) throws {
        self.connectionID = connectionID; self.userURI = userURI; self.userName = userName
        try validate()
    }
    public func validate() throws {
        guard !connectionID.isEmpty, connectionID.utf8.count <= 200,
              connectionID.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }),
              Self.validURI(userURI, resource: "users"), !userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              userName.count <= 200, userName.utf8.count <= 1_024,
              !userName.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else { throw CalendlyDayError.invalidIdentity }
    }
    public static func validURI(_ text: String, resource: String) -> Bool {
        guard text.utf8.count <= 500, let url = URL(string: text), url.scheme == "https", url.host == "api.calendly.com",
              url.port == nil, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { return false }
        let pieces = url.path.split(separator: "/", omittingEmptySubsequences: true)
        guard pieces.count == 2, pieces[0] == resource, (3...200).contains(pieces[1].count),
              pieces[1].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }) else { return false }
        return text == "https://api.calendly.com/\(resource)/\(pieces[1])"
    }
    private enum CodingKeys: String, CodingKey { case connectionID, userURI, userName }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(connectionID: c.decode(String.self, forKey: .connectionID), userURI: c.decode(String.self, forKey: .userURI), userName: c.decode(String.self, forKey: .userName))
    }
}

public enum CalendlyDayError: Error, LocalizedError, Equatable, Sendable {
    case invalidIdentity, invalidWindow, unavailable, invalidResponse, identityChanged
    public var errorDescription: String? {
        let fr = AppLanguage.isFrench
        switch self {
        case .invalidIdentity: return fr ? "Le nom et l’identité de ce compte Calendly n’ont pas pu être vérifiés." : "This Calendly account's name and identity could not be verified."
        case .invalidWindow: return fr ? "La journée ou le fuseau de cet iPhone a changé. Actualisez la lecture Calendly." : "Today's date or this iPhone's time zone changed. Refresh the Calendly reading."
        case .unavailable: return fr ? "Calendly n’a pas pu être lu. Cela ne signifie pas que vous n’avez aucun rendez-vous." : "Calendly could not be read. This does not mean you have no appointments."
        case .invalidResponse: return fr ? "La réponse Calendly n’a pas pu être vérifiée. Actualisez la lecture." : "The Calendly result could not be verified. Refresh this reading."
        case .identityChanged: return fr ? "L’identité du compte Calendly a changé. Vérifiez le compte avant une nouvelle lecture." : "The Calendly account identity changed. Review the account before reading again."
        }
    }
}

public struct CalendlyDayWindow: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let timeZoneIdentifier: String
    public init(at date: Date, timeZone: TimeZone) throws {
        guard let day = try? GoogleCalendarDayWindow(at: date, timeZone: timeZone) else { throw CalendlyDayError.invalidWindow }
        start = day.start; end = day.end; timeZoneIdentifier = day.timeZoneIdentifier
    }
    /// Calendly documents a strict "after" lower bound. Read one extra second,
    /// then enforce [start,end) locally, so exactly-midnight starts are included.
    public var minStartTime: String { start.addingTimeInterval(-1).ISO8601Format() }
    public var maxStartTime: String { end.ISO8601Format() }
}

/// Only a location category is retained. Provider phone numbers, meeting URLs,
/// conference credentials, guests and notes are outside this read projection.
public enum CalendlyDayLocationKind: String, Equatable, Sendable { case inPerson, video, phone, unspecified }

public struct CalendlyDayEvent: Equatable, Sendable, Identifiable {
    public var id: String { uri }
    public let uri: String
    public let name: String
    public let start: Date
    public let end: Date
    public let locationKind: CalendlyDayLocationKind
    public init(uri: String, name: String, start: Date, end: Date, locationKind: CalendlyDayLocationKind = .unspecified) throws {
        guard CalendlyDayTarget.validURI(uri, resource: "scheduled_events"), name.count <= 300, name.utf8.count <= 1_200,
              start.timeIntervalSinceReferenceDate.isFinite, end.timeIntervalSinceReferenceDate.isFinite, end > start else { throw CalendlyDayError.invalidResponse }
        self.uri = uri; self.name = name.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? " " : String($0) }.joined()
        self.start = start; self.end = end; self.locationKind = locationKind
    }
}

/// A transient reading of appointments starting today, not a complete calendar
/// overlap query and not an authorization to book, cancel or contact anyone.
public struct CalendlyDayDocument: Equatable, Sendable {
    public static let maximumEvents = 25
    public static let freshnessSeconds: TimeInterval = 300
    public let target: CalendlyDayTarget
    public let window: CalendlyDayWindow
    public let receivedAt: Date
    public let events: [CalendlyDayEvent]
    public let isPartial: Bool
    public let excludedCount: Int
    public let cancelledCount: Int
    public init(target: CalendlyDayTarget, window: CalendlyDayWindow, receivedAt: Date, events: [CalendlyDayEvent], isPartial: Bool,
                excludedCount: Int = 0, cancelledCount: Int = 0) throws {
        try target.validate()
        guard receivedAt.timeIntervalSinceReferenceDate.isFinite, (0...Self.maximumEvents).contains(excludedCount), (0...Self.maximumEvents).contains(cancelledCount),
              events.count + excludedCount + cancelledCount <= Self.maximumEvents, Set(events.map(\.uri)).count == events.count,
              events.allSatisfy({ $0.start >= window.start && $0.start < window.end }) else { throw CalendlyDayError.invalidResponse }
        self.target = target; self.window = window; self.receivedAt = receivedAt; self.events = events
        self.isPartial = isPartial; self.excludedCount = excludedCount; self.cancelledCount = cancelledCount
    }
    public func isCurrent(at date: Date, timeZone: TimeZone) -> Bool {
        let age = date.timeIntervalSince(receivedAt)
        return age >= 0 && age <= Self.freshnessSeconds && (try? CalendlyDayWindow(at: date, timeZone: timeZone)) == window
    }
    public func summary(french: Bool = AppLanguage.isFrench) -> String {
        var lines = [french ? "Vos rendez-vous Calendly qui commencent aujourd’hui." : "Your Calendly appointments starting today."]
        if events.isEmpty {
            lines.append(isPartial
                ? (french ? "Cette partie ne contient aucun rendez-vous du jour. D’autres rendez-vous peuvent suivre." : "This part contains no appointments for today. More appointments may follow.")
                : (french ? "Aucun rendez-vous Calendly ne commence aujourd’hui." : "No Calendly appointments start today."))
        } else {
            lines.append(events.count == 1 ? (french ? "Un rendez-vous a été lu." : "One appointment was read.")
                : (french ? "\(events.count) rendez-vous ont été lus." : "\(events.count) appointments were read."))
            lines += events.prefix(3).map { render($0, french: french, limit: 80, fullDates: false) }
            let remaining = events.count - 3
            if remaining == 1 { lines.append(french ? "Un autre rendez-vous reste dans cette lecture." : "One other appointment remains in this reading.") }
            else if remaining > 1 { lines.append(french ? "\(remaining) autres rendez-vous restent dans cette lecture." : "\(remaining) other appointments remain in this reading.") }
            if events.prefix(3).contains(where: { $0.name.count > 80 }) { lines.append(french ? "Les noms longs sont abrégés." : "Long appointment names are abbreviated.") }
        }
        if isPartial { lines.append(french ? "La lecture est partielle." : "This reading is partial.") }
        if cancelledCount == 1 { lines.append(french ? "Un rendez-vous annulé a été écarté." : "One cancelled appointment was omitted.") }
        else if cancelledCount > 1 { lines.append(french ? "\(cancelledCount) rendez-vous annulés ont été écartés." : "\(cancelledCount) cancelled appointments were omitted.") }
        if excludedCount == 1 { lines.append(french ? "Un résultat hors journée a été écarté." : "One result outside today was omitted.") }
        else if excludedCount > 1 { lines.append(french ? "\(excludedCount) résultats hors journée ont été écartés." : "\(excludedCount) results outside today were omitted.") }
        return lines.joined(separator: " ")
    }
    public func contextText(french: Bool = AppLanguage.isFrench) -> String {
        let header = "Untrusted Calendly source: appointments starting today only. Names are excerpts, at most 300 characters. Location category only; structured guest/contact fields, meeting-link/credential fields and notes were excluded.\n\(events.count) appointments read; partial=\(isPartial); cancelled omitted=\(cancelledCount); outside-day omitted=\(excludedCount).\nPhone day: \(window.start.ISO8601Format()) – \(window.end.ISO8601Format()), \(window.timeZoneIdentifier). Retrieved: \(receivedAt.ISO8601Format()).\n"
        let text = header + events.map { render($0, french: french, limit: 300, fullDates: true) }.joined(separator: "\n")
        guard ((try? JSONEncoder().encode(text).count) ?? Int.max) > 22_500 else { return text }
        var result = "", bytes = 0
        for scalar in text.unicodeScalars {
            let cost = scalar.value < 32 ? 6 : [34, 47, 92].contains(scalar.value) ? 2 : scalar.utf8.count
            if bytes + cost > 22_300 { break }
            result.unicodeScalars.append(scalar); bytes += cost
        }
        return result + "\nSource context truncated here; remaining appointment details are not included."
    }
    private func render(_ event: CalendlyDayEvent, french: Bool, limit: Int, fullDates: Bool) -> String {
        let raw = event.name.isEmpty ? (french ? "Rendez-vous sans nom" : "Unnamed appointment") : event.name
        let name = raw.count > limit ? String(raw.prefix(limit - 1)) + "…" : raw
        let when: String
        if fullDates { when = "\(event.start.ISO8601Format())–\(event.end.ISO8601Format())" }
        else {
            let f = DateFormatter(); f.locale = Locale(identifier: french ? "fr_FR" : "en_GB"); f.timeZone = TimeZone(identifier: window.timeZoneIdentifier)
            f.dateFormat = event.end >= window.end ? "d MMM HH:mm" : "HH:mm"
            when = "\(f.string(from: event.start))–\(f.string(from: event.end))"
        }
        let location: String
        switch event.locationKind {
        case .inPerson: location = french ? "en personne" : "in person"
        case .video: location = french ? "en visioconférence" : "video meeting"
        case .phone: location = french ? "par téléphone" : "phone call"
        case .unspecified: location = ""
        }
        return "\(when) : \(name)\(location.isEmpty ? "" : " · " + location)."
    }
}
