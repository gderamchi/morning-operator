import Foundation
import Testing
@testable import MorningCore

struct AppLanguageTests {
    @Test func firstLaunchAndSavedChoice() {
        #expect(AppLanguage.resolve(saved: nil, preferredLanguages: ["fr-CA"]) == "fr")
        #expect(AppLanguage.resolve(saved: nil, preferredLanguages: ["en-GB"]) == "en")
        #expect(AppLanguage.resolve(saved: nil, preferredLanguages: ["de-DE", "en-US"]) == "fr")
        #expect(AppLanguage.resolve(saved: nil, preferredLanguages: []) == "fr")
        #expect(AppLanguage.resolve(saved: "en", preferredLanguages: ["fr-FR"]) == "en")
        #expect(AppLanguage.resolve(saved: "fr", preferredLanguages: ["en-US"]) == "fr")
        #expect(AppLanguage.resolve(saved: "de", preferredLanguages: ["en-US"]) == "en")
        #expect(AppLanguage.supportedCodes == ["fr", "en"])
    }
}
