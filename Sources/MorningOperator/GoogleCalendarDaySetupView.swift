import SwiftUI
import MorningApple
import MorningCore

/// A named, read-only source choice. Adding it creates an unapproved routine draft.
@MainActor struct GoogleCalendarDaySetupView: View {
    @Bindable var store: MorningStore
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @State private var connections: [ComposioConnection] = []
    @State private var selectedConnection: ComposioConnection?
    @State private var options: [Option] = []
    @State private var selectedID: String?
    @State private var nextCursor: String?
    @State private var consumedCursors: Set<String> = []
    @State private var pageLoaded = false
    @State private var loaded = false
    @State private var busy = false
    @State private var added = false
    @State private var message: String?
    @State private var visible = false
    @State private var revision = UUID()
    @State private var operation: Task<Void, Never>?
    // The runtime revalidates the same bounded set: ten pages of fifty calendars.
    private let maximumPages = 10

    private struct Option: Identifiable, Equatable {
        let choice: GoogleCalendarChoice
        let pageCursor: String?
        let receivedAt: Date
        var id: String { choice.id }
        func isCurrent(at date: Date) -> Bool { (0..<300).contains(date.timeIntervalSince(receivedAt)) }
    }
    private var selected: Option? { options.first { $0.id == selectedID } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeading(eyebrow: "Google Calendar", title: text("Your calendar, each morning", "Votre calendrier, chaque matin"),
                    subtitle: text("Choose one calendar. MORE reads the current day in this iPhone’s time zone each morning.",
                        "Choisissez un calendrier. MORE lit le jour courant dans le fuseau de cet iPhone à chaque matin."))
                Text(text("Up to 25 events are read. MORE tells you when the reading is partial. This moment does not create or change any event.",
                    "La lecture comprend jusqu’à 25 événements. MORE indique si elle est partielle. Ce moment ne crée ni ne modifie aucun événement."))
                    .font(MorningTheme.Typography.note).fixedSize(horizontal: false, vertical: true)
                if GoogleCalendarDayUITestFixture.isRequested {
                    Text("SYNTHETIC local fixture · no Google account is used")
                        .font(MorningTheme.Typography.note).accessibilityIdentifier("googleCalendar.setup.synthetic")
                }
                if !store.composio.isConfigured {
                    Text(text("Google Calendar is unavailable in this version.", "Google Calendar n’est pas disponible dans cette version."))
                } else {
                    if let message {
                        Text(message).font(MorningTheme.Typography.note).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("googleCalendar.setup.status")
                    }
                    if busy { ProgressView(text("Checking your calendars…", "Vérification de vos calendriers…")) }
                    if loaded && connections.isEmpty {
                        Text(text("Connect a Google Calendar account, then return here to choose its calendar.",
                            "Connectez un compte Google Calendar, puis revenez ici choisir son calendrier."))
                            .font(MorningTheme.Typography.note).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("googleCalendar.setup.emptyAccount")
                    }
                    ForEach(Array(connections.enumerated()), id: \.element.id) { index, connection in
                        Button { choose(connection) } label: {
                            Label(accountName(connection, index: index), systemImage: selectedConnection?.id == connection.id ? "checkmark.circle" : "person.crop.circle")
                                .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                        }.buttonStyle(SecondaryButtonStyle()).disabled(busy)
                            .accessibilityIdentifier("googleCalendar.setup.account.\(index)")
                    }
                    if selectedConnection != nil {
                        Text(text("Calendars you can read", "Calendriers que vous pouvez lire"))
                            .font(MorningTheme.Typography.heading).fixedSize(horizontal: false, vertical: true)
                        ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                            Button { selectedID = option.id; added = false; message = nil } label: {
                                Label(option.choice.name, systemImage: selectedID == option.id ? "checkmark.circle.fill" : "calendar")
                                    .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                            }.buttonStyle(SecondaryButtonStyle()).disabled(busy)
                                .accessibilityIdentifier("googleCalendar.setup.calendar.\(index)")
                        }
                        if pageLoaded && options.isEmpty {
                            Text(nextCursor == nil
                                ? text("No named, readable calendar was returned for this account.", "Aucun calendrier nommé et lisible n’a été renvoyé pour ce compte.")
                                : text("No readable calendar on this page. More calendars are available below.", "Aucun calendrier lisible sur cette page. Vous pouvez charger les suivants."))
                                .font(MorningTheme.Typography.note).fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("googleCalendar.setup.emptyCalendars")
                        }
                        if nextCursor != nil && consumedCursors.count < maximumPages - 1 {
                            Button(text("Load more calendars", "Charger d’autres calendriers")) { loadMore() }
                                .buttonStyle(SecondaryButtonStyle()).disabled(busy).accessibilityIdentifier("googleCalendar.setup.more")
                        } else if nextCursor != nil {
                            Text(text("This list is limited to the first 500 calendars. Choose a calendar from this reading.",
                                "Cette liste se limite aux 500 premiers calendriers. Choisissez un calendrier de cette lecture."))
                                .font(MorningTheme.Typography.note).fixedSize(horizontal: false, vertical: true)
                        }
                        if let selected {
                            Text(text("Read today from “\(selected.choice.name)”, using this iPhone’s time zone when the moment runs.",
                                "Lire le jour courant dans « \(selected.choice.name) », au fuseau de cet iPhone lorsque ce moment démarre."))
                                .font(MorningTheme.Typography.note).fixedSize(horizontal: false, vertical: true)
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                Button(added ? text("Added to your routine", "Ajouté à votre routine") : text("Add this calendar moment", "Ajouter ce moment calendrier")) { addSelected() }
                                    .buttonStyle(PrimaryButtonStyle())
                                    .disabled(busy || added || !selected.isCurrent(at: context.date) || store.sessionActive || store.busy)
                                    .accessibilityIdentifier("googleCalendar.setup.add")
                                if !selected.isCurrent(at: context.date) {
                                    Text(text("This choice has expired. Refresh your calendars before adding it.", "Ce choix a expiré. Actualisez vos calendriers avant de l’ajouter."))
                                        .font(MorningTheme.Typography.note).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    Button(text("Refresh accounts and calendars", "Actualiser les comptes et calendriers")) { refreshAccounts() }
                        .buttonStyle(SecondaryButtonStyle()).disabled(busy).accessibilityIdentifier("googleCalendar.setup.refresh")
                    NavigationLink {
                        APIConnectionsView(service: store.composio, serviceID: "googlecalendar", privacyBlocked: store.privacyBlocksWork,
                            privacyGeneration: store.dataGeneration)
                    } label: { Text(text("Connect or manage Google Calendar", "Connecter ou gérer Google Calendar")) }
                        .disabled(busy).accessibilityIdentifier("googleCalendar.setup.manage")
                }
            }.padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(MorningStyle.ink).background(MorningPaper(showsSun: false))
        .navigationTitle("Google Calendar").navigationBarTitleDisplayMode(.inline).disabled(store.privacyBlocksWork)
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
        if let label = connection.accountLabel, !label.isEmpty, label != connection.id { return label }
        return text("Google Calendar account \(index + 1)", "Compte Google Calendar \(index + 1)")
    }
    private func refreshAccounts() {
        clear()
        launch { token, generation in
            let fresh = try await store.composio.connections()
            try check(token, generation)
            let active = fresh.filter { $0.service == "googlecalendar" && $0.isActive }
            guard Set(active.map(\.id)).count == active.count else { throw GoogleCalendarDayError.selectionChanged }
            connections = active; loaded = true
            if let only = active.first, active.count == 1 {
                selectedConnection = only
                try await page(for: only, cursor: nil, token: token, generation: generation)
            }
        }
    }
    private func choose(_ connection: ComposioConnection) {
        clearChoices(); selectedConnection = connection
        launch { token, generation in try await page(for: connection, cursor: nil, token: token, generation: generation) }
    }
    private func loadMore() {
        guard let connection = selectedConnection, let cursor = nextCursor, consumedCursors.count < maximumPages - 1 else { return }
        launch { token, generation in try await page(for: connection, cursor: cursor, token: token, generation: generation) }
    }
    private func page(for connection: ComposioConnection, cursor: String?, token: UUID, generation: UUID) async throws {
        let page = try await GoogleCalendarDayService(service: store.composio).calendars(connectionID: connection.id, cursor: cursor)
        try check(token, generation)
        guard selectedConnection?.id == connection.id,
              page.nextCursor.map({ $0 != cursor && !consumedCursors.contains($0) }) ?? true else { throw GoogleCalendarDayError.selectionChanged }
        let receivedAt = Date()
        var combined = options
        for choice in page.choices {
            if let prior = combined.first(where: { $0.id == choice.id }) {
                guard prior.choice == choice else { throw GoogleCalendarDayError.selectionChanged }
            } else { combined.append(Option(choice: choice, pageCursor: cursor, receivedAt: receivedAt)) }
        }
        if let cursor { consumedCursors.insert(cursor) }
        options = combined; nextCursor = page.nextCursor; pageLoaded = true
    }
    private func addSelected() {
        guard let connection = selectedConnection, let selected, selected.isCurrent(at: Date()), !store.sessionActive else { return }
        launch { token, generation in
            let fresh = try await store.composio.connections()
            try check(token, generation)
            let matching = fresh.filter { $0.id == connection.id && $0.service == "googlecalendar" && $0.isActive }
            guard matching.count == 1 else { throw GoogleCalendarDayError.selectionChanged }
            let page = try await GoogleCalendarDayService(service: store.composio).calendars(connectionID: connection.id, cursor: selected.pageCursor)
            try check(token, generation)
            guard self.selected == selected, selected.isCurrent(at: Date()),
                  page.choices.first(where: { $0.id == selected.id }) == selected.choice else { throw GoogleCalendarDayError.selectionChanged }
            if store.addGoogleCalendarDay(connection: matching[0], choice: selected.choice) {
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
                clearChoices(); selectedConnection = nil
                message = text("Your calendars could not be verified. Refresh your accounts or check the connection before choosing again.",
                    "Vos calendriers n’ont pas pu être vérifiés. Actualisez vos comptes ou vérifiez la connexion avant de choisir à nouveau.")
            }
        }
    }
    private func check(_ token: UUID, _ generation: UUID) throws {
        try Task.checkCancellation()
        guard revision == token, visible, scenePhase == .active, !store.privacyBlocksWork,
              store.dataGeneration == generation else { throw CancellationError() }
    }
    private func clearChoices() {
        options = []; selectedID = nil; nextCursor = nil; consumedCursors = []; pageLoaded = false; added = false
    }
    private func clear() {
        revision = UUID(); operation?.cancel(); operation = nil; busy = false
        connections = []; selectedConnection = nil; loaded = false; message = nil; clearChoices()
    }
    private func text(_ english: String, _ french: String) -> String { locale.language.languageCode?.identifier == "fr" ? french : english }
}
