import AuthenticationServices
import MorningApple
import SwiftUI
import UIKit

/// Hosted OAuth sign-in; readiness always comes from a fresh account check.
struct APIConnectionsView: View {
    let service: ComposioService
    var serviceID: String? = nil
    var privacyBlocked = false
    var privacyGeneration = UUID()
    var onAddToRoutine: ((ComposioConnection, ComposioTool, String) -> Bool)?
    @ViewState private var services: [ComposioAvailableService] = []
    @ViewState private var connections: [ComposioConnection] = []
    @ViewState private var selectedConnection: ComposioConnection?
    @ViewState private var busy = false
    @ViewState private var hasLoaded = false
    @ViewState private var message: String?
    @ViewState private var technicalMessage: String?
    @ViewState private var operation: Task<Void, Never>?
    @ViewState private var revision = UUID()
    @ViewState private var signIn = APIHostedSignIn()
    @Environment(\.locale) private var locale
    private var visibleServices: [ComposioAvailableService] { services.filter { serviceID == nil || $0.id == serviceID } }
    private var visibleConnections: [ComposioConnection] { connections.filter { serviceID == nil || $0.service == serviceID } }
    private var serviceName: String {
        if serviceID == nil { return text("Your accounts", "Vos comptes") }
        return visibleServices.first?.name ?? visibleConnections.first?.name ?? APIConnectionPresentation.name(serviceID ?? "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(eyebrow: text("Your connections", "Vos connexions"), title: serviceName,
                    subtitle: text("Choose what MORE can do with your account. Review each action before it runs.",
                                   "Choisissez ce que MORE peut faire avec votre compte. Vérifiez chaque action avant de la lancer."))
                if !service.isConfigured {
                    EmptyMoment(symbol: "link", title: text("Connection unavailable", "Connexion indisponible"),
                        detail: text("This connection isn't available right now. You can come back later.", "Cette connexion n’est pas disponible pour le moment. Vous pourrez revenir plus tard."))
                } else {
                    if let message {
                        Card { Text(message).font(MorningTheme.Typography.note).fixedSize(horizontal: false, vertical: true) }
                            .accessibilityIdentifier("accounts.notice")
                    }
                    if busy {
                        Card {
                            VStack(alignment: .leading, spacing: 12) {
                                ProgressView(text("Checking your connection…", "Vérification de votre connexion…"))
                                Button(text("Cancel", "Annuler")) { cancelWaiting() }.buttonStyle(SecondaryButtonStyle())
                            }
                        }
                    }
                    if visibleConnections.isEmpty { connectionChoices }
                    if hasLoaded && visibleConnections.isEmpty && !visibleServices.isEmpty {
                        Text(text("No account connected yet. Sign in above, then choose the permissions you want to share.",
                                  "Aucun compte connecté pour le moment. Identifiez-vous ci-dessus, puis choisissez les accès à partager."))
                            .font(MorningTheme.Typography.note).foregroundStyle(MorningStyle.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(visibleConnections) { connection in accountCard(connection) }
                    if !visibleConnections.isEmpty { connectionChoices }
                    if !busy {
                        Button(hasLoaded ? text("Refresh my accounts", "Actualiser mes comptes") : text("Try again", "Réessayer")) {
                            launch { try await refresh() }
                        }.buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("accounts.refresh")
                    }
                }
                Card {
                    DisclosureGroup(text("Shared data", "Données partagées")) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(text("Sign in on the service's official page and choose its permissions. MORE never asks for your password.",
                                      "Identifiez-vous sur la page officielle du service et choisissez ses autorisations. MORE ne vous demande jamais votre mot de passe."))
                            Text(text("Authorizations and requested actions pass through MORE’s connection service and Composio. Results are only shown during this session.",
                                      "Les autorisations et les actions demandées passent par le service de connexion de MORE et Composio. Les résultats restent affichés pendant cette session."))
                            if let technicalMessage {
                                DisclosureGroup(text("Connection details", "Détails de connexion")) {
                                    Text(technicalMessage).font(.raleway(.caption)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }.font(.raleway(.footnote)).foregroundStyle(MorningStyle.muted).padding(.top, 12)
                    }
                }
            }.padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .background(MorningPaper(showsSun: false))
        .foregroundStyle(MorningStyle.ink).tint(MorningStyle.accent)
        .navigationTitle(serviceName).navigationBarTitleDisplayMode(.inline)
        .disabled(privacyBlocked)
        .task(id: serviceID) {
            clearSession()
            guard service.isConfigured, !privacyBlocked else { return }
            launch { try await refresh() }
        }
        .sheet(item: $selectedConnection) { connection in
            NavigationStack {
                APIActionPickerView(service: service, connection: connection, accountName: accountTitle(connection), onAddToRoutine: onAddToRoutine)
            }
        }
        .onChange(of: privacyBlocked) { _, blocked in if blocked { clearSession() } }
        .onChange(of: privacyGeneration) { _, _ in clearSession() }
        .onDisappear { clearSession() }
    }

    @ViewBuilder private var connectionChoices: some View {
        if hasLoaded && visibleServices.isEmpty {
            Card { Text(text("This connection isn't available right now. Try refreshing your accounts later.", "Cette connexion n’est pas disponible pour le moment. Réessayez d’actualiser vos comptes plus tard.")).font(MorningTheme.Typography.note) }
        }
        ForEach(visibleServices) { available in
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    Text(visibleConnections.isEmpty ? text("Your \(available.name) account", "Votre compte \(available.name)") : text("Another account?", "Un autre compte ?"))
                        .font(MorningTheme.Typography.heading).fixedSize(horizontal: false, vertical: true)
                    if ["instagram", "whatsapp", "facebook"].contains(available.id) {
                        Text(professionalAccountNote(available.id)).font(.raleway(.footnote)).foregroundStyle(MorningStyle.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button { connect(available) } label: {
                        Text(text("Connect \(available.name)", "Connecter \(available.name)"))
                            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(PrimaryButtonStyle()).disabled(busy)
                        .accessibilityIdentifier("accounts.connect.\(available.id)")
                }
            }
        }
    }
    private func accountCard(_ connection: ComposioConnection) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text(accountTitle(connection)).font(MorningTheme.Typography.heading)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                Label(statusTitle(connection), systemImage: connection.isActive ? "checkmark.circle" : "clock")
                    .font(.raleway(.subheadline)).foregroundStyle(connection.isActive ? MorningStyle.green : MorningStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if connection.isActive {
                    Button { selectedConnection = connection } label: {
                        Text(text("Choose an action", "Choisir une action")).frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(PrimaryButtonStyle()).disabled(busy)
                } else {
                    Text(text("Finish sign-in or reconnect this account, then refresh to check its status.",
                              "Terminez l’identification ou reconnectez ce compte, puis actualisez pour vérifier son état."))
                        .font(.raleway(.footnote)).foregroundStyle(MorningStyle.muted).fixedSize(horizontal: false, vertical: true)
                }
                DisclosureGroup(text("Account settings", "Réglages du compte")) {
                    Button(text("Disconnect this account", "Déconnecter ce compte"), role: .destructive) { disconnect(connection) }
                        .buttonStyle(SecondaryButtonStyle()).disabled(busy).padding(.top, 10)
                }.font(.raleway(.subheadline))
            }
        }
    }
    private func accountTitle(_ connection: ComposioConnection) -> String {
        if let label = connection.accountLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty { return label }
        let matching = visibleConnections.filter { $0.service == connection.service }
        let name = text("\(connection.name) account", "Compte \(connection.name)")
        if matching.count > 1, let index = matching.firstIndex(where: { $0.id == connection.id }) { return "\(name) · \(index + 1)" }
        return name
    }
    private func statusTitle(_ connection: ComposioConnection) -> String {
        if connection.isActive { return text("Connected", "Connecté") }
        switch connection.status.uppercased() {
        case "INITIATED", "INITIALIZING", "PENDING": return text("Sign-in to finish", "Connexion à terminer")
        case "EXPIRED", "FAILED", "INACTIVE", "REVOKED", "DISABLED": return text("Reconnect this account", "Compte à reconnecter")
        default: return text("Connection to check", "Connexion à vérifier")
        }
    }
    private func professionalAccountNote(_ id: String) -> String {
        switch id {
        case "instagram": return text("For an Instagram Business or Creator account you manage.", "Pour un compte Instagram Business ou Creator que vous gérez.")
        case "whatsapp": return text("Requires a WhatsApp Business Platform account (WABA). A personal WhatsApp account cannot connect here.", "Nécessite un compte WhatsApp Business Platform (WABA). Un compte WhatsApp personnel ne peut pas être connecté ici.")
        default: return text("For Facebook Pages you manage.", "Pour les Pages Facebook que vous gérez.")
        }
    }
    private func refresh() async throws {
        let expected = revision
        let freshServices = try await service.services()
        let freshConnections = try await service.connections()
        try Task.checkCancellation()
        guard expected == revision, !privacyBlocked else { return }
        services = freshServices; connections = freshConnections; hasLoaded = true
    }
    private func connect(_ available: ComposioAvailableService) {
        launch {
            let previousActive = Set(connections.filter { $0.service == available.id && $0.isActive }.map(\.id))
            let authorization = try await service.startConnection(service: available.id,
                callbackURL: URL(string: ComposioService.callbackScheme + "://composio/callback")!)
            let sessionURI = try await signIn.start(authorization.authorizationURL)
            try await service.completeConnection(sessionURI: sessionURI)
            try Task.checkCancellation()
            try await refresh()
            guard !Task.isCancelled else { return }
            message = connections.contains(where: { $0.service == available.id && $0.isActive && !previousActive.contains($0.id) })
                ? text("Account connected and verified.", "Compte connecté et vérifié.")
                : text("Sign-in received. Check the updated status of your accounts below.", "Identification reçue. Vérifiez l’état actualisé de vos comptes ci-dessous.")
        }
    }
    private func disconnect(_ connection: ComposioConnection) {
        launch { try await service.disconnect(connectionID: connection.id); try await refresh() }
    }
    private func launch(_ action: @escaping @MainActor () async throws -> Void) {
        guard !privacyBlocked, !busy else { return }
        let expected = revision
        busy = true; message = nil; technicalMessage = nil
        operation = Task { @MainActor in
            defer { if expected == revision { busy = false; operation = nil } }
            do { try await action() }
            catch is CancellationError {
                guard expected == revision, !privacyBlocked else { return }
                message = text("Connection interrupted. Refresh your accounts or sign in again when you're ready.", "Connexion interrompue. Actualisez vos comptes ou reprenez l’identification quand vous le souhaitez.")
            }
            catch {
                guard expected == revision, !Task.isCancelled, !privacyBlocked else { return }
                message = APIConnectionPresentation.failureMessage(error, french: locale.language.languageCode?.identifier == "fr")
                technicalMessage = error.localizedDescription
            }
        }
    }
    private func cancelWaiting() { operation?.cancel(); signIn.cancel() }
    private func clearSession() {
        revision = UUID(); operation?.cancel(); operation = nil; signIn.cancel()
        selectedConnection = nil; connections = []; services = []; message = nil; technicalMessage = nil; busy = false; hasLoaded = false
    }
    private func text(_ en: String, _ fr: String) -> String { locale.language.languageCode?.identifier == "fr" ? fr : en }
}

private struct APIActionPickerView: View {
    let service: ComposioService
    let connection: ComposioConnection
    let accountName: String
    let onAddToRoutine: ((ComposioConnection, ComposioTool, String) -> Bool)?
    @ViewState private var tools: [ComposioTool] = []
    @ViewState private var message: String?
    @ViewState private var loading = true
    @ViewState private var query = ""
    @ViewState private var loadRevision = UUID()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    private var visibleTools: [ComposioTool] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return search.isEmpty ? tools : tools.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.description.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                PageHeading(eyebrow: accountName, title: text("What MORE can do", "Ce que MORE peut faire"),
                    subtitle: text("Choose an action, complete its details, then review it before running.",
                                   "Choisissez une action, complétez ses détails, puis vérifiez-la avant de la lancer."))
                if loading { ProgressView(text("Finding your available actions…", "Recherche des actions disponibles…")) }
                if let message {
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(message).font(MorningTheme.Typography.note).fixedSize(horizontal: false, vertical: true)
                            Button(text("Try again", "Réessayer")) { loadRevision = UUID() }.buttonStyle(SecondaryButtonStyle())
                        }
                    }
                }
                if tools.isEmpty && !loading && message == nil {
                    EmptyMoment(symbol: "sparkles", title: text("No actions available yet", "Aucune action disponible pour le moment"),
                        detail: text("Check this account's permissions or reconnect it from your accounts.", "Vérifiez les autorisations de ce compte ou reconnectez-le depuis vos comptes."))
                } else if visibleTools.isEmpty && !loading && message == nil {
                    Text(text("No matching action. Try another word.", "Aucune action correspondante. Essayez un autre mot."))
                        .font(MorningTheme.Typography.note).foregroundStyle(MorningStyle.muted)
                }
                ForEach(visibleTools) { tool in
                    NavigationLink {
                        APIActionForm(service: service, connection: connection, accountName: accountName, tool: tool, onAddToRoutine: onAddToRoutine)
                    } label: {
                        Card {
                            LinkRow(title: tool.name, detail: "", symbol: "sparkles")
                        }
                    }.buttonStyle(.plain)
                }
            }.padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .background(MorningPaper(showsSun: false)).foregroundStyle(MorningStyle.ink).tint(MorningStyle.accent)
        .navigationTitle(text("Choose an action", "Choisir une action")).navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: text("Find an action", "Rechercher une action"))
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(text("Done", "Terminer")) { dismiss() } } }
        .task(id: loadRevision) { await load() }
    }
    private func load() async {
        loading = true; message = nil
        do {
            let fresh = try await service.connections()
            guard fresh.contains(where: { $0.id == connection.id && $0.isActive }) else {
                message = text("This account needs to be reconnected before choosing an action.", "Reconnectez ce compte avant de choisir une action.")
                loading = false; return
            }
            let fetched = try await service.tools(service: connection.service)
            try Task.checkCancellation(); tools = fetched; loading = false
        } catch is CancellationError { }
        catch {
            guard !Task.isCancelled else { return }
            message = APIConnectionPresentation.failureMessage(error, french: locale.language.languageCode?.identifier == "fr")
            loading = false
        }
    }
    private func text(_ en: String, _ fr: String) -> String { locale.language.languageCode?.identifier == "fr" ? fr : en }
}

private struct APIActionForm: View {
    let service: ComposioService
    let connection: ComposioConnection
    let accountName: String
    let tool: ComposioTool
    let onAddToRoutine: ((ComposioConnection, ComposioTool, String) -> Bool)?
    @ViewState private var values: [String: String] = [:]
    @ViewState private var included: Set<String> = []
    @ViewState private var reviewedArguments: String?
    @ViewState private var advancedJSON = "{}"
    @ViewState private var useAdvanced = false
    @ViewState private var message: String?
    @ViewState private var result: String?
    @ViewState private var busy = false
    @ViewState private var outcomeUncertain = false
    @ViewState private var uncertainRequestID: UUID?
    @ViewState private var uncertainArguments: String?
    @ViewState private var operation: Task<Void, Never>?
    @Environment(\.locale) private var locale
    private var properties: [String: ComposioJSONValue] { tool.inputSchema.objectValue?["properties"]?.objectValue ?? [:] }
    private var required: Set<String> { Set(tool.inputSchema.objectValue?["required"]?.arrayValue?.compactMap(\.stringValue) ?? []) }
    private var keys: [String] { properties.keys.sorted { (required.contains($0) ? 0 : 1, $0) < (required.contains($1) ? 0 : 1, $1) } }

    var body: some View {
        MorningForm {
            Section {
                Text(tool.name).font(MorningTheme.Typography.heading).fixedSize(horizontal: false, vertical: true)
                Text(accountName).font(MorningTheme.Typography.note).foregroundStyle(MorningStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !useAdvanced {
                Section(text("Action details", "Détails de l’action")) {
                    if required.isEmpty { Text(text("You can review this action now. More options are available below.", "Vous pouvez vérifier cette action maintenant. D’autres options sont disponibles ci-dessous.")).font(MorningTheme.Typography.note) }
                    ForEach(keys.filter { required.contains($0) }, id: \.self) { key in field(key) }
                }
            }
            Section {
                DisclosureGroup(text("Advanced settings", "Réglages avancés")) {
                    if !useAdvanced {
                        ForEach(keys.filter { !required.contains($0) }, id: \.self) { key in field(key) }
                    }
                    Toggle(text("Edit all parameters as JSON", "Modifier tous les paramètres en JSON"), isOn: $useAdvanced)
                    if useAdvanced {
                        TextEditor(text: $advancedJSON).font(.system(.footnote, design: .monospaced)).frame(minHeight: 140)
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                    } else {
                        Text(text("Use this for nested fields and lists. Required complex fields need valid JSON before review.", "Utilisez cette option pour les champs imbriqués et les listes. Les champs complexes obligatoires nécessitent un JSON valide avant vérification."))
                            .font(.raleway(.caption)).foregroundStyle(.secondary)
                    }
                    Text(tool.description).font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Section {
                Button(text("Review action", "Vérifier l’action")) { review() }
                    .buttonStyle(PrimaryButtonStyle()).disabled(busy || outcomeUncertain)
            }
            if let reviewedArguments {
                Section(text("Ready to run", "Prêt à exécuter")) {
                    Text(tool.name).font(MorningTheme.Typography.heading)
                    Text(accountName).fixedSize(horizontal: false, vertical: true)
                    reviewedValues(reviewedArguments)
                    Text(text("Only the reviewed values above will be sent to this account.", "Seules les valeurs vérifiées ci-dessus seront envoyées à ce compte."))
                        .font(.raleway(.caption)).foregroundStyle(.secondary)
                    Button(text("Run this action", "Lancer cette action")) { execute(reviewedArguments) }
                        .buttonStyle(PrimaryButtonStyle()).disabled(busy || outcomeUncertain)
                    if let onAddToRoutine {
                        Button(text("Add to my routine", "Ajouter à ma routine")) {
                            message = onAddToRoutine(connection, tool, reviewedArguments)
                                ? text("Added to your routine draft. Review and approve it before starting.", "Ajouté au brouillon de votre routine. Vérifiez et approuvez-la avant de démarrer.")
                                : text("The action could not be added. Finish the current morning and check your routine.", "L’action n’a pas pu être ajoutée. Terminez le matin en cours et vérifiez votre routine.")
                        }.buttonStyle(SecondaryButtonStyle()).disabled(busy || outcomeUncertain)
                    }
                }
            }
            if busy { Section { ProgressView(); Button(text("Cancel waiting", "Arrêter l’attente")) { operation?.cancel() }.buttonStyle(SecondaryButtonStyle()) } }
            if let message { Section { Text(message).font(.raleway(.footnote)).textSelection(.enabled) } }
            if let uncertainRequestID {
                Section(text("Check this action in your account", "Vérifiez cette action dans votre compte")) {
                    Text(tool.name).font(.raleway(.headline))
                    Text(accountName).fixedSize(horizontal: false, vertical: true)
                    if let uncertainArguments { reviewedValues(uncertainArguments) }
                    DisclosureGroup(text("Request reference", "Référence de la demande")) {
                        Text(uncertainRequestID.uuidString).font(.caption.monospaced()).textSelection(.enabled)
                    }
                    Text(text("Open the connected account and check whether this exact action happened before allowing another attempt.", "Ouvrez le compte connecté et vérifiez si cette action précise a eu lieu avant d’autoriser un nouvel essai."))
                        .font(.raleway(.footnote))
                    Button(text("I checked: the action already happened", "J’ai vérifié : l’action a déjà eu lieu")) { reconcile(uncertainRequestID, occurred: true) }.buttonStyle(SecondaryButtonStyle())
                    Button(text("I checked: no action happened", "J’ai vérifié : aucune action n’a eu lieu")) { reconcile(uncertainRequestID, occurred: false) }.buttonStyle(SecondaryButtonStyle())
                }
            }
            if let result { Section { DisclosureGroup(text("Response details", "Détails de la réponse")) { Text(result).font(.system(.footnote, design: .monospaced)).textSelection(.enabled) } } }
        }
        .foregroundStyle(MorningStyle.ink).tint(MorningStyle.accent)
        .navigationTitle(text("Prepare the action", "Préparer l’action")).navigationBarTitleDisplayMode(.inline)
        .onChange(of: values) { _, _ in reviewedArguments = nil }
        .onChange(of: included) { _, _ in reviewedArguments = nil }
        .onChange(of: advancedJSON) { _, _ in reviewedArguments = nil }
        .onChange(of: useAdvanced) { _, _ in reviewedArguments = nil }
        .onDisappear { operation?.cancel(); operation = nil; result = nil; message = nil }
    }
    @ViewBuilder private func reviewedValues(_ json: String) -> some View {
        if let arguments = try? ComposioJSONValue.parseObject(json) {
            if arguments.isEmpty {
                Text(text("No extra details to send.", "Aucun détail supplémentaire à transmettre.")).font(.raleway(.footnote)).foregroundStyle(MorningStyle.muted)
            }
            ForEach(arguments.keys.sorted(), id: \.self) { key in
                if let value = arguments[key] {
                    let definition = properties[key]?.objectValue ?? [:]
                    let label = definition["title"]?.stringValue ?? key.replacingOccurrences(of: "_", with: " ").capitalized
                    if value.objectValue != nil || value.arrayValue != nil {
                        DisclosureGroup(label) {
                            Text((try? value.prettyPrintedJSON()) ?? "").font(.footnote.monospaced()).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(label).font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                            Text(readableValue(value)).font(MorningTheme.Typography.body).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
    private func readableValue(_ value: ComposioJSONValue) -> String {
        switch value {
        case .string(let value): return value.isEmpty ? text("Empty text", "Texte vide") : value
        case .bool(let value): return value ? text("Yes", "Oui") : text("No", "Non")
        case .number(let value): return NSDecimalNumber(decimal: value).stringValue
        case .null: return text("No value", "Aucune valeur")
        case .array, .object: return ""
        }
    }
    @ViewBuilder private func field(_ key: String) -> some View {
        let definition = properties[key]?.objectValue ?? [:]
        let label = definition["title"]?.stringValue ?? key.replacingOccurrences(of: "_", with: " ").capitalized
        let type = definition["type"]?.stringValue ?? "string"
        let options = definition["enum"]?.arrayValue?.compactMap(\.stringValue) ?? []
        let enabled = required.contains(key) || included.contains(key)
        VStack(alignment: .leading, spacing: 6) {
            if !required.contains(key) { Toggle(text("Include ", "Inclure ") + label, isOn: Binding(get: { included.contains(key) }, set: { if $0 { included.insert(key) } else { included.remove(key) } })) }
            if enabled {
                if type == "boolean" {
                    Toggle(label, isOn: Binding(get: { values[key] == "true" }, set: { values[key] = $0 ? "true" : "false" }))
                } else if type == "string" && !options.isEmpty {
                    Picker(label, selection: Binding(get: { values[key] ?? "" }, set: { values[key] = $0 })) {
                        Text(text("Choose", "Choisir")).tag("")
                        ForEach(options, id: \.self) { Text($0).tag($0) }
                    }
                } else if ["string", "number", "integer"].contains(type) {
                    TextField(label, text: Binding(get: { values[key] ?? "" }, set: { values[key] = $0 }), axis: .vertical)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                } else {
                    Text(label + text(" — complete in Advanced settings", " — à remplir dans Réglages avancés")).font(.raleway(.footnote))
                }
                if let description = definition["description"]?.stringValue { Text(description).font(.raleway(.caption)).foregroundStyle(.secondary) }
            }
        }.padding(.vertical, 3)
    }
    private func review() {
        do {
            var arguments: [String: ComposioJSONValue] = [:]
            if useAdvanced { arguments = try ComposioJSONValue.parseObject(advancedJSON) }
            else {
                for key in keys where required.contains(key) || included.contains(key) {
                    let type = properties[key]?.objectValue?["type"]?.stringValue ?? "string"
                    let value = values[key] ?? ""
                    switch type {
                    case "boolean": arguments[key] = .bool(value == "true")
                    case "number", "integer":
                        guard let number = try? JSONDecoder().decode(Decimal.self, from: Data(value.utf8)) else {
                            throw ComposioServiceError.invalidArguments
                        }
                        var original = number
                        var rounded = Decimal()
                        NSDecimalRound(&rounded, &original, 0, .plain)
                        guard type != "integer" || rounded == number else { throw ComposioServiceError.invalidArguments }
                        arguments[key] = .number(number)
                    case "string":
                        guard !required.contains(key) || !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ComposioServiceError.invalidArguments }
                        let options = properties[key]?.objectValue?["enum"]?.arrayValue?.compactMap(\.stringValue) ?? []
                        guard options.isEmpty || options.contains(value) else { throw ComposioServiceError.invalidArguments }
                        arguments[key] = .string(value)
                    default: throw ComposioServiceError.invalidArguments
                    }
                }
            }
            guard required.isSubset(of: Set(arguments.keys)) else { throw ComposioServiceError.invalidArguments }
            reviewedArguments = try ComposioJSONValue.object(arguments).prettyPrintedJSON()
            message = nil; result = nil
        } catch { reviewedArguments = nil; message = APIConnectionPresentation.failureMessage(error, french: locale.language.languageCode?.identifier == "fr") }
    }
    private func execute(_ json: String) {
        guard !busy, !outcomeUncertain else { return }
        busy = true; message = nil; result = nil
        operation = Task { @MainActor in
            defer { busy = false; operation = nil }
            do {
                let fresh = try await service.connections()
                guard fresh.contains(where: { $0.id == connection.id && $0.isActive }) else { throw ComposioServiceError.notAuthorized }
                let arguments = try ComposioJSONValue.parseObject(json)
                let receipt = try await service.execute(tool: tool.slug, arguments: arguments, connectionID: connection.id)
                result = try receipt.data?.prettyPrintedJSON()
                if receipt.resultAvailable == false {
                    message = text("Receipt recovered. Response content is not retained by the service.", "Confirmation récupérée. Le contenu de la réponse n’est pas conservé par le service.")
                } else {
                    message = receipt.successful ? text("Your account service confirmed the request. You can check its response below.", "Le service de votre compte a confirmé la demande. Vous pouvez consulter sa réponse ci-dessous.") : text("The service reported a failure. Check the account before another attempt.", "Le service signale un échec. Vérifiez le compte avant un nouvel essai.")
                }
                if !receipt.successful { outcomeUncertain = true; uncertainRequestID = receipt.requestID; uncertainArguments = json }
                reviewedArguments = nil
            } catch {
                if case ComposioServiceError.executionUncertain(let id) = error { outcomeUncertain = true; uncertainRequestID = id; uncertainArguments = json }
                message = error is CancellationError ? text("Waiting cancelled. If execution had started, check the account before repeating the action.", "Attente annulée. Si l’exécution avait commencé, vérifiez le compte avant de recommencer.") : APIConnectionPresentation.failureMessage(error, french: locale.language.languageCode?.identifier == "fr")
            }
        }
    }
    private func reconcile(_ id: UUID, occurred: Bool) {
        do {
            try service.reconcileExecution(requestID: id)
            uncertainRequestID = nil; uncertainArguments = nil; reviewedArguments = nil
            outcomeUncertain = occurred
            message = occurred
                ? text("Marked as already completed after your account check. This action will not be repeated here.", "Indiquée comme déjà effectuée après votre vérification. Cette action ne sera pas répétée ici.")
                : text("Account checked. Review the action again before a new attempt.", "Compte vérifié. Vérifiez de nouveau l’action avant un nouvel essai.")
        } catch { message = APIConnectionPresentation.failureMessage(error, french: locale.language.languageCode?.identifier == "fr") }
    }
    private func text(_ en: String, _ fr: String) -> String { locale.language.languageCode?.identifier == "fr" ? fr : en }
}

private enum APIConnectionPresentation {
    static func name(_ id: String) -> String {
        switch id {
        case "gmail": "Gmail"
        case "outlook": "Outlook"
        case "googlecalendar": "Google Calendar"
        case "googlecontacts": "Google Contacts"
        case "googledrive": "Google Drive"
        case "googledocs": "Google Docs"
        case "googlesheets": "Google Sheets"
        case "instagram": "Instagram"
        case "whatsapp": "WhatsApp"
        case "facebook": "Facebook"
        case "linkedin": "LinkedIn"
        case "discord": "Discord"
        case "youtube": "YouTube"
        case "reddit": "Reddit"
        case "twitter": "X (Twitter)"
        case "tiktok": "TikTok"
        case "slack": "Slack"
        case "notion": "Notion"
        case "calendly": "Calendly"
        default: "MORE"
        }
    }
    static func failureMessage(_ error: any Error, french: Bool) -> String {
        if let issue = error as? ComposioServiceError {
            switch issue {
            case .invalidArguments:
                return french ? "Vérifiez les champs et les options de l’action avant de continuer." : "Check the action's fields and options before continuing."
            case .executionUncertain:
                return french ? "Le résultat est inconnu. Vérifiez ce compte avant de lancer à nouveau cette action." : "The outcome is unknown. Check this account before running this action again."
            case .credentialsUnavailable:
                return french ? "Déverrouillez votre iPhone, puis réessayez." : "Unlock your iPhone, then try again."
            case .notAuthorized:
                return french ? "Cette autorisation n’est plus disponible. Revenez à vos comptes pour vérifier la connexion." : "This authorization is no longer available. Go back to your accounts to check the connection."
            case .notConfigured, .insecureURL:
                return french ? "Cette connexion n’est pas disponible pour le moment. Réessayez plus tard." : "This connection isn't available right now. Try again later."
            case .backend(let failure) where failure.code == "rate_limited":
                return french ? "Un instant, plusieurs demandes sont en cours. Attendez une minute puis réessayez." : "Several requests are in progress. Wait a minute, then try again."
            default: break
            }
        }
        if let issue = error as? URLError, issue.code == .notConnectedToInternet {
            return french ? "Vérifiez votre connexion à Internet, puis réessayez." : "Check your internet connection, then try again."
        }
        return french ? "La demande n’a pas abouti. Vérifiez votre connexion puis réessayez." : "The request couldn't finish. Check your connection, then try again."
    }
}

@MainActor
private final class APIHostedSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private var completion: CheckedContinuation<String, any Error>?
    private var attempt = UUID()
    func start(_ url: URL) async throws -> String {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let expected = UUID()
                attempt = expected; completion = continuation
                let session = ASWebAuthenticationSession(url: url, callbackURLScheme: ComposioService.callbackScheme) { callback, error in
                    Task { @MainActor in
                        guard self.attempt == expected else { return }
                        if let error {
                            if let authenticationError = error as? ASWebAuthenticationSessionError, authenticationError.code == .canceledLogin {
                                self.finish(.failure(CancellationError()))
                            } else { self.finish(.failure(error)) }
                            return
                        }
                        guard let callback, callback.scheme == ComposioService.callbackScheme,
                              callback.host == "composio", callback.path == "/callback" else {
                            self.finish(.failure(ComposioServiceError.invalidResponse)); return
                        }
                        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
                        let matching = items.filter { $0.name == "session_uri" }
                        guard matching.count == 1, let sessionURI = matching.first?.value, !sessionURI.isEmpty else {
                            self.finish(.failure(ComposioServiceError.invalidResponse)); return
                        }
                        self.finish(.success(sessionURI))
                    }
                }
                self.session = session
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = true
                if !session.start() { finish(.failure(ComposioServiceError.invalidResponse)) }
            }
        } onCancel: { Task { @MainActor in self.cancel() } }
    }
    func cancel() {
        attempt = UUID(); session?.cancel()
        finish(.failure(CancellationError()))
    }
    private func finish(_ result: Result<String, any Error>) {
        let continuation = completion
        completion = nil; session = nil
        continuation?.resume(with: result)
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}
