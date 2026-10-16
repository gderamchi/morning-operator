import XCTest

/// Explicit physical acceptance: no test workspace, StoreKit fixture or injected grant.
@MainActor
final class OrdinaryConnectionsAcceptanceTests: XCTestCase {
    private let bundle = "com.gibouu.morningoperator"

    func test01RealAppleOfferWhenOrdinaryAccessIsLocked() throws {
        let app = try ordinaryApp()
        if hasOrdinaryAccess(app) {
            throw XCTSkip("Existing ordinary access can include the approved Debug entry; it does not prove a StoreKit offer.")
        }

        let offer = app.buttons["onboarding.offer"]
        if offer.waitForExistence(timeout: 10) {
            offer.tap()
        } else {
            for _ in 0..<3 {
                let next = app.buttons["onboarding.next"]
                guard next.waitForExistence(timeout: 5) else { break }
                next.tap()
            }
        }

        XCTAssertTrue(app.buttons["paywall.subscribe"].waitForExistence(timeout: 10),
                      "The ordinary app did not expose its real subscription offer.")
        let price = app.staticTexts["paywall.price"]
        let loaded = price.waitForExistence(timeout: 45)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = loaded ? "ordinary-live-apple-offer" : "ordinary-apple-offer-unavailable"
        capture.lifetime = .keepAlways
        add(capture)
        XCTAssertTrue(loaded,
                      "StoreKit did not return the configured product. No purchase or entitlement was simulated.")
        XCTAssertTrue(app.buttons["paywall.restore"].exists)
        // A purchase is intentionally separate from this read-only offer check.
    }

    func test02ExistingNativeGmailReadsInsideTheOrdinaryApp() throws {
        let app = try ordinaryApp()
        try enterDeveloperAccessIfRequested(app)
        try openConnections(app)
        let reader = app.buttons["connections.gmailReader"]
        try reveal(reader, in: app)
        reader.tap()
        let messages = app.descendants(matching: .any).matching(identifier: "gmail.messages").firstMatch
        let loaded = messages.waitForExistence(timeout: 45)
        if !loaded, app.buttons["gmail.connect"].exists,
           !app.staticTexts["gmail.error"].exists, !app.staticTexts["gmail.configuration"].exists {
            throw XCTSkip("This ordinary installation has no saved native Gmail grant. No new Google consent was initiated.")
        }
        XCTAssertTrue(loaded,
                      "No fresh native Gmail result was obtained from the ordinary app's existing credential.")
        XCTAssertTrue(app.staticTexts["gmail.unread"].exists)
        XCTAssertFalse(app.staticTexts["gmail.error"].exists)
        XCTAssertFalse(app.staticTexts["gmail.messages.partial"].exists)
        // Do not inspect or export message labels, addresses, bodies or counts.
    }

    func test03ExistingCalendarGrantExposesTheRealInventory() throws {
        let app = try ordinaryApp()
        try enterDeveloperAccessIfRequested(app)
        try openConnections(app)
        let calendar = app.buttons["connections.calendar"]
        try reveal(calendar, in: app)
        calendar.tap()
        XCTAssertFalse(app.staticTexts["briefing.synthetic"].exists)
        let calendars = app.switches.matching(NSPredicate(format: "identifier BEGINSWITH %@", "briefing.calendar."))
        guard calendars.firstMatch.waitForExistence(timeout: 20) else {
            throw XCTSkip("No existing native Calendar inventory was obtained; no grant or calendar selection was changed.")
        }
        XCTAssertGreaterThan(calendars.count, 0)
        XCTAssertFalse(app.staticTexts["briefing.error"].exists)
        // Inventory establishes readable calendars, not a selected-calendar event result.
    }

    func test04ExistingRemindersGrantReturnsAFreshRead() throws {
        let app = try ordinaryApp()
        try enterDeveloperAccessIfRequested(app)
        try openConnections(app)
        let reminders = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@",
            "Find your upcoming reminders", "Retrouvez vos prochains rappels")).firstMatch
        try reveal(reminders, in: app)
        reminders.tap()
        let read = app.buttons["native.remindersRead"]
        try reveal(read, in: app)
        guard ["Show my reminders", "Afficher mes rappels"].contains(read.label) else {
            throw XCTSkip("This ordinary installation has no existing Reminders grant; no permission was requested.")
        }
        read.tap()
        let timestamp = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "Read at ", "Lus à ")).firstMatch
        XCTAssertTrue(timestamp.waitForExistence(timeout: 30), "No fresh native Reminders read timestamp appeared.")
        XCTAssertFalse(app.staticTexts["native.remindersMessage"].exists)
        // Empty dated results are valid. Never inspect titles or mark anything complete.
    }

    private func ordinaryApp() throws -> XCUIApplication {
        continueAfterFailure = false
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MORE_PHYSICAL_CONNECTIONS_ACCEPTANCE"] == "1",
                          "Requires an explicit physical acceptance opt-in.")
        #if targetEnvironment(simulator)
        throw XCTSkip("Requires the ordinary physical iPhone.")
        #else
        let app = XCUIApplication(bundleIdentifier: bundle)
        app.launchArguments = []
        app.launchEnvironment = [:]
        app.terminate()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        for identifier in ["qa.testWorkspace", "onboarding.preview", "briefing.synthetic"] {
            XCTAssertFalse(app.descendants(matching: .any).matching(identifier: identifier).firstMatch.exists,
                           "A preview or fixture cannot establish ordinary acceptance.")
        }
        return app
        #endif
    }

    private func hasOrdinaryAccess(_ app: XCUIApplication) -> Bool {
        app.buttons["morning.actions"].exists || app.buttons["permissions.allow"].exists
    }

    private func enterDeveloperAccessIfRequested(_ app: XCUIApplication) throws {
        guard ProcessInfo.processInfo.environment["MORE_PHYSICAL_DEVELOPER_ACCESS"] == "1" else { return }
        if !hasOrdinaryAccess(app) {
            let intro = app.buttons["onboarding.developerAccess"]
            let paywall = app.buttons["paywall.developerAccess"]
            _ = intro.waitForExistence(timeout: 10)
            let entry = intro.exists ? intro : paywall
            XCTAssertTrue(entry.exists && entry.isHittable,
                          "The product's explicit Debug developer entry is unavailable.")
            entry.tap()
            let note = XCTAttachment(string: "Official Debug developer entry selected through the ordinary UI. No StoreKit entitlement was asserted.")
            note.name = "ordinary-debug-access-route"
            note.lifetime = .keepAlways
            add(note)
        }
        // Defer optional setup prompts; each real service permission is checked separately.
        for _ in 0..<12 {
            let skip = app.buttons["permissions.skip"]
            let finish = app.buttons["permissions.finish"]
            if skip.exists && skip.isHittable { skip.tap() }
            else if finish.exists && finish.isHittable { finish.tap() }
            else if app.buttons["morning.actions"].waitForExistence(timeout: 2), app.buttons["morning.actions"].isHittable { return }
        }
        XCTAssertTrue(app.buttons["morning.actions"].waitForExistence(timeout: 10))
    }

    private func openConnections(_ app: XCUIApplication) throws {
        let landscape = app.buttons["morning.actions"]
        guard landscape.waitForExistence(timeout: 8) else {
            throw XCTSkip("Ordinary access/setup is incomplete. No fixture or system permission was injected.")
        }
        landscape.tap()
        let settings = app.buttons["morning.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        let connections = app.buttons["setup.connections"]
        try reveal(connections, in: app)
        connections.tap()
        XCTAssertTrue(app.buttons["connections.instagram"].waitForExistence(timeout: 10))
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) throws {
        for direction in [true, false] {
            for _ in 0..<14 {
                if element.exists && element.isHittable { return }
                let list = app.collectionViews.firstMatch
                let container = list.exists ? list : app.scrollViews.firstMatch
                if direction { container.swipeUp() } else { container.swipeDown() }
            }
        }
        XCTFail("The ordinary destination was not reachable.")
    }
}
