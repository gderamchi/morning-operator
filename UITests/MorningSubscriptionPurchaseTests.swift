import StoreKit
import StoreKitTest
import XCTest

/// Real StoreKit 2 calls against a local Xcode store, with no App Store payment.
@MainActor
final class MorningSubscriptionPurchaseTests: XCTestCase {
    private let productID = "com.gibouu.more.monthly"

    func testNoPurchaseAndEmptyRestoreKeepThePaywallClosedToHome() throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        let app = launch()
        defer { app.terminate() }
        showPaywall(in: app)
        XCTAssertTrue(app.staticTexts["paywall.price"].label.contains("4,99"))
        XCTAssertTrue(app.staticTexts["paywall.price"].label.contains("€"))
        XCTAssertTrue(app.buttons["paywall.subscribe"].label.contains("7"), "The fixture offers one free week.")
        tap("paywall.restore", in: app)
        XCTAssertTrue(app.staticTexts["paywall.notice"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertFalse(app.buttons["morning.actions"].exists)
        XCTAssertEqual(app.alerts.count, 0, "Restoring must not request routine permissions.")
    }

    func testPurchaseThroughPaywallUnlocksHome() throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        let app = launch()
        defer { app.terminate() }
        showPaywall(in: app)
        tap("paywall.subscribe", in: app)
        XCTAssertTrue(app.buttons["morning.actions"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertFalse(app.buttons["paywall.subscribe"].exists)
        XCTAssertEqual(session.allTransactions().count, 1)
    }

    func testExistingVerifiedSubscriptionOpensHome() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        try await session.buyProduct(identifier: productID)
        let app = launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["morning.actions"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertFalse(app.staticTexts["onboarding.heading"].exists)
    }

    func testRefundRevokesAccessWhileTheAppIsOpen() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        let transaction = try await session.buyProduct(identifier: productID)
        let app = launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["morning.actions"].waitForExistence(timeout: 20), app.debugDescription)
        try session.refundTransaction(identifier: UInt(transaction.id))
        XCTAssertTrue(app.staticTexts["onboarding.heading"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertFalse(app.buttons["morning.actions"].exists)
    }

    func testExpirationRemovesAccessOnForegroundRefresh() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        try await session.buyProduct(identifier: productID)
        let app = launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["morning.actions"].waitForExistence(timeout: 20), app.debugDescription)
        XCUIDevice.shared.press(.home)
        try session.expireSubscription(productIdentifier: productID)
        app.activate()
        XCTAssertTrue(app.staticTexts["onboarding.heading"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertFalse(app.buttons["morning.actions"].exists)
    }

    func testUnverifiedSubscriptionDoesNotUnlockHome() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        try await session.buyProduct(identifier: productID)
        try await session.setSimulatedError(.verification(.invalidSignature), forAPI: .verification)
        let app = launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["onboarding.heading"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertFalse(app.buttons["morning.actions"].exists)
    }

    func testCancelledPurchaseLeavesTheOfferReadyWithoutAnError() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        try await session.setSimulatedError(.generic(.userCancelled), forAPI: .purchase)
        let app = launch()
        defer { app.terminate() }
        showPaywall(in: app)
        tap("paywall.subscribe", in: app)
        let button = app.buttons["paywall.subscribe"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true AND label CONTAINS '7'"), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
        XCTAssertFalse(app.buttons["morning.actions"].exists)
        XCTAssertFalse(app.staticTexts["paywall.notice"].exists)
        XCTAssertTrue(session.allTransactions().isEmpty)
    }

    func testPendingPurchaseSurvivesForegroundUntilStoreKitApprovesIt() throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        session.askToBuyEnabled = true
        let app = launch()
        defer { app.terminate() }
        showPaywall(in: app)
        tap("paywall.subscribe", in: app)
        let button = app.buttons["paywall.subscribe"]
        let pending = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == false AND label CONTAINS 'attente'"), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [pending], timeout: 15), .completed)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.staticTexts["paywall.price"].waitForExistence(timeout: 10))
        let stillPending = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == false AND label CONTAINS 'attente'"), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [stillPending], timeout: 15), .completed)
        XCTAssertFalse(app.buttons["morning.actions"].exists)
        let transaction = try XCTUnwrap(session.allTransactions().first)
        try session.approveAskToBuyTransaction(identifier: transaction.identifier)
        XCTAssertTrue(app.buttons["morning.actions"].waitForExistence(timeout: 20), app.debugDescription)
    }

    private func makeSession() throws -> SKTestSession {
        continueAfterFailure = false
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "MORE", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        session.storefront = "FRA"
        session.locale = Locale(identifier: "fr_FR")
        session.timeRate = .realTime
        return session
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing", "--ui-testing-real-subscription", "--ui-testing-empty-workspace",
            "--ui-testing-workspace=\(UUID().uuidString)", "--theme-phase=day", "--ui-testing-reduce-motion",
            "-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR"
        ]
        app.launch()
        return app
    }

    private func showPaywall(in app: XCUIApplication) {
        XCTAssertTrue(app.buttons["onboarding.offer"].waitForExistence(timeout: 15), app.debugDescription)
        tap("onboarding.offer", in: app)
        XCTAssertTrue(app.staticTexts["paywall.price"].waitForExistence(timeout: 20), app.debugDescription)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons["paywall.subscribe"])
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
    }

    private func tap(_ identifier: String, in app: XCUIApplication) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 5), app.debugDescription)
        for _ in 0..<8 where !button.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(button.isHittable, app.debugDescription)
        button.tap()
    }
}
