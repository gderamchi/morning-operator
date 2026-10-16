import MorningApple
import MorningCore
import SwiftUI

/// The caller keeps this sheet unavailable during an active morning session.
struct VoicePickerView: View {
    @Bindable var speech: SpeechCoordinator
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            MorningList {
                voiceRow(.male)
                voiceRow(.female)
            }
            .navigationTitle("Voice")
            .navigationBarTitleDisplayMode(.inline)
            .tint(MorningStyle.accent)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("voice.done")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 320, minHeight: 220)
        #endif
    }

    private func voiceRow(_ gender: MorningVoiceGender) -> some View {
        let name = gender == .male
            ? String(localized: "Male", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
            : String(localized: "Female", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
        return Button {
            speech.voiceGender = gender
        } label: {
            HStack {
                Text(name).foregroundStyle(.primary)
                Spacer()
                if speech.voiceGender == gender {
                    Image(systemName: "checkmark").foregroundStyle(MorningStyle.accent)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier(gender == .male ? "voice.gender.male" : "voice.gender.female")
        .accessibilityLabel(name)
        .accessibilityValue(speech.voiceGender == gender
            ? String(localized: "Selected", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) : "")
        .accessibilityAddTraits(speech.voiceGender == gender ? .isSelected : [])
    }
}
