import Foundation
import Testing
@testable import MorningCore

@Suite("Solar estimates are local, seasonal and timezone aware")
struct MorningSolarCalculatorTests {
    private func calendar(_ zone: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        return calendar
    }

    private func date(_ month: Int, _ day: Int, in calendar: Calendar) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12)))
    }

    @Test func parisSolsticesHaveDifferentDayLengthsAndPlausibleLocalEvents() throws {
        let calendar = try calendar("Europe/Paris")
        let summer = try #require(MorningSolarDay.calculate(for: date(6, 21, in: calendar), latitude: 48.8566,
                                                            longitude: 2.3522, calendar: calendar))
        let winter = try #require(MorningSolarDay.calculate(for: date(12, 21, in: calendar), latitude: 48.8566,
                                                            longitude: 2.3522, calendar: calendar))
        // Rounded sunrise/set landmarks; allow the few-minute error of the NOAA approximation.
        #expect(abs(summer.sunriseMinute - (5 * 60 + 47)) < 10)
        #expect(abs(summer.sunsetMinute - (21 * 60 + 58)) < 10)
        #expect(abs(winter.sunriseMinute - (8 * 60 + 42)) < 10)
        #expect(abs(winter.sunsetMinute - (16 * 60 + 56)) < 10)
        #expect(summer.sunsetMinute - summer.sunriseMinute > 16 * 60)
        #expect(winter.sunsetMinute - winter.sunriseMinute < 9 * 60)
        #expect(summer.condition == .dayAndNight && winter.condition == .dayAndNight)
    }

    @Test func theSouthernHemisphereReversesTheSeasons() throws {
        let calendar = try calendar("Australia/Sydney")
        let summer = try #require(MorningSolarDay.calculate(for: date(12, 21, in: calendar), latitude: -33.8688,
                                                            longitude: 151.2093, calendar: calendar))
        let winter = try #require(MorningSolarDay.calculate(for: date(6, 21, in: calendar), latitude: -33.8688,
                                                            longitude: 151.2093, calendar: calendar))
        #expect(abs(summer.sunriseMinute - (5 * 60 + 41)) < 10)
        #expect(abs(summer.sunsetMinute - (20 * 60 + 6)) < 10)
        #expect(summer.sunsetMinute - summer.sunriseMinute > winter.sunsetMinute - winter.sunriseMinute)
    }

    @Test func daylightSavingUsesTheEventDateAndPhoneCalendar() throws {
        let paris = try calendar("Europe/Paris")
        let before = try #require(MorningSolarDay.calculate(for: date(3, 28, in: paris), latitude: 48.8566,
                                                            longitude: 2.3522, calendar: paris))
        let after = try #require(MorningSolarDay.calculate(for: date(3, 29, in: paris), latitude: 48.8566,
                                                           longitude: 2.3522, calendar: paris))
        #expect((55...65).contains(after.sunriseMinute - before.sunriseMinute))
        let utc = try calendar("UTC")
        let sameDate = try date(6, 21, in: paris)
        let local = try #require(MorningSolarDay.calculate(for: sameDate, latitude: 48.8566, longitude: 2.3522, calendar: paris))
        let universal = try #require(MorningSolarDay.calculate(for: sameDate, latitude: 48.8566, longitude: 2.3522, calendar: utc))
        #expect(abs(local.sunriseMinute - universal.sunriseMinute - 120) < 0.1)
        #expect(abs(local.sunsetMinute - universal.sunsetMinute - 120) < 0.1)
    }

    @Test func aDistantSelectedCityCanHaveDaylightAcrossPhoneMidnight() throws {
        let newYork = try calendar("America/New_York")
        let solar = try #require(MorningSolarDay.calculate(for: date(6, 21, in: newYork), latitude: 35.6762,
                                                           longitude: 139.6503, calendar: newYork))
        #expect(solar.sunriseMinute < 0 && solar.sunsetMinute > 0)
        #expect(MorningCelestialClock.scene(atMinute: 0, solar: solar).sun.opacity == 1)
        #expect(MorningCelestialClock.scene(atMinute: 12 * 60, solar: solar).moon.opacity == 1)
        #expect(MorningDayClock.blend(atMinute: 0, solar: solar).dominant == .day)
    }

    @Test func polarDayAndNightAreExplicitInBothHemispheres() throws {
        let calendar = try calendar("Arctic/Longyearbyen")
        for latitude in [78.2232, 90.0, -78.2232, -90.0] {
            let june = try #require(MorningSolarDay.calculate(for: date(6, 21, in: calendar), latitude: latitude,
                                                              longitude: 15.6469, calendar: calendar))
            let december = try #require(MorningSolarDay.calculate(for: date(12, 21, in: calendar), latitude: latitude,
                                                                  longitude: 15.6469, calendar: calendar))
            #expect(june.condition == (latitude > 0 ? .allDay : .allNight))
            #expect(december.condition == (latitude > 0 ? .allNight : .allDay))
            #expect(MorningDayClock.blend(atMinute: 0, solar: june) == .steady(latitude > 0 ? .day : .night))
        }
    }

    @Test func invalidCoordinatesAreRejected() {
        for (latitude, longitude) in [(91.0, 0.0), (0, 181), (.nan, 0), (0, .infinity)] {
            #expect(MorningSolarDay.calculate(for: Date(), latitude: latitude, longitude: longitude) == nil)
        }
    }
}
