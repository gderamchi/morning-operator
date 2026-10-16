import SwiftUI
import MorningApple
import MorningCore

/// A named source choice; adding it never approves or starts the routine.
@MainActor struct CalendlyDaySetupView: View {
    @Bindable var store: MorningStore
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @State private var connections: [ComposioConnection] = []
    @State private var selectedConnection: ComposioConnection?
    @State private var identity: CalendlyIdentity?
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
                PageHeading(eyebrow: "Calendly", title: text("Your Calendly appointments, each morning", "Vos rendez-vous Calendly, chaque matin"),
                    subtitle: text("Choose an account. MORE reads appointments starting today in this iPhone’s time zone.",
                        "Choisissez un compte. MORE lit les rendez-vous qui commencent aujourd’hui dans le fuseau de cet iPhone."))
                Text(text("Up to 25 active appointments are read. MORE tells you when the reading is partial. This moment does not create or cancel an appointment.",
                    "La lecture comprend jusqu’à 25 rendez-vous actifs. MORE indique si elle est partielle. Ce moment ne crée ni n’annule de rendez-vous."))
                    .font(MorningTheme.Typography.note).fixedSize(horizontal: false, vertical: true)
                if CalendlyDayUITestFixture.isRequested {
                    Text("SYNTHETIC local fixture · no Calendly account is used")
                        .font(MorningTheme.Typography.note).accessibilityIdentifier("calendly.setup.synthetic")
                }
                if !store.composio.isConfigured {
                    Text(text("Calendly is unavailable in this version.", "Calendly n’est pas disponible dans cette version."))
                } else {
                    if let message {
                        Text(message).font(MorningTheme.Typography.note).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("calendly.setup.status")
                    }
                    if busy { ProgressView(text("Checking your Calendly account…", "Vérification de votre compte Calendly…")) }
                    if loaded && connections.isEmpty {
                        Text(text("Connect a Calendly account, then return here to choose its appointments.",
                            "Connectez un compte Calendly, puis revenez ici choisir ses rendez-vous."))
                            .font(MorningTheme.Typography.note).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("calendly.setup.emptyAccount")
                    }
                    ForEach(Array(connections.enumerated()), id: \.element.id) { index, connection in
                        Button { choose(connection) } label: {
                            Label(accountName(connection, index: index), systemImage: selectedConnection?.id == connection.id ? "checkmark.circle" : "person.crop.circle")
                                .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                        }.buttonStyle(SecondaryButtonStyle()).disabled(busy)
                            .accessibilityIdentifier("calendly.setup.account.\(index)")
                    }
                    if let identity {
                        Text(identity.userName).font(MorningTheme.Typography.heading)
                            .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("calendly.setup.identity")
                        Text(text("Read appointments for “\(identity.userName)” that start today. The day is recalculated in this iPhone’s time zone when the moment runs.",
                            "Lire les rendez-vous de « \(identity.userName) » qui commencent aujourd’hui. La journée sera recalculée dans le fuseau de cet iPhone lorsque ce moment démarre."))
                            .font(MorningTheme.Typography.note).fixedSize(horizontal: false, vertical: true)
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Button(added ? text("Added to your routine", "Ajouté à votre routine") : text("Add this Calendly moment", "Ajouter ce moment Calendly")) { addSelected() }
                                .buttonStyle(PrimaryButtonStyle())
                                .disabled(busy || added || !identity.isCurrent(at: context.date) || store.sessionActive || store.busy)
                                .accessibilityIdentifier("calendly.setup.add")
                            if !identity.isCurrent(at: context.date) {
                                Text(text("This choice has expired. Refresh your account before adding it.", "Ce choix a expiré. Actualisez votre compte avant de l’ajouter."))
                                    .font(MorningTheme.Typography.note).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    Button(text("Refresh Calendly accounts", "Actualiser les comptes Calendly")) { refreshAccounts() }
                        .buttonStyle(SecondaryButtonStyle()).disabled(busy).accessibilityIdentifier("calendly.setup.refresh")
                    NavigationLink {
                        APIConnectionsView(service: store.composio, serviceID: "calendly", privacyBlocked: store.privacyBlocksWork,
                            privacyGeneration: store.dataGeneration)
                    } label: { Text(text("Connect or manage Calendly", "Connecter ou gérer Calendly")) }
                        .disabled(busy).accessibilityIdentifier("calendly.setup.manage")
                }
            }.padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(MorningStyle.ink).background(MorningPaper(showsSun: false))
        .navigationTitle("Calendly").navigationBarTitleDisplayMode(.inline).disabled(store.privacyBlocksWork)
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
        return text("Calendly account \(index + 1)", "Compte Calendly \(index + 1)")
    }
    private func refreshAccounts() {
        clear()
        launch { token, generation in
            let fresh = try await store.composio.connections()
            try check(token, generation)
            let active = fresh.filter { $0.service == "calendly" && $0.isActive }
            guard Set(active.map(\.id)).count == active.count else { throw CalendlyDayError.identityChanged }
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
        let fresh = try await CalendlyDayService(service: store.composio).identity(connectionID: connection.id)
        try check(token, generation)
        guard selectedConnection?.id == connection.id, fresh.connectionID == connection.id, fresh.isCurrent(at: Date()) else { throw CalendlyDayError.identityChanged }
        identity = fresh
    }
    private func addSelected() {
        guard let connection = selectedConnection, let identity, identity.isCurrent(at: Date()), !store.sessionActive else { return }
        launch { token, generation in
            let connections = try await store.composio.connections()
            try check(token, generation)
            let matching = connections.filter { $0.id == connection.id && $0.service == "calendly" && $0.isActive }
            guard matching.count == 1 else { throw CalendlyDayError.identityChanged }
            let fresh = try await CalendlyDayService(service: store.composio).identity(connectionID: connection.id)
            try check(token, generation)
            guard self.identity == identity, selectedConnection?.id == connection.id, identity.isCurrent(at: Date()),
                  fresh.isCurrent(at: Date()), fresh.target == identity.target else { throw CalendlyDayError.identityChanged }
            if store.addCalendlyDay(connection: matching[0], identity: fresh) {
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
                message = text("Your Calendly account could not be verified. Refresh your accounts or check the connection before choosing again.",
                    "Votre compte Calendly n’a pas pu être vérifié. Actualisez vos comptes ou vérifiez la connexion avant de choisir à nouveau.")
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
