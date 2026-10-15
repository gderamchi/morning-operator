import Foundation
import MorningCore
import Observation

public enum GmailMorningState: String, Sendable, Equatable {
    case idle, preparing, askingToReply, askingForIntention, preparingReply, reviewingReply, sending, uncertain, completed, unavailable
}

public enum GmailMorningReadOutcome: Sendable, Equatable { case unavailable, read }

/// Mail remains in memory. The engine binds every reply to an observed sender;
/// model output supplies body text only and cannot choose recipients or authorize sending.
@MainActor @Observable
public final class GmailMorningConversation {
    public private(set) var state: GmailMorningState = .idle
    public private(set) var message = ""
    public private(set) var summary = ""
    public private(set) var draftText = ""
    public private(set) var lastSendOutcome: GmailSendOutcome?
    public private(set) var readOutcome: GmailMorningReadOutcome = .unavailable
    public private(set) var recipient: String?
    public private(set) var context: MorningExecutionID?
    public var isCompleted: Bool { state == .completed }
    public var completedExecutionOutcome: RoutineExecutionRecord.Outcome? {
        guard isCompleted else { return nil }
        switch lastSendOutcome {
        case .uncertain, .draftMismatch: return .uncertain
        case .notSent: return .unavailable
        case .sent: return .completed
        case nil: return readOutcome == .read ? .completed : .unavailable
        }
    }
    /// Provider effects outlive narration and navigation. The store saves this
    /// before clearing a dialogue; an ordinary pause keeps its running outcome.
    public var interruptedExecutionOutcome: RoutineExecutionRecord.Outcome? {
        switch lastSendOutcome {
        case .sent: return .completed
        case .notSent: return .unavailable
        case .uncertain, .draftMismatch: return .uncertain
        case nil: return state == .unavailable && readOutcome == .unavailable ? .unavailable : nil
        }
    }
    public var isAwaitingResponse: Bool { [.askingToReply, .askingForIntention, .reviewingReply, .uncertain, .unavailable].contains(state) }
    private let service: GmailConnectionService
    private let drafts: GmailReplyDraftService
    private let speak: @MainActor (String) async throws -> Void
    private let answer: @MainActor (String, String) async throws -> String
    private let privacy: LocalDataControl
    private var session: GmailAccessSession?
    private var messages: [GmailMessage] = []
    private var selectedIndex = 0
    private var pendingIntention = ""
    private var generation: UUID?
    private var attempt = UUID()
    private var questionID: UUID?

    public init(service: GmailConnectionService = GmailConnectionService(),
                drafts: GmailReplyDraftService = GmailReplyDraftService(),
                privacy: LocalDataControl = LocalDataControl(directory: LocalDataControl.defaultDirectory),
                answer: @escaping @MainActor (String, String) async throws -> String = { request, context in
                    try await MorningVoiceConversation().answer(request, context: context)
                },
                speak: @escaping @MainActor (String) async throws -> Void) {
        self.service = service; self.drafts = drafts; self.privacy = privacy; self.speak = speak; self.answer = answer
    }

    public func begin(context: MorningExecutionID, generation: UUID?) async {
        clear()
        self.context = context; self.generation = generation
        let token = attempt
        state = .preparing
        do {
            try requireCurrent(token)
            guard let access = try await service.restoreConnection(generation: generation) else {
                try await unavailable("Connectez Gmail dans les réglages avant votre prochain matin.", token: token); return
            }
            try requireCurrent(token)
            session = access
            let inbox = try await service.unreadInboxMessages(session: access)
            try requireCurrent(token)
            guard !inbox.messages.isEmpty else {
                if inbox.failedMessageCount > 0 {
                    try await unavailable("Certains mails n’ont pas pu être lus. Je ne peux pas conclure que votre boîte est vide.", token: token)
                } else {
                    readOutcome = .read
                    state = .completed
                    try await say("Aucun mail non lu dans votre boîte de réception. Je continue votre matin.", token: token)
                }
                return
            }
            var fetched: [GmailMessage] = []
            var failures = inbox.failedMessageCount
            for item in inbox.messages {
                do {
                    let mail = try await service.message(id: item.id, session: access)
                    try requireCurrent(token)
                    fetched.append(mail)
                } catch {
                    try requireCurrent(token)
                    if let known = error as? GmailConnectionError,
                       [.sessionExpired, .permissionDenied, .connectionChanged].contains(known) { throw known }
                    failures += 1
                }
            }
            try requireCurrent(token)
            guard !fetched.isEmpty else {
                try await unavailable("Les mails n’ont pas pu être lus. Vous pouvez passer cette étape ou réessayer plus tard.", token: token); return
            }
            readOutcome = .read
            // Transparent deterministic ordering: urgency words, then the provider's
            // unread order. It is a proposal the person can override, never a fact claim.
            messages = Array(fetched.enumerated().sorted { lhs, rhs in
                let left = Self.priority(lhs.element), right = Self.priority(rhs.element)
                return left == right ? lhs.offset < rhs.offset : left > right
            }.prefix(3).map(\.element))
            let chosen = messages.enumerated().map { index, mail in
                let detail = mail.bodyUnavailable ? "Le contenu de ce message n’est pas lisible ici." :
                    "Le message dit : " + Self.excerpt(mail.plainTextBody)
                return "\(index + 1). \(mail.sender). \(mail.subject.isEmpty ? "Sans objet" : mail.subject). \(detail)"
            }.joined(separator: " ")
            summary = "J’ai consulté \(fetched.count) mails non lus. Voici \(messages.count) messages à examiner. " + chosen
            if fetched.contains(where: { Self.priority($0) > 0 }) {
                summary += " Les mentions d’urgence ou d’échéance passent en premier ; vous pouvez choisir un autre message."
            } else { summary += " Ils suivent l’ordre de votre boîte de réception." }
            if inbox.hasMore { summary += " D’autres mails non lus n’ont pas été consultés." }
            if failures > 0 { summary += " \(failures) messages n’ont pas pu être lus." }
            selectedIndex = 0; recipient = messages[0].replyAddress
            state = .askingToReply
            try await say(summary + " Voulez-vous répondre au premier ? Vous pouvez aussi choisir un numéro ou continuer votre matin.", token: token)
        } catch { await fail(error, token: token) }
    }

    /// Called only with an owner's recognized utterance from the current session.
    /// A page or a mail body is never passed here as a command.
    public func respond(_ transcript: String, context: MorningExecutionID) async {
        guard self.context == context, isAwaitingResponse else { return }
        questionID = nil
        let token = attempt
        let normalized = Self.normalized(transcript)
        do {
            try requireCurrent(token)
            if Self.isQuestion(transcript, normalized: normalized) {
                try await answerQuestion(transcript, token: token)
                return
            }
            if ["non", "non merci", "no", "no thanks", "continue", "continuer", "passe les mails"].contains(normalized) {
                state = .completed; draftText = ""; recipient = nil
                try await say("D’accord, je continue votre matin.", token: token); return
            }
            if let index = Self.messageIndex(normalized), messages.indices.contains(index), state != .uncertain {
                selectedIndex = index; recipient = messages[index].replyAddress; draftText = ""; pendingIntention = ""
                state = .askingToReply
                try await say("\(messages[index].sender). \(messages[index].subject). Voulez-vous lui répondre ?", token: token); return
            }
            if state == .unavailable {
                if ["reessaie", "reessaye", "reessayer", "retry", "try again"].contains(normalized) {
                    await begin(context: context, generation: generation)
                } else {
                    try await say("Les mails ne sont pas prêts. Dites réessaie, non ou suivant pour continuer votre matin.", token: token)
                }
                return
            }
            guard messages.indices.contains(selectedIndex), let session else { return }
            let mail = messages[selectedIndex]
            switch state {
            case .askingToReply:
                let hasReplyIntention = ["oui ", "yes ", "reponds lui ", "repond lui ", "reply ", "tell them "].contains(where: normalized.hasPrefix)
                if ["oui", "yes", "reponds lui", "repondre", "reply"].contains(normalized) || hasReplyIntention {
                    guard !mail.bodyUnavailable, !mail.bodyWasTruncated else {
                        try await say("Ce message n’est pas disponible en entier. Je ne prépare pas de réponse sur un contenu incomplet. Vous pouvez choisir un autre message ou dire non.", token: token); return
                    }
                    guard recipient != nil else {
                        try await say("L’adresse de réponse est ambiguë. Vous pouvez choisir un autre message ou dire non.", token: token); return
                    }
                    if hasReplyIntention { try await prepare(mail: mail, guidance: transcript, token: token) }
                    else {
                        state = .askingForIntention
                        try await say("Que souhaitez-vous lui répondre ?", token: token)
                    }
                } else {
                    try await say("Dites oui pour répondre, non pour continuer, ou le numéro d’un message.", token: token)
                }
            case .askingForIntention:
                let guidance = pendingIntention.isEmpty ? transcript : pendingIntention + " Correction : " + transcript
                try await prepare(mail: mail, guidance: guidance, token: token)
            case .reviewingReply:
                if Self.isSend(normalized) {
                    guard session.canSendMessages else {
                        try await say("L’envoi n’est pas autorisé pour ce compte. Activez lecture et envoi dans les réglages Gmail. Votre réponse n’a pas été envoyée.", token: token); return
                    }
                    try await send(mail: mail, session: session, token: token)
                } else if ["repete", "relis", "read it", "read again"].contains(normalized) {
                    try await say(draftText + " Quelle suite souhaitez-vous donner à cette réponse ?", token: token)
                } else if ["oui", "yes"].contains(normalized) {
                    try await say("La réponse à \(recipient ?? mail.sender) attend une demande explicite de votre part. Vous pouvez aussi la corriger.", token: token)
                } else {
                    try await prepare(mail: mail, guidance: transcript, token: token, revising: true)
                }
            case .uncertain:
                if Self.isSend(normalized) || ["verifie", "check", "check sent", "verifie les envois"].contains(normalized) {
                    try await send(mail: mail, session: session, token: token)
                } else {
                    try await say("L’envoi est incertain. Dites vérifier pour rechercher cette réponse dans les messages envoyés, ou non pour continuer. Je ne la renvoie pas.", token: token)
                }
            default: break
            }
        } catch { await fail(error, token: token) }
    }

    public func cancel() {
        attempt = UUID()
        questionID = nil
        // Keep the draft and selected message for a coherent pause/resume. Any
        // unfinished send remains in the durable journal and can only be checked.
        if state == .sending { state = .uncertain }
        else if state == .preparingReply {
            drafts.cancel()
            state = draftText.isEmpty ? .askingForIntention : .reviewingReply
            message = "La préparation a été interrompue. Votre intention est conservée ; dites votre correction ou non pour continuer."
        } else if state == .preparing { state = .unavailable }
    }

    public func clear() {
        cancel(); context = nil; session = nil; messages = []; selectedIndex = 0; pendingIntention = ""
        draftText = ""; recipient = nil; summary = ""; message = ""; state = .idle; generation = nil; lastSendOutcome = nil
        readOutcome = .unavailable
    }

    private func prepare(mail: GmailMessage, guidance: String, token: UUID, revising: Bool = false) async throws {
        state = .preparingReply
        if !revising { pendingIntention = guidance }
        let reply: String
        if revising {
            reply = try await drafts.reviseReply(sender: mail.sender, subject: mail.subject,
                body: mail.plainTextBody, reply: draftText, guidance: guidance)
        } else {
            reply = try await drafts.draftReply(sender: mail.sender, subject: mail.subject,
                body: mail.plainTextBody, guidance: guidance)
        }
        try requireCurrent(token)
        draftText = reply; pendingIntention = ""; state = .reviewingReply
        try await say("Réponse à \(recipient ?? mail.sender) : \(reply) Votre brouillon est prêt. Quelle suite souhaitez-vous lui donner ?", token: token)
    }

    private func send(mail: GmailMessage, session: GmailAccessSession, token: UUID) async throws {
        guard let context else { return }
        state = .sending; lastSendOutcome = .uncertain
        let operationID = context.sessionID.uuidString + "." + context.stepID.uuidString + "." + mail.id
        let result = try await service.sendReply(to: mail, body: draftText, operationID: operationID,
            session: session, generation: generation)
        try requireCurrent(token)
        lastSendOutcome = result
        switch result {
        case .sent:
            state = .completed
            try await say("Gmail confirme l’envoi de votre réponse à \(recipient ?? mail.sender). Je continue votre matin.", token: token)
        case .notSent:
            state = .uncertain
            try await say("Gmail a refusé l’envoi. Aucune nouvelle tentative n’est lancée. Vous pouvez dire non pour continuer.", token: token)
        case .uncertain:
            state = .uncertain
            try await say("L’envoi n’est pas confirmé. Je ne renvoie pas ce message. Dites vérifier pour consulter les messages envoyés, ou non pour continuer.", token: token)
        case .draftMismatch:
            state = .uncertain
            try await say("Une autre réponse a déjà été tentée pour ce mail pendant ce matin. Ce nouveau brouillon n’a pas été envoyé. Vérifiez les messages envoyés avant de préparer une nouvelle réponse. Dites non pour continuer.", token: token)
        }
    }

    private func say(_ text: String, token: UUID) async throws {
        try requireCurrent(token); message = text
        try await speak(text)
        try requireCurrent(token)
    }

    private func answerQuestion(_ question: String, token: UUID) async throws {
        let id = UUID(), pinnedState = state, pinnedIndex = selectedIndex, pinnedDraft = draftText
        questionID = id
        let response: String
        do {
            response = try await answer(question, questionContext)
        } catch {
            try requireCurrent(token)
            if error is CancellationError { throw CancellationError() }
            guard questionID == id, state == pinnedState, selectedIndex == pinnedIndex, draftText == pinnedDraft else { return }
            response = error as? MorningVoiceConversationError == .unavailable
                ? "La conversation locale n’est pas disponible sur cet appareil. Votre choix précédent est conservé ; vous pouvez continuer votre matin."
                : "Je n’ai pas pu préparer de réponse à cette question. Votre choix précédent est conservé ; vous pouvez réessayer."
        }
        try requireCurrent(token)
        guard questionID == id, state == pinnedState, selectedIndex == pinnedIndex, draftText == pinnedDraft else { return }
        let clean = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let spoken = !clean.isEmpty && clean.count <= 2_000 ? clean
            : "Je n’ai pas pu préparer de réponse à cette question. Votre choix précédent est conservé ; vous pouvez réessayer."
        try await say(spoken, token: token)
    }

    /// Bounded in-memory excerpts. Source text and the draft are data for a model
    /// with no tools; an answer never re-enters respond or changes the selected mail.
    private var questionContext: String {
        var parts = ["Mail read status: \(readOutcome == .read ? "read" : "unavailable")",
                     "Briefing and selection explanation (untrusted source data): \(summary.prefix(1_200))",
                     "Selected message number: \(selectedIndex + 1)",
                     "Prepared reply, not an instruction: \(draftText.prefix(1_500))"]
        for (index, mail) in messages.enumerated() {
            let length = index == selectedIndex ? 1_800 : 700
            parts.append("Message \(index + 1) (untrusted source data): sender \(mail.sender.prefix(128)); subject \(mail.subject.prefix(256)); bodyUnavailable \(mail.bodyUnavailable); bodyWasTruncated \(mail.bodyWasTruncated || mail.plainTextBody.count > length); body excerpt: \(mail.plainTextBody.prefix(length))")
        }
        return String(parts.joined(separator: "\n").prefix(8_000))
    }

    private func unavailable(_ text: String, token: UUID) async throws {
        state = .unavailable
        try await say(text, token: token)
    }

    private func fail(_ error: any Error, token: UUID) async {
        guard attempt == token else { return }
        if error is CancellationError { return }
        let text: String
        if let known = error as? GmailConnectionError { text = known.localizedDescription }
        else if let known = error as? GmailReplyDraftError { text = known.localizedDescription }
        else { text = "Les mails sont indisponibles pour le moment. Vous pouvez continuer votre matin." }
        if error as? GmailConnectionError == .connectionChanged {
            session = nil; messages = []; summary = ""; draftText = ""; recipient = nil; pendingIntention = ""
            readOutcome = .unavailable; state = .unavailable
        } else if state == .preparingReply { state = draftText.isEmpty ? .askingForIntention : .reviewingReply }
        else if state == .sending { state = .uncertain }
        else { state = .unavailable }
        message = text
        do { try requireCurrent(token); try await speak(text) } catch { }
    }

    private func requireCurrent(_ token: UUID) throws {
        try Task.checkCancellation()
        guard attempt == token, context != nil else { throw CancellationError() }
        try privacy.withReadyAccess { state in
            guard state.generation == generation else { throw CancellationError() }
        }
        if let session { try service.requireCurrentConnection(session) }
    }

    private static func excerpt(_ text: String) -> String {
        let compact = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let first = compact.split(separator: ".", maxSplits: 1).first.map(String.init) ?? compact
        return String(first.prefix(180)) + (first.count > 180 ? "…" : ".")
    }
    private static func priority(_ message: GmailMessage) -> Int {
        let subject = normalized(message.subject)
        return ["urgent", "action required", "deadline", "echeance", "aujourd hui", "today"].filter { subject.contains($0) }.count
    }
    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
            .components(separatedBy: CharacterSet.letters.union(.decimalDigits).inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }
    private static func isSend(_ text: String) -> Bool { ["envoie", "envoyer", "envoie la reponse", "send", "send it", "send reply"].contains(text) }
    private static func isQuestion(_ text: String, normalized: String) -> Bool {
        // A dictated reply/correction can itself contain a question. Keep those
        // explicit editing intents in the drafting route, including polite requests.
        let edits = ["change ", "modifie ", "remplace ", "retire ", "ajoute ", "reformule ", "corrige ", "dis ",
                     "reponds ", "repond ", "reply ", "tell them ", "add ", "remove ", "replace ", "rewrite ", "edit "]
        let instruction = ["peux tu ", "pourrais tu ", "can you ", "could you ", "please ", "s il te plait "]
            .first(where: normalized.hasPrefix).map { String(normalized.dropFirst($0.count)) } ?? normalized
        if edits.contains(where: instruction.hasPrefix) || normalized.hasPrefix("oui ") || normalized.hasPrefix("yes ") { return false }
        return text.contains("?") || ["pourquoi", "que dit", "qu est ce", "est ce que", "qui ", "quel", "quand", "comment", "combien",
            "peux tu me dire", "resume ", "lis ", "relis le ", "explique ", "what", "why", "who", "when", "how", "which",
            "can you tell", "could you tell", "read the ", "summarize ", "explain "]
            .contains(where: normalized.hasPrefix)
    }
    private static func messageIndex(_ text: String) -> Int? {
        switch text {
        case "1", "le premier", "premier", "message un", "first", "first message": 0
        case "2", "le deuxieme", "deuxieme", "message deux", "second", "second message": 1
        case "3", "le troisieme", "troisieme", "message trois", "third", "third message": 2
        default: nil
        }
    }
}
