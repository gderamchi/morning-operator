import Foundation

/// Today's calendar as short spoken sentences for the live demo: the first (or next)
/// event, this morning's events, free time, and all-day events. Titles are spoken only;
/// the caller never logs them. Times use the calendar's time zone, 24-hour clock.
public enum LiveDemoDayPlan {
    public struct Event: Codable, Equatable, Sendable {
        public let title: String
        public let start: Date
        public let end: Date
        public let isAllDay: Bool

        public init(title: String, start: Date, end: Date, isAllDay: Bool) {
            self.title = title; self.start = start; self.end = end; self.isAllDay = isAllDay
        }
    }

    public struct Gap: Equatable, Sendable {
        public let start: Date
        public let end: Date
        public var duration: TimeInterval { end.timeIntervalSince(start) }
    }

    public static let minimumGap: TimeInterval = 30 * 60
    public static let maximumGaps = 3

    public static func sentences(events: [Event], now: Date, calendar: Calendar) -> [String] {
        guard let day = calendar.dateInterval(of: .day, for: now) else { return [] }
        let allDay = events.filter { $0.isAllDay && $0.start < day.end && $0.end > day.start }
        let timed = events.filter { !$0.isAllDay && $0.end > day.start && $0.start < day.end }
            .sorted { $0.start != $1.start ? $0.start < $1.start : $0.end < $1.end }
        var result: [String] = []
        guard !timed.isEmpty else {
            result.append("Your day is free.")
            result += allDaySentences(allDay)
            return result
        }

        // 1. In progress, then the first or the next event.
        if let current = timed.first(where: { $0.start <= now && $0.end > now }) {
            result.append("Right now you have \(spoken(current.title)), until \(time(current.end, calendar)).")
        }
        if let next = timed.first(where: { $0.start > now }) {
            let earlier = timed.contains { $0.start <= now }
            result.append(earlier ? "Your next event is at \(time(next.start, calendar)): \(spoken(next.title))."
                                  : "Your first meeting today is at \(time(next.start, calendar)): \(spoken(next.title)).")
        } else {
            result.append("You have no more events today.")
        }

        // 2. This morning (starts before 12:00).
        if let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now) {
            let morning = timed.filter { $0.start < noon }
            switch morning.count {
            case 0: result.append("You have nothing this morning.")
            case 1: result.append("This morning you have one event.")
            default: result.append("This morning you have \(morning.count) events.")
            }
            for event in morning.prefix(5) {
                result.append("At \(time(max(event.start, day.start), calendar)), \(spoken(event.title)).")
            }
        }

        // 3. Free time between 09:00 and 19:00, from now on.
        let gaps = freeGaps(events: timed, now: now, calendar: calendar)
        if gaps.isEmpty {
            result.append("You have no long free time left today.")
        } else {
            for gap in gaps {
                result.append("You are free from \(time(gap.start, calendar)) to \(time(gap.end, calendar)).")
            }
        }
        result += allDaySentences(allDay)
        return result
    }

    /// Gaps of at least 30 minutes inside 09:00-19:00 that are still ahead (from `now`),
    /// with overlapping events merged. All-day events never block. At most three: the
    /// longest are kept and returned in time order.
    public static func freeGaps(events: [Event], now: Date, calendar: Calendar) -> [Gap] {
        guard let windowStart = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now),
              let windowEnd = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: now) else { return [] }
        let start = max(windowStart, roundedUp(now, calendar: calendar))
        guard start < windowEnd else { return [] }
        let busy = events.filter { !$0.isAllDay && $0.end > start && $0.start < windowEnd }
            .map { (max($0.start, start), min($0.end, windowEnd)) }
            .sorted { $0.0 < $1.0 }
        var gaps: [Gap] = []
        var cursor = start
        for (busyStart, busyEnd) in busy {
            if busyStart > cursor { gaps.append(Gap(start: cursor, end: busyStart)) }
            cursor = max(cursor, busyEnd)
        }
        if cursor < windowEnd { gaps.append(Gap(start: cursor, end: windowEnd)) }
        let long = gaps.filter { $0.duration >= minimumGap }
        let kept = long.sorted { $0.duration != $1.duration ? $0.duration > $1.duration : $0.start < $1.start }
            .prefix(maximumGaps)
        return kept.sorted { $0.start < $1.start }
    }

    /// Up to the next 5 minutes, so "free from 10:02" reads as "free from 10:05".
    static func roundedUp(_ date: Date, calendar: Calendar) -> Date {
        let minute = calendar.component(.minute, from: date)
        let second = calendar.component(.second, from: date)
        let remainder = minute % 5
        guard remainder != 0 || second != 0 else { return date }
        let floor = calendar.date(bySetting: .second, value: 0, of: date)
            .flatMap { calendar.date(byAdding: .minute, value: -remainder, to: $0) } ?? date
        return calendar.date(byAdding: .minute, value: 5, to: floor) ?? date
    }

    static func allDaySentences(_ events: [Event]) -> [String] {
        var seen: Set<String> = []
        return events.filter { seen.insert($0.title).inserted }.prefix(2).map { "Today is also \(spoken($0.title))." }
    }

    static func time(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// One line, short: a title is read aloud, never logged.
    static func spoken(_ title: String) -> String {
        let line = LiveDemoDraft.sanitize(title) ?? "an untitled event"
        return line.count > 80 ? String(line.prefix(80)) : line
    }
}

/// Which parts of the demo to run (`MO_LIVE_DEMO_STEPS=calendar,reels`). Default: all.
public enum LiveDemoSteps {
    public static let all: Set<LiveDemoStep> = [.messages, .mail, .weather, .calendar, .reels]

    public static func from(environment: [String: String]) -> Set<LiveDemoStep> {
        guard let raw = environment["MO_LIVE_DEMO_STEPS"]?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else {
            return all
        }
        let chosen = raw.split(separator: ",").compactMap { LiveDemoStep(rawValue: $0.trimmingCharacters(in: .whitespaces)) }
        return Set(chosen).intersection(all)
    }
}
