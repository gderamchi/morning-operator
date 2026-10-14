import SwiftUI
import MorningCore
import MorningApple

/// Settings → Your day → Short extras. Turning an extra on is the only moment a Health or
/// Contacts prompt can appear; reading never prompts.
struct MorningExtrasSettingsSection: View {
    @Bindable var store: MorningStore
    @ViewState<String?> private var message = nil
    @ViewState<Bool> private var working = false
    private var extras: MorningExtrasProvider { store.extras }

    var body: some View {
        Section {
            ForEach(MorningExtraKind.allCases, id: \.self) { kind in
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(title(kind), isOn: Binding(get: { extras.preferences.enabled.contains(kind) },
                                                      set: { on in change(kind, on) }))
                        .disabled(working || !extras.isConnected(kind))
                        .accessibilityIdentifier("extras.\(kind.rawValue)")
                    if let note = note(kind) {
                        Text(note).font(.caption).foregroundStyle(MorningStyle.muted)
                    }
                }
            }
            if needsHealthPrompt {
                Button("Allow Health for sleep and steps") { requestHealth() }
                    .disabled(working).accessibilityIdentifier("extras.allowHealth")
            }
            if let message { Text(message).font(.caption).accessibilityIdentifier("extras.message") }
        } header: { Text("Short extras") } footer: {
            Text("Up to three short facts after the opening, about ten seconds in all. Nothing read for them is saved; only these choices are. When a source has nothing, MORE says nothing about it.")
        }
    }

    private var needsHealthPrompt: Bool {
        extras.isConnected(.sleep) && !extras.preferences.healthAccessRequested
            && !extras.preferences.enabled.isDisjoint(with: [.sleep, .steps])
    }

    private func title(_ kind: MorningExtraKind) -> LocalizedStringKey {
        switch kind {
        case .sleep: "Sleep last night"
        case .steps: "Steps yesterday"
        case .screenTime: "Screen time yesterday"
        case .weatherChange: "Weather change worth knowing"
        case .calendar: "Calendar clash or tight gap"
        case .birthday: "Birthdays among contacts"
        }
    }

    private func note(_ kind: MorningExtraKind) -> LocalizedStringKey? {
        guard extras.isConnected(kind) else {
            return kind == .screenTime ? "Not available in this version." : "Not available in this build."
        }
        switch kind {
        case .sleep: return "No Apple Watch needed: an iPhone with a Sleep schedule records time in bed."
        case .steps: return "Counted by your iPhone, compared with your 7-day average."
        case .weatherChange:
            return store.briefing.settings.weatherLocation == nil ? "Choose a city above first." : nil
        case .calendar:
            return store.briefing.settings.calendarIDs.isEmpty ? "Choose calendars above first." : nil
        case .birthday:
            return extras.preferences.enabled.contains(.birthday) && !extras.birthdaysAuthorized
                ? "Contacts access is off. Allow it in the Settings app." : "Names are spoken, never saved."
        case .screenTime: return nil
        }
    }

    private func change(_ kind: MorningExtraKind, _ on: Bool) {
        working = true; message = nil
        Task {
            defer { working = false }
            do { try await extras.setEnabled(kind, on) }
            catch { message = String(localized: "This choice couldn't be saved or the permission couldn't be asked. \(error.localizedDescription)") }
        }
    }

    private func requestHealth() {
        working = true; message = nil
        Task {
            defer { working = false }
            do { try await extras.requestHealthAccess() }
            catch { message = String(localized: "Health access couldn't be asked. \(error.localizedDescription)") }
        }
    }
}
