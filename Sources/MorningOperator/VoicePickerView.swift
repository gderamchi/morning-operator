import AVFAudio
import MorningApple
import MorningCore
import SwiftUI

/// The caller keeps this sheet unavailable during an active morning session.
struct VoicePickerView: View {
    @Bindable var speech: SpeechCoordinator
    @Environment(\.dismiss) private var dismiss
    @ViewState<String> private var search = ""
    @ViewState<[SpeechVoiceDescriptor]> private var voices = []
    @ViewState<UUID?> private var previewID = nil

    var body: some View {
        NavigationStack {
            MorningList {
                Section {
                    voiceRow(name: AppLanguage.localized("Automatic"), detail: automaticDetail, identifier: nil)
                        .accessibilityIdentifier("voice.default")
                } footer: {
                    Text("Matches MORE’s language, then prefers a higher-quality installed voice. Your choice applies to spoken morning steps.")
                }

                Section {
                    Button {
                        speech.speak(speech.previewText)
                        previewID = speech.playbackID
                    } label: {
                        Label("Preview selected voice", systemImage: "speaker.wave.2")
                    }
                    .accessibilityIdentifier("voice.preview")
                    .accessibilityValue(speech.statusText)

                    if let previewID, speech.playbackID == previewID {
                        if speech.state == .preparing {
                            ProgressView("Preparing audio…")
                        } else if speech.state == .paused {
                            Button("Resume preview") { speech.resume() }
                                .accessibilityIdentifier("voice.resumePreview")
                        }
                        Button {
                            stopPreview()
                        } label: {
                            Label("Stop preview", systemImage: "stop.circle")
                        }
                        .accessibilityIdentifier("voice.stopPreview")
                    }
                    if let error = speech.lastError {
                        Text(error).font(.raleway(.footnote)).foregroundStyle(MorningStyle.muted)
                    }
                } footer: {
                    if let selected = speech.voiceIdentifier, !voices.contains(where: { $0.id == selected }) {
                        Text("Your saved voice is unavailable. Speech uses the automatic choice until you select another.")
                    } else {
                        Text("Listen through your current audio output. These are Apple system speech voices; Siri may use a different voice.")
                    }
                }

                Section {
                    ForEach(filteredVoices) { voice in
                        voiceRow(name: voice.name,
                            detail: "\(languageName(voice.language)) · \(voice.quality.displayName)", identifier: voice.id)
                            .accessibilityIdentifier("voice.option.\(voice.id)")
                    }
                    if filteredVoices.isEmpty {
                        Text(search.isEmpty ? String(localized: "No installed voice is available for MORE’s language.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) : String(localized: "No matching voices.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale))
                            .foregroundStyle(MorningStyle.muted)
                    }
                } header: {
                    Text("Installed voices")
                } footer: {
                    Text("Voice language: \(AppLanguage.isFrench ? "Français" : "English")")
                        .accessibilityIdentifier("voice.currentLanguage")
                    Text("Only voices that match MORE’s language are shown. Your own routine text is preserved.")
                }

                Section("More natural voices") {
                    if !hasHigherQualityVoiceForAppLanguage {
                        Text("No Enhanced or Premium voice is available here for MORE’s language yet.")
                            .font(.raleway(.subheadline))
                    }
                    #if os(iOS)
                    Text("In Settings → Accessibility → Read & Speak → Voices, choose your language and download an Enhanced or Premium voice if offered. Return here after the download finishes.")
                        .font(.raleway(.footnote)).foregroundStyle(MorningStyle.muted)
                    Link("Apple’s voice settings guide", destination: URL(string: "https://support.apple.com/guide/iphone/iph96b214f0/ios")!)
                    #else
                    Text(AppLanguage.localized("More voices can be downloaded through the accessibility voice controls in System Settings. Return here when the download finishes."))
                        .font(.raleway(.footnote)).foregroundStyle(MorningStyle.muted)
                    #endif
                    Button("Refresh installed voices") { speech.repairVoiceSelection(); voices = speech.availableVoices }
                        .accessibilityIdentifier("voice.refresh")
                }
            }
            .navigationTitle("Your morning voice")
            .searchable(text: $search, prompt: "Search names or languages")
            .tint(MorningStyle.accent)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("voice.done")
                }
            }
            .onAppear { speech.repairVoiceSelection(); voices = speech.availableVoices }
            .onChange(of: AppLanguage.code) { _, _ in stopPreview(); voices = speech.availableVoices }
            .onReceive(NotificationCenter.default.publisher(for: AVSpeechSynthesizer.availableVoicesDidChangeNotification)) { _ in
                speech.repairVoiceSelection()
                voices = speech.availableVoices
            }
            .onDisappear { stopPreview() }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 520)
        #endif
    }

    private var filteredVoices: [SpeechVoiceDescriptor] {
        let compatible = voices.filter { speech.matchesPreferredLanguage($0.language) }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return compatible }
        return compatible.filter {
            $0.name.localizedStandardContains(query)
                || $0.language.localizedStandardContains(query)
                || languageName($0.language).localizedStandardContains(query)
                || $0.quality.displayName.localizedStandardContains(query)
        }
    }

    private var automaticDetail: String {
        guard let voice = speech.recommendedVoice else { return String(localized: "Follow MORE’s language", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) }
        return "\(voice.name) · \(languageName(voice.language)) · \(voice.quality.displayName)"
    }

    private var hasHigherQualityVoiceForAppLanguage: Bool {
        voices.contains { speech.matchesPreferredLanguage($0.language) && $0.quality != .standard }
    }

    private func voiceRow(name: String, detail: String, identifier: String?) -> some View {
        Button {
            stopPreview()
            speech.voiceIdentifier = identifier
        } label: {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).foregroundStyle(.primary)
                    Text(detail).font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                }
                Spacer()
                if speech.voiceIdentifier == identifier {
                    Image(systemName: "checkmark").foregroundStyle(MorningStyle.accent)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityLabel("\(name), \(detail)")
        .accessibilityValue(speech.voiceIdentifier == identifier ? String(localized: "Selected", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) : "")
    }

    private func languageName(_ code: String) -> String {
        AppLanguage.locale.localizedString(forIdentifier: code) ?? code
    }

    private func stopPreview() {
        guard let previewID else { return }
        self.previewID = nil
        if speech.playbackID == previewID { speech.stop() }
    }
}
