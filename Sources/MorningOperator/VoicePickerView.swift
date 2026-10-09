import AVFAudio
import MorningApple
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
            List {
                Section {
                    voiceRow(name: "System default", detail: "Follow this device’s language", identifier: nil)
                        .accessibilityIdentifier("voice.default")
                } footer: {
                    Text("Choose a voice already available on this device. Your choice applies to spoken morning steps.")
                }

                Section("Available voices") {
                    ForEach(filteredVoices) { voice in
                        voiceRow(name: voice.name, detail: languageName(voice.language), identifier: voice.id)
                            .accessibilityIdentifier("voice.option.\(voice.id)")
                    }
                    if filteredVoices.isEmpty {
                        Text(search.isEmpty ? "No additional built-in voices are available here." : "No matching voices.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button {
                        speech.speak("Good morning. Let’s make a little room for your day.")
                        previewID = speech.playbackID
                    } label: {
                        Label("Preview selected voice", systemImage: "speaker.wave.2")
                    }
                    .accessibilityIdentifier("voice.preview")

                    if let previewID, speech.playbackID == previewID {
                        Button {
                            stopPreview()
                        } label: {
                            Label("Stop preview", systemImage: "stop.circle")
                        }
                        .accessibilityIdentifier("voice.stopPreview")
                    }
                    if let error = speech.lastError {
                        Text(error).font(.footnote).foregroundStyle(.secondary)
                    }
                } footer: {
                    if let selected = speech.voiceIdentifier, !voices.contains(where: { $0.id == selected }) {
                        Text("Your saved voice is unavailable on this device. Speech will use the system default until you choose another.")
                    } else {
                        Text("The preview uses your current audio output. More voices can be downloaded in the device’s accessibility settings.")
                    }
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
            .onAppear { voices = speech.availableVoices }
            .onReceive(NotificationCenter.default.publisher(for: AVSpeechSynthesizer.availableVoicesDidChangeNotification)) { _ in
                voices = speech.availableVoices
            }
            .onDisappear { stopPreview() }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 520)
        #endif
    }

    private var filteredVoices: [SpeechVoiceDescriptor] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return voices }
        return voices.filter {
            $0.name.localizedStandardContains(query)
                || $0.language.localizedStandardContains(query)
                || languageName($0.language).localizedStandardContains(query)
        }
    }

    private func voiceRow(name: String, detail: String, identifier: String?) -> some View {
        Button {
            stopPreview()
            speech.voiceIdentifier = identifier
        } label: {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
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
        .accessibilityValue(speech.voiceIdentifier == identifier ? "Selected" : "")
    }

    private func languageName(_ code: String) -> String {
        Locale.current.localizedString(forIdentifier: code) ?? code
    }

    private func stopPreview() {
        guard let previewID else { return }
        self.previewID = nil
        if speech.playbackID == previewID { speech.stop() }
    }
}
