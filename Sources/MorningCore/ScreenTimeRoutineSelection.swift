import Foundation

/// Shared app-moment policy. Returned facts stay in their source even when they
/// do not qualify as a separate moment. No generated IDs or live clock are used.
public struct ScreenTimeRoutineSelection: Equatable, Sendable {
    public static let maximumSuggestedApps = 8
    public static let plannedMinutesRange = 1...240
    public struct Candidate: Equatable, Sendable {
        public let bundleIdentifier: String
        public let minutes: Int
        public let morningsSeen: Int
        public let minutesMeasured: Bool
        public let categoryName: String?
        fileprivate let hour: Double
        fileprivate let first: Int
    }
    public let candidates: [Candidate]
    public let excludedBundleIdentifiers: [String]
    public let morningsUsed: Int
    public let morningsFound: Int
    public let typicalStartMinuteOfDay: Int

    public static func from(mornings: [ScreenTimeMorning], nextMorning: Date, calendar: Calendar) -> Self {
        select(mornings.map { morning in
            Input(start: morning.start, zone: morning.timeZone, apps: morning.apps.map {
                App(id: $0.bundleIdentifier, seconds: $0.seconds, hour: $0.firstHourIndex,
                    first: $0.isFirstPickupApp, measured: $0.secondsMeasured, category: $0.categoryName)
            })
        }, nextMorning: nextMorning, calendar: calendar)
    }

    public static func from(reports: [ScreenTimeObservationEvidence], referenceDate: Date) throws -> Self {
        guard referenceDate.timeIntervalSince1970.isFinite,
              referenceDate.timeIntervalSince1970 >= -62_135_596_800,
              referenceDate.timeIntervalSince1970 < 253_402_300_800,
              Set(reports.map(\.timeZoneIdentifier)).count <= 1 else { throw ScreenTimeObservationError.invalidEvidence }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = reports.first.flatMap { TimeZone(identifier: $0.timeZoneIdentifier) } ?? TimeZone(secondsFromGMT: 0)!
        let nextMorning = calendar.component(.hour, from: referenceDate) < 12 ? referenceDate
            : calendar.date(byAdding: .day, value: 1, to: referenceDate) ?? referenceDate
        return select(reports.compactMap { report in
            guard let window = report.morningWindow else { return nil }
            return Input(start: window.start, zone: calendar.timeZone, apps: report.apps.map {
                // The archived aggregate carries hourly order, not timed app pickups.
                App(id: $0.bundleIdentifier, seconds: $0.seconds, hour: $0.firstHourIndex,
                    first: false, measured: $0.secondsMeasured, category: nil)
            })
        }, nextMorning: nextMorning, calendar: calendar)
    }

    private struct App {
        let id: String; let seconds: Double; let hour: Int; let first: Bool; let measured: Bool; let category: String?
    }
    private struct Input { let start: Date; let zone: TimeZone; let apps: [App] }
    private struct Seen {
        var seconds: [Double] = []; var hours: [Double] = []; var first = 0; var measured = true; var category: String?
    }
    private static func select(_ input: [Input], nextMorning: Date, calendar: Calendar) -> Self {
        let all = input.filter { !$0.apps.isEmpty }
        let weekend = calendar.isDateInWeekend(nextMorning)
        let sameKind = all.filter {
            var local = calendar; local.timeZone = $0.zone
            return local.isDateInWeekend($0.start) == weekend
        }
        let mornings = sameKind.count >= 2 ? sameKind : all
        let needed = max(1, (mornings.count + 1) / 2)
        var seen: [String: Seen] = [:]
        for morning in mornings {
            for app in morning.apps where app.seconds >= 30 {
                var item = seen[app.id] ?? Seen()
                item.seconds.append(app.seconds); item.hours.append(Double(app.hour))
                if app.first { item.first += 1 }
                item.measured = item.measured && app.measured; item.category = item.category ?? app.category
                seen[app.id] = item
            }
        }
        let candidates = seen.compactMap { id, item -> Candidate? in
            guard item.seconds.count >= needed else { return nil }
            let minutes = Int((median(item.seconds) / 60).rounded())
            guard minutes >= plannedMinutesRange.lowerBound else { return nil }
            return Candidate(bundleIdentifier: id, minutes: min(minutes, plannedMinutesRange.upperBound),
                morningsSeen: item.seconds.count, minutesMeasured: item.measured,
                categoryName: item.category, hour: median(item.hours), first: item.first)
        }
        let leader = candidates.filter { $0.first > 0 }.sorted {
            if $0.first != $1.first { return $0.first > $1.first }
            if $0.hour != $1.hour { return $0.hour < $1.hour }
            return $0.bundleIdentifier < $1.bundleIdentifier
        }.first?.bundleIdentifier
        let ordered = candidates.sorted {
            if ($0.bundleIdentifier == leader) != ($1.bundleIdentifier == leader) { return $0.bundleIdentifier == leader }
            if $0.hour != $1.hour { return $0.hour < $1.hour }
            if $0.minutes != $1.minutes { return $0.minutes > $1.minutes }
            return $0.bundleIdentifier < $1.bundleIdentifier
        }
        let positiveIDs = Set(all.flatMap { $0.apps.filter { $0.seconds > 0 }.map(\.id) })
        let starts = mornings.map { morning -> Double in
            var local = calendar; local.timeZone = morning.zone
            return Double(local.component(.hour, from: morning.start) * 60 + local.component(.minute, from: morning.start))
        }
        return Self(candidates: ordered,
            excludedBundleIdentifiers: positiveIDs.subtracting(ordered.map(\.bundleIdentifier)).sorted(),
            morningsUsed: mornings.count, morningsFound: all.count,
            typicalStartMinuteOfDay: starts.isEmpty ? 0 : Int(median(starts).rounded()) % (24 * 60))
    }
    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted(), middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
