import XCTest

/// Private, owner-authorized ordinary-phone evidence. This never injects speech or changes saved facts.
@MainActor
final class OrdinaryVoiceMemoryAcceptanceTests: XCTestCase {
    private var app: XCUIApplication!

    func testOrdinaryVoiceMemoryAcceptance() throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        guard environment["MO_ORDINARY_VOICE_MEMORY"] == "1" else {
            throw XCTSkip("Requires explicit MO_ORDINARY_VOICE_MEMORY=1; no app was activated.")
        }
        let phase = environment["MO_ORDINARY_VOICE_PHASE"] ?? "inspect"
        guard ["inspect", "inspectSettings", "memoryCheck"].contains(phase) else {
            throw XCTSkip("Choose inspect, inspectSettings or memoryCheck before activating the app.")
        }
        let base = "com.gibouu.morningoperator"
        guard let bundle = environment["MO_ORDINARY_VOICE_BUNDLE_ID"],
              bundle == base || bundle == base + ".personal" || bundle.hasPrefix(base + ".personal.") || bundle.hasPrefix(base + ".personal-"),
              !["fixture", "demo", "qa"].contains(where: bundle.lowercased().contains),
              bundle.range(of: #"^[A-Za-z0-9.-]+$"#, options: .regularExpression) != nil else {
            throw XCTSkip("Provide the exact ordinary MORE or personal bundle; fixture, demo and QA bundles are refused.")
        }
        #if targetEnvironment(simulator)
        throw XCTSkip("This acceptance requires a physical iPhone; no simulator app was activated.")
        #else
        app = XCUIApplication(bundleIdentifier: bundle)
        app.activate()
        guard app.wait(for: .runningForeground, timeout: 10) else {
            XCTFail("The selected ordinary app did not become foreground.")
            return
        }
        try requireOrdinaryState()
        switch phase {
        case "inspect":
            capture("ordinary-voice-current")
        case "inspectSettings":
            try openSettings()
            capture("ordinary-voice-settings")
        case "memoryCheck":
            try openMemory()
            guard try denialIsVisible() else {
                capture("ordinary-voice-memory-denial-missing")
                XCTFail("The existing scooter-denial fact was not visible. No fact was created or changed.")
                return
            }
            capture("ordinary-voice-memory-before-relaunch")
            app.terminate()
            app.activate()
            guard app.wait(for: .runningForeground, timeout: 10) else {
                XCTFail("Ordinary MORE did not return after normal reactivation.")
                return
            }
            try requireOrdinaryState()
            try openMemory()
            let retained = try denialIsVisible()
            capture("ordinary-voice-memory-after-relaunch")
            XCTAssertTrue(retained, "The same scooter-denial fact was not visible after relaunch.")
        default:
            break
        }
        #endif
    }

    private func requireOrdinaryState() throws {
        guard app.state == .runningForeground else {
            throw XCTSkip("MORE left the foreground; no further navigation was attempted.")
        }
        guard app.alerts.count == 0,
              XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.count == 0,
              !app.buttons["permissions.allow"].exists else {
            throw XCTSkip("A permission or unexpected alert requires the owner. No permission control was pressed.")
        }
        guard !app.descendants(matching: .any)["qa.testWorkspace"].exists,
              !app.staticTexts["briefing.synthetic"].exists else {
            throw XCTSkip("A synthetic workspace or source cannot provide ordinary-phone acceptance.")
        }
    }

    private func openSettings() throws {
        try requireOrdinaryState()
        if app.buttons["setup.intelligence"].exists { return }
        let settings = app.buttons["morning.settings"]
        if !settings.exists {
            let controls = app.buttons["morning.actions"]
            guard controls.waitForExistence(timeout: 5), controls.isHittable,
                  ["Show controls", "Afficher les commandes"].contains(controls.label) else {
                throw XCTSkip("Leave ordinary MORE on Home or Settings. No unrelated screen was dismissed.")
            }
            controls.tap()
        }
        try requireOrdinaryState()
        guard settings.waitForExistence(timeout: 5), settings.isHittable else {
            throw XCTSkip("The ordinary Settings control was not reachable.")
        }
        settings.tap()
        try requireOrdinaryState()
    }

    private func openMemory() throws {
        if app.staticTexts["intelligence.status"].exists { return }
        try openSettings()
        let memory = app.buttons["setup.intelligence"]
        guard try reveal(memory) else { throw XCTSkip("The Intelligence & memory navigation was not reachable.") }
        memory.tap()
        guard app.staticTexts["intelligence.status"].waitForExistence(timeout: 5) else {
            XCTFail("The ordinary Intelligence & memory screen did not open.")
            return
        }
        try requireOrdinaryState()
    }

    private func denialIsVisible() throws -> Bool {
        let fact = app.staticTexts.matching(NSPredicate(format: "label IN %@", [
            "Vous n’avez pas de trottinette électrique.", "You do not have an electric scooter."
        ])).firstMatch
        return try reveal(fact)
    }

    private func reveal(_ element: XCUIElement) throws -> Bool {
        let scroll = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch
            : (app.tables.firstMatch.exists ? app.tables.firstMatch : app.scrollViews.firstMatch)
        for downward in [false, true] {
            for _ in 0..<8 {
                try requireOrdinaryState()
                if element.exists && element.isHittable { return true }
                guard scroll.exists else { return false }
                if downward { scroll.swipeDown() } else { scroll.swipeUp() }
            }
        }
        return element.exists && element.isHittable
    }

    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name + "-private-screen"; image.lifetime = .keepAlways; add(image)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "-private-accessibility"; tree.lifetime = .keepAlways; add(tree)
    }
}
