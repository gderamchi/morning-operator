import XCTest

/// One real provider per invocation. No injected accounts, grants or provider content exports.
@MainActor
final class OrdinaryAPIConsentAcceptanceTests: XCTestCase {
    private let toolkitIDs = ["gmail", "outlook", "googlecalendar", "googledrive", "googledocs", "googlesheets",
                              "notion", "slack", "calendly", "linkedin", "discord", "youtube", "reddit",
                              "instagram", "whatsapp", "facebook"]

    func test01RequestedProviderConsentReconcilesFreshActiveInventory() throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["MORE_PHYSICAL_API_CONSENT"] == "1",
                          "Requires explicit ordinary physical API consent opt-in.")
        #if targetEnvironment(simulator)
        throw XCTSkip("Requires the ordinary physical iPhone.")
        #else
        let toolkit = environment["MORE_PHYSICAL_API_TOOLKIT"] ?? ""
        try require(toolkitIDs.contains(toolkit), "Supply one toolkit exposed by the ordinary Connections page.")
        let app = XCUIApplication(bundleIdentifier: "com.gibouu.morningoperator")
        app.launchArguments = []
        app.launchEnvironment = [:]
        app.terminate()
        app.launch()
        try require(app.wait(for: .runningForeground, timeout: 15), "The ordinary app did not open.")
        for identifier in ["qa.testWorkspace", "onboarding.preview", "briefing.synthetic"] {
            try require(!app.descendants(matching: .any).matching(identifier: identifier).firstMatch.exists,
                        "Synthetic state cannot establish real API consent.")
        }
        try openOrdinaryConnections(app)
        if toolkit == "gmail" { try tap(app.buttons["connections.gmailActions"], in: app) }
        if ["instagram", "whatsapp", "facebook"].contains(toolkit) {
            try tap(app.buttons["connections.professional"], in: app)
        }
        try tap(app.buttons["connections.account.\(toolkit)"], in: app)
        let manageIDs = ["slack": "slack.setup.manage", "googlecalendar": "googleCalendar.setup.manage",
                         "calendly": "calendly.setup.manage", "outlook": "outlook.setup.manage"]
        if let identifier = manageIDs[toolkit] { try tap(app.buttons[identifier], in: app) }
        let refresh = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label IN %@",
            "accounts.refresh", ["Refresh my accounts", "Actualiser mes comptes"])).firstMatch
        try require(refresh.waitForExistence(timeout: 45), "No successful initial Worker account inventory appeared.")
        try require(!app.descendants(matching: .any).matching(identifier: "accounts.notice").firstMatch.exists,
                    "The ordinary account inventory reported an error.")
        try tap(app.buttons["accounts.connect.\(toolkit)"], in: app)
        stage("API_REAL_CONNECT_DISPATCHED", toolkit: toolkit)
        try awaitActualConsent(app, toolkit: toolkit,
            approvedGoogleAccount: environment["MORE_PHYSICAL_GOOGLE_ACCOUNT"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        // Both completion notices are published only after session reconciliation and fresh inventory.
        try require(refresh.waitForExistence(timeout: 45), "The reconciled Worker inventory did not finish loading.")
        let active = app.staticTexts.matching(NSPredicate(format: "label IN %@", ["Connected", "Connecté"])).firstMatch
        let choose = app.buttons.matching(NSPredicate(format: "label IN %@", ["Choose an action", "Choisir une action"])).firstMatch
        try require(active.exists && choose.exists,
                    "The actual consent callback did not produce an ACTIVE account in the fresh service inventory.")
        stage("API_REAL_CONSENT_AND_FRESH_ACTIVE_INVENTORY_CONFIRMED", toolkit: toolkit)
        // No action picker, provider-content read, disconnect or duplicate Connect retry.
        #endif
    }

    private func awaitActualConsent(_ app: XCUIApplication, toolkit: String, approvedGoogleAccount: String) throws {
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let completionLabels = ["Account connected and verified.", "Compte connecté et vérifié.",
                                "Sign-in received. Check the updated status of your accounts below.",
                                "Identification reçue. Vérifiez l’état actualisé de vos comptes ci-dessous."]
        var deadline = Date().addingTimeInterval(75)
        var extendedForOwner = false
        var lastStage: String?
        var choseGoogleAccount = false
        var enteredGoogleAccount = false
        var currentOwnerGate: String?
        repeat {
            currentOwnerGate = nil
            let completed = app.staticTexts.matching(NSPredicate(format: "label IN %@", completionLabels)).firstMatch
            if completed.exists { return }
            let systemAlert = system.alerts.firstMatch
            let alert = systemAlert.exists ? systemAlert : app.alerts.firstMatch
            if alert.exists {
                let words = ([alert.label] + alert.staticTexts.allElementsBoundByIndex.map(\.label)).joined(separator: " ").lowercased()
                let domains = ["composio.dev", "composio.io", "google.com", "notion.so", "notion.com", "slack.com",
                               "microsoftonline.com", "live.com", "calendly.com", "linkedin.com", "discord.com",
                               "reddit.com", "facebook.com", "instagram.com", "whatsapp.com"]
                let moreNamed = words.contains("“more”") || words.contains("\"more\"") || words.hasPrefix("more ") ||
                    alert.staticTexts["MORE"].exists
                let proceed = alert.buttons.matching(NSPredicate(format: "label IN %@", ["Continue", "Continuer"])).firstMatch
                if moreNamed && domains.contains(where: words.contains) && proceed.exists && proceed.isHittable {
                    proceed.tap()
                    stage("API_MATCHING_SYSTEM_SIGN_IN_CONTINUE_ACCEPTED", toolkit: toolkit)
                    continue
                }
                currentOwnerGate = "HUMAN_ACTION_REQUIRED_API_SYSTEM_AUTHENTICATION"
            }
            let web = app.webViews.firstMatch
            if web.exists {
                let blockPrefixes = ["Access blocked", "Accès bloqué", "This app is blocked", "Cette application est bloquée",
                                     "Google hasn’t verified this app", "Google hasn't verified this app",
                                     "Google n’a pas validé cette application", "Google n'a pas validé cette application",
                                     "This browser or app may not be secure"]
                let blocked = NSCompoundPredicate(orPredicateWithSubpredicates: blockPrefixes.map {
                    NSPredicate(format: "label BEGINSWITH[cd] %@", $0)
                })
                if web.staticTexts.matching(blocked).firstMatch.exists {
                    stage("API_PROVIDER_BLOCK_PRESENTED", toolkit: toolkit)
                    try require(false, "The real provider presented a block; the page remains intact for local review.")
                }
                let googleVisible = knownHostVisible("accounts.google.com", in: app)
                let chooser = web.staticTexts.matching(NSPredicate(format: "label IN %@",
                    ["Choose an account", "Choisir un compte", "Sélectionner un compte"])).firstMatch.exists
                if googleVisible && chooser && !choseGoogleAccount {
                    let candidates = web.buttons.allElementsBoundByIndex + web.links.allElementsBoundByIndex + web.staticTexts.allElementsBoundByIndex
                    let account = candidates.first { element in
                        !approvedGoogleAccount.isEmpty && element.isHittable && element.label.split(whereSeparator: {
                            $0.isWhitespace || "<>()[],;".contains($0)
                        }).contains { String($0).caseInsensitiveCompare(approvedGoogleAccount) == .orderedSame }
                    }
                    if let account {
                        let frame = account.frame
                        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
                        choseGoogleAccount = true
                        stage("API_APPROVED_GOOGLE_ACCOUNT_SELECTED", toolkit: toolkit)
                        continue
                    }
                    currentOwnerGate = "HUMAN_ACTION_REQUIRED_API_ACCOUNT_SELECTION"
                }
                let email = web.textFields.matching(NSPredicate(format: "identifier == %@ OR label IN %@",
                    "identifierId", ["Email or phone", "Adresse e-mail ou téléphone"])).firstMatch
                if googleVisible && email.exists && email.isHittable && !enteredGoogleAccount {
                    let value = email.value as? String ?? ""
                    let empty = value.isEmpty || ["Email or phone", "Adresse e-mail ou téléphone"].contains(value)
                    if !approvedGoogleAccount.isEmpty && (empty || value.caseInsensitiveCompare(approvedGoogleAccount) == .orderedSame) {
                        if empty { email.tap(); email.typeText(approvedGoogleAccount) }
                        let next = web.buttons.matching(NSPredicate(format: "label IN %@", ["Next", "Suivant"])).firstMatch
                        if next.exists && next.isHittable && next.isEnabled {
                            next.tap(); enteredGoogleAccount = true
                            stage("API_APPROVED_GOOGLE_ACCOUNT_ENTERED", toolkit: toolkit)
                            continue
                        }
                    } else { currentOwnerGate = "HUMAN_ACTION_REQUIRED_API_ACCOUNT_SELECTION" }
                }
                let ownerChoices = web.staticTexts.matching(NSPredicate(format: "label IN %@", [
                    "Select a workspace", "Choose a workspace", "Sélectionner un espace de travail", "Choisir un espace de travail",
                    "Select pages", "Select Pages", "Sélectionner des pages", "Choose your business", "Choisissez votre entreprise"
                ])).firstMatch.exists
                if ownerChoices { currentOwnerGate = "HUMAN_ACTION_REQUIRED_API_WORKSPACE_OR_PROFESSIONAL_ACCOUNT" }
                let protectedStep = system.secureTextFields.firstMatch.exists || app.secureTextFields.firstMatch.exists ||
                    web.staticTexts.matching(NSPredicate(format: "label IN %@", [
                        "Verify it’s you", "Verify it's you", "Confirmez votre identité", "2-Step Verification", "Validation en deux étapes",
                        "Use your passkey", "Utiliser votre clé d’accès", "Utiliser votre clé d'accès", "Check your phone", "Consultez votre téléphone"
                    ])).firstMatch.exists
                if protectedStep { currentOwnerGate = "HUMAN_ACTION_REQUIRED_API_PASSWORD_PASSKEY_OR_TWO_FACTOR" }
                // Only an explicitly identified MORE/Composio authorization page may grant its known consent action.
                let namedClient = web.staticTexts.matching(NSPredicate(format:
                    "(label CONTAINS[cd] %@ OR label CONTAINS[cd] %@) AND (label CONTAINS[cd] %@ OR label CONTAINS[cd] %@ OR label CONTAINS[cd] %@ OR label CONTAINS[cd] %@)",
                    "MORE", "Composio", "access", "accès", "Sign in", "connexion")).firstMatch.exists
                let consentHost = googleVisible || ["www.notion.so", "www.notion.com", "slack.com", "login.microsoftonline.com",
                    "calendly.com", "www.linkedin.com", "discord.com", "www.reddit.com", "www.facebook.com"].contains {
                        knownHostVisible($0, in: app)
                    }
                if currentOwnerGate == nil && namedClient && consentHost {
                    let allow = web.buttons.matching(NSPredicate(format: "label IN %@",
                        ["Continue", "Continuer", "Allow", "Autoriser", "Authorize", "Authorize access", "Autoriser l’accès"])).firstMatch
                    if allow.exists && allow.isHittable && allow.isEnabled {
                        allow.tap(); stage("API_KNOWN_PROVIDER_SCOPE_CONSENT_ACCEPTED", toolkit: toolkit)
                        continue
                    }
                }
                if currentOwnerGate == nil && (web.textFields.firstMatch.exists || chooser ||
                    ["instagram", "whatsapp", "facebook"].contains(toolkit)) {
                    currentOwnerGate = "HUMAN_ACTION_REQUIRED_API_PROVIDER_ACCOUNT_SETUP"
                }
            }
            let protectedTitles = ["Face ID", "Touch ID", "Enter Passcode", "Enter iPhone Passcode",
                                   "Saisir le code", "Saisir le code de l’iPhone", "Saisir le code de l'iPhone"]
            if system.secureTextFields.firstMatch.exists || app.secureTextFields.firstMatch.exists ||
                system.staticTexts.matching(NSPredicate(format: "label IN %@", protectedTitles)).firstMatch.exists ||
                app.staticTexts.matching(NSPredicate(format: "label IN %@", protectedTitles)).firstMatch.exists {
                currentOwnerGate = "HUMAN_ACTION_REQUIRED_API_PASSWORD_PASSKEY_OR_TWO_FACTOR"
            }
            if let currentOwnerGate {
                if lastStage != currentOwnerGate { stage(currentOwnerGate, toolkit: toolkit); lastStage = currentOwnerGate }
                if !extendedForOwner { deadline = Date().addingTimeInterval(180); extendedForOwner = true }
            }
            let notice = app.descendants(matching: .any).matching(identifier: "accounts.notice").firstMatch
            if !web.exists && notice.exists {
                stage("API_APP_REPORTED_CONNECTION_ERROR", toolkit: toolkit)
                try require(false, "The ordinary app reported a connection failure; no fresh ACTIVE result is claimed.")
            }
            Thread.sleep(forTimeInterval: 0.4)
        } while Date() < deadline
        if currentOwnerGate != nil {
            throw XCTSkip("The actual provider authentication/account step remains presented for its owner; no grant success is claimed.")
        }
        try require(false, "The real provider route did not complete callback reconciliation; the current page remains open.")
    }

    private func knownHostVisible(_ host: String, in app: XCUIApplication) -> Bool {
        if app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR value == %@", host, host)).firstMatch.exists { return true }
        return app.textFields.allElementsBoundByIndex.contains {
            guard let value = $0.value as? String, let url = URL(string: value) else { return false }
            return url.scheme == "https" && url.host?.lowercased() == host
        }
    }

    private func openOrdinaryConnections(_ app: XCUIApplication) throws {
        if ProcessInfo.processInfo.environment["MORE_PHYSICAL_DEVELOPER_ACCESS"] == "1" && !app.buttons["morning.actions"].exists {
            let intro = app.buttons["onboarding.developerAccess"]
            _ = intro.waitForExistence(timeout: 8)
            let entry = intro.exists ? intro : app.buttons["paywall.developerAccess"]
            try require(entry.exists && entry.isHittable, "The official Debug entry is unavailable.")
            entry.tap()
            for _ in 0..<12 {
                if app.buttons["permissions.skip"].exists && app.buttons["permissions.skip"].isHittable { app.buttons["permissions.skip"].tap() }
                else if app.buttons["permissions.finish"].exists && app.buttons["permissions.finish"].isHittable { app.buttons["permissions.finish"].tap() }
                else if app.buttons["morning.actions"].waitForExistence(timeout: 2) { break }
            }
        }
        let landscape = app.buttons["morning.actions"]
        try require(landscape.waitForExistence(timeout: 10), "Ordinary access/setup is incomplete.")
        let settings = app.buttons["morning.settings"]
        for _ in 0..<3 {
            if settings.exists && settings.isHittable { break }
            landscape.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.65)).tap()
            if settings.waitForExistence(timeout: 2) { break }
        }
        try tap(settings, in: app)
        try tap(app.buttons["setup.connections"], in: app)
        try require(app.buttons["connections.instagram"].waitForExistence(timeout: 10), "The ordinary Connections page did not open.")
    }

    private func tap(_ element: XCUIElement, in app: XCUIApplication) throws {
        for upward in [true, false] {
            for _ in 0..<16 {
                if element.exists && element.isHittable && element.isEnabled { element.tap(); return }
                let list = app.collectionViews.firstMatch
                let container = list.exists ? list : app.scrollViews.firstMatch
                let start = container.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: upward ? 0.68 : 0.32))
                let end = container.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: upward ? 0.40 : 0.60))
                start.press(forDuration: 0.01, thenDragTo: end)
            }
        }
        try require(false, "The requested ordinary control was not reachable; no replacement route was invented.")
    }

    private func require(_ condition: Bool, _ message: String) throws {
        guard condition else {
            XCTFail(message)
            throw NSError(domain: "OrdinaryAPIConsentAcceptanceTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Required real API consent check failed."])
        }
    }

    private func stage(_ name: String, toolkit: String) {
        print(name + " toolkit=" + toolkit)
        let attachment = XCTAttachment(string: name + " toolkit=" + toolkit)
        attachment.name = "ordinary-api-consent-stage"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
