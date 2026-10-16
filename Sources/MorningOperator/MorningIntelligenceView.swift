import SwiftUI
import MorningApple

struct MorningIntelligenceView: View {
    @Bindable var store: MorningStore
    @State private var model = MoreLanguageModel.shared
    @State private var memory = MorePersonalMemory.shared
    @State private var apiKey = ""
    @State private var allowsSharing = false
    @State private var issue: String?
    private var french: Bool { AppLanguage.isFrench }

    var body: some View {
        MorningForm {
            Section(french ? "Modèle actif" : "Active model") {
                Text(model.summary).accessibilityIdentifier("intelligence.status")
                Text(french
                    ? "Le modèle comprend les observations, prépare les réponses et propose les actions. MORE vérifie les autorisations avant toute exécution."
                    : "The model understands observations, prepares answers and proposes actions. MORE checks permissions before execution.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("OpenAI") {
                SecureField(french ? "Clé API personnelle" : "Personal API key", text: $apiKey)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("intelligence.apiKey")
                if !model.usesOpenAI || !apiKey.isEmpty {
                    Toggle(french ? "J’accepte ce partage pour activer OpenAI" : "I agree to this sharing to enable OpenAI", isOn: $allowsSharing)
                        .accessibilityIdentifier("intelligence.consent")
                }
                Text(french
                    ? "Si vous activez OpenAI, les extraits choisis pour l’analyse, les demandes vocales transcrites, les faits personnels mémorisés et le contexte utile des services seront envoyés à OpenAI. Les vidéos brutes et l’audio restent sur l’iPhone. Le stockage des réponses est désactivé. Les règles de conservation d’OpenAI restent applicables."
                    : "Enabling OpenAI sends selected analysis excerpts, transcribed voice requests, saved personal facts and relevant service context to OpenAI. Raw videos and audio stay on this iPhone. Response storage is disabled. OpenAI retention rules still apply.")
                    .font(.footnote).foregroundStyle(.secondary)
                if !model.usesOpenAI || !apiKey.isEmpty {
                  Button(french ? "Utiliser OpenAI" : "Use OpenAI") {
                    update {
                        try model.configureOpenAI(apiKey: apiKey, enabled: true)
                        apiKey = ""
                        allowsSharing = false
                    }
                }.disabled(!allowsSharing || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("intelligence.enable")
                }
                if model.usesOpenAI {
                    Button(french ? "Revenir au modèle Apple local" : "Use Apple's local model") {
                        update { try model.useLocal() }
                    }.accessibilityIdentifier("intelligence.local")
                }
                Button(french ? "Effacer la clé OpenAI" : "Remove OpenAI key", role: .destructive) {
                    update { try model.forget() }
                }.accessibilityIdentifier("intelligence.forgetKey")
                if let issue { Text(issue).font(.footnote).foregroundStyle(.secondary) }
            } footer: {
                Text(french
                    ? "La clé est conservée dans le trousseau de cet iPhone. Aucun basculement automatique vers OpenAI. Les frais de votre compte OpenAI s’appliquent."
                    : "The key is stored in this iPhone's Keychain. MORE never switches to OpenAI automatically. Your OpenAI account usage charges apply.")
            }
            Section(french ? "Ce que MORE retient de vous" : "What MORE remembers about you") {
                if memory.facts.isEmpty {
                    Text(french ? "Aucune habitude personnelle mémorisée." : "No personal habits saved yet.")
                }
                ForEach(memory.facts) { fact in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(fact.displayText).fixedSize(horizontal: false, vertical: true)
                        Button(french ? "Oublier" : "Forget", role: .destructive) {
                            update { try memory.forget(fact.key) }
                        }
                    }
                }
                Text(french
                    ? "MORE retient les faits personnels et préférences que vous lui indiquez et corrigez. Dites par exemple : « Je n’ai pas de trottinette, je prends les transports. » Une nouvelle correction remplace le fait précédent. MORE garde jusqu’à 24 faits récents."
                    : "MORE remembers personal facts and preferences you state and correct. For example: “I don't have an electric scooter; I take public transport.” A correction replaces the previous fact. MORE keeps up to 24 recent facts.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .disabled(store.privacyBlocksWork || store.sessionActive || store.busy)
        .navigationTitle(french ? "Intelligence et mémoire" : "Intelligence & memory")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { apiKey = "" }
    }

    private func update(_ action: () throws -> Void) {
        do {
            try action()
            issue = nil
            store.refreshCapabilities()
        } catch {
            issue = french ? "Ce réglage n’a pas pu être enregistré. Réessayez." : "This setting could not be saved. Try again."
        }
    }
}
