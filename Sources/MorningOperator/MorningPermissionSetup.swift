import AVFAudio
import AlarmKit
import Foundation
import MorningApple
import MorningCore
import Observation
import Speech
import SwiftUI
import UserNotifications

@MainActor @Observable
final class MorningPermissionSetup {
    var isPresented = false
    private(set) var remaining: [MorningPermission] = []
    private(set) var isRequesting = false
    private enum Outcome { case skipped, allowed, denied, unavailable }
    private enum SaveIssue { case restore, save }
    private var outcome: Outcome?
    private var issue: SaveIssue?
    var lastOutcome: String? {
        switch outcome {
        case .skipped: Self.text("You can enable this access later in iPhone Settings.", "Vous pourrez activer cet accès plus tard dans les réglages de l’iPhone.")
        case .allowed: Self.text("Access is ready. You remain in control of when MORE uses it.", "L’accès est prêt. Vous gardez le contrôle de son utilisation par MORE.")
        case .denied: Self.text("Access wasn't enabled. Your morning can continue, and you can change this later in Settings.", "L’accès n’a pas été activé. Votre matinée peut continuer ; vous pourrez le modifier dans les réglages.")
        case .unavailable: Self.text("This access isn't available right now. Continue and review it later in Settings.", "Cet accès est indisponible pour le moment. Continuez et retrouvez-le plus tard dans les réglages.")
        case nil: nil
        }
    }
    var saveIssue: String? {
        switch issue {
        case .restore: Self.text("Your access choices couldn't be restored. You can still review them; the saved file stays intact.", "Vos choix d’accès n’ont pas pu être relus. Vous pouvez les revoir ; le fichier enregistré reste intact.")
        case .save: Self.text("These access choices couldn't be saved. MORE may ask you to review them next time.", "Ces choix d’accès n’ont pas pu être enregistrés. MORE pourra vous les présenter à la prochaine ouverture.")
        case nil: nil
        }
    }
    private var progress = MorningPermissionProgress()
    private let file: AtomicJSONFile<MorningPermissionProgress>
    private let control: LocalDataControl
    private let isolated: Bool
    private var generation: UUID?
    private var attempt: UUID?
    private var requestTask: Task<Void, Never>?
    private var canSave = true
    var current: MorningPermission? { remaining.first }
    var needsInitialSetup: Bool { !progress.pending(supported: supported).isEmpty && !isolatedBypass }
    private var isolatedBypass: Bool {
        isolated && !ProcessInfo.processInfo.arguments.contains("--ui-testing-permissions")
    }

    init(directory: URL, isolated: Bool) {
        self.isolated = isolated
        control = LocalDataControl(directory: directory)
        file = AtomicJSONFile(url: directory.appendingPathComponent("permission-setup.json"), maximumBytes: 16 * 1_024)
        do {
            progress = try control.withReadyAccess { state in
                generation = state.generation
                do { return try file.load() }
                catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
                    // Data(contentsOf:) and bounded FileHandle reads use different
                    // Cocoa codes for a genuinely absent first-launch file.
                    return MorningPermissionProgress()
                }
            }
        } catch {
            canSave = false
            issue = .restore
        }
    }

    var screenTimeUnavailableNote: String? {
        supported.contains(.screenTime) ? nil : Self.text("Screen Time needs a compatible iPhone and app capability. You can review its availability later from Learn or Settings.", "Temps d’écran nécessite un iPhone compatible et un accès disponible dans cette version. Retrouvez son état plus tard dans Apprendre ou Réglages.")
    }
    private var supported: [MorningPermission] {
        var values: [MorningPermission] = [.location, .calendar, .reminders]
        if isolated || Self.screenTimeCapabilityAvailable { values.append(.screenTime) }
        values += [.speech, .microphone, .notifications, .alarms]
        return values
    }

    func presentIfNeeded() {
        guard needsInitialSetup, !isPresented else { return }
        remaining = progress.pending(supported: supported)
        isPresented = true
    }

    func revisit() {
        guard !isRequesting else { return }
        remaining = supported; outcome = nil
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) { isPresented = true }
    }

    func skip() {
        guard let current, !isRequesting else { return }
        resolve(current, outcome: .skipped)
    }

    func allow(store: MorningStore) {
        guard let permission = current, !isRequesting, !store.privacyBlocksWork else { return }
        let id = UUID(); attempt = id; isRequesting = true
        requestTask = Task { @MainActor [weak self, weak store] in
            guard let self, let store else { return }
            let allowed: Bool
            do {
                if isolated {
                    // Explicit isolated fixture: tests exercise explanation/queue/persistence,
                    // never alter the simulator or a person's system authorizations.
                    allowed = !ProcessInfo.processInfo.arguments.contains("--ui-testing-permissions-denied")
                } else {
                    switch permission {
                    case .location:
                        _ = await store.briefing.enableCurrentLocation()
                        allowed = store.briefing.locationAuthorization == .authorized
                    case .calendar:
                        await store.briefing.requestCalendarAccess()
                        allowed = store.briefing.isCalendarAuthorized
                    case .reminders:
                        let reminders = ReminderService()
                        try await reminders.requestReminderAccess()
                        allowed = reminders.hasReminderAccess
                    case .screenTime:
                        try await store.screenTimeSource.requestAccess()
                        store.refreshScreenTimeAccess()
                        allowed = store.screenTimeSource.access == .approved
                    case .speech:
                        let raw = await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
                            let completion: @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void = {
                                continuation.resume(returning: $0.rawValue)
                            }
                            SFSpeechRecognizer.requestAuthorization(completion)
                        }
                        allowed = raw == SFSpeechRecognizerAuthorizationStatus.authorized.rawValue
                    case .microphone:
                        allowed = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                            let completion: @Sendable (Bool) -> Void = { continuation.resume(returning: $0) }
                            AVAudioApplication.requestRecordPermission(completionHandler: completion)
                        }
                    case .notifications:
                        allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                    case .alarms:
                        allowed = try await AlarmManager.shared.requestAuthorization() == .authorized
                    }
                }
                guard attempt == id, !Task.isCancelled, !store.privacyBlocksWork else { return }
                isRequesting = false; requestTask = nil; attempt = nil
                resolve(permission, outcome: allowed ? .allowed : .denied)
            } catch {
                guard attempt == id, !store.privacyBlocksWork else { return }
                isRequesting = false; requestTask = nil; attempt = nil
                if !(error is CancellationError) {
                    resolve(permission, outcome: .unavailable)
                }
            }
        }
    }

    func finish() {
        guard !isRequesting else { return }
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) { isPresented = false }
    }

    func cancelForBackground() {
        attempt = nil; requestTask?.cancel(); requestTask = nil; isRequesting = false
    }

    /// Privacy cleanup cancels publication before the app removes the owned file.
    func cancelForPrivacy() {
        attempt = nil; requestTask?.cancel(); requestTask = nil
        isRequesting = false; isPresented = false; remaining = []; outcome = nil
    }
    func resetAfterPrivacy() {
        progress = MorningPermissionProgress(); generation = try? control.status().generation
        canSave = true; issue = nil
    }

    private func resolve(_ permission: MorningPermission, outcome: Outcome) {
        guard remaining.first == permission else { return }
        var next = progress; next.resolve(permission)
        do {
            guard canSave else { throw CocoaError(.fileReadCorruptFile) }
            try control.withReadyAccess { state in
                guard state.generation == generation else { throw LocalDataControlError.staleGeneration }
                try file.save(next)
            }
            progress = next
        } catch {
            issue = .save
            // Keep this launch usable even when persistence is unavailable.
            progress = next
        }
        remaining.removeFirst(); self.outcome = outcome
    }

    private static var screenTimeCapabilityAvailable: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        guard #available(iOS 26.4, *) else { return false }
        // Personal development profiles disclose the capabilities they grant.
        // When a profile is absent, don't present a permission we can't establish.
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(from: data[start.lowerBound..<end.upperBound], options: [], format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any]
        else { return false }
        return entitlements["com.apple.developer.family-controls"] as? Bool == true &&
            entitlements["com.apple.developer.family-controls.app-and-website-usage"] as? Bool == true
        #endif
    }

    nonisolated static func text(_ english: String, _ french: String) -> String { AppLanguage.isFrench ? french : english }
}

struct MorningPermissionSetupView: View {
    @Bindable var store: MorningStore
    @Environment(\.scenePhase) private var scenePhase
    private var setup: MorningPermissionSetup { store.permissionSetup }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text("MORE").font(.raleway(.caption, .semibold)).tracking(4).foregroundStyle(MorningStyle.muted)
                if let permission = setup.current {
                    Text(MorningPermissionSetup.text("Make room for your morning.", "Préparons votre matinée."))
                        .font(.raleway(.title, .semibold))
                    Text(MorningPermissionSetup.text("Each access has a purpose. Choose what works for you, even if you learn your routine later.",
                        "Chaque accès a un rôle. Choisissez ceux qui vous conviennent, même si vous apprenez votre routine plus tard."))
                        .foregroundStyle(MorningStyle.muted)
                    Image(systemName: permission.symbol).font(.system(size: 48, weight: .light)).foregroundStyle(MorningStyle.accent)
                        .accessibilityHidden(true).padding(.vertical, 8)
                    Text(permission.title).font(.raleway(.title2, .semibold))
                        .accessibilityIdentifier("permissions.title.\(permission.rawValue)")
                    Text(permission.explanation).fixedSize(horizontal: false, vertical: true)
                    if let outcome = setup.lastOutcome {
                        Text(outcome).font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                            .accessibilityIdentifier("permissions.lastOutcome")
                    }
                    if setup.isRequesting { ProgressView(MorningPermissionSetup.text("Waiting for your choice…", "En attente de votre choix…")) }
                    Button(MorningPermissionSetup.text("Continue and allow", "Continuer et autoriser")) { if scenePhase == .active { setup.allow(store: store) } }
                        .buttonStyle(PrimaryButtonStyle()).disabled(setup.isRequesting || scenePhase != .active)
                        .accessibilityIdentifier("permissions.allow")
                    Button(MorningPermissionSetup.text("Not now", "Plus tard")) { setup.skip() }
                        .buttonStyle(SecondaryButtonStyle()).disabled(setup.isRequesting)
                        .accessibilityIdentifier("permissions.skip")
                } else {
                    Text(MorningPermissionSetup.text("Your morning is yours.", "Votre matinée vous appartient."))
                        .font(.raleway(.title, .semibold))
                    Text(MorningPermissionSetup.text("Your access choices are ready. Learn your routine whenever you want. You can review every access in Settings → iPhone permissions.",
                        "Vos choix d’accès sont prêts. Apprenez votre routine quand vous le souhaitez. Retrouvez les accès dans Réglages → Accès iPhone."))
                    if let outcome = setup.lastOutcome { Text(outcome).foregroundStyle(MorningStyle.muted) }
                    if let note = setup.screenTimeUnavailableNote { Text(note).font(.raleway(.caption)).foregroundStyle(MorningStyle.muted) }
                    Button(MorningPermissionSetup.text("Open MORE", "Ouvrir MORE")) { setup.finish() }
                        .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("permissions.finish")
                }
                if let issue = setup.saveIssue { Text(issue).font(.raleway(.caption)).foregroundStyle(MorningStyle.muted) }
            }.padding(30).frame(maxWidth: 600, alignment: .leading).frame(maxWidth: .infinity)
        }
        .id(setup.current)
        .background(MorningPaper(showsSun: false)).foregroundStyle(MorningStyle.ink)
        .font(MorningTheme.Typography.body)
        .interactiveDismissDisabled()
        .onChange(of: scenePhase) { _, phase in if phase == .background { setup.cancelForBackground() } }
        .transaction { $0.animation = nil; $0.disablesAnimations = true }
    }
}

private extension MorningPermission {
    var title: String {
        switch self {
        case .location: MorningPermissionSetup.text("The weather, where you are", "La météo, là où vous êtes")
        case .calendar: MorningPermissionSetup.text("See your day ahead", "Voir la journée qui arrive")
        case .reminders: MorningPermissionSetup.text("Keep your thoughts close", "Garder vos idées à portée")
        case .screenTime: MorningPermissionSetup.text("Understand your habits", "Comprendre vos habitudes")
        case .speech: MorningPermissionSetup.text("Understand your words", "Comprendre vos mots")
        case .microphone: MorningPermissionSetup.text("Hear you during your morning", "Vous entendre pendant votre matinée")
        case .notifications: MorningPermissionSetup.text("A timely invitation", "Une invitation au bon moment")
        case .alarms: MorningPermissionSetup.text("Wake up with MORE", "Se réveiller avec MORE")
        }
    }
    var explanation: String {
        switch self {
        case .location: MorningPermissionSetup.text("While MORE is open, your location brings you local weather and a sky that follows the sun. Your coordinates go to Apple Weather for local conditions and stay out of your saved history. An approximate location is enough; you can choose a city instead.", "Quand MORE est ouvert, votre position apporte la météo locale et un ciel qui suit le soleil. Vos coordonnées sont transmises à Apple Météo pour la météo et ne sont pas enregistrées dans votre historique. Une position approximative suffit ; vous pouvez aussi choisir une ville.")
        case .calendar: MorningPermissionSetup.text("MORE can read your upcoming events for your morning recap. Apple requires full calendar access; you choose which calendars MORE reads in Settings. Saving an event still needs your instruction.", "MORE peut lire vos prochains rendez-vous pour votre récap du matin. Apple exige l’accès complet ; vous choisissez les calendriers à lire dans les réglages. Enregistrer un événement nécessite toujours votre instruction.")
        case .reminders: MorningPermissionSetup.text("MORE can read upcoming reminders and save a thought as a reminder when you ask. Permission alone never creates, changes or completes a reminder.", "MORE peut lire vos rappels à venir et enregistrer une idée en rappel à votre demande. Cette autorisation ne crée, ne modifie et ne termine aucun rappel à elle seule.")
        case .screenTime: MorningPermissionSetup.text("Available app-use times help MORE understand your morning habits and propose a routine for you to review. The available coverage depends on your iPhone and Apple's approval; it doesn't reveal what you read inside other apps.", "Les durées d’utilisation disponibles aident MORE à comprendre vos habitudes et à proposer une routine à relire. La couverture dépend de votre iPhone et de l’autorisation Apple ; elle ne révèle pas ce que vous lisez dans les autres apps.")
        case .speech: MorningPermissionSetup.text("Speech recognition turns your spoken instructions into text so you can pause, ask a question or shape a draft. MORE uses on-device recognition; this access doesn't activate the microphone.", "La reconnaissance vocale transforme vos instructions en texte pour mettre en pause, poser une question ou préparer un brouillon. MORE utilise la reconnaissance sur l’appareil ; cet accès n’active pas le microphone.")
        case .microphone: MorningPermissionSetup.text("The microphone lets MORE hear your instructions during the voice interaction you start. It stays off during this setup. You can stop a listening turn at any time.", "Le microphone permet à MORE d’entendre vos instructions pendant l’interaction vocale que vous démarrez. Il reste éteint pendant cette configuration. Vous pouvez arrêter une écoute à tout moment.")
        case .notifications: MorningPermissionSetup.text("Notifications can invite you to your next morning or remind you to start a recording. Nothing is scheduled by granting access; you choose the time later.", "Les notifications peuvent vous inviter à votre prochaine matinée ou vous rappeler de démarrer un enregistrement. Autoriser cet accès ne programme rien ; vous choisirez l’heure plus tard.")
        case .alarms: MorningPermissionSetup.text("MORE can schedule the morning alarm you choose, with a shortcut into your morning when you stop it. Allowing alarms doesn't create an alarm; you set it later.", "MORE peut programmer le réveil que vous choisissez et ouvrir votre matinée à son arrêt. Autoriser les réveils n’en crée aucun ; vous le réglerez plus tard.")
        }
    }
    var symbol: String {
        switch self {
        case .location: "location"
        case .calendar: "calendar"
        case .reminders: "checklist"
        case .screenTime: "hourglass"
        case .speech: "text.bubble"
        case .microphone: "mic"
        case .notifications: "bell"
        case .alarms: "alarm"
        }
    }
}
