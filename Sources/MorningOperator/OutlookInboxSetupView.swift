import SwiftUI
import MorningApple
import MorningCore

/// A named source choice; adding it never approves or starts the routine.
@MainActor struct OutlookInboxSetupView: View {
    @Bindable var store: MorningStore
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @State private var connections: [ComposioConnection] = []
    @State private var selectedConnection: ComposioConnection?
    @State private var identity: OutlookIdentity?
    @State private var loaded = false
    @State private var busy = false
    @State private var added = false
    @State private var message: String?
    @State private var visible = false
    @State private var revision = UUID()
    @State private var operation: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeading(eyebrow: "Outlook", title: text("Your Outlook Inbox, each morning", "Votre boîte Outlook, chaque matin"),
                    subtitle: text("Choose an account and review its identity. MORE reads up to three previews of unread Inbox messages, including older unread messages.",
                        "Choisissez un compte et vérifiez son identité. MORE lit au plus trois aperçus de messages non lus de la boîte de réception, même anciens."))
                Text(text("These are previews, not full messages or the entire Inbox. Choose a preview to read its body. MORE does not rank importance, send a reply or mark a message as read.",
                    "Il s’agit d’aperçus, pas des messages complets ni de toute la boîte. Choisissez un aperçu pour lire son corps. MORE ne classe pas leur importance, n’envoie aucune réponse et ne marque aucun message comme lu."))
                    .font(MorningTheme.Typography.note).fixedSize(horizontal: false, vertical: true)
                if OutlookInboxUITestFixture.isRequested {
                    Text("SYNTHETIC local fixture · no Outlook account is used")
                        .font(MorningTheme.Typography.note).accessibilityIdentifier("outlook.setup.synthetic")
                }
                if !store.composio.isConfigured {
                    Text(text("Outlook is unavailable in this version.", "Outlook n’est pas disponible dans cette version."))
                } else {
                    if let message {
                        Text(message).font(MorningTheme.Typography.note).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("outlook.setup.status")
                    }
                    if busy { ProgressView(text("Checking your Outlook account…", "Vérification de votre compte Outlook…")) }
                    if loaded && connections.isEmpty {
                        Text(text("Connect an Outlook account, then return here to review its Inbox identity.",
                            "Connectez un compte Outlook, puis revenez ici vérifier l’identité de sa boîte."))
                            .font(MorningTheme.Typography.note).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("outlook.setup.emptyAccount")
                    }
                    ForEach(Array(connections.enumerated()), id: \.element.id) { index, connection in
                        Button { choose(connection) } label: {
                            Label(accountName(connection, index: index), systemImage: selectedConnection?.id == connection.id ? "checkmark.circle" : "person.crop.circle")
                                .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                        }.buttonStyle(SecondaryButtonStyle()).disabled(busy)
                            .accessibilityIdentifier("outlook.setup.account.\(index)")
                    }
                    if let identity {
                        Text(identity.target.sourceLabel()).font(MorningTheme.Typography.heading)
                            .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("outlook.setup.identity")
                        Text(text("Read unread Inbox previews for “\(identity.target.sourceLabel())”. Message bodies are read only after you choose one of these previews.",
                            "Lire les aperçus non lus de la boîte de « \(identity.target.sourceLabel()) ». Le corps d’un message n’est lu qu’après votre choix dans ces aperçus."))
                            .font(MorningTheme.Typography.note).fixedSize(horizontal: false, vertical: true)
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Button(added ? text("Added to your routine", "Ajouté à votre routine") : text("Add this Outlook reading", "Ajouter cette lecture Outlook")) { addSelected() }
                                .buttonStyle(PrimaryButtonStyle())
                                .disabled(busy || added || !identity.isCurrent(at: context.date) || store.sessionActive || store.busy)
                                .accessibilityIdentifier("outlook.setup.add")
                            if !identity.isCurrent(at: context.date) {
                                Text(text("This choice has expired. Refresh your account before adding it.", "Ce choix a expiré. Actualisez votre compte avant de l’ajouter."))
                                    .font(MorningTheme.Typography.note).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    Button(text("Refresh Outlook accounts", "Actualiser les comptes Outlook")) { refreshAccounts() }
                        .buttonStyle(SecondaryButtonStyle()).disabled(busy).accessibilityIdentifier("outlook.setup.refresh")
                    NavigationLink {
                        APIConnectionsView(service: store.composio, serviceID: "outlook", privacyBlocked: store.privacyBlocksWork,
                            privacyGeneration: store.dataGeneration)
                    } label: { Text(text("Connect or manage Outlook", "Connecter ou gérer Outlook")) }
                        .disabled(busy).accessibilityIdentifier("outlook.setup.manage")
                }
            }.padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(MorningStyle.ink).background(MorningPaper(showsSun: false))
        .navigationTitle("Outlook").navigationBarTitleDisplayMode(.inline).disabled(store.privacyBlocksWork)
        .onAppear { visible = true; refreshAccounts() }
        .onDisappear { visible = false; clear() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { clear() }
            else if phase == .active && visible { refreshAccounts() }
        }
        .onChange(of: store.dataGeneration) { _, _ in clear(); if visible { refreshAccounts() } }
        .onChange(of: store.privacyBlocksWork) { _, blocked in
            if blocked { clear() } else if visible { refreshAccounts() }
        }
    }

    private func accountName(_ connection: ComposioConnection, index: Int) -> String {
        if let label = connection.accountLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty, label != connection.id { return label }
        return text("Outlook account \(index + 1)", "Compte Outlook \(index + 1)")
    }
    private func refreshAccounts() {
        clear()
        launch { token, generation in
            let fresh = try await store.composio.connections()
            try check(token, generation)
            let active = fresh.filter { $0.service == "outlook" && $0.isActive }
            guard Set(active.map(\.id)).count == active.count else { throw OutlookInboxError.identityChanged }
            connections = active; loaded = true
            if let only = active.first, active.count == 1 {
                selectedConnection = only
                try await loadIdentity(only, token: token, generation: generation)
            }
        }
    }
    private func choose(_ connection: ComposioConnection) {
        identity = nil; added = false; selectedConnection = connection
        launch { token, generation in try await loadIdentity(connection, token: token, generation: generation) }
    }
    private func loadIdentity(_ connection: ComposioConnection, token: UUID, generation: UUID) async throws {
        let fresh = try await OutlookInboxService(service: store.composio).identity(connectionID: connection.id)
        try check(token, generation)
        guard selectedConnection?.id == connection.id, fresh.connectionID == connection.id, fresh.isCurrent(at: Date()) else { throw OutlookInboxError.identityChanged }
        identity = fresh
    }
    private func addSelected() {
        guard let connection = selectedConnection, let identity, identity.isCurrent(at: Date()), !store.sessionActive else { return }
        launch { token, generation in
            let connections = try await store.composio.connections()
            try check(token, generation)
            let matching = connections.filter { $0.id == connection.id && $0.service == "outlook" && $0.isActive }
            guard matching.count == 1 else { throw OutlookInboxError.identityChanged }
            let fresh = try await OutlookInboxService(service: store.composio).identity(connectionID: connection.id)
            try check(token, generation)
            guard self.identity == identity, selectedConnection?.id == connection.id, identity.isCurrent(at: Date()),
                  fresh.isCurrent(at: Date()), fresh.target == identity.target else { throw OutlookInboxError.identityChanged }
            if store.addOutlookInboxMoment(connection: matching[0], identity: fresh) {
                added = true
                message = text("Added to your draft routine. Review and approve it in Routine before starting.",
                    "Ajouté au brouillon de votre routine. Relisez et validez-le dans Routine avant de démarrer.")
            } else { message = text("This moment could not be added. Check your routine before trying again.", "Ce moment n’a pas pu être ajouté. Vérifiez votre routine avant de réessayer.") }
        }
    }
    private func launch(_ work: @escaping @MainActor (UUID, UUID) async throws -> Void) {
        guard visible, scenePhase == .active, !store.privacyBlocksWork, store.composio.isConfigured else { return }
        operation?.cancel(); revision = UUID(); busy = true; message = nil
        let token = revision, generation = store.dataGeneration
        operation = Task { @MainActor in
            defer { if revision == token { busy = false; operation = nil } }
            do { try await work(token, generation) }
            catch is CancellationError { }
            catch {
                guard (try? check(token, generation)) != nil else { return }
                identity = nil; selectedConnection = nil; added = false
                message = text("Your Outlook account could not be verified. Refresh your accounts or check the connection before choosing again.",
                    "Votre compte Outlook n’a pas pu être vérifié. Actualisez vos comptes ou vérifiez la connexion avant de choisir à nouveau.")
            }
        }
    }
    private func check(_ token: UUID, _ generation: UUID) throws {
        try Task.checkCancellation()
        guard revision == token, visible, scenePhase == .active, !store.privacyBlocksWork, store.dataGeneration == generation else { throw CancellationError() }
    }
    private func clear() {
        revision = UUID(); operation?.cancel(); operation = nil; busy = false
        connections = []; selectedConnection = nil; identity = nil; loaded = false; added = false; message = nil
    }
    private func text(_ english: String, _ french: String) -> String { locale.language.languageCode?.identifier == "fr" ? french : english }
}
