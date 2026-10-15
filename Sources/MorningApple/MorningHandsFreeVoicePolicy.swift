import Foundation
import MorningCore

public enum MorningHandsFreeControl: Sendable, Equatable {
    case session(MorningVoiceCommand)
    case extend
}

/// Only whole, final user utterances authorize controls. Conversation text never
/// becomes an execution instruction merely because it mentions a control verb.
public enum MorningHandsFreeVoicePolicy {
    public static func control(in text: String) -> MorningHandsFreeControl? {
        if let command = MorningVoiceCommandParser.parse(text) { return .session(command) }
        var words = normalized(text)
        if words.hasPrefix("more ") { words.removeFirst(5) }
        switch words {
        case "extend", "more time", "two more minutes", "add two minutes", "add 2 minutes",
             "prolonge", "prolonger", "encore deux minutes", "encore 2 minutes",
             "ajoute deux minutes", "ajoute 2 minutes": return .extend
        case "continue please", "continue s il te plait", "reprends la routine", "reprends mon matin":
            return .session(.resume)
        case "next please", "passe a la suite", "passe a l etape suivante", "on passe a la suite":
            return .session(.next)
        case "stop please", "arrete mon matin", "arrete le matin": return .session(.stop)
        default: return nil
        }
    }

    /// Short replies must remain interruptible even when MORE mentioned the same
    /// words. Their protection is the shared acoustic path plus execution policy,
    /// not a substring ban. Long reflected source passages still fail closed.
    public static func isOutputEcho(_ text: String, output: String?, acousticDuplexIsActive: Bool = false) -> Bool {
        let candidate = normalized(text)
        guard candidate.count >= 3, let output else { return false }
        if acousticDuplexIsActive, isShortInterruption(candidate) { return false }
        return (" " + normalized(output) + " ").contains(" " + candidate + " ")
    }

    private static func isShortInterruption(_ candidate: String) -> Bool {
        if control(in: candidate) != nil { return true }
        return ["oui", "oui merci", "yes", "yes please", "non", "non merci", "no", "no thanks",
                "envoie", "envoyer", "envoie la reponse", "send", "send it", "send reply",
                "reponds lui", "repondre", "reply", "relis", "read it", "first", "first message",
                "second", "second message", "third", "third message", "le premier", "premier",
                "le deuxieme", "deuxieme", "le troisieme", "troisieme", "1", "2", "3"].contains(candidate)
    }

    public static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.letters.union(.decimalDigits).inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }
}

public struct MorningHandsFreeUtterance: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let context: MorningVoiceCommandContext
    public let text: String

    public init(id: UUID = UUID(), context: MorningVoiceCommandContext, text: String) {
        self.id = id; self.context = context; self.text = text
    }
}

/// The first final result belongs to the context at speech onset, not the context
/// when an idle recognition window began or a delayed model response arrived.
struct MorningHandsFreeVoiceTurn: Sendable {
    private(set) var context: MorningVoiceCommandContext?
    private(set) var isFinished = false
    let id = UUID()

    mutating func begin(in context: MorningVoiceCommandContext) {
        guard !isFinished, self.context == nil else { return }
        self.context = context
    }

    mutating func accept(_ text: String, isFinal: Bool) -> MorningHandsFreeUtterance? {
        guard !isFinished, isFinal else { return nil }
        isFinished = true
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let context, !text.isEmpty, text.count <= 4_000 else { return nil }
        return .init(id: id, context: context, text: text)
    }

    mutating func cancel() { isFinished = true }
}
