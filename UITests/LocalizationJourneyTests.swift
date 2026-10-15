import XCTest

/// Synthetic data in a unique workspace. Never installs on or controls a physical phone.
@MainActor
final class LocalizationJourneyTests: XCTestCase {
    func testLanguageSwitchPersistsAndFiltersInstalledVoices() {
        continueAfterFailure = false
        let workspace = UUID()
        var app = launch(workspace: workspace, initialLanguage: "fr")
        openSettings(app)
        choose("Français", in: app)
        XCTAssertTrue(app.staticTexts["Langue"].exists)
        attach("localization-fr-settings", app)
        verifyVoices(app, french: true)

        choose("English", in: app)
        XCTAssertTrue(app.staticTexts["Language"].exists)
        attach("localization-en-settings", app)
        verifyVoices(app, french: false)
        app.terminate()

        // No preference override on relaunch: the choice must come from saved defaults,
        // while the device continues to prefer French.
        app = launch(workspace: workspace, systemLanguage: "fr")
        openSettings(app)
        let picker = app.segmentedControls["setup.language"]
        scrollTo(picker, in: app)
        XCTAssertTrue(picker.buttons["English"].isSelected, app.debugDescription)
        XCTAssertTrue(app.staticTexts["Language"].exists)
        choose("Français", in: app)
        XCTAssertTrue(picker.buttons["Français"].isSelected)
        verifyVoices(app, french: true)
        app.terminate()
    }

    func testSameConnectionsAndRoutineInBothLanguagesWithoutChangingSavedText() {
        continueAfterFailure = false
        let workspace = UUID()
        let app = launch(workspace: workspace, initialLanguage: "fr")
        openSettings(app)
        scrollTo(app.buttons["setup.routine"], in: app, upward: false)
        app.buttons["setup.routine"].tap()
        let moment = app.descendants(matching: .any)["routine.step.0"].firstMatch
        XCTAssertTrue(moment.waitForExistence(timeout: 10), app.debugDescription)
        moment.tap()
        let titleField = app.textFields["step.name"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 10), app.debugDescription)
        titleField.tap()
        titleField.typeText(" — Salut / Hello (é)")
        let originalTitle = titleField.value as? String
        XCTAssertTrue(originalTitle?.contains("Salut / Hello") == true)
        app.buttons["step.save"].tap()
        attach("localization-fr-routine", app)
        back(app)
        scrollTo(app.buttons["setup.connections"], in: app, upward: false)
        app.buttons["setup.connections"].tap()
        XCTAssertTrue(app.navigationBars["Apps et comptes"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["connections.gmailReader"].exists)
        attach("localization-fr-connections", app)
        back(app)
        choose("English", in: app)
        scrollTo(app.buttons["setup.connections"], in: app, upward: false)
        app.buttons["setup.connections"].tap()
        XCTAssertTrue(app.navigationBars["Apps & accounts"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["connections.gmailReader"].exists)
        attach("localization-en-connections", app)
        back(app)
        scrollTo(app.buttons["setup.routine"], in: app, upward: false)
        app.buttons["setup.routine"].tap()
        XCTAssertTrue(moment.waitForExistence(timeout: 10))
        moment.tap()
        XCTAssertTrue(titleField.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(titleField.value as? String, originalTitle)
        app.buttons["Cancel"].tap()
        attach("localization-en-routine-retained", app)
        app.terminate()
    }

    func testLanguageSwitchPausesSameSyntheticSession() {
        continueAfterFailure = false
        let app = launch(workspace: UUID(), initialLanguage: "fr", extraArguments: ["--ui-testing-automation"])
        app.buttons["morning.actions"].tap()
        app.buttons["morning.begin"].tap()
        let current = app.staticTexts["morning.currentStep"]
        XCTAssertTrue(current.waitForExistence(timeout: 10), app.debugDescription)
        let title = current.label
        let settings = app.buttons["morning.settings"]
        scrollTo(settings, in: app)
        settings.tap()
        choose("English", in: app)
        back(app)
        if !current.exists { app.buttons["morning.actions"].tap() }
        XCTAssertTrue(current.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(current.label, title)
        XCTAssertTrue(app.buttons["morning.playback"].label.contains("Continue"), app.debugDescription)
        attach("localization-active-session-preserved-paused", app)
        app.terminate()
    }

    func testUnsupportedSystemLanguageStartsInFrench() {
        continueAfterFailure = false
        let app = launch(workspace: UUID(), initialLanguage: "unsupported", systemLanguage: "de")
        openSettings(app)
        let picker = app.segmentedControls["setup.language"]
        scrollTo(picker, in: app)
        XCTAssertEqual(picker.buttons.count, 2)
        XCTAssertTrue(picker.buttons["Français"].isSelected)
        XCTAssertTrue(app.staticTexts["Langue"].exists)
        attach("localization-unsupported-system-fallback", app)
        app.terminate()
    }

    private func launch(workspace: UUID, initialLanguage: String? = nil, systemLanguage: String = "en", extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture-mode", "--ui-testing-approved", "--light-preview",
                               "--ui-testing-workspace=\(workspace.uuidString)", "-AppleLanguages", "(\(systemLanguage))",
                               "-AppleLocale", systemLanguage == "fr" ? "fr_FR" : "en_US"]
        app.launchArguments += extraArguments
        if let initialLanguage { app.launchArguments += ["-more.appLanguage", initialLanguage] }
        app.launch()
        XCTAssertTrue(app.buttons["morning.actions"].waitForExistence(timeout: 15), app.debugDescription)
        return app
    }

    private func openSettings(_ app: XCUIApplication) {
        app.buttons["morning.actions"].tap()
        let settings = app.buttons["morning.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5), app.debugDescription)
        scrollTo(settings, in: app)
        settings.tap()
        XCTAssertTrue(app.buttons["setup.connections"].waitForExistence(timeout: 10), app.debugDescription)
    }

    private func choose(_ language: String, in app: XCUIApplication) {
        let picker = app.segmentedControls["setup.language"]
        scrollTo(picker, in: app)
        picker.buttons[language].tap()
        XCTAssertTrue(picker.buttons[language].isSelected, app.debugDescription)
    }

    private func verifyVoices(_ app: XCUIApplication, french: Bool) {
        let voice = app.buttons["setup.voice"]
        scrollTo(voice, in: app)
        voice.tap()
        let automatic = app.buttons["voice.default"]
        XCTAssertTrue(automatic.waitForExistence(timeout: 10), app.debugDescription)
        let language = app.staticTexts["voice.currentLanguage"]
        scrollTo(language, in: app)
        XCTAssertTrue(language.label.contains(french ? "Français" : "English"), language.label)
        if french {
            XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'voice.option.' AND label CONTAINS[c] 'Samantha'")).firstMatch.exists)
        }
        attach(french ? "localization-fr-voices" : "localization-en-voices", app)
        app.buttons["voice.done"].tap()
    }

    private func back(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5), app.debugDescription)
        back.tap()
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, upward: Bool = true) {
        _ = element.waitForExistence(timeout: 5)
        for _ in 0..<6 where !(element.exists && element.isHittable) {
            if upward { app.swipeUp() } else { app.swipeDown() }
        }
        for _ in 0..<10 where !(element.exists && element.isHittable) {
            if upward { app.swipeDown() } else { app.swipeUp() }
        }
        XCTAssertTrue(element.exists && element.isHittable, app.debugDescription)
    }

    private func attach(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
