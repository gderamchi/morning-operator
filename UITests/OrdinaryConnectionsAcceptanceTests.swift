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

    func test05PublicCityMapsAndWeatherReadRestoresUnconfiguredWeather() throws {
        let previousFailurePolicy = continueAfterFailure
        defer { continueAfterFailure = previousFailurePolicy }
        let app = try ordinaryApp()
        try enterDeveloperAccessIfRequested(app)
        try openConnections(app)
        let calendar = app.buttons["connections.calendar"]
        try reveal(calendar, in: app)
        calendar.tap()
        XCTAssertFalse(app.staticTexts["briefing.synthetic"].exists)

        let source = app.descendants(matching: .any).matching(identifier: "briefing.locationSource").firstMatch
        try reveal(source, in: app)
        let knownSources = ["Current location", "Position actuelle", "Choose a city", "Choisir une ville"]
        func readSource() -> String? {
            let children = source.descendants(matching: .staticText).allElementsBoundByIndex +
                source.descendants(matching: .button).allElementsBoundByIndex
            let pickerElements = [source] + children
            let texts = pickerElements.flatMap { [$0.label, $0.value as? String ?? ""] }
            let choices = knownSources.filter { choice in
                texts.contains { $0.localizedCaseInsensitiveContains(choice) }
            }
            guard choices.count == 1 else {
                let metadata = pickerElements.map {
                    "type=\($0.elementType.rawValue); label=\($0.label); value=\($0.value as? String ?? "<nil>")"
                }.joined(separator: "\n")
                let attachment = XCTAttachment(string: metadata)
                attachment.name = "ordinary-weather-picker-selection-only"
                attachment.lifetime = .keepAlways
                add(attachment)
                return nil
            }
            return choices[0]
        }
        guard let originalSource = readSource() else {
            XCTFail("The ordinary weather picker did not expose its original selection; no setting was changed.")
            return
        }
        if app.descendants(matching: .any).matching(identifier: "briefing.currentLocation").firstMatch.exists ||
            app.buttons["briefing.removeWeather"].exists {
            throw XCTSkip("Existing weather is configured; no weather selection was changed.")
        }
        let city = app.descendants(matching: .any).matching(identifier: "briefing.city").firstMatch
        var attemptedOurCity = false

        func require(_ condition: Bool, _ message: String) throws {
            guard condition else {
                XCTFail(message)
                throw NSError(domain: "OrdinaryConnectionsAcceptanceTests", code: 5,
                    userInfo: [NSLocalizedDescriptionKey: "Required public-city UI check failed."])
            }
        }
        func selectSource(_ labels: [String]) -> Bool {
            if let selection = readSource(), labels.contains(selection) { return true }
            try? reveal(source, in: app)
            guard source.exists && source.isHittable else { return false }
            source.tap()
            let option = app.buttons.matching(NSPredicate(format: "label IN %@", labels)).firstMatch
            guard option.waitForExistence(timeout: 5), option.isHittable else { return false }
            option.tap()
            guard let selection = readSource() else { return false }
            return labels.contains(selection)
        }
        func showsOurCity() -> Bool {
            guard city.exists else { return false }
            let text = ([city.label, city.value as? String ?? ""] +
                city.descendants(matching: .staticText).allElementsBoundByIndex.map(\.label)).joined(separator: " ")
            return text.localizedCaseInsensitiveContains("Paris") && text.localizedCaseInsensitiveContains("France")
        }

        // The picker saves immediately. Restore it even if search, weather or an assertion fails.
        continueAfterFailure = true
        defer {
            if attemptedOurCity {
                try? reveal(city, in: app)
                if city.exists {
                    if showsOurCity() {
                        let remove = app.buttons["briefing.removeWeather"]
                        try? reveal(remove, in: app)
                        if remove.exists && remove.isHittable { remove.tap() }
                        else { try? require(false, "The temporary city's Remove weather control was unavailable.") }
                        try? require(city.waitForNonExistence(timeout: 5), "The temporary public city must be removed.")
                    } else {
                        try? require(false, "An unexpected city is present; it was preserved rather than removed.")
                    }
                }
            }
            try? require(selectSource([originalSource]), "The original weather-source selection must be restored.")
            try? require(readSource() == originalSource, "The original weather-source selection must match exactly.")
            if attemptedOurCity { try? require(!showsOurCity(), "Paris must not remain configured after this read.") }
            let done = app.navigationBars.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Done", "Terminé")).firstMatch
            if done.exists && done.isHittable { done.tap() }
        }

        try require(selectSource(["Choose a city", "Choisir une ville"]), "The ordinary picker did not select Choose a city.")
        let search = app.textFields["briefing.citySearch"]
        try reveal(search, in: app)
        try require(search.exists && search.isHittable, "The public city search field was unavailable.")
        // Current-location mode can hide a saved fallback city; inspect after switching modes.
        guard !city.exists, !app.buttons["briefing.removeWeather"].exists else {
            throw XCTSkip("An existing weather city is configured; its value and the original picker were preserved.")
        }
        search.tap()
        search.typeText("Paris, France")
        let searchButton = app.buttons["briefing.searchCities"]
        try reveal(searchButton, in: app)
        try require(searchButton.exists && searchButton.isHittable && searchButton.isEnabled,
                    "The explicit city-search action was unavailable.")
        searchButton.tap()
        let result = app.buttons.matching(NSPredicate(format:
            "identifier BEGINSWITH %@ AND label CONTAINS[cd] %@ AND label CONTAINS[cd] %@",
            "briefing.cityResult.", "Paris", "France")).firstMatch
        try require(result.waitForExistence(timeout: 25), "Apple Maps did not return Paris, France.")
        try reveal(result, in: app)
        try require(result.exists && result.isHittable, "The real Paris, France result was not reachable.")
        attemptedOurCity = true
        result.tap()
        try require(city.waitForExistence(timeout: 5), "The selected public city did not appear.")
        try require(showsOurCity(), "The selected public city must be Paris, France.")

        let attribution = app.descendants(matching: .any).matching(identifier: "weather.sources").firstMatch
        try reveal(attribution, in: app)
        try require(attribution.exists && attribution.isHittable, "No admitted native Apple Weather snapshot appeared.")
        let wind = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "km/h")).firstMatch
        try reveal(wind, in: app)
        try require(wind.exists && wind.isHittable, "The native snapshot must contain a measured wind value.")
        try require(!app.staticTexts["briefing.error"].exists, "The ordinary briefing reported an error.")
        try require(!app.staticTexts["briefing.synthetic"].exists, "A synthetic source cannot establish provider acceptance.")
        let note = XCTAttachment(string: "Real Apple Maps result selected for public Paris, France; admitted Apple Weather attribution and measured wind present. No location permission or owner content was requested. Cleanup assertions run in defer.")
        note.name = "ordinary-public-city-provider-evidence"
        note.lifetime = .keepAlways
        add(note)
    }

    func test06OrdinaryWorkerLoadsFreshNotionServiceAndEmptyInventory() throws {
        let app = try ordinaryApp()
        try enterDeveloperAccessIfRequested(app)
        try openConnections(app)
        let notion = app.buttons["connections.account.notion"]
        try reveal(notion, in: app)
        XCTAssertTrue(notion.exists && notion.isHittable, "The ordinary Worker service list did not expose Notion.")
        notion.tap()
        XCTAssertTrue(app.navigationBars["Notion"].waitForExistence(timeout: 10))

        // Both labels require hasLoaded, set only after services and connections succeed.
        let refresh = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label IN %@",
            "accounts.refresh", ["Refresh my accounts", "Actualiser mes comptes"])).firstMatch
        XCTAssertTrue(refresh.waitForExistence(timeout: 45), "No successful fresh Worker services/connections read appeared.")
        try reveal(refresh, in: app)
        XCTAssertTrue(refresh.isHittable && refresh.isEnabled)
        let empty = app.staticTexts.matching(NSPredicate(format: "label IN %@", [
            "No account connected yet. Sign in above, then choose the permissions you want to share.",
            "Aucun compte connecté pour le moment. Identifiez-vous ci-dessus, puis choisissez les accès à partager."
        ])).firstMatch
        XCTAssertTrue(empty.exists, "The fresh Notion inventory did not report an empty account state.")
        XCTAssertTrue(app.buttons["accounts.connect.notion"].exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "accounts.notice").firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Connection unavailable"].exists)
        XCTAssertFalse(app.staticTexts["Connexion indisponible"].exists)
        let note = XCTAttachment(string: "The ordinary iPhone app completed installation-authenticated Worker services and connections reads and displayed the fresh empty Notion inventory. No sign-in, tool-catalog read or Notion action was initiated.")
        note.name = "ordinary-worker-services-and-connections-evidence"
        note.lifetime = .keepAlways
        add(note)
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
        let settings = app.buttons["morning.settings"]
        for _ in 0..<3 {
            if settings.exists && settings.isHittable { break }
            // Controls auto-hide; observe each attempt before tapping the landscape again.
            landscape.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.65)).tap()
            if settings.waitForExistence(timeout: 2) { break }
        }
        XCTAssertTrue(settings.exists && settings.isHittable, "The ordinary Home controls did not expose Settings.")
        settings.tap()
        let connections = app.buttons["setup.connections"]
        for _ in 0..<3 {
            if app.buttons["connections.instagram"].exists { break }
            guard connections.exists else { break }
            try reveal(connections, in: app)
            connections.tap()
            if app.buttons["connections.instagram"].waitForExistence(timeout: 3) { break }
        }
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
