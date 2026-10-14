import Foundation

/// Pure decisions for the tethered live-morning demo (UITests/LiveMorningDemoTests.swift).
/// Only the UI-test target links this library; the shipped app never does.
/// Nothing here sends, posts or deletes: the demo has no code path that can.

// MARK: - Opt-in gate

public enum LiveDemoGate {
    public enum Decision: Equatable, Sendable {
        case run
        case skip(String)
    }

    /// The demo drives other apps on a real, tethered phone with the owner present.
    /// It runs only with `MO_LIVE_DEMO=1`, never on a simulator and never in CI.
    public static func evaluate(environment: [String: String], isSimulator: Bool) -> Decision {
        guard environment["MO_LIVE_DEMO"] == "1" else {
            return .skip("The live morning demo needs TEST_RUNNER_MO_LIVE_DEMO=1. No app was opened.")
        }
        guard !isSimulator else {
            return .skip("The live morning demo runs only on a tethered physical iPhone.")
        }
        for key in ["CI", "GITHUB_ACTIONS", "CONTINUOUS_INTEGRATION"] {
            if let value = environment[key], !value.isEmpty, value.lowercased() != "false", value != "0" {
                return .skip("The live morning demo never runs in CI.")
            }
        }
        return .run
    }

    /// Read conversations are used only with an explicit second flag.
    public static func allowsReadConversations(environment: [String: String]) -> Bool {
        environment["MO_LIVE_DEMO_ANY"] == "1"
    }

    /// Number of reels to swipe through. Default 10, bounded to 0...50 so a typo cannot
    /// leave the phone swiping for an hour.
    public static func reelCount(environment: [String: String]) -> Int {
        guard let raw = environment["MO_LIVE_DEMO_REELS"]?.trimmingCharacters(in: .whitespaces),
              let value = Int(raw) else { return 10 }
        return min(max(value, 0), 50)
    }
}

// MARK: - Tap policy

/// Every tap the demo makes goes through this policy. A forbidden word in a label or
/// identifier always wins, so a control that sends, replies, posts, likes, follows,
/// shares or deletes can never be tapped, whatever kind the caller claims it is.
public enum LiveDemoTapPolicy {
    public enum Kind: Sendable, Equatable {
        /// A list row that opens a conversation. Its label holds message text, so only
        /// the element type is checked, never its words (see `permits`).
        case listRow
        /// The compose text field or text view (focus only; typing never sends).
        case composeField
        /// A back-navigation button.
        case back
        /// A tab or feed selector, e.g. "Reels" or "For You".
        case feedTab
        /// A mailbox row, e.g. "Inbox".
        case mailbox
    }

    static let forbiddenWords: Set<String> = [
        "send", "sent", "reply", "replies", "forward", "post", "share", "like", "liked", "unlike",
        "heart", "love", "follow", "following", "unfollow", "subscribe", "comment", "comments",
        "delete", "remove", "trash", "archive", "junk", "block", "report", "unsubscribe",
        "call", "facetime", "audio", "video", "buy", "pay", "save", "repost", "remix", "gift",
        "react", "tapback", "emoji", "camera", "record", "microphone", "dictate", "dictation",
        "mute", "pin", "hide", "flag", "move", "edit", "undo", "compose", "new"
    ]

    static let backLabels: Set<String> = ["back", "messages", "mailboxes", "inbox", "all inboxes", "close"]
    static let feedTabLabels: Set<String> = ["reels", "for you", "home"]
    static let mailboxLabels: Set<String> = ["inbox", "all inboxes"]
    static let composeLabels: Set<String> = ["message", "imessage", "text message", "messagebodyfield",
                                             "rcs message", "sms"]

    /// Lowercased words in a label or identifier, split on anything not a letter or digit.
    static func words(_ text: String) -> [String] {
        text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }

    public static func containsForbiddenWord(_ text: String) -> Bool {
        words(text).contains { forbiddenWords.contains($0) }
            // camelCase identifiers such as "sendButton" or "likeButton"
            || forbiddenWords.contains { word in
                text.lowercased().replacingOccurrences(of: " ", with: "").contains(word + "button")
            }
    }

    public static func permits(kind: Kind, label: String, identifier: String, isButtonLike: Bool) -> Bool {
        let normalizedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedID = identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch kind {
        case .listRow:
            // A row is a cell, never a button. Its words are message text, so they are not
            // matched against the forbidden list; a cell whose identifier names an action is.
            return !isButtonLike && !containsForbiddenWord(identifier)
        case .composeField:
            return !isButtonLike && !containsForbiddenWord(identifier)
                && (composeLabels.contains(normalizedLabel) || composeLabels.contains(normalizedID))
        case .back:
            return !containsForbiddenWord(label) && !containsForbiddenWord(identifier)
                && backLabels.contains(normalizedLabel)
        case .feedTab:
            return !containsForbiddenWord(label) && !containsForbiddenWord(identifier)
                && feedTabLabels.contains(normalizedLabel)
        case .mailbox:
            return !containsForbiddenWord(label) && !containsForbiddenWord(identifier)
                && mailboxLabels.contains(normalizedLabel)
        }
    }
}

// MARK: - Draft text

public enum LiveDemoDraft {
    /// One line, no control characters, at most 280 characters. A newline is removed so
    /// typing can never act as a return key in any compose field.
    public static func sanitize(_ text: String) -> String? {
        let scalars = text.unicodeScalars.map { scalar -> Character in
            CharacterSet.controlCharacters.contains(scalar) || CharacterSet.newlines.contains(scalar)
                ? " " : Character(scalar)
        }
        let collapsed = String(scalars).split(whereSeparator: { $0 == " " }).joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(280))
    }
}

// MARK: - Speech timing

public enum LiveDemoSpeechTiming {
    /// Generous upper bound for one utterance at the default rate: 4 s + 1 s per 12
    /// characters, capped at 90 s. Used only as a timeout, never as a wait.
    public static func timeout(forCharacters count: Int) -> TimeInterval {
        min(90, 4 + Double(max(count, 0)) / 12)
    }
}
