import Foundation
import Testing
@testable import MorningCore

@Suite("Primary device language")
struct AppLanguageTests {
    @Test("French variants use French regardless of region", arguments: [
        "fr", "fr-FR", "fr-CA", "fr-BE", "fr-CH", "fr_CA", "fr-Latn-CA", "fr-CA-u-ca-gregory"
    ])
    func frenchVariants(_ primary: String) {
        #expect(AppLanguage.resolvedCode(preferredLanguages: [primary, "en-US"]) == "fr")
    }

    @Test("A secondary French preference never changes a non-French primary language", arguments: [
        "en", "en-GB", "es-ES", "de-DE", "ar-SA", "ja-JP", "zh-Hant-TW", "pt-BR", ""
    ])
    func otherLanguagesUseEnglish(_ primary: String) {
        #expect(AppLanguage.resolvedCode(preferredLanguages: [primary, "fr-FR", "en-US"]) == "en")
    }

    @Test("Missing language preferences default to English")
    func missingPreferences() {
        #expect(AppLanguage.resolvedCode(preferredLanguages: []) == "en")
    }

    @Test("Region does not select the interface language")
    func languageIsIndependentOfRegion() {
        let french = AppLanguage.resolvedLocale(preferredLanguages: ["fr-CA"], current: Locale(identifier: "en_US"))
        #expect(french.language.languageCode?.identifier == "fr")
        #expect(french.region?.identifier == "US")
        let english = AppLanguage.resolvedLocale(preferredLanguages: ["es-ES", "fr-FR"], current: Locale(identifier: "fr_FR"))
        #expect(english.language.languageCode?.identifier == "en")
        #expect(english.region?.identifier == "FR")
    }

    @Test("Fallback preserves regional, calendar, and hour-format preferences")
    func preservesRegionalPreferences() {
        var components = Locale.Components(languageCode: "ar", script: "Arab", languageRegion: "SA")
        components.calendar = .gregorian
        components.hourCycle = .zeroToTwentyThree
        components.numberingSystem = Locale.NumberingSystem("latn")
        let current = Locale(components: components)
        let resolved = AppLanguage.resolvedLocale(preferredLanguages: ["ar-SA", "fr-FR"], current: current)
        #expect(resolved.language.languageCode?.identifier == "en")
        #expect(resolved.language.script?.identifier == "Latn")
        #expect(resolved.region == current.region)
        #expect(resolved.calendar.identifier == current.calendar.identifier)
        #expect(resolved.hourCycle == current.hourCycle)
        #expect(resolved.numberingSystem == current.numberingSystem)
    }

    @Test("A locale already using the interface language keeps its exact settings")
    func matchingLocaleIsPreserved() {
        let current = Locale(identifier: "fr_CA@calendar=gregorian;hours=h23;numbers=latn")
        #expect(AppLanguage.resolvedLocale(preferredLanguages: ["fr-CA"], current: current) == current)
    }

    @Test("A compiled bundle follows the primary language rather than secondary French")
    func bundleLookupFollowsTheResolvedLanguage() throws {
        _ = try #require(Bundle.module.path(forResource: "fr", ofType: "lproj"), "The String Catalog must be compiled for this proof.")
        let english = AppLanguage.resolvedLocale(preferredLanguages: ["es-ES", "fr-FR"], current: Locale(identifier: "es_ES"))
        let french = AppLanguage.resolvedLocale(preferredLanguages: ["fr-CA", "en"], current: Locale(identifier: "en_US"))
        #expect(AppLanguage.localized("Weather", bundle: .module, locale: english) == "Weather")
        #expect(AppLanguage.localized("Weather", bundle: .module, locale: french) == "Météo")
        let next = "Calendar"
        #expect(AppLanguage.localized("Next: \(next)", bundle: .module, locale: english) == "Next: Calendar")
        #expect(AppLanguage.localized("Next: \(next)", bundle: .module, locale: french) == "Ensuite : Calendar")
    }
}
