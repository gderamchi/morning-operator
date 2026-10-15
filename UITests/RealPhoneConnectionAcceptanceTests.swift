import XCTest

/// Owner-assisted checks of the installed ordinary app, never a seeded workspace.
/// Screenshots may contain private data: keep the resulting xcresult local.
@MainActor
final class RealPhoneConnectionAcceptanceTests: XCTestCase {
    private var app: XCUIApplication!

    private func activateOrdinaryApp() throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        guard environment["MO_REAL_PHONE_CONNECTIONS"] == "1" else {
            throw XCTSkip("Requires explicit MO_REAL_PHONE_CONNECTIONS=1; no app was activated.")
        }
        #if targetEnvironment(simulator)
        throw XCTSkip("This acceptance suite requires the owner's physical iPhone.")
        #else
        guard let bundle = environment["MO_REAL_PHONE_BUNDLE_ID"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              bundle.hasPrefix("com.gibouu.morningoperator."),
              !bundle.lowercased().contains("fixture"), !bundle.lowercased().contains(".qa") else {
            throw XCTSkip("Provide the explicit installed ordinary MORE bundle in MO_REAL_PHONE_BUNDLE_ID.")
        }
        app = XCUIApplication(bundleIdentifier: bundle)
        // Activate the existing ordinary app without launch arguments or launch environment.
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "The selected ordinary app did not reach the foreground.")
        try refusePermissionOrFixtureScreens()
        #endif
    }

    func testBackendConfiguredAndOptionalExistingGmailAPIAccount() throws {
        try openConnections()
        let gmailActions = app.buttons["connections.gmailActions"]
        XCTAssertTrue(gmailActions.waitForExistence(timeout: 25),
                      "The installed app did not load its configured live service catalogue. No backend readiness is claimed.")
        XCTAssertTrue(app.buttons["connections.account.outlook"].exists,
                      "The live catalogue did not expose the expected configured Outlook service.")
        capture("real-phone-configured-connections")

        guard ProcessInfo.processInfo.environment["MO_REAL_PHONE_EXPECT_GMAIL_ACCOUNT"] == "1" else { return }
        reveal(gmailActions)
        if !app.buttons["connections.account.gmail"].exists { gmailActions.tap() }
        let gmail = app.buttons["connections.account.gmail"]
        reveal(gmail)
        gmail.tap()
        defer { returnToConnections() }
        try refusePermissionOrFixtureScreens()
        let loaded = app.buttons["accounts.refresh"]
        XCTAssertTrue(loaded.waitForExistence(timeout: 25), "The Gmail API account check did not finish.")
        XCTAssertFalse(app.descendants(matching: .any)["accounts.notice"].exists,
                       "The Gmail API account check reported a connection problem.")
        let activeAccount = button(labels: ["Choose an action", "Choisir une action"])
        XCTAssertTrue(activeAccount.exists,
                      "No active Gmail API account was verified for this installation. No sign-in was attempted.")
        // Presence of this action chooser proves ACTIVE metadata; never open or run it.
        capture("real-phone-existing-gmail-api-account")
    }

    func testExistingCalendarAccessWithoutChangingSelection() throws {
        try openConnections()
        let calendar = button(containing: ["Calendar & weather", "Calendrier et météo"])
        reveal(calendar)
        calendar.tap()
        defer { returnToConnections(calendar: true) }
        try refusePermissionOrFixtureScreens()
        XCTAssertFalse(app.staticTexts["briefing.synthetic"].exists, "Synthetic calendars cannot establish real access.")
        let choices = app.switches.matching(NSPredicate(format: "identifier BEGINSWITH %@", "briefing.calendar."))
        let readiness = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ OR identifier IN %@",
            "briefing.calendar.", ["briefing.calendarConnect", "briefing.error"]))
        XCTAssertTrue(readiness.firstMatch.waitForExistence(timeout: 15), "The calendar connection screen did not become ready.")
        capture("real-phone-existing-calendar-access")
        guard choices.count > 0 else {
            throw XCTSkip("No existing readable calendar inventory was exposed. No permission or calendar selection was changed.")
        }
        XCTAssertFalse(app.staticTexts["briefing.error"].exists, "The existing calendar source reported a read error.")
        // Inventory only: no calendar toggle, event mutation, or speech preview is used.
    }

    func testReadRemindersOnlyWithPreviouslyGrantedAccess() throws {
        try openConnections()
        let reminders = button(containing: ["Reminders", "Rappels"])
        reveal(reminders)
        reminders.tap()
        defer { returnToConnections() }
        let read = app.buttons["native.remindersRead"]
        XCTAssertTrue(read.waitForExistence(timeout: 10), "The native Reminders page did not open.")
        try refusePermissionOrFixtureScreens()
        guard ["Show my reminders", "Afficher mes rappels"].contains(read.label) else {
            capture("real-phone-reminders-access-required")
            throw XCTSkip("Reminders access is not already granted. The permission request was not pressed.")
        }
        reveal(read)
        XCTAssertTrue(read.isEnabled, "A reminder read is already in progress; no duplicate request was made.")
        read.tap()
        try refusePermissionOrFixtureScreens()
        let readAt = app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "Read at ", "Lus à ")).firstMatch
        XCTAssertTrue(readAt.waitForExistence(timeout: 20),
                      "The native Reminders read did not produce its success timestamp. Empty data alone is not success.")
        XCTAssertFalse(app.staticTexts["native.remindersMessage"].exists,
                       "The native Reminders read reported a problem.")
        capture("real-phone-native-reminders-read")
        // Never tap a reminder's completion button, even when the list is nonempty.
    }

    private func openConnections() throws {
        try activateOrdinaryApp()
        try refusePermissionOrFixtureScreens()
        if isConnectionsPage { return }
        let connections = app.buttons["setup.connections"]
        if !connections.exists {
            let settings = app.buttons["morning.settings"]
            if !settings.exists {
                let controls = app.buttons["morning.actions"]
                guard controls.waitForExistence(timeout: 10), controls.isHittable,
                      ["Show controls", "Afficher les commandes"].contains(controls.label) else {
                    capture("real-phone-navigation-unavailable")
                    throw XCTSkip("Leave ordinary MORE on Home, Settings, or Apps & accounts. No other screen was dismissed.")
                }
                controls.tap()
            }
            reveal(settings)
            settings.tap()
        }
        reveal(connections)
        connections.tap()
        XCTAssertTrue(connectionsNavigation.waitForExistence(timeout: 10), "Apps & accounts did not open.")
        try refusePermissionOrFixtureScreens()
    }

    private var connectionsNavigation: XCUIElement {
        app.navigationBars.matching(NSPredicate(format: "identifier IN %@ OR label IN %@",
            ["Apps & accounts", "Apps et comptes"], ["Apps & accounts", "Apps et comptes"])).firstMatch
    }

    private var isConnectionsPage: Bool {
        connectionsNavigation.exists && app.buttons["connections.gmailReader"].exists
    }

    private func returnToConnections(calendar: Bool = false) {
        guard app.alerts.count == 0,
              XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.count == 0 else { return }
        if isConnectionsPage { return }
        if calendar {
            let done = app.navigationBars.buttons.matching(NSPredicate(format: "label IN %@", ["Done", "Terminé"])).firstMatch
            if done.exists && done.isHittable { done.tap() }
            if isConnectionsPage { return }
        }
        let back = app.navigationBars.buttons.matching(NSPredicate(
            format: "label IN %@", ["Apps & accounts", "Apps et comptes", "Back", "Retour"])).firstMatch
        if back.exists && back.isHittable { back.tap() }
    }

    private func refusePermissionOrFixtureScreens() throws {
        if app.alerts.count > 0 || XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.count > 0 {
            capture("real-phone-permission-or-alert-blocked")
            throw XCTSkip("A system permission or app alert requires the owner. No alert button was pressed.")
        }
        XCTAssertFalse(app.descendants(matching: .any)["qa.testWorkspace"].exists,
                       "An isolated test workspace cannot provide ordinary-data acceptance evidence.")
        XCTAssertFalse(app.staticTexts["briefing.synthetic"].exists,
                       "Synthetic sources cannot provide real-phone acceptance evidence.")
    }

    private func button(labels: [String]) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label IN %@", labels)).firstMatch
    }

    private func button(containing labels: [String]) -> XCUIElement {
        app.buttons.matching(NSCompoundPredicate(orPredicateWithSubpredicates:
            labels.map { NSPredicate(format: "label CONTAINS %@", $0) })).firstMatch
    }

    private func reveal(_ element: XCUIElement) {
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            guard scroll.exists else { break }
            if element.exists && element.frame.midY < scroll.frame.midY { scroll.swipeDown() }
            else { scroll.swipeUp() }
        }
        XCTAssertTrue(element.exists && element.isHittable, "The expected read-only navigation control is not reachable.")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
