import Foundation
import Testing
@testable import MorningCore

@Suite("Saved Screen Time coverage")
struct ScreenTimeObservationEvidenceTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(identifier: "Europe/Paris")!; return value
    }
    private func at(_ day: Int, _ hour: Int, month: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }
    private func hour(_ start: Date, id: String, seconds: Double) -> ScreenTimeHour {
        .init(interval: .init(start: start, duration: 3600), firstPickup: start,
            longestActivity: .init(start: start, duration: seconds), apps: [.init(bundleIdentifier: id, seconds: seconds)])
    }

    @Test("Only the detector's retained window supplies app evidence; later use stays out")
    func retainedWindow() throws {
        let hours = [hour(at(13, 22), id: "com.apple.mobilemail", seconds: 600),
                     hour(at(14, 7), id: "com.burbn.instagram", seconds: 1200),
                     hour(at(14, 13), id: "com.example.Evening", seconds: 600)]
        let sources = try ScreenTimeObservationEvidence.make(hours: hours, queryStart: at(13, 18), now: at(14, 16), calendar: calendar)
        let morning = try #require(sources.first { $0.day == at(14, 0) })
        #expect(morning.hasMorningEvidence)
        #expect(morning.apps.map(\.bundleIdentifier) == ["com.burbn.instagram"])
        #expect(morning.apps[0].seconds == 1200)
        #expect(!morning.apps[0].secondsMeasured)
        #expect(morning.returnedIntervals.count == 2)
        #expect(morning.morningWindow?.start == at(14, 7))
        #expect(!morning.renderedText(french: false).contains("Evening"))
    }

    @Test("An empty answer creates no dated observations; sparse returned days keep their unknown windows")
    func unknownCoverage() throws {
        #expect(try ScreenTimeObservationEvidence.make(hours: [], queryStart: at(12, 0), now: at(14, 14), calendar: calendar).isEmpty)
        let sources = try ScreenTimeObservationEvidence.make(hours: [hour(at(12, 8), id: "com.burbn.instagram", seconds: 1200),
            hour(at(14, 18), id: "com.example.Evening", seconds: 600)], queryStart: at(12, 0), now: at(14, 22), calendar: calendar)
        #expect(sources.map(\.day) == [at(12, 0), at(14, 0)])
        #expect(sources.allSatisfy { !$0.hasMorningEvidence && $0.morningWindow == nil && $0.apps.isEmpty && $0.returnedIntervals.count == 1 })
        #expect(sources.allSatisfy { $0.renderedText(french: false).contains("Missing periods remain unknown") })
        #expect(try JSONDecoder().decode([ScreenTimeObservationEvidence].self, from: JSONEncoder().encode(sources)) == sources)
    }

    @Test("A report beginning mid-morning cannot turn all-day minutes into a morning")
    func insufficientWindow() throws {
        let result = try ScreenTimeObservationEvidence.make(hours: [hour(at(14, 8), id: "com.burbn.instagram", seconds: 1200)],
            queryStart: at(14, 0), now: at(14, 14), calendar: calendar)
        #expect(result.count == 1 && result[0].returnedIntervals.count == 1)
        #expect(result[0].morningWindow == nil && result[0].apps.isEmpty)
    }

    @Test("Day boundaries follow the report's zone across the 25-hour autumn day")
    func daylightSavingCoverage() throws {
        let result = try ScreenTimeObservationEvidence.make(hours: [hour(at(25, 18), id: "com.example.Evening", seconds: 600)],
            queryStart: at(25, 0), now: at(26, 0), calendar: calendar)
        #expect(result.count == 1)
        #expect(result[0].requestedWindow.duration == 25 * 3600)
        #expect(result[0].day == at(25, 0) && result[0].timeZoneIdentifier == "Europe/Paris")
    }

    @Test("Malformed measurements fail before they can become a saved zero or a habit")
    func invalidMeasurements() throws {
        for seconds in [Double.nan, -Double.infinity, -1, 3601] {
            let raw = ScreenTimeHour(interval: .init(start: at(14, 7), duration: 3600),
                apps: [.init(bundleIdentifier: "com.burbn.instagram", seconds: seconds)])
            #expect(throws: ScreenTimeObservationError.invalidEvidence) {
                try ScreenTimeObservationEvidence.make(hours: [raw], queryStart: at(14, 0), now: at(14, 14), calendar: calendar)
            }
        }
        #expect(throws: ScreenTimeObservationError.invalidEvidence) {
            try ScreenTimeObservationEvidence(day: at(14, 0), timeZoneIdentifier: "Europe/Paris",
                requestedWindow: .init(start: at(14, 0), end: at(14, 14)), retrievedAt: at(14, 14), returnedIntervals: [],
                morningWindow: nil, apps: [.init(bundleIdentifier: "com.burbn.instagram", seconds: 60, secondsMeasured: true, firstHourIndex: 0)])
        }
    }
}
