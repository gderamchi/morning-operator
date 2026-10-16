import Foundation
import MorningCore

public enum MorningHandsFreeControl: Sendable, Equatable {
    case session(MorningVoiceCommand)
    case extend
    case refreshBriefing
}

/// Only whole, final user utterances authorize controls. Conversation text never
/// becomes an execution instruction merely because it mentions a control verb.
public enum MorningHandsFreeVoicePolicy {
    /// Read-only questions may return to the interrupted morning. Requested
    /// effects and editing intents need their own dialogue instead.
    public static func isInformationalQuestion(_ text: String) -> Bool {
        let words = normalized(text)
        let effects: Set<String> = ["envoie", "envoyer", "send", "sending", "cree", "creer", "create", "creating",
            "ajoute", "ajouter", "add", "change", "modifie", "modifier", "remplace", "retire", "delete",
            "supprime", "supprimer", "termine", "complete", "marque", "mark", "book", "reserve", "reponds", "reply"]
        guard !words.split(separator: " ").contains(where: { effects.contains(String($0)) }) else { return false }
        return text.contains("?") || ["pourquoi", "que dit", "qu est ce", "c est quoi", "est ce que", "qui ", "quel", "quand", "comment",
            "combien", "ou ", "peux tu me dire", "peux tu expliquer", "peux tu m expliquer", "peux tu resumer",
            "tu peux me dire", "dis moi ", "resume ", "explique ", "what", "why", "who", "when", "how", "where",
            "which", "can you tell", "could you tell", "can you explain", "could you explain", "can you summarize",
            "tell me ", "summarize ", "explain "].contains(where: words.hasPrefix)
    }
    public static func control(in text: String, language: MorningVoiceCommandLanguage? = nil) -> MorningHandsFreeControl? {
        if let command = MorningVoiceCommandParser.parse(text, language: language) { return .session(command) }
        var words = normalized(text)
        if words.hasPrefix("more ") { words.removeFirst(5) }
        if language != .french {
            switch words {
            case "refresh this briefing", "update this briefing", "refresh this recap", "update this recap": return .refreshBriefing
            case "extend", "more time", "two more minutes", "add two minutes", "add 2 minutes": return .extend
            case "continue please": return .session(.resume)
            case "next please": return .session(.next)
            case "stop please": return .session(.stop)
            default: break
            }
        }
        if language != .english {
            switch words {
            case "actualise ce briefing", "actualise le briefing", "actualise ce recapitulatif", "mets a jour ce briefing": return .refreshBriefing
            case "prolonge", "prolonger", "encore deux minutes", "encore 2 minutes", "ajoute deux minutes", "ajoute 2 minutes": return .extend
            case "continue s il te plait", "reprends la routine", "reprends mon matin": return .session(.resume)
            case "passe a la suite", "passe a l etape suivante", "on passe a la suite": return .session(.next)
            case "arrete mon matin", "arrete le matin": return .session(.stop)
            default: break
            }
        }
        return nil
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
                "note a moi meme", "une note a moi meme", "send me an email", "email myself",
                "ajoute", "ajouter", "confirme l ajout", "add it", "confirm addition", "confirme la completion",
                "confirme termine", "marque termine", "mark complete",
                "second", "second message", "third", "third message", "le premier", "premier",
                "le deuxieme", "deuxieme", "le troisieme", "troisieme", "1", "2", "3"].contains(candidate)
    }

    public static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.letters.union(.decimalDigits).inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// A single conversational interruption, scoped at speech onset. Explicit pause
/// changes the app's pauseRevision even if the session was already paused.
public struct MorningVoiceContinuationTicket: Sendable, Equatable {
    public let id: UUID
    public let context: MorningVoiceCommandContext
    public let privacyGeneration: UUID
    public let pauseRevision: UUID
    public let wasRunning: Bool
}

public struct MorningVoiceContinuationPolicy: Sendable {
    public private(set) var ticket: MorningVoiceContinuationTicket?
    public init() {}
    public func mayInherit(context: MorningVoiceCommandContext, privacyGeneration: UUID, pauseRevision: UUID) -> Bool {
        guard let ticket, ticket.wasRunning else { return false }
        return isCurrent(ticket, context: context, privacyGeneration: privacyGeneration, pauseRevision: pauseRevision)
    }
    public mutating func begin(context: MorningVoiceCommandContext, privacyGeneration: UUID,
        pauseRevision: UUID, wasRunning: Bool) {
        ticket = .init(id: UUID(), context: context, privacyGeneration: privacyGeneration,
            pauseRevision: pauseRevision, wasRunning: wasRunning)
    }
    public func isCurrent(_ value: MorningVoiceContinuationTicket, context: MorningVoiceCommandContext?,
        privacyGeneration: UUID, pauseRevision: UUID) -> Bool {
        ticket == value && value.context == context && value.privacyGeneration == privacyGeneration && value.pauseRevision == pauseRevision
    }
    public mutating func discard(_ value: MorningVoiceContinuationTicket?) {
        if ticket == value { ticket = nil }
    }
    public mutating func invalidate() { ticket = nil }
    public mutating func consume(_ value: MorningVoiceContinuationTicket, context: MorningVoiceCommandContext?,
        privacyGeneration: UUID, pauseRevision: UUID, speechFinished: Bool, isPaused: Bool,
        isForeground: Bool, hasPendingDialogue: Bool, canResumeRetainedExecution: Bool) -> Bool {
        guard isCurrent(value, context: context, privacyGeneration: privacyGeneration, pauseRevision: pauseRevision) else { return false }
        ticket = nil
        return value.wasRunning && speechFinished && isPaused && isForeground && !hasPendingDialogue && canResumeRetainedExecution
    }
}

public struct MorningHandsFreeUtterance: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let context: MorningVoiceCommandContext
    public let text: String
    public let languageGeneration: UUID

    public init(id: UUID = UUID(), context: MorningVoiceCommandContext, text: String,
                languageGeneration: UUID = UUID()) {
        self.id = id; self.context = context; self.text = text; self.languageGeneration = languageGeneration
    }
}

/// The first final result belongs to the context at speech onset, not the context
/// when an idle recognition window began or a delayed model response arrived.
struct MorningHandsFreeVoiceTurn: Sendable {
    private(set) var context: MorningVoiceCommandContext?
    private(set) var isFinished = false
    let id = UUID()
    let languageGeneration: UUID

    init(languageGeneration: UUID = UUID()) { self.languageGeneration = languageGeneration }

    mutating func begin(in context: MorningVoiceCommandContext) {
        guard !isFinished, self.context == nil else { return }
        self.context = context
    }

    mutating func accept(_ text: String, isFinal: Bool) -> MorningHandsFreeUtterance? {
        guard !isFinished, isFinal else { return nil }
        isFinished = true
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let context, !text.isEmpty, text.count <= 4_000 else { return nil }
        return .init(id: id, context: context, text: text, languageGeneration: languageGeneration)
    }

    mutating func cancel() { isFinished = true }
}
