import Foundation

// MARK: - Spoken reply intent

/// What the owner said after "Do you want to reply?". Exact, small grammar: anything
/// that is not clearly a decline, a bare yes, or a reply phrase is `.unclear` and skipped.
/// No outcome sends anything; `.draft` only types into the compose field.
public enum LiveDemoReplyIntent: Equatable, Sendable {
    case silence
    case decline
    /// "yes" with no text: ask what to say, then listen once more.
    case affirm
    case draft(String)
    case unclear

    static let declines: Set<String> = [
        "no", "nope", "nah", "no thanks", "no thank you", "not now", "later", "skip", "skip it",
        "next", "nothing", "no reply", "dont reply", "do not reply", "leave it", "ignore", "ignore it",
        "no need", "pass", "cancel", "stop"
    ]
    static let affirms: Set<String> = [
        "yes", "yeah", "yep", "sure", "ok", "okay", "yes please", "please", "reply", "yes reply",
        "i do", "yes i do", "go ahead"
    ]
    /// Leading phrases that introduce the reply text. Longest first.
    static let draftPrefixes: [String] = [
        "yes reply with", "yes reply saying", "yes reply", "yes say", "yes tell them", "yes tell him",
        "yes tell her", "yes write", "reply with", "reply saying", "reply", "say", "tell them",
        "tell him", "tell her", "write", "answer", "respond with", "respond", "send", "yes send", "yes"
    ].sorted { $0.count > $1.count }

    /// Folds case, diacritics and apostrophes; keeps the original wording for the draft.
    public static func normalizedWords(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "\u{2019}", with: "")
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }

    public static func parse(_ transcript: String) -> LiveDemoReplyIntent {
        let words = normalizedWords(transcript)
        guard !words.isEmpty else { return .silence }
        let phrase = words.joined(separator: " ")
        if declines.contains(phrase) { return .decline }
        if affirms.contains(phrase) { return .affirm }
        // A negation anywhere ("no don't reply", "don't send it") is a decline, never a draft.
        if words.first == "no" || phrase.hasPrefix("dont") || phrase.hasPrefix("do not") { return .decline }
        for prefix in draftPrefixes {
            let prefixWords = prefix.split(separator: " ").map(String.init)
            guard words.count > prefixWords.count, Array(words.prefix(prefixWords.count)) == prefixWords else { continue }
            guard let text = originalText(after: prefixWords.count, in: transcript),
                  let draft = LiveDemoDraft.sanitize(text) else { return .unclear }
            return .draft(draft)
        }
        return .unclear
    }

    /// The text that answers "What should I say?". A decline still declines.
    public static func parseDictation(_ transcript: String) -> LiveDemoReplyIntent {
        let words = normalizedWords(transcript)
        guard !words.isEmpty else { return .silence }
        let phrase = words.joined(separator: " ")
        if declines.contains(phrase) || phrase == "never mind" || phrase == "nevermind" { return .decline }
        guard let draft = LiveDemoDraft.sanitize(transcript) else { return .silence }
        return .draft(draft)
    }

    /// Drops the first `count` words of the original transcript, keeping its casing and
    /// punctuation, and trims leading separators such as a comma or colon.
    static func originalText(after count: Int, in transcript: String) -> String? {
        var remaining = count
        var index = transcript.startIndex
        var inWord = false
        while index < transcript.endIndex {
            let isWordCharacter = transcript[index].unicodeScalars.allSatisfy {
                CharacterSet.alphanumerics.contains($0) || $0 == "'" || $0 == "\u{2019}"
            }
            if isWordCharacter, !inWord {
                if remaining == 0 { break }
                inWord = true
            } else if !isWordCharacter, inWord {
                inWord = false
                remaining -= 1
            }
            index = transcript.index(after: index)
        }
        // Trim only leading separators; the reply keeps its own ending punctuation.
        let separators = CharacterSet(charactersIn: ",:;.-").union(.whitespacesAndNewlines)
        let rest = String(transcript[index...].drop { $0.unicodeScalars.allSatisfy(separators.contains) })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? nil : rest
    }
}

// MARK: - List rows (Messages and Mail)

public struct LiveDemoListRow: Equatable, Sendable {
    public let isUnread: Bool
    public let sender: String
    /// Messages: the latest message preview. Mail: the subject.
    public let detail: String

    public init(isUnread: Bool, sender: String, detail: String) {
        self.isUnread = isUnread; self.sender = sender; self.detail = detail
    }

    /// A row is unread when its accessibility value names it, or its label starts with
    /// the word "Unread" (how VoiceOver announces it). A preview that merely contains the
    /// word later in the label does not count.
    public static func isUnread(label: String, value: String) -> Bool {
        if LiveDemoTapPolicy.words(value).contains("unread") { return true }
        return LiveDemoTapPolicy.words(label).first == "unread"
    }

    /// Builds a row from the cell's label and the labels of its static texts, in screen
    /// order. Static texts are preferred; the comma-separated label is the fallback.
    public static func parse(label: String, value: String, texts: [String]) -> LiveDemoListRow? {
        let unread = isUnread(label: label, value: value)
        let cleanedTexts = texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !isNoise($0) }
        var parts = cleanedTexts
        if parts.count < 2 {
            parts = label.components(separatedBy: ", ").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !isNoise($0) }
        }
        guard let sender = parts.first else { return nil }
        let detail = parts.dropFirst().first ?? ""
        return LiveDemoListRow(isUnread: unread, sender: sender, detail: detail)
    }

    /// Status words, times and dates that VoiceOver adds around a row's content.
    static func isNoise(_ text: String) -> Bool {
        let lower = text.lowercased()
        if ["unread", "read", "pinned", "muted", "flagged", "vip", "attachment", "has attachment",
            "yesterday", "today", "now", "draft", "delivered"].contains(lower) { return true }
        let weekdays = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
        if weekdays.contains(lower) { return true }
        let patterns = [
            #"^\d{1,2}[:.h]\d{2}(\s?[ap]\.?m\.?)?$"#,          // 9:41, 9:41 AM, 09h41
            #"^\d{1,4}[/.-]\d{1,2}([/.-]\d{1,4})?$"#,           // 14/10/2026, 10/14
            #"^\d+\s?(min|mins|m|h|hr|hrs|d|w)( ago)?$"#         // 5m, 2 h ago
        ]
        return patterns.contains { lower.range(of: $0, options: .regularExpression) != nil }
    }
}

// MARK: - Weather

public enum LiveDemoWeather {
    /// The first temperature on screen and the short condition text after it, in reading
    /// order, e.g. ("14°", "Mostly Cloudy"). Nil when no temperature is visible.
    public static func summary(texts: [String]) -> (temperature: String, condition: String?)? {
        let cleaned = texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard let index = cleaned.firstIndex(where: isTemperature) else { return nil }
        let condition = cleaned[(index + 1)...].prefix(3).first(where: isConditionLike)
        return (cleaned[index], condition)
    }

    static func isTemperature(_ text: String) -> Bool {
        text.range(of: #"^-?\d{1,3}°[CF]?$"#, options: .regularExpression) != nil
    }

    static func isConditionLike(_ text: String) -> Bool {
        text.count <= 40 && text.count >= 3
            && text.unicodeScalars.allSatisfy { CharacterSet.letters.union(.whitespaces).contains($0) }
    }
}

// MARK: - Instagram

public enum LiveDemoInstagram {
    /// The unread count Instagram puts in its Direct tab label, e.g.
    /// "Direct messages - 3 unread messages" -> 3. Nil when the label has no count.
    public static func unreadCount(fromTabLabel label: String) -> Int? {
        let words = label.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        guard let index = words.firstIndex(of: "unread"), index > 0, let count = Int(words[index - 1]) else { return nil }
        return count
    }

    /// Instagram's end-of-new-posts marker, in English or French, by text or identifier.
    public static func isCaughtUpMarker(text: String, identifier: String = "") -> Bool {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "\u{2019}", with: "'")
        let phrases = ["you're all caught up", "youre all caught up", "you've seen all new posts", "you have seen all new posts",
                       "you've seen the latest posts", "vous etes a jour", "vous avez vu toutes les nouvelles publications",
                       "vous avez vu les dernieres publications", "tu es a jour", "tu as vu toutes les nouvelles publications"]
        let id = identifier.lowercased()
        return phrases.contains { folded.contains($0) }
            || ["caught-up", "caught_up", "caughtup", "end-of-feed", "end_of_feed"].contains { id.contains($0) }
    }
}
