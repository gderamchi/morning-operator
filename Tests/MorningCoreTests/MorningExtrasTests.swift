import Foundation
import Testing
@testable import MorningCore

@Suite("Morning extras — selection, rotation and wording (synthetic values only)")
struct MorningExtrasTests {
    private let paris = "Europe/Paris"
    private let day = 9_400
    /// 16:00 in Paris on 13 October 2026.
    private let afternoon = Date(timeIntervalSince1970: 1_791_900_000)

    private func compose(_ facts: [MorningExtraFact], enabled: Set<MorningExtraKind> = Set(MorningExtraKind.allCases),
                         spoken: [MorningExtraKind: Int] = [:], locale: String = "en_GB") -> MorningExtrasSelection {
        var preferences = MorningExtrasPreferences(enabled: enabled)
        for (kind, day) in spoken { preferences.lastSpokenDay[kind.rawValue] = day }
        return MorningExtrasComposer.compose(facts: facts, preferences: preferences, day: day,
                                             localeIdentifier: locale, timeZoneIdentifier: paris)
    }

    @Test func everyExtraStartsOff() {
        #expect(MorningExtrasPreferences().enabled.isEmpty)
        #expect(MorningExtrasPreferences().confirmedHealthKinds.isEmpty)
        #expect(!MorningExtrasPreferences().healthAccessRequested)
    }

    @Test func noFactsMeansSilence() {
        #expect(compose([]).items.isEmpty)
        #expect(compose([]).text == "")
    }

    @Test func missingOrZeroValuesAreNeverSpokenAsZero() {
        let selection = compose([.sleptMinutes(0), .inBedMinutes(-5), .steps(yesterday: 0, weeklyAverage: 6_000),
                                 .screenTime(yesterdayMinutes: 0, weeklyAverageMinutes: nil),
                                 .temperatureChange(celsiusDelta: .nan, unit: .celsius), .birthdays(["  "])])
        #expect(selection.items.isEmpty)
    }

    @Test func aKindThatIsOffIsNeverSaid() {
        let selection = compose([.sleptMinutes(440), .birthdays(["Anna"])], enabled: [.steps])
        #expect(selection.items.isEmpty)
    }

    @Test func atMostThreeAndTimelyFactsFirst() {
        let selection = compose([.sleptMinutes(440), .steps(yesterday: 9_000, weeklyAverage: 6_000),
                                 .birthdays(["Anna"]), .precipitation(.rain, from: afternoon),
                                 .calendarConflict(first: "Standup", second: "Dentist", at: afternoon)])
        #expect(selection.kinds == [.calendar, .weatherChange, .birthday])
        #expect(selection.items.count == MorningExtrasComposer.maximumItems)
        #expect(selection.estimatedSeconds <= MorningExtrasComposer.speechBudgetSeconds)
    }

    @Test func theWholeSetStaysUnderTenSecondsOfSpeech() {
        let long = String(repeating: "Very long meeting title ", count: 6)
        let selection = compose([.calendarConflict(first: long, second: long, at: afternoon),
                                 .sleptMinutes(440), .steps(yesterday: 9_000, weeklyAverage: nil)])
        // The calendar sentence alone is longer than the budget, so it is skipped, not cut.
        #expect(!selection.kinds.contains(.calendar))
        #expect(selection.kinds == [.sleep, .steps])
        #expect(selection.estimatedSeconds <= 10)
        for items in [selection.items] { #expect(items.allSatisfy { MorningExtrasComposer.estimatedSeconds($0.text) <= 10 }) }
    }

    @Test func rotationLetsAnotherHabitKindSpeakAfterYesterday() {
        let facts: [MorningExtraFact] = [.sleptMinutes(440), .steps(yesterday: 6_100, weeklyAverage: 6_000),
                                         .screenTime(yesterdayMinutes: 120, weeklyAverageMinutes: 118),
                                         .temperatureChange(celsiusDelta: 6, unit: .celsius)]
        let first = compose(facts)
        #expect(first.kinds == [.weatherChange, .sleep, .steps])
        // The next morning the kinds said yesterday step back and screen time gets its turn.
        var next = MorningExtrasPreferences(enabled: Set(MorningExtraKind.allCases))
        next.recordSpoken(first.kinds, day: day - 1)
        let second = MorningExtrasComposer.compose(facts: facts, preferences: next, day: day,
                                                   localeIdentifier: "en_GB", timeZoneIdentifier: paris)
        #expect(second.kinds.first == .screenTime)
    }

    @Test func timelyKindsAreNotRotated() {
        let selection = compose([.birthdays(["Anna"]), .sleptMinutes(440)], spoken: [.birthday: day - 1, .sleep: day - 1])
        #expect(selection.kinds.first == .birthday)
    }

    @Test func sameDayRerunGivesTheSameSentences() {
        let facts: [MorningExtraFact] = [.sleptMinutes(440), .steps(yesterday: 6_100, weeklyAverage: 6_000)]
        let first = compose(facts)
        let again = compose(facts, spoken: Dictionary(uniqueKeysWithValues: first.kinds.map { ($0, day) }))
        #expect(again == first)
    }

    @Test func englishSentences() {
        #expect(compose([.sleptMinutes(440)]).text == "You slept 7 hours 20 minutes last night.")
        #expect(compose([.sleptMinutes(60)]).text == "You slept 1 hour last night.")
        #expect(compose([.inBedMinutes(45)]).text == "Time in bed last night: 45 minutes.")
        #expect(compose([.steps(yesterday: 7_620, weeklyAverage: 6_000)]).text
            == "Yesterday: 7,620 steps, about 1,600 more than your 7-day average.")
        #expect(compose([.steps(yesterday: 6_100, weeklyAverage: 6_000)]).text
            == "Yesterday: 6,100 steps, close to your 7-day average.")
        #expect(compose([.steps(yesterday: 3_000, weeklyAverage: nil)]).text == "Yesterday: 3,000 steps.")
        #expect(compose([.steps(yesterday: 20, weeklyAverage: 14)]).text == "Yesterday: 20 steps, about 6 more than your 7-day average.")
        #expect(compose([.temperatureChange(celsiusDelta: -10, unit: .celsius)]).text
            == "Today’s high is 10 °C colder than yesterday’s.")
        #expect(compose([.precipitation(.rain, from: afternoon)]).text == "Rain likely from 16:00.")
        #expect(compose([.precipitation(.snow, from: nil)]).text == "Snow likely now.")
        #expect(compose([.tightGap(minutes: 5, first: "Standup", second: "Dentist", at: afternoon)]).text
            == "Calendar: 5 minutes between Standup and Dentist at 16:00.")
        #expect(compose([.birthdays(["Anna", "Ben", "Chloé"])]).text == "Birthdays today: Anna, Ben and 1 other.")
        #expect(compose([.screenTime(yesterdayMinutes: 190, weeklyAverageMinutes: 150)]).text
            == "Screen time yesterday: 3 hours 10 minutes, 40 minutes more than your weekly average.")
    }

    @Test func frenchSentences() {
        func fr(_ fact: MorningExtraFact) -> String { compose([fact], locale: "fr_FR").text }
        #expect(fr(.sleptMinutes(440)) == "Vous avez dormi 7 heures 20 minutes cette nuit.")
        #expect(fr(.inBedMinutes(480)) == "Temps au lit cette nuit : 8 heures.")
        // French groups digits with a narrow no-break space; compare the words around the numbers.
        let steps = fr(.steps(yesterday: 4_380, weeklyAverage: 6_000))
        #expect(steps.hasPrefix("Hier : 4") && steps.contains("380 pas, environ 1"))
        #expect(steps.hasSuffix("600 de moins que votre moyenne sur 7 jours."))
        #expect(fr(.temperatureChange(celsiusDelta: 7.4, unit: .celsius)) == "Maximum du jour : 7 °C de plus qu’hier.")
        #expect(fr(.precipitation(.mixed, from: afternoon)) == "Précipitations probables à partir de 16:00.")
        #expect(fr(.birthdays(["Anna"])) == "C’est l’anniversaire d’Anna aujourd’hui.")
        #expect(fr(.birthdays(["Paul"])) == "C’est l’anniversaire de Paul aujourd’hui.")
        #expect(fr(.calendarConflict(first: "Réunion", second: "Dentiste", at: afternoon))
            == "Agenda : « Réunion » et « Dentiste » se chevauchent à 16:00.")
    }

    @Test func aTemperatureDifferenceConvertsWithoutTheOffset() {
        // 10 °C warmer is 18 °F warmer, never 50.
        #expect(compose([.temperatureChange(celsiusDelta: 10, unit: .fahrenheit)]).text
            == "Today’s high is 18 °F warmer than yesterday’s.")
    }

    @Test func aSmallTemperatureChangeIsNotWorthSaying() {
        #expect(compose([.temperatureChange(celsiusDelta: 4.9, unit: .celsius)]).items.isEmpty)
        #expect(compose([.temperatureChange(celsiusDelta: -4.9, unit: .fahrenheit)]).items.isEmpty)
    }

    @Test func clockTimesUseTheGivenTimeZone() {
        let tokyo = MorningExtrasComposer.compose(facts: [.precipitation(.rain, from: afternoon)],
            preferences: .init(), day: day, localeIdentifier: "en_GB", timeZoneIdentifier: "Asia/Tokyo")
        #expect(tokyo.text == "Rain likely from 23:00.")
    }

    @Test func dayNumbersFollowTheLocalDate() throws {
        let paris = try #require(TimeZone(identifier: "Europe/Paris"))
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        // 23:30 UTC: 01:30 in Paris and 08:30 in Tokyo, the same local date in both.
        let instant = Date(timeIntervalSince1970: 1_791_847_800)
        let inParis = try #require(MorningExtrasDay.number(for: instant, timeZone: paris))
        let inTokyo = try #require(MorningExtrasDay.number(for: instant, timeZone: tokyo))
        #expect(inTokyo == inParis)
        let nextDay = try #require(MorningExtrasDay.number(for: instant.addingTimeInterval(86_400), timeZone: paris))
        #expect(nextDay == inParis + 1)
        #expect(MorningExtrasDay.number(for: Date(timeIntervalSinceReferenceDate: .infinity), timeZone: paris) == nil)
    }

    @Test func earlierDefaultOnHealthExtrasNeedExplicitConfirmation() throws {
        let legacy = Data(#"{"enabled":["sleep","steps","weatherChange"],"healthAccessRequested":true,"lastSpokenDay":{"sleep":2}}"#.utf8)
        let saved = try JSONDecoder().decode(MorningExtrasPreferences.self, from: legacy)
        #expect(saved.enabled == [.sleep, .steps, .weatherChange])
        #expect(saved.lastSpokenDay == ["sleep": 2])
        #expect(saved.confirmedHealthKinds.isEmpty)
    }

    @Test func preferencesRoundTripAndDropUnknownKinds() throws {
        var preferences = MorningExtrasPreferences(enabled: [.birthday, .sleep], healthAccessRequested: true)
        preferences.recordSpoken([.sleep], day: day)
        let data = try JSONEncoder().encode(preferences)
        #expect(try JSONDecoder().decode(MorningExtrasPreferences.self, from: data) == preferences)
        let future = Data(#"{"enabled":["sleep","moonPhase"],"lastSpokenDay":{"moonPhase":3,"sleep":2}}"#.utf8)
        let decoded = try JSONDecoder().decode(MorningExtrasPreferences.self, from: future)
        #expect(decoded.enabled == [.sleep])
        #expect(decoded.lastSpokenDay == ["sleep": 2])
        #expect(!decoded.healthAccessRequested)
        // Values, names and sentences are never part of the saved document.
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("slept") && !text.contains("Anna"))
    }
}

@Suite("Closing questions")
struct MorningClosingQuestionsTests {
    @Test func threeQuestionsInOrderEachMappedToItsCapture() {
        var flow = MorningClosingQuestions()
        #expect(flow.current == .dream)
        #expect(flow.current?.captureKind == .dream)
        flow.advance()
        #expect(flow.current == .remember)
        #expect(flow.current?.captureKind == .reminder)
        flow.advance()
        #expect(flow.current == .note)
        #expect(flow.current?.captureKind == .thought)
        flow.advance()
        #expect(flow.isFinished && flow.current == nil)
        flow.advance()
        #expect(flow.isFinished)
    }

    @Test func silenceAndNoSkip() {
        for answer in [nil, "", "   ", "No", "no.", "No thanks!", "Nothing", "non", "Non merci", "rien", "Pas maintenant", "nope"] {
            #expect(MorningClosingQuestions.interpret(answer) == .declined, "\(answer ?? "nil")")
        }
    }

    @Test func anAnswerThatStartsWithNoIsStillReviewed() {
        #expect(MorningClosingQuestions.interpret("No, remind me at 5 to call the bank")
            == .content("No, remind me at 5 to call the bank"))
        #expect(MorningClosingQuestions.interpret(" I dreamed of a garden ") == .content("I dreamed of a garden"))
        #expect(MorningClosingQuestions.interpret("Nothing important but buy milk") == .content("Nothing important but buy milk"))
    }

    @Test func promptsInBothLanguages() {
        #expect(MorningClosingQuestion.dream.prompt(french: false) == "Did you have a dream you want to note?")
        #expect(MorningClosingQuestion.remember.prompt(french: false) == "Anything you want to remember today, or something you forgot?")
        #expect(MorningClosingQuestion.note.prompt(french: false) == "Any note to take?")
        #expect(MorningClosingQuestion.dream.prompt(french: true) == "Avez-vous fait un rêve que vous voulez noter ?")
        #expect(MorningClosingQuestion.note.prompt(french: true) == "Une note à prendre ?")
    }
}
