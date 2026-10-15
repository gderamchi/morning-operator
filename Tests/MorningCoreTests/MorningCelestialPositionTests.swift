import Foundation
import Testing
@testable import MorningCore

@Suite("Celestial artwork follows local time")
struct MorningCelestialPositionTests {
    @Test func theSunMovesFromLeftToRightOverTheDaylightArc() {
        let rise = MorningCelestialClock.scene(atMinute: 7 * 60)
        let morning = MorningCelestialClock.scene(atMinute: 9 * 60)
        let noon = MorningCelestialClock.scene(atMinute: 13 * 60)
        let set = MorningCelestialClock.scene(atMinute: 19 * 60)
        #expect(rise.sun.centerX == 0.12 && rise.sun.centerY == 0.76)
        #expect(rise.sun.centerX < morning.sun.centerX && morning.sun.centerX < noon.sun.centerX)
        #expect(morning.sun.centerY > noon.sun.centerY)
        #expect(abs(noon.sun.centerX - 0.5) < 0.001 && abs(noon.sun.centerY - 0.18) < 0.001)
        #expect(abs(set.sun.centerX - 0.88) < 0.001 && abs(set.sun.centerY - 0.76) < 0.001)
        #expect(noon.sun.opacity == 1 && noon.moon.opacity == 0)
    }

    @Test func theDecorativeMoonFollowsTheNightArcAcrossMidnight() {
        let evening = MorningCelestialClock.scene(atMinute: 19 * 60)
        let late = MorningCelestialClock.scene(atMinute: 22 * 60)
        let middle = MorningCelestialClock.scene(atMinute: 60)
        let dawn = MorningCelestialClock.scene(atMinute: 7 * 60)
        #expect(evening.moon.centerX == 0.12 && evening.moon.centerY == 0.76)
        #expect(evening.moon.centerX < late.moon.centerX && late.moon.centerX < middle.moon.centerX)
        #expect(evening.moon.centerY > late.moon.centerY && late.moon.centerY > middle.moon.centerY)
        #expect(abs(middle.moon.centerY - 0.18) < 0.001)
        #expect(abs(dawn.moon.centerX - 0.88) < 0.001)
        #expect(middle.sun.opacity == 0 && middle.moon.opacity == 1)
    }

    @Test func everyVisibleMinuteIsFiniteBoundedAndContinuousIncludingMidnight() {
        for solar in [MorningSolarDay.fixed, .init(sunriseMinute: -400, sunsetMinute: 500),
                      .init(sunriseMinute: 60, sunsetMinute: 1400)] {
            var prior = MorningCelestialClock.scene(atMinute: 0, solar: solar)
            for minute in 1...1440 {
                let next = MorningCelestialClock.scene(atMinute: Double(minute), solar: solar)
                for (before, body) in [(prior.sun, next.sun), (prior.moon, next.moon)] {
                    #expect(body.centerX.isFinite && body.centerY.isFinite && body.opacity.isFinite)
                    #expect((0...1).contains(body.opacity))
                    #expect((0.12...0.88).contains(body.centerX) && (0.179...0.761).contains(body.centerY))
                    // Invisible bodies reset behind the landscape for the following arc.
                    if before.opacity > 0 || body.opacity > 0 {
                        #expect(abs(body.centerX - before.centerX) < 0.012)
                        #expect(abs(body.centerY - before.centerY) < 0.025)
                    }
                    #expect(abs(body.opacity - before.opacity) < 0.076)
                }
                prior = next
            }
            #expect(prior == MorningCelestialClock.scene(atMinute: 0, solar: solar))
        }
    }

    @Test func datesUseTheProvidedLocalCalendarAndOutOfRangeMinutesWrap() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Paris"))
        let nine = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 9)))
        #expect(MorningCelestialClock.scene(at: nine, calendar: calendar) == MorningCelestialClock.scene(for: .morning))
        #expect(MorningCelestialClock.scene(atMinute: -60) == MorningCelestialClock.scene(atMinute: 23 * 60))
        #expect(MorningCelestialClock.scene(atMinute: 1440 + 9 * 60) == MorningCelestialClock.scene(for: .morning))
    }

    @Test func solarShiftAndInvalidSourcesCannotBreakTheJourney() {
        let winter = MorningSolarDay(sunriseMinute: 600, sunsetMinute: 840)
        #expect(MorningCelestialClock.scene(atMinute: 600, solar: winter).sun.centerY == 0.76)
        #expect(MorningCelestialClock.scene(atMinute: 720, solar: winter).sun.centerY < 0.19)
        for solar in [MorningSolarDay(sunriseMinute: .nan, sunsetMinute: .infinity),
                      MorningSolarDay(sunriseMinute: 900, sunsetMinute: 900)] {
            #expect(MorningCelestialClock.scene(atMinute: 540, solar: solar) == MorningCelestialClock.scene(atMinute: 540))
        }
        #expect(MorningCelestialClock.scene(atMinute: .nan).sun.centerY.isFinite)
    }

    @Test func polarDaysHoldTheirBodyWithoutAnInventedMidnightSunset() {
        for condition in [MorningSolarDay.Condition.allDay, .allNight] {
            let solar = MorningSolarDay(sunriseMinute: 0, sunsetMinute: 0, condition: condition)
            let scene = MorningCelestialClock.scene(atMinute: 0, solar: solar)
            #expect(scene == MorningCelestialClock.scene(atMinute: 12 * 60, solar: solar))
            #expect(scene.sun.opacity == (condition == .allDay ? 1 : 0))
            #expect(scene.moon.opacity == (condition == .allNight ? 1 : 0))
        }
    }
}
