import Foundation
import Testing
@testable import MorningCore

@Suite("Language crosses the widget boundary without routine content")
struct InterfaceLanguageProjectionTests {
    @Test func oldPayloadsStillDecodeAndLanguageChangesPublishNewProgress() throws {
        let instant = Date(timeIntervalSince1970: 1_800_000_000)
        let english = try MorningActivityContentState(category: .calendar, status: .paused,
            completedSteps: 0, totalSteps: 2, updatedAt: instant, languageIdentifier: "en")
        let french = try MorningActivityContentState(category: .calendar, status: .paused,
            completedSteps: 0, totalSteps: 2, updatedAt: instant, languageIdentifier: "fr")
        #expect(!english.hasSameProgress(as: french))
        #expect(english.locale.language.languageCode?.identifier == "en")
        #expect(french.locale.language.languageCode?.identifier == "fr")
        var legacy = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(french)) as? [String: Any])
        legacy.removeValue(forKey: "languageIdentifier")
        let decoded = try JSONDecoder().decode(MorningActivityContentState.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(decoded.languageIdentifier == nil)
        #expect(decoded.completedSteps == french.completedSteps && decoded.stepTimer == french.stepTimer)
        legacy["languageIdentifier"] = "PRIVATE_INVALID_VALUE"
        #expect(try JSONDecoder().decode(MorningActivityContentState.self, from: JSONSerialization.data(withJSONObject: legacy)).languageIdentifier == nil)
    }

    @Test func widgetNamesAndWeatherConditionsUseExplicitPayloadLanguage() throws {
        let french = Locale(identifier: "fr_FR"), english = Locale(identifier: "en_US")
        #expect(MorningActivityCategory.calendar.displayName(locale: french) == "Calendrier")
        #expect(MorningActivityCategory.calendar.displayName(locale: english) == "Calendar")
        #expect(StepDestination.app(.maps).displayName(locale: french) == "Plans")
        #expect(StepDestination.app(.maps).displayName(locale: english) == "Maps")
        #expect(MorningWeatherCondition.clear.displayName(locale: french) == "Ciel dégagé")
        #expect(MorningWeatherCondition.clear.displayName(locale: english) == "Clear skies")
        for condition in MorningWeatherCondition.allCases {
            #expect(!condition.displayName(locale: french).isEmpty)
            #expect(!condition.displayName(locale: english).isEmpty)
        }
        let timer = MorningActivityStepTimer(stepID: UUID(), destination: .app(.mail), endsAt: .now,
            nextDestination: .app(.maps), hasNextStep: true)
        #expect(timer.nextLabel(locale: french).contains("Plans"))
        #expect(timer.nextLabel(locale: english).contains("Maps"))
    }
}
