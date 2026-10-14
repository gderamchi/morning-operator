import Foundation

/// Distinctive interface phrases of popular apps, in English and French, matched against
/// a sampled screen's text. Deterministic and offline. A bare app name is never enough,
/// because notifications, folders and links mention other apps.
public enum ObservationAppSignatures {
    struct Rule {
        let app: String
        /// Any one phrase is enough.
        var any: [String] = []
        /// Every phrase in at least one group must appear.
        var all: [[String]] = []
        var pattern: String? = nil
        /// Lines (after the status bar) that must each match this whole-line pattern.
        var lines: (pattern: String, count: Int)? = nil
    }

    /// A message's own time, as chat apps print it under each bubble: "12:06".
    static let messageTime = #"^\d{1,2}:\d{2}$"#
    /// The same time followed by WhatsApp's read ticks, which text recognition reads as
    /// "//", "/", "v", "w" or the tick characters themselves: "12:01 //", "12:00 V".
    static let messageTimeWithTicks = #"^\d{1,2}:\d{2} ?(//|/|\\\\|v|vv|w|✓|✓✓)$"#

    // Order matters: the first matching rule wins (Gmail before Mail, for example).
    static let rules: [Rule] = [
        // OCR often reads "AI" as "Al", so Meta AI phrases stop at "meta a". WhatsApp uses
        // the infinitive "Demander", Messenger the imperative "Demandez".
        .init(app: "Messenger", any: ["demandez a meta a"], all: [["messenger", "quoi de neuf"]]),
        .init(app: "WhatsApp", any: ["demander a meta a", "ask meta a", "en ligne aujourd'hui a", "en ligne aujourd’hui a",
                                     "vu aujourd'hui a", "vu aujourd’hui a", "last seen today at", "touchez ici pour les infos"],
              all: [["discussions", "communautes"], ["discussions", "actus"], ["chats", "communities", "updates"]]),
        // Inside a conversation: WhatsApp's unread divider, or a sent message's ticks.
        .init(app: "WhatsApp", any: ["messages non lus", "message non lu", "unread messages", "unread message"],
              lines: (messageTimeWithTicks, 1)),
        .init(app: "Duolingo", any: ["quest points", "points de quete", "daily quests", "quetes du jour"],
              pattern: #"section \d+, (unit|unite) \d+"#),
        .init(app: "LinkedIn", any: ["offres d'emploi", "offres d’emploi", "mon reseau", "my network", "mes posts"],
              all: [["jobs", "my network"]]),
        .init(app: "Instagram", any: ["votre story", "your story"], all: [["reels", "pour vous", "suivis"]]),
        .init(app: "Snapchat", any: ["snap map", "spotlight"], all: [["my ai", "chat"], ["chat", "pres de moi"]]),
        .init(app: "TikTok", all: [["pour toi", "abonnements"], ["for you", "following", "friends"], ["pour toi", "amis"]]),
        .init(app: "Gmail", any: ["boite principale", "rechercher dans les e-mails", "search in mail", "search in emails"]),
        .init(app: "Mail", any: ["boites aux lettres", "mailboxes"], all: [["selectionner", "principale"], ["select", "primary"]]),
        .init(app: "YouTube", all: [["shorts", "abonnements"], ["shorts", "subscriptions"]]),
        .init(app: "Facebook", any: ["quoi de neuf ?", "what's on your mind"]),
        .init(app: "Netflix", any: ["ma liste netflix"], all: [["nouveautes", "ma liste", "series"]]),
        .init(app: "Spotify", any: ["votre bibliotheque spotify"], all: [["accueil", "rechercher", "votre bibliotheque"],
                                                                          ["home", "search", "your library"]]),
        .init(app: "X", all: [["pour vous", "abonnements", "quoi de neuf"], ["for you", "following", "what's happening"]]),
        .init(app: "Reddit", any: ["r/popular", "join community"], all: [["accueil", "communautes", "r/"]]),
        .init(app: "Discord", any: ["direct messages", "messages prives"], all: [["serveurs", "messages prives"]]),
        .init(app: "Slack", any: ["unreads", "huddles"], all: [["fils de discussion", "huddles"]]),
        // Apple's own apps, last: their words are more generic.
        .init(app: "Music", any: ["epinglez votre musique", "pin your favorite music", "ecouter maintenant", "listen now"],
              all: [["bibliotheque", "playlists", "artistes"], ["library", "playlists", "artists"]]),
        .init(app: "Weather", any: ["ma position", "my location"],
              pattern: #"\b\d{1,2}°\n(nuageux|bruine|ensoleille|pluie|averses|couvert|degage|orageux|neige|brouillard|partiellement nuageux|cloudy|mostly cloudy|sunny|clear|rain|drizzle|showers|snow|fog)\b"#),
        .init(app: "Messages", any: ["imessage", "message texte", "text message"], all: [["modifier", "messages"], ["edit", "messages"]])
    ]

    /// The app whose interface phrases appear in this screen text, if exactly one rule matches first.
    public static func app(in text: String) -> ObservedApp? {
        let lines = text.split(whereSeparator: \.isNewline).map { ObservedApp.key(for: String($0)) }
        let whole = lines.joined(separator: "\n")
        let lineSet = Set(lines)
        // The first line is the status bar clock; it is never a message time.
        let body = lines.dropFirst()
        func count(_ pattern: String) -> Int {
            body.filter { $0.range(of: pattern, options: .regularExpression) != nil }.count
        }
        func has(_ phrase: String) -> Bool { lineSet.contains(phrase) || whole.contains(phrase) }
        for rule in rules {
            let byAny = rule.any.contains(where: has)
            let byAll = rule.all.contains { group in group.allSatisfy(has) }
            let byPattern = rule.pattern.map { whole.range(of: $0, options: .regularExpression) != nil } ?? false
            // Ticks alone could be noise; a conversation also shows several message times.
            let byLines = rule.lines.map { count($0.pattern) >= $0.count && count(messageTime) + count($0.pattern) >= 3 } ?? false
            if byAny || byAll || byPattern || byLines { return ObservedApp(name: rule.app) }
        }
        return nil
    }
}
