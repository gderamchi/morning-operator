import Foundation

/// Only operation metadata is saved. Page text, mail and voice input stay in memory.
public struct RoutineExecutionRecord: Codable, Equatable, Sendable, Identifiable {
    public enum Outcome: String, Codable, Sendable {
        case running, completed, budgetFinished, skipped, unavailable, uncertain, interrupted
    }
    public var id: UUID { stepID }
    public let sessionID: UUID
    public let stepID: UUID
    public var outcome: Outcome
    public var observedContents: Int
    public var confirmedLikes: Int
    /// A provider receipt was observed even if presenting its result later failed.
    /// No provider content is retained in the record.
    public var confirmedExternalEffect: Bool?
    public var updatedAt: Date

    public init(sessionID: UUID, stepID: UUID, outcome: Outcome, observedContents: Int = 0,
                confirmedLikes: Int = 0, confirmedExternalEffect: Bool? = nil, updatedAt: Date = Date()) {
        self.sessionID = sessionID; self.stepID = stepID; self.outcome = outcome
        self.observedContents = max(0, observedContents); self.confirmedLikes = max(0, confirmedLikes)
        self.confirmedExternalEffect = confirmedExternalEffect
        self.updatedAt = updatedAt
    }
}

public extension RoutineStep {
    var executionDescription: String {
        let service: String?
        switch target {
        case let .inAppWeb(url): service = WebMorningSite(url: url)?.displayName ?? url.host
        case let .externalApp(app, _): service = app.displayName
        case let .shortcut(name, _): service = "Shortcuts · \(name)"
        case let .connectedAPI(name, _, _, _): service = name.replacingOccurrences(of: "_", with: " ").capitalized
        case nil: service = automation == .gmailInbox ? "Gmail" : nil
        }
        return service.map { "\($0) · \(operationDescription)" } ?? operationDescription
    }
    private var operationDescription: String {
        let fr = AppLanguage.isFrench
        if case .inAppWeb = target {
            guard let webBehavior else { return fr ? "Ouvrir la page ; navigation manuelle." : "Open the page; browse yourself." }
            let behavior: String
            switch webBehavior {
            case .browseFeed: behavior = fr ? "Parcourir les publications" : "Browse the feed"
            case .watchVideos: behavior = fr ? "Lire les vidéos et passer aux suivantes" : "Play videos and move to the next"
            case .watchStories: behavior = fr ? "Ouvrir et parcourir les stories" : "Open and browse stories"
            case .readHeadlines: behavior = fr ? "Parcourir et lire les titres" : "Browse and read headlines"
            case .readUnread: behavior = fr ? "Lire les conversations non lues" : "Read unread conversations"
            }
            let likes = webLikesAllowed == true
                ? (fr ? ". Aimer jusqu’à 3 contenus affichés." : ". Like up to 3 displayed contents.")
                : (fr ? ". Aucun like." : ". No likes.")
            return behavior + likes
        }
        if case .externalApp = target { return fr ? "Ouvrir l’application ; les gestes restent manuels." : "Open the app; its actions remain manual." }
        if case .shortcut = target { return fr ? "Exécuter le raccourci installé et vérifier son retour." : "Run the installed shortcut and check its return." }
        if case .connectedAPI = target { return fr ? "Effectuer l’action du compte présentée ci-dessous." : "Perform the account action described below." }
        switch automation {
        case .spokenNote: return fr ? "Lire le texte de ce moment." : "Read this moment’s text."
        case .todayCalendar: return fr ? "Lire les événements du jour de vos calendriers choisis." : "Read today’s events from your selected calendars."
        case .morningBriefing: return fr ? "Préparer et lire votre calendrier et la météo disponibles." : "Prepare and read your available calendar and weather."
        case .savedObservation: return fr ? "Lire votre extrait enregistré, sans le présenter comme une information du jour." : "Read your saved excerpt as a past observation."
        case .timedMoment: return fr ? "Vous laisser ce temps, puis passer automatiquement à la suite." : "Give you this time, then continue automatically."
        case .gmailInbox: return fr ? "Lire vos mails non lus, préparer et corriger une réponse. Envoyer seulement à votre demande." : "Read unread mail, prepare and edit a reply. Send only when you ask."
        case nil: return fr ? "Moment personnel. Dites « suivant » lorsque vous avez terminé." : "Your own moment. Say “next” when you finish."
        }
    }
}
