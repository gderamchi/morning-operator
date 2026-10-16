import XCTest

/// Explicit physical acceptance: no test workspace, StoreKit fixture or injected grant.
@MainActor
final class OrdinaryConnectionsAcceptanceTests: XCTestCase {
    private let bundle = "com.gibouu.morningoperator"

    func test01RealAppleOfferOrExistingVerifiedAccess() throws {
        let app = try ordinaryApp()
        if hasOrdinaryAccess(app) { return }

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
        try openConnections(app)
        let reader = app.buttons["connections.gmailReader"]
        try reveal(reader, in: app)
        reader.tap()
        let messages = app.descendants(matching: .any).matching(identifier: "gmail.messages").firstMatch
        let loaded = messages.waitForExistence(timeout: 45)
        XCTAssertTrue(loaded,
                      "No fresh native Gmail result was obtained from the ordinary app's existing credential.")
        XCTAssertTrue(app.staticTexts["gmail.unread"].exists)
        XCTAssertFalse(app.staticTexts["gmail.error"].exists)
        XCTAssertFalse(app.staticTexts["gmail.messages.partial"].exists)
        // Do not inspect or export message labels, addresses, bodies or counts.
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

    private func openConnections(_ app: XCUIApplication) throws {
        let landscape = app.buttons["morning.actions"]
        guard landscape.waitForExistence(timeout: 8) else {
            throw XCTSkip("Ordinary access/setup is incomplete; no subscription or permission bypass was used.")
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
