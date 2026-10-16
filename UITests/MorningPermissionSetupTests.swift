import XCTest
import UIKit

/// Isolated permission explanations, persistence and weather-source selection.
/// Synthetic sources never change iOS authorizations or contact weather providers.
@MainActor
final class MorningPermissionSetupTests: XCTestCase {
    func testEachAccessHasAnExplanationBeforeAllowAndPersistsWhenRoutineLearningIsDeferred() {
        let app = launchFixture(denied: true)
        let permissions = ["location", "calendar", "reminders", "screenTime", "speech", "microphone", "notifications", "alarms"]
        for permission in permissions {
            let title = app.staticTexts["permissions.title.\(permission)"]
            XCTAssertTrue(title.waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertFalse(app.staticTexts["Your access choices couldn't be restored. You can still review them; the saved file stays intact."].exists)
            XCTAssertFalse(app.staticTexts["These access choices couldn't be saved. MORE may ask you to review them next time."].exists)
            XCTAssertEqual(app.alerts.count, 0)
            let allow = app.buttons["permissions.allow"]
            reveal(allow, app)
            allow.tap()
        }
        let finish = app.buttons["permissions.finish"]
        reveal(finish, app)
        XCTAssertFalse(app.staticTexts["These access choices couldn't be saved. MORE may ask you to review them next time."].exists)
        finish.tap()
        XCTAssertTrue(finish.waitForNonExistence(timeout: 5))
        app.terminate(); launchConfirmedWorkspace(app)
        XCTAssertFalse(app.buttons["permissions.allow"].waitForExistence(timeout: 2), "Access setup must not repeat when routine onboarding was deferred.")
        openSettingsFromHome(app)
        let revisit = app.buttons["setup.permissions"]
        reveal(revisit, app); revisit.tap()
        XCTAssertTrue(app.staticTexts["permissions.title.location"].waitForExistence(timeout: 5))
    }

    func testSkippingOneAccessStillExplainsTheNextAndSpeechIsSeparateFromMicrophone() {
        let app = launchFixture()
        for permission in ["location", "calendar", "reminders", "screenTime", "speech"] {
            XCTAssertTrue(app.staticTexts["permissions.title.\(permission)"].waitForExistence(timeout: 5))
            let skip = app.buttons["permissions.skip"]
            reveal(skip, app)
            XCTAssertEqual(skip.label, "Not now")
            skip.tap()
        }
        XCTAssertTrue(app.staticTexts["permissions.title.microphone"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["permissions.title.microphone"].label, "Make your voice heard.")
        XCTAssertEqual(app.alerts.count, 0)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "synthetic-permission-explanation-microphone"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testFrenchLargestTextExplainsEveryAccessAndReturnsToTopWithoutAnimation() {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launchFixture(frenchLargestText: true, phase: "night")
        let permissions = ["location", "calendar", "reminders", "screenTime", "speech", "microphone", "notifications", "alarms"]
        for (index, permission) in permissions.enumerated() {
            if index == 4 {
                XCUIDevice.shared.orientation = .landscapeLeft
                let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    let frame = app.frame
                    return frame.width > frame.height
                }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 5), .completed, app.debugDescription)
            }
            XCTAssertTrue(app.staticTexts["permissions.title.\(permission)"].waitForExistence(timeout: 5))
            XCTAssertTrue(element("permissions.progress", in: app).isHittable,
                          "Progress must stay available while long text scrolls.")
            XCTAssertFalse(app.staticTexts["permissions.explanation"].exists,
                           "Each new choice should start with its details closed.")
            if index == 0 {
                let details = element("permissions.details", in: app)
                reveal(details, app); details.tap()
                XCTAssertTrue(app.staticTexts["permissions.explanation"].waitForExistence(timeout: 5))
                attach("permissions-night-fr-largest-expanded-portrait", app)
            }
            let allow = app.buttons["permissions.allow"]
            reveal(allow, app)
            let skip = app.buttons["permissions.skip"]
            reveal(skip, app)
            XCTAssertEqual(skip.label, "Plus tard")
            skip.tap()
        }
        let finish = app.buttons["permissions.finish"]
        for control in [app.buttons["permissions.learn"], finish, element("permissions.progress", in: app)] {
            reveal(control, app)
            let frame = control.frame
            XCTAssertGreaterThan(frame.width, 0, control.debugDescription)
            XCTAssertGreaterThanOrEqual(frame.minX, app.frame.minX - 1,
                                        "The complete control must fit horizontally: \(control.debugDescription)")
            XCTAssertLessThanOrEqual(frame.maxX, app.frame.maxX + 1,
                                     "The complete control must fit horizontally: \(control.debugDescription)")
        }
        XCTAssertEqual(finish.label, "Plus tard")
        attach("permissions-night-fr-largest-completion-landscape", app)
        attach("permissions-night-fr-largest-completion-landscape-screen", app,
               screenshot: XCUIScreen.main.screenshot())
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "permissions-night-fr-largest-completion-landscape-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        finish.tap()
        XCTAssertTrue(finish.waitForNonExistence(timeout: 5))
    }

    func testCompletingAccessChoicesCanContinueIntoRealRoutineLearning() {
        let app = launchFixture()
        skipAllPermissions(in: app)
        let learn = app.buttons["permissions.learn"]
        reveal(learn, app); learn.tap()
        XCTAssertTrue(app.buttons["learn.screenTime"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["learn.connections"].exists, "Continue must open the existing learning journey.")
        XCTAssertFalse(app.buttons["permissions.allow"].exists)
        XCTAssertFalse(app.buttons["permissions.learn"].exists)
        XCTAssertEqual(app.alerts.count, 0)
        app.terminate(); launchConfirmedWorkspace(app)
        XCTAssertFalse(app.buttons["permissions.allow"].waitForExistence(timeout: 2),
                       "Opening learning must keep the access choices saved.")
    }

    func testRevisitingPermissionsReturnsToSettingsWithoutOfferingOnboardingAgain() {
        let app = launchFixture(french: true)
        skipAllPermissions(in: app)
        let later = app.buttons["permissions.finish"]
        reveal(later, app); later.tap()
        openSettingsFromHome(app)
        let revisit = app.buttons["setup.permissions"]
        reveal(revisit, app); revisit.tap()
        skipAllPermissions(in: app)
        XCTAssertFalse(app.buttons["permissions.learn"].exists,
                       "Reviewing access from Settings must not restart routine onboarding.")
        let done = app.buttons["permissions.finish"]
        reveal(done, app)
        XCTAssertEqual(done.label, "Terminer")
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["setup.permissions"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["learn.screenTime"].exists)
    }

    func testFrenchChoicesUseDistinctDayAndNightPaperWithDetailsInitiallyHidden() throws {
        var luminances: [String: Double] = [:]
        for phase in ["day", "night"] {
            let app = launchFixture(french: true, phase: phase)
            XCTAssertTrue(app.staticTexts["permissions.title.location"].waitForExistence(timeout: 5), app.debugDescription)
            let benefit = app.staticTexts["permissions.benefit"]
            XCTAssertTrue(benefit.exists)
            XCTAssertFalse(benefit.label.isEmpty)
            XCTAssertFalse(app.staticTexts["permissions.explanation"].exists,
                           "The first view should show the short benefit, with detail available on demand.")
            XCTAssertFalse(app.staticTexts["permissions.lastOutcome"].exists)
            let screenshot = app.screenshot()
            luminances[phase] = try paperLuminance(screenshot)
            attach("permissions-\(phase)-fr-compact", app, screenshot: screenshot)
            let details = element("permissions.details", in: app)
            reveal(details, app); details.tap()
            let explanation = app.staticTexts["permissions.explanation"]
            XCTAssertTrue(explanation.waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertGreaterThan(explanation.label.count, benefit.label.count)
            attach("permissions-\(phase)-fr-expanded", app)
            let skip = app.buttons["permissions.skip"]
            reveal(skip, app); skip.tap()
            XCTAssertTrue(app.staticTexts["permissions.title.calendar"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["permissions.explanation"].exists)
            XCTAssertFalse(app.staticTexts["permissions.lastOutcome"].exists,
                           "The previous choice must not add a second explanation to the next screen.")
            XCTAssertEqual(app.alerts.count, 0)
            app.terminate()
        }
        XCTAssertGreaterThan(try XCTUnwrap(luminances["day"]) - XCTUnwrap(luminances["night"]), 0.4,
                             "The rendered paper must visibly darken at night, independently of the artwork.")
    }

    func testManualCitySelectionFromCurrentLocationSurvivesRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-empty-workspace", "--ui-testing-briefing-fixture",
            "--ui-testing-workspace=\(UUID().uuidString)", "-more.appLanguage", "en", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        launchConfirmedWorkspace(app)
        openYourDayFromHome(app)
        MorningUITestNavigation.chooseManualWeatherCity(in: app)
        let search = app.textFields["briefing.citySearch"]
        reveal(search, app)
        search.tap(); search.typeText("Synthetic\n")
        let result = app.buttons["briefing.cityResult.48.0,2.0"]
        XCTAssertTrue(result.waitForExistence(timeout: 5), app.debugDescription)
        reveal(result, app); result.tap()
        assertSelectedCity(in: app)
        XCTAssertEqual(app.alerts.count, 0, "Choosing a manual city must not request GPS access.")
        app.terminate(); launchConfirmedWorkspace(app)
        openYourDayFromHome(app)
        assertSelectedCity(in: app)
        // The search row is offered only in manual mode, so its presence also
        // establishes the stored source choice rather than only a cached label.
        reveal(app.textFields["briefing.citySearch"], app)
        XCTAssertEqual(app.alerts.count, 0)
    }

    private func openSettingsFromHome(_ app: XCUIApplication) {
        let actions = app.buttons["morning.actions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 5), app.debugDescription)
        actions.tap()
        let settings = app.buttons["morning.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5), app.debugDescription)
        settings.tap()
        XCTAssertTrue(app.buttons["setup.briefing"].waitForExistence(timeout: 5), app.debugDescription)
    }

    private func assertSelectedCity(in app: XCUIApplication) {
        let city = app.descendants(matching: .any).matching(identifier: "briefing.city").firstMatch
        reveal(city, app)
        XCTAssertTrue(city.label.contains("Synthetic City") || (city.value as? String)?.contains("Synthetic City") == true,
                      "The saved city must be exposed by its native labeled row: \(city.debugDescription)")
    }

    private func openYourDayFromHome(_ app: XCUIApplication) {
        openSettingsFromHome(app)
        let briefing = app.buttons["setup.briefing"]
        reveal(briefing, app); briefing.tap()
        XCTAssertTrue(app.staticTexts["briefing.synthetic"].waitForExistence(timeout: 5), app.debugDescription)
    }

    private func launchFixture(denied: Bool = false, frenchLargestText: Bool = false,
                               french: Bool = false, phase: String = "day") -> XCUIApplication {
        continueAfterFailure = false
        let french = french || frenchLargestText
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-empty-workspace", "--ui-testing-permissions",
            "--ui-testing-workspace=\(UUID().uuidString)", "--theme-phase=\(phase)", "--ui-testing-reduce-motion",
            "-more.appLanguage", french ? "fr" : "en", "-AppleLanguages", french ? "(fr)" : "(en)", "-AppleLocale", french ? "fr_FR" : "en_US"]
        if frenchLargestText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        if denied { app.launchArguments.append("--ui-testing-permissions-denied") }
        launchConfirmedWorkspace(app)
        XCTAssertTrue(app.staticTexts["permissions.title.location"].waitForExistence(timeout: 5), app.debugDescription)
        return app
    }

    private func launchConfirmedWorkspace(_ app: XCUIApplication) {
        continueAfterFailure = false
        let prefix = "--ui-testing-workspace="
        let workspace = String(app.launchArguments.first { $0.hasPrefix(prefix) }!.dropFirst(prefix.count))
        app.launch()
        let marker = app.staticTexts["qa.testWorkspace"]
        if !marker.waitForExistence(timeout: 5) || marker.value as? String != workspace {
            app.terminate()
            app.launch()
        }
        XCTAssertTrue(marker.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(marker.value as? String, workspace, app.debugDescription)
    }

    private func skipAllPermissions(in app: XCUIApplication) {
        for permission in ["location", "calendar", "reminders", "screenTime", "speech", "microphone", "notifications", "alarms"] {
            XCTAssertTrue(app.staticTexts["permissions.title.\(permission)"].waitForExistence(timeout: 5), app.debugDescription)
            let skip = app.buttons["permissions.skip"]
            reveal(skip, app); skip.tap()
        }
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        if element.exists, element.isHittable { return }
        let content: XCUIElement
        if app.scrollViews["permissions.content"].exists {
            content = app.scrollViews["permissions.content"]
        } else if app.scrollViews.firstMatch.exists {
            content = app.scrollViews.firstMatch
        } else {
            content = app.collectionViews.firstMatch
        }
        for _ in 0..<10 {
            if element.exists, element.isHittable { break }
            if content.exists {
                if element.exists, element.frame.maxY < content.frame.minY { content.swipeDown() }
                else { content.swipeUp() }
            } else { app.swipeUp() }
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }

    /// Sample the outer gutter, away from the landscape, text and controls. This
    /// checks actual pixels instead of an appearance value supplied by the app.
    private func paperLuminance(_ screenshot: XCUIScreenshot) throws -> Double {
        let image = try XCTUnwrap(screenshot.image.cgImage)
        let patch = try XCTUnwrap(image.cropping(to: CGRect(x: CGFloat(image.width) * 0.02,
            y: CGFloat(image.height) * 0.25, width: 5, height: 5).integral))
        var bytes = [UInt8](repeating: 0, count: 4)
        return try bytes.withUnsafeMutableBytes { (storage: UnsafeMutableRawBufferPointer) in
            let context = try XCTUnwrap(CGContext(data: storage.baseAddress, width: 1, height: 1,
                bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(patch, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return (0.2126 * Double(storage[0]) + 0.7152 * Double(storage[1]) + 0.0722 * Double(storage[2])) / 255
        }
    }

    private func attach(_ name: String, _ app: XCUIApplication, screenshot: XCUIScreenshot? = nil) {
        let screenshot = screenshot ?? app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
        if let directory = ProcessInfo.processInfo.environment["MO_ONBOARDING_SCREENSHOT_DIR"] {
            do {
                let url = URL(fileURLWithPath: directory, isDirectory: true)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                try screenshot.pngRepresentation.write(to: url.appendingPathComponent(name + ".png"), options: .atomic)
            } catch { XCTFail("Could not save the synthetic permission screenshot: \(error)") }
        }
    }
}
