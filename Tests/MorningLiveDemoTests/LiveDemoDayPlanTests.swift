import Foundation
import Testing
@testable import MorningLiveDemo

@Suite("Live morning demo day plan")
struct LiveDemoDayPlanTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: hour, minute: minute))!
    }

    private func event(_ title: String, _ start: (Int, Int), _ end: (Int, Int)) -> LiveDemoDayPlan.Event {
        .init(title: title, start: at(start.0, start.1), end: at(end.0, end.1), isAllDay: false)
    }

    private var allDay: LiveDemoDayPlan.Event {
        .init(title: "Holiday", start: at(0), end: calendar.date(byAdding: .day, value: 1, to: at(0))!, isAllDay: true)
    }

    @Test("First meeting, morning list, free time in time order, all-day once")
    func ordinaryDay() {
        let events = [event("Standup", (10, 0), (10, 30)), event("Review", (11, 0), (12, 0)),
                      event("Lunch", (12, 30), (13, 30)), event("Call", (17, 30), (18, 0)), allDay]
        let sentences = LiveDemoDayPlan.sentences(events: events, now: at(7, 30), calendar: calendar)
        #expect(sentences == [
            "Your first meeting today is at 10:00: Standup.",
            "This morning you have 2 events.",
            "At 10:00, Standup.", "At 11:00, Review.",
            "You are free from 09:00 to 10:00.",
            "You are free from 13:30 to 17:30.",
            "You are free from 18:00 to 19:00.",
            "Today is also Holiday."
        ])
    }

    @Test("A meeting in progress, then the next event; free time starts from now")
    func inProgress() {
        let events = [event("Standup", (9, 0), (9, 30)), event("Workshop", (10, 0), (11, 30)), event("Review", (14, 0), (15, 0))]
        let sentences = LiveDemoDayPlan.sentences(events: events, now: at(10, 12), calendar: calendar)
        #expect(sentences.first == "Right now you have Workshop, until 11:30.")
        #expect(sentences[1] == "Your next event is at 14:00: Review.")
        let gaps = LiveDemoDayPlan.freeGaps(events: events, now: at(10, 12), calendar: calendar)
        #expect(gaps.map(\.start) == [at(11, 30), at(15, 0)])
        #expect(gaps.map(\.end) == [at(14, 0), at(19, 0)])
    }

    @Test("Overlapping events merge; short gaps are dropped; at most three, longest kept")
    func overlapsAndLimits() {
        let events = [event("A", (9, 0), (10, 0)), event("B", (9, 30), (10, 45)),   // merged to 10:45
                      event("C", (11, 0), (11, 30)),                               // 15 min gap dropped
                      event("D", (12, 0), (12, 30)), event("E", (13, 0), (14, 0)),
                      event("F", (15, 0), (18, 0))]
        let gaps = LiveDemoDayPlan.freeGaps(events: events, now: at(8), calendar: calendar)
        // Candidates: 11:30-12:00 (30), 12:30-13:00 (30), 14:00-15:00 (60), 18:00-19:00 (60).
        #expect(gaps.count == 3)
        #expect(gaps.map(\.start) == [at(11, 30), at(14, 0), at(18, 0)])
    }

    @Test("Events past 19:00 and all-day events never block the window")
    func lateAndAllDay() {
        let events = [event("Dinner", (19, 30), (22, 0)), allDay]
        let gaps = LiveDemoDayPlan.freeGaps(events: events, now: at(8), calendar: calendar)
        #expect(gaps == [LiveDemoDayPlan.Gap(start: at(9), end: at(19))])
        let sentences = LiveDemoDayPlan.sentences(events: events, now: at(8), calendar: calendar)
        #expect(sentences.first == "Your first meeting today is at 19:30: Dinner.")
        #expect(sentences.contains("You have nothing this morning."))
        #expect(sentences.last == "Today is also Holiday.")
    }

    @Test("No events: the day is free; all-day only still says so")
    func noEvents() {
        #expect(LiveDemoDayPlan.sentences(events: [], now: at(8), calendar: calendar) == ["Your day is free."])
        #expect(LiveDemoDayPlan.sentences(events: [allDay], now: at(8), calendar: calendar)
                == ["Your day is free.", "Today is also Holiday."])
    }

    @Test("After the last event and after 19:00")
    func evening() {
        let events = [event("Standup", (9, 0), (9, 30))]
        let sentences = LiveDemoDayPlan.sentences(events: events, now: at(20), calendar: calendar)
        #expect(sentences.first == "You have no more events today.")
        #expect(sentences.contains("You have no long free time left today."))
    }

    @Test("Times use the calendar's time zone")
    func timeZones() {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        // 10:00 in Paris (UTC+2 in October) is 17:00 in Tokyo.
        #expect(LiveDemoDayPlan.time(at(10), tokyo) == "17:00")
        #expect(LiveDemoDayPlan.time(at(10), calendar) == "10:00")
        #expect(LiveDemoDayPlan.roundedUp(at(10, 2), calendar: calendar) == at(10, 5))
        #expect(LiveDemoDayPlan.roundedUp(at(10, 5), calendar: calendar) == at(10, 5))
    }

    @Test("Steps option")
    func steps() {
        #expect(LiveDemoSteps.from(environment: [:]) == LiveDemoSteps.all)
        #expect(LiveDemoSteps.from(environment: ["MO_LIVE_DEMO_STEPS": "calendar,reels"]) == [.calendar, .reels])
        #expect(LiveDemoSteps.from(environment: ["MO_LIVE_DEMO_STEPS": "calendar, sound-check, bogus"]) == [.calendar])
    }
}
