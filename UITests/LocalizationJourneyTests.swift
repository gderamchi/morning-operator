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
        let frenchInvitation = app.staticTexts["Aucune invitation n’est programmée."]
        scrollTo(frenchInvitation, in: app)
        XCTAssertTrue(frenchInvitation.exists)
        verifyVoices(app, french: true)

        choose("English", in: app)
        XCTAssertTrue(app.staticTexts["Language"].exists)
        attach("localization-en-settings", app)
        let englishInvitation = app.staticTexts["No invitation is scheduled."]
        scrollTo(englishInvitation, in: app)
        XCTAssertTrue(englishInvitation.exists)
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
        let current = app.scrollViews["morning.captions"]
        XCTAssertTrue(current.waitForExistence(timeout: 10), app.debugDescription)
        let identity = current.value as? String
        let ids = identity?.split(separator: "|") ?? []
        XCTAssertEqual(ids.count, 2)
        XCTAssertTrue(ids.allSatisfy { UUID(uuidString: String($0)) != nil })
        current.tap()
        let settings = app.buttons["morning.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5), app.debugDescription)
        settings.tap()
        choose("English", in: app)
        back(app)
        XCTAssertTrue(current.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(current.value as? String, identity)
        if !app.buttons["morning.playback"].exists { current.tap() }
        XCTAssertTrue(app.buttons["morning.playback"].label.contains("Continue"), app.debugDescription)
        attach("localization-active-session-preserved-paused", app)
        app.terminate()
    }

    func testPairedLearningAndNativeEmptyStates() {
        continueAfterFailure = false
        for french in [true, false] {
            let code = french ? "fr" : "en"
            var app = launch(workspace: UUID(), initialLanguage: code, extraArguments: ["--ui-testing-empty-workspace"])
            app.buttons["morning.actions"].tap()
            app.buttons["morning.begin"].tap()
            XCTAssertTrue(app.buttons["learn.screenTime"].waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertTrue(app.buttons["learn.connections"].exists)
            attach("localization-\(code)-learn-empty", app)
            app.buttons["learn.screenTime"].tap()
            scrollTo(app.buttons["learn.import"], in: app)
            XCTAssertTrue(app.buttons["learn.import"].exists, app.debugDescription)
            attach("localization-\(code)-learn-import", app)
            app.terminate()

            app = launch(workspace: UUID(), initialLanguage: code)
            openSettings(app)
            scrollTo(app.buttons["setup.connections"], in: app, upward: false)
            app.buttons["setup.connections"].tap()
            let reminders = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", french ? "Rappels" : "Reminders")).firstMatch
            scrollTo(reminders, in: app)
            reminders.tap()
            XCTAssertTrue(app.buttons["native.remindersRead"].waitForExistence(timeout: 10), app.debugDescription)
            attach("localization-\(code)-native-reminders-empty", app)
            app.terminate()
        }
    }

    func testPairedInAppBrowserControls() {
        continueAfterFailure = false
        for french in [true, false] {
            let code = french ? "fr" : "en"
            let app = XCUIApplication()
            let workspace = UUID().uuidString
            app.launchArguments = ["--ui-testing", "--web-morning", "--web-morning-site=news", "--light-preview",
                                   "--ui-testing-workspace=\(workspace)", "-more.appLanguage", code, "-webMorning.explained", "NO"]
            launchConfirmedWorkspace(app, workspace: workspace)
            let explanation = app.buttons["web.aboutDone"]
            if explanation.waitForExistence(timeout: 4) {
                attach("localization-\(code)-browser-explanation", app)
                explanation.tap()
            }
            XCTAssertTrue(app.buttons["web.close"].waitForExistence(timeout: 15), app.debugDescription)
            XCTAssertEqual(app.buttons["web.close"].label, french ? "Fermer" : "Close")
            XCTAssertEqual(app.buttons["web.reload"].label, french ? "Recharger la page" : "Reload page")
            attach("localization-\(code)-browser-controls", app)
            app.terminate()
        }
    }

    func testSleepStaysOffAndItsUnavailableReaderErrorFollowsThePersistedLanguage() {
        continueAfterFailure = false
        let workspace = UUID()
        let fixture = ["--ui-testing-briefing-fixture"]
        var app = launch(workspace: workspace, initialLanguage: "en", extraArguments: fixture)
        defer { app.terminate() }
        openSettings(app)
        let sources = app.buttons["setup.briefing"]
        scrollTo(sources, in: app, upward: false)
        XCTAssertEqual(sources.label, "Calendar, weather & sleep")
        sources.tap()
        XCTAssertTrue(app.staticTexts["briefing.synthetic"].waitForExistence(timeout: 5), app.debugDescription)
        let sleep = app.switches["briefing.healthIncluded"].firstMatch
        scrollTo(sleep, in: app)
        XCTAssertEqual(sleep.label, "Include recorded sleep")
        XCTAssertEqual(sleep.value as? String, "0")
        let issue = app.staticTexts["briefing.healthError"]
        XCTAssertFalse(issue.exists)
        attach("localization-en-sleep-off-default", app)

        // This fixture has no HealthKit reader. One attempted inclusion cannot prompt or read Health.
        let nativeSwitch = sleep.switches.firstMatch
        if nativeSwitch.exists { nativeSwitch.tap() } else { sleep.tap() }
        XCTAssertTrue(issue.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(issue.label, "Sleep reading is not available in this version.")
        XCTAssertEqual(sleep.value as? String, "0")
        XCTAssertEqual(app.alerts.count, 0)
        attach("localization-en-sleep-unavailable", app)
        app.navigationBars["Your day"].buttons["Done"].tap()

        choose("Français", in: app)
        scrollTo(sources, in: app, upward: false)
        XCTAssertEqual(sources.label, "Calendrier, météo et sommeil")
        sources.tap()
        XCTAssertTrue(app.navigationBars["Votre journée"].waitForExistence(timeout: 5), app.debugDescription)
        scrollTo(sleep, in: app)
        XCTAssertEqual(sleep.label, "Inclure le sommeil enregistré")
        XCTAssertEqual(sleep.value as? String, "0")
        XCTAssertTrue(issue.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(issue.label, "La lecture du sommeil n’est pas disponible dans cette version.")
        XCTAssertEqual(app.alerts.count, 0)
        attach("localization-fr-sleep-retained-error-off", app)
        app.terminate()

        // The saved French choice must win over English system preferences; no second Health action.
        app = launch(workspace: workspace, systemLanguage: "en", extraArguments: fixture)
        openSettings(app)
        let picker = app.segmentedControls["setup.language"]
        scrollTo(picker, in: app)
        XCTAssertTrue(picker.buttons["Français"].isSelected, app.debugDescription)
        let restoredSources = app.buttons["setup.briefing"]
        scrollTo(restoredSources, in: app, upward: false)
        XCTAssertEqual(restoredSources.label, "Calendrier, météo et sommeil")
        restoredSources.tap()
        let restoredSleep = app.switches["briefing.healthIncluded"].firstMatch
        scrollTo(restoredSleep, in: app)
        XCTAssertEqual(restoredSleep.label, "Inclure le sommeil enregistré")
        XCTAssertEqual(restoredSleep.value as? String, "0")
        XCTAssertFalse(app.staticTexts["briefing.healthError"].exists, "Connection failures stay transient across relaunch.")
        XCTAssertEqual(app.alerts.count, 0)
        attach("localization-fr-sleep-off-after-relaunch", app)
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
        app.launchArguments = ["--ui-testing", "--fixture-mode", "--ui-testing-approved", "--light-preview", "--ui-testing-reduce-motion",
                               "--ui-testing-workspace=\(workspace.uuidString)", "-AppleLanguages", "(\(systemLanguage))",
                               "-AppleLocale", systemLanguage == "fr" ? "fr_FR" : "en_US"]
        app.launchArguments += extraArguments
        if let initialLanguage { app.launchArguments += ["-more.appLanguage", initialLanguage] }
        launchConfirmedWorkspace(app, workspace: workspace.uuidString)
        let home = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.buttons["morning.actions"].exists || app.scrollViews["morning.captions"].exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [home], timeout: 15), .completed, app.debugDescription)
        return app
    }

    private func launchConfirmedWorkspace(_ app: XCUIApplication, workspace: String) {
        app.launch()
        let marker = app.staticTexts["qa.testWorkspace"]
        if !marker.waitForExistence(timeout: 5) || marker.value as? String != workspace {
            app.terminate()
            app.launch()
        }
        XCTAssertTrue(marker.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(marker.value as? String, workspace, app.debugDescription)
    }

    private func openSettings(_ app: XCUIApplication) {
        let settings = app.buttons["morning.settings"]
        if !(settings.exists && settings.isHittable) {
            let reading = app.scrollViews["morning.captions"]
            if reading.exists { reading.tap() }
            else { app.buttons["morning.actions"].tap() }
        }
        XCTAssertTrue(settings.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(settings.isHittable, app.debugDescription)
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
        // Exercise the actual simulator speech path, separately from phone audibility.
        scrollTo(app.buttons["voice.preview"], in: app, upward: false)
        app.buttons["voice.preview"].tap()
        let stop = app.buttons["voice.stopPreview"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5), app.debugDescription)
        let speaking = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", french ? "Lecture en cours…" : "Speaking…"), object: app.buttons["voice.preview"])
        XCTAssertEqual(XCTWaiter.wait(for: [speaking], timeout: 8), .completed, app.debugDescription)
        // The utterance may finish naturally after the speaking assertion. Done
        // also stops any unfinished preview through the sheet's onDisappear.
        app.buttons["voice.done"].tap()
    }

    private func back(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5), app.debugDescription)
        back.tap()
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, upward: Bool = true) {
        _ = element.waitForExistence(timeout: 5)
        for _ in 0..<6 {
            if element.exists && element.isHittable { break }
            if upward { app.swipeUp() } else { app.swipeDown() }
        }
        for _ in 0..<10 {
            if element.exists && element.isHittable { break }
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
