import AppIntents
import Foundation
import MorningApple
import MorningCore

/// Any app the person picks in their automation: a suggested name or one they type.
/// iOS does not let this app list installed apps, so the name is the person's own.
struct ShortcutAppEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "App"
    static let defaultQuery = ShortcutAppQuery()
    let id: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(id)") }
    var observedApp: ObservedApp? { ObservedApp(name: id) }
    init(_ app: ObservedApp) { id = app.displayName }
}

struct ShortcutAppQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [ShortcutAppEntity] {
        identifiers.compactMap { ObservedApp(name: $0).map(ShortcutAppEntity.init) }
    }

    /// Matching suggestions first; the typed name itself is always offered too.
    func entities(matching string: String) async throws -> [ShortcutAppEntity] {
        let key = ObservedApp.key(for: string)
        var matches = ObservedApp.suggested.filter { $0.id.contains(key) }
        if let typed = ObservedApp(name: string), !matches.contains(typed) { matches.insert(typed, at: 0) }
        return matches.map(ShortcutAppEntity.init)
    }

    func suggestedEntities() async throws -> [ShortcutAppEntity] {
        ObservedApp.suggested.map(ShortcutAppEntity.init)
    }
}

enum ShortcutAppTransition: String, AppEnum {
    case entered, exited
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "App transition"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .entered: "Opened or switched to", .exited: "Closed or switched from"
    ]
    var kind: AppTransitionKind { self == .entered ? .entered : .exited }
}

/// Add this action to user-created per-app Opened/Closed personal automations.
/// It neither observes other apps by itself nor brings Morning Operator to the foreground.
struct LogAppTransitionIntent: AppIntent {
    static let title: LocalizedStringResource = "Log an app transition"
    static let description = IntentDescription("Record a transition supplied by your configured App automation. Counts observed app entries, not pickups. This action does not start screen recording.")
    static let supportedModes: IntentModes = .background

    @Parameter(title: "App") var app: ShortcutAppEntity
    @Parameter(title: "Transition", default: .entered) var transition: ShortcutAppTransition
    @Parameter(title: "Event ID", description: "Optional UUID generated once for this event. Reuse it only when retrying that same event.")
    var eventID: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$app): \(\.$transition)") { \.$eventID }
    }

    func perform() async throws -> some IntentResult {
        let supplied = eventID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let id: UUID
        if let supplied, !supplied.isEmpty {
            guard let parsed = UUID(uuidString: supplied) else { throw TransitionIntentError.invalidEventID }
            id = parsed
        } else { id = UUID() }
        guard let observed = app.observedApp else { throw TransitionIntentError.invalidApp }
        try await AppTransitionLogStore.shared.record(app: observed, kind: transition.kind, eventID: id)
        return .result()
    }
}

private enum TransitionIntentError: LocalizedError {
    case invalidEventID, invalidApp
    var errorDescription: String? {
        switch self {
        case .invalidEventID: String(localized: "Use a valid UUID for the event identifier, or leave it empty.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
        case .invalidApp: String(localized: "Choose an app name of up to 60 characters.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
        }
    }
}
