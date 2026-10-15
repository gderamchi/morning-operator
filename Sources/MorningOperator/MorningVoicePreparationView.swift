import SwiftUI
import MorningApple
import MorningCore
import UIKit

/// Requests system grants only after this explicit UI action. It never starts
/// an audio engine, records a test sample or declares an acoustic check passed.
struct MorningVoicePreparationView: View {
    @Bindable var store: MorningStore
    var startRequest: MorningVoiceStartRequest? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var operation: Task<Void, Never>?
    @State private var visible = false
    @State private var preparedStartPending = false
    @State private var releaseIssue: String?
    private var french: Bool { AppLanguage.isFrench }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    PageHeading(eyebrow: french ? "Votre voix" : "Your voice",
                        title: french ? "Préparer l’écoute" : "Prepare listening",
                        subtitle: french ? "Autorisez la reconnaissance locale et le microphone avant votre matin. L’écoute commencera seulement pendant la session."
                            : "Allow local recognition and microphone access before your morning. Listening starts only during the session.")
                    MorningVoiceAccessStatusView(access: store.voiceAccess)
                    if let releaseIssue { Text(releaseIssue).font(.raleway(.subheadline)).accessibilityIdentifier("voice.access.releaseIssue") }
                    if store.forcesVoicePreparationReviewForUITests {
                        Text("SYNTHETIC prestart entry · system permission statuses are real · no simulated microphone")
                            .font(.raleway(.caption)).accessibilityIdentifier("voice.access.synthetic")
                    }
                    Text(french ? "Cette préparation n’enregistre aucun son et ne teste pas le microphone. La lecture à voix haute et l’enchaînement de votre routine restent des choix distincts."
                         : "This preparation records no audio and does not test the microphone. Reading aloud and continuing your routine remain separate choices.")
                        .font(.raleway(.subheadline)).fixedSize(horizontal: false, vertical: true)
                    if store.voiceAccess.snapshot.canRequest {
                        Button(startRequest == nil
                            ? (french ? "Préparer les autorisations" : "Prepare permissions")
                            : (french ? "Préparer puis commencer" : "Prepare, then begin")) { prepare() }
                            .buttonStyle(PrimaryButtonStyle()).disabled(store.voiceAccess.isRequesting)
                            .accessibilityIdentifier("voice.access.prepare")
                    } else if store.voiceAccess.snapshot.isReady, let startRequest {
                        Button(french ? "Commencer avec l’écoute" : "Begin with listening") {
                            if store.finishVoicePreparation(startRequest, listen: true) { dismiss() }
                        }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("voice.access.begin")
                    }
                    if store.voiceAccess.isRequesting { ProgressView(french ? "Autorisations en cours…" : "Preparing permissions…") }
                    if store.voiceAccess.snapshot.canOpenSettings {
                        Link(french ? "Ouvrir les réglages iPhone" : "Open iPhone settings",
                             destination: URL(string: UIApplication.openSettingsURLString)!)
                            .accessibilityIdentifier("voice.access.settings")
                    }
                    Button(french ? "Actualiser l’état" : "Refresh status") {
                        store.voiceAccess.refresh(language: store.voicePreparationLanguage)
                    }.buttonStyle(SecondaryButtonStyle()).disabled(store.voiceAccess.isRequesting)
                        .accessibilityIdentifier("voice.access.refresh")
                    if let startRequest {
                        Button(french ? "Commencer sans écoute" : "Begin without listening") {
                            beginWithoutListening(startRequest)
                        }.buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("voice.access.withoutListening")
                        Text(french ? "MORE pourra lire et enchaîner les moments selon vos réglages. Utilisez les boutons pour le contrôler pendant ce matin."
                             : "MORE can still read and continue moments according to your settings. Use the buttons to control this morning.")
                            .font(.raleway(.caption)).fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity, alignment: .leading)
            }.background(MorningPaper(showsSun: false)).foregroundStyle(MorningStyle.ink)
                .navigationTitle(french ? "Écoute" : "Listening").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button(french ? "Fermer" : "Close") { stopRequest(); dismiss() }
                        .accessibilityIdentifier("voice.access.close")
                } }
        }
        .onAppear { visible = true; store.voiceAccess.refresh(language: store.voicePreparationLanguage) }
        .onDisappear { visible = false; stopRequest() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { stopRequest(); dismiss() }
            else if phase == .active {
                store.voiceAccess.refresh(language: store.voicePreparationLanguage)
                completePreparedStart()
            }
        }
        .onChange(of: store.dataGeneration) { _, _ in stopRequest(); dismiss() }
        .onChange(of: store.routine?.id) { _, _ in if startRequest != nil { stopRequest(); dismiss() } }
        .onChange(of: store.privacyBlocksWork) { _, blocked in if blocked { stopRequest(); dismiss() } }
    }

    private func stopRequest() {
        preparedStartPending = false
        operation?.cancel(); operation = nil; store.voiceAccess.cancel()
    }
    private func completePreparedStart() {
        guard preparedStartPending, visible, scenePhase == .active, let startRequest else { return }
        if store.finishVoicePreparation(startRequest, listen: true) { preparedStartPending = false; dismiss() }
    }
    private func beginWithoutListening(_ request: MorningVoiceStartRequest) {
        stopRequest(); releaseIssue = nil
        operation = Task { @MainActor in
            do {
                // An earlier duplex owner must release completely before normal
                // TTS is allowed to use its output-only playback session.
                try await store.handsFreeVoice.stopAndRelease()
                try Task.checkCancellation()
                guard visible, scenePhase == .active, store.voicePreparationIsCurrent(request) else { return }
                operation = nil
                if store.finishVoicePreparation(request, listen: false) { dismiss() }
            } catch is CancellationError { operation = nil }
            catch {
                operation = nil
                guard visible, store.voicePreparationIsCurrent(request) else { return }
                releaseIssue = french ? "Le microphone n’a pas pu être libéré. Réessayez avant de commencer."
                    : "The microphone could not be released. Try again before beginning."
            }
        }
    }
    private func prepare() {
        guard visible, scenePhase == .active, !store.privacyBlocksWork, !store.voiceAccess.isRequesting else { return }
        let generation = store.dataGeneration
        operation = Task { @MainActor in
            do {
                let ready = try await store.voiceAccess.requestAccess(language: store.voicePreparationLanguage)
                try Task.checkCancellation()
                guard visible, scenePhase != .background, generation == store.dataGeneration, !store.privacyBlocksWork else { return }
                operation = nil
                preparedStartPending = ready.isReady && startRequest != nil
                completePreparedStart()
            } catch { operation = nil }
        }
    }
}

struct MorningVoiceAccessStatusView: View {
    @Bindable var access: MorningVoiceAccess
    var body: some View {
        Text(access.snapshot.description(french: AppLanguage.isFrench))
            .font(.raleway(.subheadline)).fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("voice.access.status")
    }
}
