import Foundation

/// One app inside one hourly Screen Time segment, as the system reported it.
public struct ScreenTimeAppHour: Equatable, Sendable {
    public let bundleIdentifier: String
    public let seconds: TimeInterval
    /// Pickups that went straight into this app.
    public let pickups: Int
    /// Screen Time's localized category name, when the row carried one.
    public let categoryName: String?

    public init(bundleIdentifier: String, seconds: TimeInterval, pickups: Int = 0, categoryName: String? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.seconds = seconds
        self.pickups = pickups
        self.categoryName = categoryName
    }
}

/// One hourly segment: the finest grain the API offers. Hours without use are not returned.
public struct ScreenTimeHour: Equatable, Sendable {
    public let interval: DateInterval
    public let firstPickup: Date?
    public let longestActivity: DateInterval?
    public let apps: [ScreenTimeAppHour]

    public init(interval: DateInterval, firstPickup: Date? = nil, longestActivity: DateInterval? = nil, apps: [ScreenTimeAppHour]) {
        self.interval = interval
        self.firstPickup = firstPickup
        self.longestActivity = longestActivity
        self.apps = apps
    }
}

/// One morning found in Screen Time data, with the minutes each app took inside it.
public struct ScreenTimeMorning: Equatable, Sendable {
    public struct AppUse: Equatable, Sendable {
        public let bundleIdentifier: String
        public let seconds: TimeInterval
        /// False when an hour only partly inside the morning contributed: its minutes were
        /// shared out in proportion and may include use just after the morning.
        public let secondsMeasured: Bool
        /// Whole hours between the morning's first hour and the first hour this app was used.
        public let firstHourIndex: Int
        /// True for the app the first hour's pickups point to (opened straight from the Lock Screen).
        public let isFirstPickupApp: Bool
        public let categoryName: String?
    }

    public let start: Date
    public let end: Date
    public let endReason: DetectedMorning.EndReason
    public let timeZone: TimeZone
    /// In likely order: the first-pickup app, then by hour of first use, then by minutes.
    public let apps: [AppUse]

    /// Local minutes after midnight of the start, in the morning's own time zone.
    public var startMinuteOfDay: Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: start)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

/// What one read of Screen Time produced.
public struct ScreenTimeLearning: Equatable, Sendable {
    public let mornings: [ScreenTimeMorning]
    /// Start of the earliest hour the API returned, nil when it returned nothing.
    public let earliestData: Date?
    /// Local days from the earliest returned hour to `now`, both included: how far back the data went.
    public let daysOfData: Int
    /// Local days whose morning could not be found (no use, or no 3-hour gap before it on record).
    public let daysWithoutMorning: Int
}

public enum ScreenTimeMorningLearner {
    /// Splits hourly data into local days and finds each day's morning with the owner's rule
    /// (`MorningStartDetector`). Rows from MORE itself, test runners and system sheets are
    /// left out of both the minutes and the use evidence; a morning still running (`ongoing`)
    /// is left out because its minutes are not final.
    /// - Parameters:
    ///   - queryStart: the start of the interval that was asked for. Coverage begins at the
    ///     later of this and the earliest returned hour: before that, silence is unknown, not sleep.
    ///   - latestStartHour: a first use at or after this local hour is not a morning (a day
    ///     with no morning use would otherwise make its evening the "morning").
    public static func learn(hours rawHours: [ScreenTimeHour], queryStart: Date, now: Date,
                             calendar: Calendar = .current, ownBundleIdentifiers: Set<String> = [],
                             latestStartHour: Int = 14,
                             policy: MorningDetectionPolicy = MorningDetectionPolicy()) -> ScreenTimeLearning {
        let hours = cleaned(rawHours, ownBundleIdentifiers: ownBundleIdentifiers, now: now)
        guard let earliest = hours.first?.interval.start else {
            return ScreenTimeLearning(mornings: [], earliestData: nil, daysOfData: 0, daysWithoutMorning: 0)
        }
        let coveredFrom = max(queryStart, earliest)
        var uses: [PhoneUse] = []
        for hour in hours {
            let seconds = hour.apps.reduce(0) { $0 + $1.seconds }
            uses += PhoneUse.fromScreenTimeSegment(hour: hour.interval, totalSeconds: seconds,
                firstPickup: hour.firstPickup, longestActivity: hour.longestActivity, sessionGap: policy.sessionGap)
        }
        var mornings: [ScreenTimeMorning] = []
        var missing = 0
        var days = 0
        var day = calendar.startOfDay(for: earliest)
        let lastDay = calendar.startOfDay(for: now)
        while day <= lastDay, days < 60 {
            days += 1
            switch MorningStartDetector.detect(uses: uses, on: day, coveredFrom: coveredFrom, now: now,
                                               policy: policy, calendar: calendar) {
            case .found(let detected) where calendar.component(.hour, from: detected.start) >= latestStartHour:
                missing += 1
            case .found(let detected) where detected.endReason != .ongoing:
                mornings.append(morning(detected, hours: hours, calendar: calendar))
            case .found: break
            case .noData, .noSleepGapCovered: missing += 1
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return ScreenTimeLearning(mornings: mornings, earliestData: earliest, daysOfData: days, daysWithoutMorning: missing)
    }

    /// Drops noise rows and rows without time, merges hours returned twice (a repeated live
    /// read: the later copy wins) and sorts by start. An hour left with no app keeps no
    /// pickup or longest-session evidence when all of its rows were MORE or a test runner:
    /// that use was driven by tests, not by the owner.
    static func cleaned(_ hours: [ScreenTimeHour], ownBundleIdentifiers: Set<String>, now: Date) -> [ScreenTimeHour] {
        var byStart: [Date: ScreenTimeHour] = [:]
        for hour in hours where hour.interval.start <= now && hour.interval.duration > 0 { byStart[hour.interval.start] = hour }
        return byStart.values.sorted { $0.interval.start < $1.interval.start }.compactMap { hour in
            var seen = Set<String>()
            var apps: [ScreenTimeAppHour] = []
            for app in hour.apps where app.seconds.isFinite && app.seconds > 0 {
                guard !ScreenTimeAppCatalog.isNoise(app.bundleIdentifier, ownBundleIdentifiers: ownBundleIdentifiers) else { continue }
                // One app is listed once per hour; a duplicate keeps its larger figure, never a sum.
                if seen.insert(app.bundleIdentifier).inserted { apps.append(app) }
                else if let index = apps.firstIndex(where: { $0.bundleIdentifier == app.bundleIdentifier }), apps[index].seconds < app.seconds {
                    apps[index] = app
                }
            }
            let clipped = apps.map { app in
                ScreenTimeAppHour(bundleIdentifier: app.bundleIdentifier, seconds: min(app.seconds, hour.interval.duration),
                                  pickups: max(0, app.pickups), categoryName: app.categoryName)
            }
            let onlyOwnUse = clipped.isEmpty && hour.apps.contains { ScreenTimeAppCatalog.isOwnOrTest($0.bundleIdentifier, ownBundleIdentifiers: ownBundleIdentifiers) }
                && hour.apps.allSatisfy { ScreenTimeAppCatalog.isOwnOrTest($0.bundleIdentifier, ownBundleIdentifiers: ownBundleIdentifiers) || $0.seconds <= 0 }
            if onlyOwnUse { return nil }
            guard !clipped.isEmpty || hour.firstPickup != nil || hour.longestActivity != nil else { return nil }
            return ScreenTimeHour(interval: hour.interval, firstPickup: hour.firstPickup, longestActivity: hour.longestActivity, apps: clipped)
        }
    }

    /// Minutes per app inside one detected morning.
    ///
    /// An hour wholly inside the morning counts in full and is measured. So is the part of the
    /// first hour before the start when that hour has a first pickup: nothing came before it.
    /// An hour that runs past the end of the morning is shared out: its apps keep at most
    /// the minutes the morning spent in that hour, in proportion, and are marked estimated.
    static func morning(_ detected: DetectedMorning, hours: [ScreenTimeHour], calendar: Calendar) -> ScreenTimeMorning {
        let start = detected.start, end = detected.end
        let inside = hours.filter { hour in
            end > start ? hour.interval.end > start && hour.interval.start < end
                : hour.interval.start <= start && start < hour.interval.end
        }
        guard let firstHour = inside.first else {
            return ScreenTimeMorning(start: start, end: end, endReason: detected.endReason, timeZone: calendar.timeZone, apps: [])
        }
        struct Total { var seconds: TimeInterval = 0; var measured = true; var firstHour: Date; var category: String? }
        var totals: [String: Total] = [:]
        for hour in inside {
            let leadKnown = hour.interval.start >= start || hour.firstPickup != nil
            let tailKnown = hour.interval.end <= end
            let overlap = max(0, min(hour.interval.end, end).timeIntervalSince(max(hour.interval.start, start)))
            let sum = hour.apps.reduce(0) { $0 + $1.seconds }
            let whole = leadKnown && tailKnown
            // A zero-length morning still owns its hour's use, estimated.
            let share = whole ? 1 : (sum > 0 ? min(1, (end > start ? overlap : hour.interval.duration) / sum) : 0)
            for app in hour.apps {
                let seconds = app.seconds * share
                guard seconds > 0 else { continue }
                var total = totals[app.bundleIdentifier] ?? Total(firstHour: hour.interval.start, category: app.categoryName)
                total.seconds += seconds
                total.measured = total.measured && whole
                total.firstHour = min(total.firstHour, hour.interval.start)
                total.category = total.category ?? app.categoryName
                totals[app.bundleIdentifier] = total
            }
        }
        // The first hour's pickups name the app opened straight from the Lock Screen.
        let firstApp = firstHour.apps.filter { $0.pickups > 0 && totals[$0.bundleIdentifier] != nil }
            .max { $0.pickups != $1.pickups ? $0.pickups < $1.pickups : $0.seconds < $1.seconds }?.bundleIdentifier
        let apps = totals.map { id, total in
            ScreenTimeMorning.AppUse(bundleIdentifier: id, seconds: total.seconds, secondsMeasured: total.measured,
                firstHourIndex: max(0, Int((total.firstHour.timeIntervalSince(firstHour.interval.start) / 3600).rounded(.down))),
                isFirstPickupApp: id == firstApp, categoryName: total.category)
        }.sorted(by: likelyOrder)
        return ScreenTimeMorning(start: start, end: end, endReason: detected.endReason, timeZone: calendar.timeZone, apps: apps)
    }

    private static func likelyOrder(_ lhs: ScreenTimeMorning.AppUse, _ rhs: ScreenTimeMorning.AppUse) -> Bool {
        if lhs.isFirstPickupApp != rhs.isFirstPickupApp { return lhs.isFirstPickupApp }
        if lhs.firstHourIndex != rhs.firstHourIndex { return lhs.firstHourIndex < rhs.firstHourIndex }
        if lhs.seconds != rhs.seconds { return lhs.seconds > rhs.seconds }
        return lhs.bundleIdentifier < rhs.bundleIdentifier
    }
}

public extension ScreenTimeAppCatalog {
    /// MORE itself (any build) or an XCTest runner: use driven by tests, never the owner's routine.
    static func isOwnOrTest(_ bundleIdentifier: String, ownBundleIdentifiers: Set<String> = []) -> Bool {
        let lower = bundleIdentifier.lowercased()
        return ownBundleIdentifiers.contains(bundleIdentifier) || lower == "com.gibouu.morningoperator"
            || lower.hasPrefix("com.gibouu.morningoperator.") || lower.hasPrefix("com.apple.test.")
            || lower.hasSuffix(".xctrunner") || lower.contains("xctest")
    }
}

/// A routine suggested from several mornings of Screen Time. It is saved apart from the
/// routine and changes nothing until the owner approves it; he can leave steps out and
/// change minutes first.
public struct ScreenTimeRoutineProposal: Codable, Equatable, Sendable, Identifiable {
    public static let maximumSteps = 8
    public static let minutesRange = 1...240
    /// Minutes from which a social, video or game app is flagged as a likely scroll.
    public static let attentionSinkMinutes = 15

    public struct Step: Codable, Equatable, Sendable, Identifiable {
        public let id: UUID
        public let bundleIdentifier: String
        public let title: String
        public let kind: ScreenTimeAppCatalog.Kind
        /// Median minutes over the mornings the app was used.
        public let medianMinutes: Int
        public let morningsSeen: Int
        /// True when every contributing hour lay wholly inside its morning.
        public let minutesMeasured: Bool
        /// True only for the first-pickup app when it was first on most mornings; any other
        /// position comes from hourly data and is estimated.
        public let orderMeasured: Bool
        /// Social, video or games with a typical stretch of `attentionSinkMinutes` or more.
        public let isAttentionSink: Bool
        /// Owner's edits before approval.
        public var included: Bool
        public var minutes: Int

        public var isMeasured: Bool { minutesMeasured }
    }

    public let id: UUID
    public let createdAt: Date
    /// The routine this suggestion was made against; approving needs the same one.
    public let baseRoutineID: UUID?
    public let typicalStartMinuteOfDay: Int
    public let timeZoneIdentifier: String
    /// Comparable mornings used, and all the mornings found.
    public let morningsUsed: Int
    public let morningsFound: Int
    /// How far back Screen Time returned data, in local days.
    public let daysOfData: Int
    public private(set) var steps: [Step]

    public var includedSteps: [Step] { steps.filter(\.included) }

    /// Builds the suggestion from mornings of the same kind as `nextMorning` (weekday or
    /// weekend) when at least two exist, otherwise from all of them. Apps used on at least
    /// half of those mornings are kept, with their median minutes; apps under a minute are dropped.
    /// Returns nil when no morning or no app qualifies.
    public static func make(from learning: ScreenTimeLearning, nextMorning: Date, baseRoutineID: UUID?,
                            calendar: Calendar = .current, now: Date = .now) -> ScreenTimeRoutineProposal? {
        let all = learning.mornings.filter { !$0.apps.isEmpty }
        guard !all.isEmpty else { return nil }
        let weekend = calendar.isDateInWeekend(nextMorning)
        let sameKind = all.filter { morning in
            var local = calendar
            local.timeZone = morning.timeZone
            return local.isDateInWeekend(morning.start) == weekend
        }
        let mornings = sameKind.count >= 2 ? sameKind : all
        let needed = max(1, (mornings.count + 1) / 2)

        struct Seen { var seconds: [TimeInterval] = []; var hours: [Int] = []; var first = 0; var measured = true; var category: String? }
        var seen: [String: Seen] = [:]
        for morning in mornings {
            for app in morning.apps where app.seconds >= 30 {
                var item = seen[app.bundleIdentifier] ?? Seen()
                item.seconds.append(app.seconds)
                item.hours.append(app.firstHourIndex)
                if app.isFirstPickupApp { item.first += 1 }
                item.measured = item.measured && app.secondsMeasured
                item.category = item.category ?? app.categoryName
                seen[app.bundleIdentifier] = item
            }
        }
        struct Candidate { let id: String; let minutes: Int; let hour: Double; let first: Int; let item: Seen }
        let candidates = seen.compactMap { id, item -> Candidate? in
            guard item.seconds.count >= needed else { return nil }
            let minutes = Int((median(item.seconds) / 60).rounded())
            guard minutes >= 1 else { return nil }
            return Candidate(id: id, minutes: min(minutes, minutesRange.upperBound), hour: median(item.hours.map(Double.init)), first: item.first, item: item)
        }
        guard !candidates.isEmpty else { return nil }
        // The app opened first on the most mornings leads; ties keep hourly order.
        let leader = candidates.filter { $0.first > 0 }.max { $0.first != $1.first ? $0.first < $1.first : $0.hour > $1.hour }?.id
        let ordered = candidates.sorted { lhs, rhs in
            if (lhs.id == leader) != (rhs.id == leader) { return lhs.id == leader }
            if lhs.hour != rhs.hour { return lhs.hour < rhs.hour }
            if lhs.minutes != rhs.minutes { return lhs.minutes > rhs.minutes }
            return lhs.id < rhs.id
        }.prefix(maximumSteps)
        let steps = ordered.map { candidate in
            let entry = ScreenTimeAppCatalog.entry(for: candidate.id, categoryName: candidate.item.category)
            return Step(id: UUID(), bundleIdentifier: candidate.id, title: entry.name, kind: entry.kind,
                        medianMinutes: candidate.minutes, morningsSeen: candidate.item.seconds.count,
                        minutesMeasured: candidate.item.measured,
                        orderMeasured: candidate.id == leader && candidate.first * 2 >= mornings.count,
                        isAttentionSink: entry.kind.isAttentionSink && candidate.minutes >= attentionSinkMinutes,
                        included: true, minutes: candidate.minutes)
        }
        let starts = mornings.map { Double($0.startMinuteOfDay) }
        return ScreenTimeRoutineProposal(id: UUID(), createdAt: now, baseRoutineID: baseRoutineID,
            typicalStartMinuteOfDay: Int(median(starts).rounded()) % (24 * 60),
            timeZoneIdentifier: calendar.timeZone.identifier, morningsUsed: mornings.count,
            morningsFound: all.count, daysOfData: learning.daysOfData, steps: Array(steps))
    }

    public mutating func setIncluded(_ included: Bool, stepID: UUID) {
        guard let index = steps.firstIndex(where: { $0.id == stepID }) else { return }
        steps[index].included = included
    }

    public mutating func setMinutes(_ minutes: Int, stepID: UUID) {
        guard let index = steps.firstIndex(where: { $0.id == stepID }) else { return }
        steps[index].minutes = min(max(minutes, Self.minutesRange.lowerBound), Self.minutesRange.upperBound)
    }

    /// The draft routine for the included steps, in order. Kept rituals and saved timing
    /// choices of the current routine are carried over the same way as for any suggestion.
    public func draft(preserving base: RoutineVersion?, preferences: RoutinePreferenceJournal, at date: Date = .now) throws -> RoutineVersion {
        let steps = includedSteps.map { step in
            RoutineStep(title: step.title, detail: Self.detail(for: step, of: morningsUsed), kind: step.kind.stepKind,
                        durationMinutes: step.minutes)
        }
        guard !steps.isEmpty else { throw ScreenTimeProposalError.nothingIncluded }
        let candidate = RoutineVersion(createdAt: date, sourceLabel: String(localized: "From Screen Time", bundle: .module), steps: steps)
        // As for any suggestion, kept moments come back only through the journal.
        let inheritance = base.map { prior -> RoutineVersion in var copy = prior; copy.steps = []; return copy }
        let inferred = RoutineVersion.inferredDraft(from: candidate, preserving: inheritance, at: date)
        var routine = inferred
        routine.steps = try preferences.reconcile(steps: inferred.steps).steps
        return routine
    }

    static func detail(for step: Step, of mornings: Int) -> String {
        let usual = String(localized: "Usually \(step.medianMinutes) min, on \(step.morningsSeen) of \(mornings) mornings.", bundle: .module)
        let label = step.minutesMeasured
            ? String(localized: "Measured by Screen Time.", bundle: .module)
            : String(localized: "Estimated from hourly Screen Time.", bundle: .module)
        return usual + " " + label
    }

    /// Bounds checked when a saved suggestion is read back.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        baseRoutineID = try values.decodeIfPresent(UUID.self, forKey: .baseRoutineID)
        typicalStartMinuteOfDay = try values.decode(Int.self, forKey: .typicalStartMinuteOfDay)
        timeZoneIdentifier = try values.decode(String.self, forKey: .timeZoneIdentifier)
        morningsUsed = try values.decode(Int.self, forKey: .morningsUsed)
        morningsFound = try values.decode(Int.self, forKey: .morningsFound)
        daysOfData = try values.decode(Int.self, forKey: .daysOfData)
        steps = try values.decode([Step].self, forKey: .steps)
        guard (0..<(24 * 60)).contains(typicalStartMinuteOfDay), (1...60).contains(morningsUsed),
              (morningsUsed...60).contains(morningsFound), (0...60).contains(daysOfData),
              (1...Self.maximumSteps).contains(steps.count), Set(steps.map(\.id)).count == steps.count,
              steps.allSatisfy({ step in
                  !step.title.isEmpty && step.title.count <= 120 && step.bundleIdentifier.count <= 255
                      && Self.minutesRange.contains(step.minutes) && Self.minutesRange.contains(step.medianMinutes)
                      && (1...morningsUsed).contains(step.morningsSeen)
              }) else { throw ScreenTimeProposalError.invalidProposal }
    }

    private init(id: UUID, createdAt: Date, baseRoutineID: UUID?, typicalStartMinuteOfDay: Int, timeZoneIdentifier: String,
                 morningsUsed: Int, morningsFound: Int, daysOfData: Int, steps: [Step]) {
        self.id = id; self.createdAt = createdAt; self.baseRoutineID = baseRoutineID
        self.typicalStartMinuteOfDay = typicalStartMinuteOfDay; self.timeZoneIdentifier = timeZoneIdentifier
        self.morningsUsed = morningsUsed; self.morningsFound = morningsFound; self.daysOfData = daysOfData; self.steps = steps
    }
}

public enum ScreenTimeProposalError: Error, Equatable, Sendable {
    case nothingIncluded, invalidProposal
}

private func median(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    let middle = sorted.count / 2
    return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
}
