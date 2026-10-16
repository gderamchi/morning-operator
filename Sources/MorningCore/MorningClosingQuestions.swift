import Foundation

/// The questions that end a completed morning, asked one at a time. Each answer goes to the
/// existing capture review; nothing here saves a note or creates a reminder.
public enum MorningClosingQuestion: String, Codable, Sendable, CaseIterable {
    case dream, remember, note

    /// The kind the review screen starts with. The words still decide: "remind me at 5 to…"
    /// stays a reminder after any question, and "I dreamed…" stays a dream.
    public var captureKind: QuickCaptureKind {
        switch self {
        case .dream: .dream
        case .remember: .reminder
        case .note: .thought
        }
    }

    public func prompt(french: Bool) -> String {
        switch self {
        case .dream:
            french ? "Avez-vous fait un rêve que vous voulez noter ?" : "Did you have a dream you want to note?"
        case .remember:
            french ? "Quelque chose à vous rappeler aujourd’hui, ou que vous avez oublié ?"
                : "Anything you want to remember today, or something you forgot?"
        case .note:
            french ? "Une note à prendre ?" : "Any note to take?"
        }
    }
}

/// How a spoken or typed answer is taken.
public enum MorningClosingAnswer: Sendable, Equatable {
    /// "No", "nothing", "non merci", or silence: go to the next question.
    case declined
    /// Words to review.
    case content(String)
}

/// Where the closing questions are. Memory only: a relaunch does not resume them.
public struct MorningClosingQuestions: Sendable, Equatable {
    public private(set) var remaining: [MorningClosingQuestion]

    public init(_ questions: [MorningClosingQuestion] = MorningClosingQuestion.allCases) { remaining = questions }

    public var current: MorningClosingQuestion? { remaining.first }
    public var isFinished: Bool { remaining.isEmpty }

    /// The current question is done, answered or declined. The next one becomes current.
    public mutating func advance() { if !remaining.isEmpty { remaining.removeFirst() } }

    /// Only a whole answer that is a refusal declines. "No, remind me to call the bank" is
    /// content: it is reviewed like any other answer rather than thrown away.
    public static func interpret(_ transcript: String?) -> MorningClosingAnswer {
        let text = transcript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { return .declined }
        let normalized = text.lowercased()
            .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "’", with: "'")
            .components(separatedBy: CharacterSet.letters.union(.whitespaces).union(CharacterSet(charactersIn: "'")).inverted)
            .joined()
            .split(separator: " ").joined(separator: " ")
        return declines.contains(normalized) ? .declined : .content(text)
    }

    static let declines: Set<String> = [
        "no", "nope", "nah", "no thanks", "no thank you", "nothing", "nothing today", "none", "not now",
        "skip", "next", "no nothing", "not today", "pass", "no i didn't", "no i did not", "i didn't", "no dream",
        "non", "non merci", "nan", "rien", "rien du tout", "pas maintenant", "pas aujourd'hui", "suivant",
        "passe", "aucun", "aucune", "non rien", "je passe", "pas de reve"
    ]
}
