import SwiftUI
import MorningCore

struct StepTargetEditor: View {
    @Binding var target: RoutineStepTarget?
    private var selectedApp: StepApp? {
        guard case let .externalApp(app, _) = target else { return nil }; return app
    }
    private var detail: String {
        guard case let .externalApp(_, detail) = target else { return "" }; return detail ?? ""
    }
    private var selectedChoice: String {
        switch target {
        case let .externalApp(app, _): "app.\(app.rawValue)"
        case let .inAppWeb(url): WebMorningSite(url: url).map { "web.\($0.rawValue)" } ?? "web.saved"
        case .shortcut: "shortcut"
        case .connectedAPI: "api.saved"
        case nil: "none"
        }
    }
    private func select(_ choice: String) {
        if choice.hasPrefix("app."), let app = StepApp(rawValue: String(choice.dropFirst(4))) {
            target = .externalApp(app, detail: nil)
        } else if choice.hasPrefix("web."), let site = WebMorningSite(rawValue: String(choice.dropFirst(4))) {
            target = .inAppWeb(site: site.table.startURL)
        } else if choice == "shortcut" { target = .shortcut(name: "", input: "") }
        else if choice == "none" { target = nil }
    }
    var body: some View {
        Section {
            Picker("Open", selection: Binding(get: { selectedChoice }, set: select)) {
                Text("None").tag("none")
                Section("On this iPhone") {
                    Text("Run an installed Shortcut").tag("shortcut")
                }
                Section("In MORE") {
                    ForEach(WebMorningSite.allCases) { site in Text(site.displayName).tag("web.\(site.rawValue)") }
                    if selectedChoice == "web.saved" { Text("Saved page").tag("web.saved") }
                }
                Section("Another app") {
                    ForEach(StepApp.allCases, id: \.self) { app in Text(app.displayName).tag("app.\(app.rawValue)") }
                }
                if selectedChoice == "api.saved" {
                    Section("From your accounts") { Text("Saved service action").tag("api.saved") }
                }
            }.accessibilityIdentifier("step.targetApp")
            if let app = selectedApp, app.detailKind != .none {
                TextField(prompt(app.detailKind), text: Binding(get: { detail }, set: { target = .externalApp(app, detail: $0) }))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("step.targetDetail")
            }
            if case let .shortcut(name, input) = target {
                TextField("Installed shortcut name", text: Binding(get: { name }, set: { target = .shortcut(name: $0, input: input) }))
                    .autocorrectionDisabled().accessibilityIdentifier("step.shortcutName")
                TextField("Input (optional)", text: Binding(get: { input }, set: { target = .shortcut(name: name, input: $0) }), axis: .vertical)
                    .lineLimit(2...5)
                Text("Add and authorize the shortcut in Shortcuts first. Its name alone does not verify a connection.")
                    .font(.footnote).foregroundStyle(MorningStyle.muted)
            }
            if case let .connectedAPI(service, _, tool, arguments) = target {
                Text(service.capitalized).font(.subheadline)
                DisclosureGroup("Saved action details") {
                    Text(tool).font(.caption)
                    Text(arguments).font(.caption.monospaced()).textSelection(.enabled)
                }
            }
            Text("Choose an action from Apps & accounts, then add it to your routine.")
                .font(.footnote).foregroundStyle(MorningStyle.muted)
        } header: { Text("During this moment") } footer: {
            Text("One timer, in MORE or another app. Choose Next when you're ready.")
        }
    }
    private func prompt(_ kind: StepAppDetailKind) -> String {
        switch kind {
        case .none: ""
        case .phoneNumber: String(localized: "Phone number (optional)")
        case .messageID: String(localized: "Mail Message-ID (optional)")
        case .username: String(localized: "Username (optional)")
        case .place: String(localized: "Place (optional)")
        case .webAddress: String(localized: "Web address")
        }
    }
}
