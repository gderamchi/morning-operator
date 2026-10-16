import AppIntents
import Foundation
import MorningCore
import MorningApple

/// The same intent type is built into MORE and its widget. LiveActivityIntent runs
/// in MORE's process, so it edits MORE's timer without an app group or opening UI.
struct AddStepTimeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Add two minutes"
    static let description = IntentDescription("Add two minutes to the current morning step.")
    static let supportedModes: IntentModes = .background
    @Parameter(title: "Session") var session: String?
    @Parameter(title: "Step") var step: String?
    @Parameter(title: "Displayed end") var expectedEndToken: String?
    init() {}
    init(sessionID: UUID, stepID: UUID, expectedEnd: Date) {
        session = sessionID.uuidString; step = stepID.uuidString
        expectedEndToken = StepTimer.extensionToken(for: expectedEnd)
    }
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let sessionID = session.flatMap(UUID.init(uuidString:))
        let stepID = step.flatMap(UUID.init(uuidString:))
        let expectedEnd = expectedEndToken.flatMap(StepTimer.deadline(fromExtensionToken:))
        guard (session == nil) == (step == nil),
              session == nil || sessionID != nil, step == nil || stepID != nil,
              // A rendered widget must identify both its step and its displayed
              // end. Older/malformed bound requests must not become unguarded
              // voice requests merely because their token is missing.
              session == nil ? expectedEndToken == nil : expectedEnd != nil else {
            return .result(dialog: IntentDialog(stringLiteral: String(localized: "This step timer is unavailable.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)))
        }
        let result = await StepTimerExtension.addTwoMinutes(sessionID: sessionID,
            stepID: stepID, expectedEnd: expectedEnd)
        #if DEBUG
        if ["com.gibouu.morningoperator.qa", "com.gibouu.morningoperator.systemqa"].contains(Bundle.main.bundleIdentifier ?? "") {
            let outcome: String
            switch result {
            case .extended: outcome = "extended"
            case .duplicate: outcome = "duplicate"
            case .limitReached: outcome = "limitReached"
            case nil: outcome = "unavailable"
            }
            let args = ProcessInfo.processInfo.arguments
            UserDefaults.standard.set("uiTesting:\(args.contains("--ui-testing"))|timer:\(StepTimerFile.load() != nil)|result:\(outcome)",
                forKey: "qa.stepIntentOutcome")
        }
        #endif
        switch result {
        case .extended: return .result(dialog: IntentDialog(stringLiteral: String(localized: "Two minutes added.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)))
        case .duplicate: return .result(dialog: IntentDialog(stringLiteral: String(localized: "This timer already changed.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)))
        case .limitReached: return .result(dialog: IntentDialog(stringLiteral: String(localized: "This step has reached its extension limit.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)))
        case nil: return .result(dialog: IntentDialog(stringLiteral: String(localized: "There is no current step timer.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)))
        }
    }
}
