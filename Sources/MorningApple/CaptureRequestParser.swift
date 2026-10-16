import MorningCore
import Foundation

public enum CaptureDestination: String, Codable, CaseIterable, Sendable {
    case thought, dream, reminder, calendar
}

/// A suggestion for the capture review screen, never an authorization to write to EventKit.
public struct ParsedCaptureRequest: Sendable, Equatable {
    public let originalText: String
    public let content: String
    public let destination: CaptureDestination
    public let suggestedDate: Date?
    public let matchedDatePhrase: String?
    public let dateExplanation: String?
    public let needsDateReview: Bool
}

/// Small, deterministic English/French grammar. Unknown or ambiguous dates stay unresolved.
/// In particular, a dream mentioning a future time does not become a reminder.
public enum CaptureRequestParser {
    public static func parse(
        _ text: String,
        now: Date = Date(),
        calendar: Calendar = .current,
        morningHour: Int = 9,
        defaultDestination: CaptureDestination = .thought
    ) -> ParsedCaptureRequest {
        let original = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let classification = classify(original, otherwise: defaultDestination)
        guard classification.destination == .reminder || classification.destination == .calendar else {
            return ParsedCaptureRequest(originalText: original, content: classification.content,
                destination: classification.destination, suggestedDate: nil, matchedDatePhrase: nil,
                dateExplanation: nil, needsDateReview: false)
        }

        let body = classification.content
        // Only one supported expression at the end of the request is accepted. This avoids
        // stripping times out of quoted narrative or silently choosing between two deadlines.
        let matches = dateMatches(body)
        guard matches.count == 1, let match = matches.first else { return unresolved(original, classification: classification) }
        let trailing = body[match.range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)).isEmpty
        // A clock time may also open the request: "at 5 to call the bank", "à 17h d'appeler la banque".
        let leading: Bool = {
            guard case .clock = match.kind, body[..<match.range.lowerBound].trimmingCharacters(in: .whitespaces).isEmpty
            else { return false }
            return true
        }()
        guard trailing || leading else { return unresolved(original, classification: classification) }
        // A clock time with a day word elsewhere in the request ("at 5 tomorrow to…", "tomorrow
        // at 17:30") is not today's time: leave the date to the person.
        if case .clock = match.kind {
            let outside = String(body[..<match.range.lowerBound]) + " " + String(body[match.range.upperBound...])
            if outside.range(of: Self.dayWords, options: [.regularExpression, .caseInsensitive]) != nil
                // An explicit zone (EST, CEST, UTC…) names another clock than this device's.
                || outside.range(of: #"\b(?:UTC|GMT|Z|[A-Z]{1,4}T)\b"#, options: .regularExpression) != nil {
                return unresolved(original, classification: classification)
            }
        }

        let proposed: Date?
        let explanation: String
        switch match.kind {
        case .morning:
            guard (0...23).contains(morningHour),
                  let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
            else { return unresolved(original, classification: classification) }
            proposed = calendar.date(bySettingHour: morningHour, minute: 0, second: 0, of: tomorrow,
                matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
            explanation = String(localized: "Suggested \(String(format: "%02d:00", morningHour)) on the next calendar day in \(calendar.timeZone.identifier). Review the time before saving.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale)
        case .relative(let seconds):
            proposed = now.addingTimeInterval(seconds)
            explanation = String(localized: "Calculated from capture time using \(Int(seconds / 60)) elapsed minutes. Review the date and time before saving.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale)
        case .clock(let hour, let minute, let meridiem, let exact):
            proposed = nextClockTime(hour: hour, minute: minute, meridiem: meridiem, exact: exact, after: now, calendar: calendar)
            // The explanation names the resolved time, not the spoken token: "5 pm" is 17:00.
            let resolved = proposed.map { date -> String in
                let parts = calendar.dateComponents([.hour, .minute], from: date)
                return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
            } ?? ""
            explanation = String(localized: "Suggested the next \(resolved) in \(calendar.timeZone.identifier). Review the time before saving.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale)
        }
        guard let proposed, proposed.timeIntervalSinceReferenceDate.isFinite else {
            return unresolved(original, classification: classification)
        }
        let remainder = leading && !trailing ? String(body[match.range.upperBound...]) : String(body[..<match.range.lowerBound])
        var content = remainder.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;")))
        if leading && !trailing, let link = content.range(of: #"^(?:to\b|d['’]|de\b)\s*"#, options: [.regularExpression, .caseInsensitive]) {
            content = String(content[link.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !content.isEmpty else { return unresolved(original, classification: classification) }
        return ParsedCaptureRequest(originalText: original, content: content,
            destination: classification.destination, suggestedDate: proposed,
            matchedDatePhrase: String(body[match.range]), dateExplanation: explanation, needsDateReview: true)
    }

    private struct Classification {
        let destination: CaptureDestination
        let content: String
    }

    private static func classify(_ text: String, otherwise fallback: CaptureDestination) -> Classification {
        let prefixes: [(CaptureDestination, String)] = [
            (.dream, #"^(?:dream\s*:|r[êe]ve\s*:)\s*"#),
            (.reminder, #"^(?:remind\s+me\s+to\s+|remind\s+me\s+|reminder\s*:\s*|rappelle[- ]moi\s+de\s+|rappelle[- ]moi\s+|rappel\s*:\s*)"#),
            (.calendar, #"^(?:add\s+to\s+my\s+calendar\s*:?\s*|calendar\s*:\s*|schedule\s+|calendrier\s*:\s*|planifie\s+)"#),
            (.thought, #"^(?:thought\s*:|idea\s*:|pens[ée]e\s*:|id[ée]e\s*:)\s*"#)
        ]
        for (destination, pattern) in prefixes {
            if let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                return Classification(destination: destination,
                    content: String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        if text.range(of: #"^(?:I\s+dream(?:ed|t)\b|j['’]ai\s+r[êe]v[ée]\b)"#,
                      options: [.regularExpression, .caseInsensitive]) != nil {
            return Classification(destination: .dream, content: text)
        }
        return Classification(destination: fallback, content: text)
    }

    private enum DateKind {
        case morning, relative(TimeInterval)
        /// A wall-clock time. `meridiem` is nil when the words gave neither am nor pm.
        case clock(hour: Int, minute: Int, meridiem: Meridiem?, exact: Bool)
    }
    private enum Meridiem { case am, pm }

    /// The first instant after `now` showing this clock time. Without am or pm, an hour from
    /// 1 to 12 may be either: the earlier of the two upcoming times is proposed, so "at 5"
    /// said at 08:00 proposes 17:00 today. The person reviews the time before saving.
    private static func nextClockTime(hour: Int, minute: Int, meridiem: Meridiem?, exact: Bool, after now: Date,
                                      calendar: Calendar) -> Date? {
        var hours: [Int]
        switch meridiem {
        case .am: hours = [hour % 12]
        case .pm: hours = [hour % 12 + 12]
        case nil: hours = exact || !(1...12).contains(hour) ? [hour] : [hour % 12, hour % 12 + 12]
        }
        hours = hours.filter { (0...23).contains($0) }
        return hours.compactMap { value in
            calendar.nextDate(after: now, matching: DateComponents(hour: value, minute: minute, second: 0),
                              matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
        }
        // A time skipped by a clock change ("02:30" on the spring-forward night) comes back as
        // another time. That is not what was said: leave it to the person.
        .filter { date in
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            return hours.contains(parts.hour ?? -1) && parts.minute == minute
        }.min()
    }
    private struct DateMatch {
        let range: Range<String.Index>
        let kind: DateKind
    }

    private static func dateMatches(_ text: String) -> [DateMatch] {
        var result: [DateMatch] = []
        let full = NSRange(text.startIndex..<text.endIndex, in: text)
        if let regex = try? NSRegularExpression(pattern: #"\b(?:tomorrow\s+morning|next\s+morning|demain\s+matin)\b"#, options: .caseInsensitive) {
            for match in regex.matches(in: text, range: full) {
                if let range = Range(match.range, in: text) { result.append(DateMatch(range: range, kind: .morning)) }
            }
        }
        let pattern = #"\b(?:in|dans)\s*(\d{1,4}|one|two|three|four|five|six|seven|eight|nine|ten|une?|deux|trois|quatre)\s*(hours?|hrs?|h|minutes?|mins?|heures?)\b"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            for match in regex.matches(in: text, range: full) {
                guard let range = Range(match.range, in: text),
                      let numberRange = Range(match.range(at: 1), in: text),
                      let unitRange = Range(match.range(at: 2), in: text)
                else { continue }
                let words = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
                    "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
                    "un": 1, "une": 1, "deux": 2, "trois": 3, "quatre": 4]
                let value = String(text[numberRange]).lowercased()
                let amount = Int(value) ?? words[value] ?? 0
                let multiplier = text[unitRange].lowercased().hasPrefix("m") ? 60 : 3_600
                let seconds = amount * multiplier
                // Zero, implausibly long intervals and multiple dates require manual review.
                guard seconds > 0, seconds <= 30 * 86_400 else { continue }
                result.append(DateMatch(range: range, kind: .relative(TimeInterval(seconds))))
            }
        }
        // "at 5", "at 5:30 pm", "at 17:00", "à 17h", "à 17 h 30". Hours above 23 or minutes above
        // 59 are not times; "at 25" stays unresolved.
        // The token must end at a space, punctuation or the end: "at 17:300", "at 5:3" and
        // "at 5th" are not times.
        let clock = #"(?:\bat|(?<!\w)à)\s+(\d{1,2})(?:(:|\s*h\s*)(\d{2}))?(?:\s*(a\.?m\.?|p\.?m\.?)|\s*(h))?(?=$|[\s,;!?]|\.(?:\s|$))(?!\s+(?:\d|%|h\b|(?:hours?|heures?|minutes?|mins?|o['’]?clock|past|half|quarter|thirty|fifteen|forty|forty-five|twenty|ten|five|demie|quart|moins|pile)\b|et\s+(?:demie|quart)\b))"#
        if let regex = try? NSRegularExpression(pattern: clock, options: .caseInsensitive) {
            for match in regex.matches(in: text, range: full) {
                guard let range = Range(match.range, in: text), let hourRange = Range(match.range(at: 1), in: text),
                      let hour = Int(text[hourRange]) else { continue }
                let minute = Range(match.range(at: 3), in: text).flatMap { Int(text[$0]) } ?? 0
                let marker = Range(match.range(at: 4), in: text).map { text[$0].lowercased() }
                let meridiem: Meridiem? = marker.map { $0.hasPrefix("p") ? .pm : .am }
                guard (0...59).contains(minute), meridiem == nil ? (0...23).contains(hour) : (1...12).contains(hour) else { continue }
                // 24-hour notation is exact: a French "h", a leading zero ("07:30"), or an hour
                // from 13 or 0. Only a bare 1 to 12 without am or pm is ambiguous.
                let separator = Range(match.range(at: 2), in: text).map { text[$0].lowercased() } ?? ""
                let hourText = String(text[hourRange])
                let exact = separator.contains("h") || match.range(at: 5).location != NSNotFound
                    || (hourText.count == 2 && hourText.hasPrefix("0")) || !(1...12).contains(hour)
                // Trim a trailing space the optional groups may have consumed.
                var end = range.upperBound
                while end > range.lowerBound, text[text.index(before: end)].isWhitespace { end = text.index(before: end) }
                result.append(DateMatch(range: range.lowerBound..<end, kind: .clock(hour: hour, minute: minute, meridiem: meridiem, exact: exact)))
            }
        }
        return result
    }

    static let dayWords = #"\b(?:today|tonight|tomorrow|yesterday|next|this|on|morning|afternoon|evening|night|noon|midnight|monday|tuesday|wednesday|thursday|friday|saturday|sunday|weekend|week|month|aujourd['’]hui|ce\s+soir|demain|hier|prochain|prochaine|lundi|mardi|mercredi|jeudi|vendredi|samedi|dimanche|semaine|semaines|mois|days?|jours?|weeks?|months?|years?|ans|années?|utc|gmt|cet|cest|edt|cst|cdt|mst|mdt|pst|pdt|bst|jst|time|heure\s+de|matin|matinée|après-midi|soir|soirée|nuit|midi|minuit|january|february|march|april|may|june|july|august|september|october|november|december|janvier|février|mars|avril|mai|juin|juillet|août|septembre|octobre|novembre|décembre|le\s+\d{1,2}|\d{1,2}(?:st|nd|rd|th|er|e)|\d{1,2}[/.-]\d{1,2})\b"#

    private static func unresolved(_ original: String, classification: Classification) -> ParsedCaptureRequest {
        ParsedCaptureRequest(originalText: original, content: classification.content,
            destination: classification.destination, suggestedDate: nil, matchedDatePhrase: nil,
            dateExplanation: String(localized: "No single supported date was resolved. Choose a date and time, or save a reminder without a date.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale),
            needsDateReview: true)
    }
}
