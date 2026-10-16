import SwiftUI
import MorningApple
import MorningCore

struct MorningConversationView: View {
    @Bindable var store: MorningStore
    @Environment(\.dismiss) private var dismiss
    @State private var starting = false
    private var french: Bool { AppLanguage.isFrench }

    var body: some View {
        NavigationStack {
            MorningForm {
                Section {
                    Text(french ? "Parlez naturellement à MORE. Vous pouvez l’interrompre et poursuivre la conversation."
                         : "Talk naturally with MORE. Interrupt and continue the conversation.")
                    if let caption = store.cloudVoice.caption { Text(caption).accessibilityIdentifier("cloudVoice.caption") }
                    if let error = store.cloudVoice.errorMessage { Text(error).foregroundStyle(MorningStyle.muted) }
                    if let error = store.cloudVoiceStartIssue { Text(error).foregroundStyle(MorningStyle.muted) }
                    if store.cloudVoice.isActive {
                        Label(store.cloudVoice.state == .speaking
                              ? (french ? "MORE parle" : "MORE is speaking")
                              : (french ? "MORE vous écoute" : "MORE is listening"), systemImage: "waveform")
                        Button(french ? "Arrêter la conversation" : "End conversation", role: .destructive) { store.stopCloudVoice() }
                            .accessibilityIdentifier("cloudVoice.stop")
                    } else {
                        Button {
                            starting = true
                            Task {
                                await store.startCloudVoice()
                                starting = false
                                if store.cloudVoice.isActive, store.session?.status == .paused { store.resume() }
                            }
                        } label: {
                            if starting { ProgressView() }
                            else { Text(french ? "Utiliser ElevenLabs" : "Use ElevenLabs") }
                        }.disabled(starting || store.cloudVoiceReleasing || store.privacyBlocksWork ||
                                   store.voiceInputBlocksPlayback)
                            .accessibilityIdentifier("cloudVoice.start")
                    }
                } header: { Text(french ? "Conversation naturelle" : "Natural conversation") }
                footer: {
                    Text(french
                         ? "En démarrant, vous partagez votre voix et les lectures de MORE durant cette conversation avec ElevenLabs et Google Gemini. L’écoute s’arrête en quittant l’app ou en arrêtant le matin."
                         : "Starting shares your voice and MORE’s spoken text during this conversation with ElevenLabs and Google Gemini. Listening ends when you leave the app or end the morning.")
                }
                Section {
                    DisclosureGroup(french ? "Quelles informations sont partagées ?" : "What is shared?") {
                        Text(french
                             ? "Les aperçus et récapitulatifs que vous lancez vous-même durant la conversation sont partagés. Si un matin est en cours, ses étapes et les informations que MORE prononce depuis vos sources choisies sont aussi partagées : calendrier, météo, messages lus et mesures Santé inclus dans cette routine. Aucun enregistrement vidéo ni historique Santé complet n’est envoyé."
                             : "Previews and recaps you choose to play during the conversation are shared. During an active morning, its routine steps and information MORE speaks from your chosen sources are also shared: calendar, weather, read messages and Health measurements included in this routine. No video recording or complete Health history is sent.")
                            .accessibilityIdentifier("cloudVoice.sharingDetails")
                        if let routine = store.sessionActive ? store.session?.routine : store.routine {
                            ForEach(routine.steps) { step in Text(step.title).font(.subheadline) }
                        }
                        Text(french
                             ? "Ce choix vaut pour cette session. L’autorisation Apple Santé seule n’active jamais ce partage. Vous pouvez garder la voix locale."
                             : "This choice applies to this session. Apple Health permission alone never enables this sharing. You can keep local voice.")
                        Link(french ? "Confidentialité ElevenLabs" : "ElevenLabs privacy", destination: URL(string: "https://elevenlabs.io/privacy-policy")!)
                    }.font(.footnote).foregroundStyle(MorningStyle.muted)
                }
            }
            .navigationTitle(french ? "Parler avec MORE" : "Talk with MORE")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.cloudVoice.isActive ? (french ? "Retour au matin" : "Back to morning") : String(localized: "Done")) { dismiss() }
                }
            }
        }.tint(MorningStyle.accent)
    }
}
