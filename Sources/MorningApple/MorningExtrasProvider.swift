import Contacts
import CoreLocation
import Foundation
import MorningCore
import Observation
import WeatherKit

// The readers behind the morning extras. Every reader is injected and every read is
// bounded; a reader that is missing, not permitted, failed or late produces no fact, and
// a missing fact is silence. Nothing read here is saved: only the person's choices and the
// day each kind was last said go to `morning-extras.json`.

/// Steps per local day. The HealthKit reader lives in MorningHealth.
@MainActor
public protocol StepCountProviding {
    /// The summed step count of each interval, in order, or nil for an interval with no
    /// recorded sample. Never prompts. A refused read looks like no samples.
    func stepTotals(for days: [DateInterval]) async throws -> [Int?]
}

/// Sleep and steps through one Health permission.
@MainActor
public protocol MorningHealthExtrasProviding: SleepObservationProviding, StepCountProviding {
    /// Shows Apple's Health prompt for sleep analysis and step count, once. Call only from
    /// the person turning an extra on. Returning does not mean reading was allowed.
    func requestExtrasAccess() async throws
}

/// The hook for Screen Time (built elsewhere). No implementation ships with this change:
/// until one is injected, the screen-time extra is silent.
@MainActor
public protocol ScreenTimeSummaryProviding {
    /// Minutes of screen time per interval, nil for an interval without coverage.
    func screenTimeMinutes(for days: [DateInterval]) async throws -> [Int?]
}

/// Contact birthdays. The native reader uses Contacts.
@MainActor
public protocol BirthdayProviding {
    var isAuthorized: Bool { get }
    /// Call only from the person turning the birthday extra on.
    func requestAccess() async throws -> Bool
    /// Display names of contacts whose birthday is on this month and day. Never prompts.
    func names(bornOn month: Int, day: Int) async throws -> [String]
}

/// Forecast values for the weather-change extra. Memory only.
public struct WeatherOutlook: Sendable, Equatable {
    public struct Hour: Sendable, Equatable {
        public let start: Date
        /// 0 to 1.
        public let chance: Double
        /// Nil when the hour has no precipitation type.
        public let kind: MorningExtraPrecipitation?
        public init(start: Date, chance: Double, kind: MorningExtraPrecipitation?) {
            self.start = start; self.chance = chance; self.kind = kind
        }
    }
    public let yesterdayHighCelsius: Double?
    public let todayHighCelsius: Double?
    public let hours: [Hour]

    public init(yesterdayHighCelsius: Double?, todayHighCelsius: Double?, hours: [Hour]) {
        self.yesterdayHighCelsius = yesterdayHighCelsius; self.todayHighCelsius = todayHighCelsius; self.hours = hours
    }
}

/// The local-day frame every reader is given, built once per preparation.
public struct MorningExtrasFrame: Sendable, Equatable {
    public let now: Date
    public let timeZone: TimeZone
    public let todayStart: Date
    public let todayEnd: Date
    /// Yesterday first, then the seven days before it, newest first.
    public let yesterday: DateInterval
    public let previousWeek: [DateInterval]

    public init?(now: Date, timeZone: TimeZone) {
        guard now.timeIntervalSinceReferenceDate.isFinite else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        // Each day is the calendar's own interval, so a day across a clock change is 23 or 25
        // hours long, and a day that starts at 01:00 (a midnight clock change) starts there.
        guard let today = calendar.dateInterval(of: .day, for: now) else { return nil }
        var days: [DateInterval] = []
        var previousStart = today.start
        for _ in 0..<8 {
            guard let day = calendar.dateInterval(of: .day, for: previousStart.addingTimeInterval(-1)) else { return nil }
            days.append(day)
            previousStart = day.start
        }
        self.now = now; self.timeZone = timeZone; todayStart = today.start; todayEnd = today.end
        yesterday = days[0]; previousWeek = Array(days.dropFirst())
    }
}

/// The pure steps from read values to facts. Kept apart from the readers so each rule has a test.
public enum MorningExtrasFacts {
    /// A seven-day mean needs at least this many days with a record.
    public static let minimumAverageDays = 4
    /// An hour counts as "precipitation likely" from this chance.
    public static let precipitationChance = 0.5
    /// Two events closer than this make a tight gap.
    public static var tightGapMinutes: Int { MorningExtrasComposer.tightGapMinutes }

    public static func sleep(_ input: SleepBriefingInput, at now: Date, timeZone: TimeZone) -> MorningExtraFact? {
        guard case .snapshot(let snapshot) = input else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        if case .recorded(let night) = SleepNight.summarize(snapshot.samples, readAt: snapshot.readAt, at: now, calendar: calendar) {
            return .sleptMinutes(night.asleepMinutes)
        }
        return SleepNight.inBedMinutes(snapshot.samples, at: now, calendar: calendar).map(MorningExtraFact.inBedMinutes)
    }

    /// `values[0]` is yesterday, the rest the week before. Nil, negative or zero is no record.
    public static func steps(_ values: [Int?]) -> MorningExtraFact? {
        guard let yesterday = values.first ?? nil, yesterday > 0 else { return nil }
        return .steps(yesterday: yesterday, weeklyAverage: average(Array(values.dropFirst())))
    }

    public static func screenTime(_ values: [Int?]) -> MorningExtraFact? {
        guard let yesterday = values.first ?? nil, yesterday > 0 else { return nil }
        return .screenTime(yesterdayMinutes: yesterday, weeklyAverageMinutes: average(Array(values.dropFirst())))
    }

    /// The mean of the recorded days. A recorded zero is a real day and counts; nil is no
    /// record and is left out. A zero or invalid mean gives no comparison.
    static func average(_ values: [Int?]) -> Int? {
        let recorded = values.compactMap { $0 }
        guard recorded.count >= minimumAverageDays, recorded.allSatisfy({ $0 >= 0 }) else { return nil }
        let mean = Int((Double(recorded.reduce(0, +)) / Double(recorded.count)).rounded())
        return mean > 0 ? mean : nil
    }

    /// Today's and yesterday's highs from daily entries dated by their start in the city's
    /// time zone. Today is the entry whose 20 to 26 hours contain `now` (a city day can be
    /// 23 or 25 hours); yesterday is the entry just before it, 20 to 26 hours earlier.
    /// Anything else is no record.
    public static func cityDayHighs(_ days: [(start: Date, highCelsius: Double)], now: Date) -> (yesterday: Double?, today: Double?) {
        let sorted = days.filter { $0.start.timeIntervalSinceReferenceDate.isFinite }.sorted { $0.start < $1.start }
        // Today must be bounded: the next entry starts after now, 20 to 26 hours after today's.
        // Without that successor nothing proves today's entry is still today.
        guard let index = sorted.lastIndex(where: { $0.start <= now }), index + 1 < sorted.count,
              (20 * 3_600...26 * 3_600).contains(sorted[index + 1].start.timeIntervalSince(sorted[index].start))
        else { return (nil, nil) }
        let today = sorted[index]
        guard index > 0 else { return (nil, today.highCelsius) }
        let previous = sorted[index - 1]
        let gap = today.start.timeIntervalSince(previous.start)
        return ((20 * 3_600...26 * 3_600).contains(gap) ? previous.highCelsius : nil, today.highCelsius)
    }

    /// Precipitation later today comes first; otherwise a notable change of the daily high.
    /// Hours are taken from the start of the current hour to the end of today.
    public static func weather(_ outlook: WeatherOutlook, frame: MorningExtrasFrame,
                               unit: MorningExtraTemperatureUnit) -> [MorningExtraFact] {
        var facts: [MorningExtraFact] = []
        let hourStart = frame.now.addingTimeInterval(-3_600)
        if let hour = outlook.hours.filter({
            $0.start.timeIntervalSinceReferenceDate.isFinite && $0.start > hourStart && $0.start < frame.todayEnd
                && $0.chance.isFinite && $0.chance >= precipitationChance && $0.chance <= 1 && $0.kind != nil
        }).min(by: { $0.start < $1.start }), let kind = hour.kind {
            facts.append(.precipitation(kind, from: hour.start <= frame.now ? nil : hour.start))
        }
        if let today = outlook.todayHighCelsius, let yesterday = outlook.yesterdayHighCelsius,
           today.isFinite, yesterday.isFinite {
            facts.append(.temperatureChange(celsiusDelta: today - yesterday, unit: unit))
        }
        return facts
    }

    /// The first overlap or tight gap among today's timed events that have not ended, where
    /// the later event starts from now on: a clash already under way is not news, and its
    /// start may be on another day. All-day events never clash with anything.
    public static func calendar(_ events: [CalendarEventSummary], frame: MorningExtrasFrame) -> MorningExtraFact? {
        let timed = events.filter {
            !$0.isAllDay && $0.end > $0.start && $0.end > frame.now && $0.start < frame.todayEnd
                && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.sorted { ($0.start, $0.end) < ($1.start, $1.end) }
        guard var previous = timed.first else { return nil }
        for event in timed.dropFirst() {
            if event.start < previous.end, event.start >= frame.now {
                return .calendarConflict(first: previous.title, second: event.title, at: event.start)
            }
            let gap = Int(event.start.timeIntervalSince(previous.end) / 60)
            if event.start >= frame.now, gap < tightGapMinutes {
                return .tightGap(minutes: gap, first: previous.title, second: event.title, at: event.start)
            }
            if event.end > previous.end { previous = event }
        }
        return nil
    }
}

/// Saves the person's choices and the rotation record. Kinds and day numbers only.
@MainActor
public final class MorningExtrasPreferencesStore {
    public static let fileName = "morning-extras.json"
    private let file: AtomicJSONFile<MorningExtrasPreferences>
    private let control: LocalDataControl

    public init(directory: URL = LocalDataControl.defaultDirectory) {
        file = AtomicJSONFile(url: directory.appendingPathComponent(Self.fileName), maximumBytes: 16_384)
        control = LocalDataControl(directory: directory)
    }

    /// Defaults when there is no file. An unreadable file also gives the defaults; it is
    /// replaced only by the next explicit change.
    public func load() -> MorningExtrasPreferences {
        let loaded: MorningExtrasPreferences?? = try? control.withReadyAccess { _ in try? file.load() }
        return (loaded ?? nil) ?? .init()
    }

    public func save(_ preferences: MorningExtrasPreferences) throws {
        try control.withReadyAccess { _ in try file.save(preferences) }
    }
}

/// Prepares the extras for one morning. No work happens without an explicit call; reading
/// never prompts; asking for access happens only through the `request…` methods.
@MainActor @Observable
public final class MorningExtrasProvider {
    public typealias WeatherOutlookProvider = @MainActor (WeatherLocation, MorningExtrasFrame) async throws -> WeatherOutlook
    public typealias CalendarEventsProvider = @MainActor (MorningExtrasFrame) async throws -> [CalendarEventSummary]

    public private(set) var preferences: MorningExtrasPreferences
    @ObservationIgnored private let store: MorningExtrasPreferencesStore?
    @ObservationIgnored private let health: (any MorningHealthExtrasProviding)?
    @ObservationIgnored private let screenTime: (any ScreenTimeSummaryProviding)?
    @ObservationIgnored private let birthdays: (any BirthdayProviding)?
    @ObservationIgnored private let weatherOutlook: WeatherOutlookProvider?
    @ObservationIgnored private let timeout: Duration

    public init(store: MorningExtrasPreferencesStore?, health: (any MorningHealthExtrasProviding)? = nil,
                screenTime: (any ScreenTimeSummaryProviding)? = nil, birthdays: (any BirthdayProviding)? = nil,
                weatherOutlook: WeatherOutlookProvider? = nil, timeout: Duration = .seconds(4)) {
        self.store = store; self.health = health; self.screenTime = screenTime
        self.birthdays = birthdays; self.weatherOutlook = weatherOutlook
        self.timeout = min(max(timeout, .milliseconds(1)), .seconds(10))
        preferences = store?.load() ?? .init()
    }

    /// Which kinds this build can read at all. A kind without a reader is shown as unavailable.
    public func isConnected(_ kind: MorningExtraKind) -> Bool {
        switch kind {
        case .sleep, .steps: health != nil
        case .screenTime: screenTime != nil
        case .birthday: birthdays != nil
        case .weatherChange: weatherOutlook != nil
        case .calendar: true
        }
    }

    public var birthdaysAuthorized: Bool { birthdays?.isAuthorized ?? false }

    public func reload() { preferences = store?.load() ?? .init() }

    /// Turns a kind on or off. Turning sleep, steps or birthdays on is the one moment their
    /// permission prompt may appear; turning anything off never prompts.
    public func setEnabled(_ kind: MorningExtraKind, _ on: Bool) async throws {
        var next = preferences
        if on { next.enabled.insert(kind) } else { next.enabled.remove(kind) }
        if on, kind == .sleep || kind == .steps, let health {
            try await health.requestExtrasAccess()
            next.healthAccessRequested = true
        }
        if on, kind == .birthday, let birthdays, !birthdays.isAuthorized {
            _ = try await birthdays.requestAccess()
        }
        try save(next)
    }

    /// Default-on sleep and steps still need the Health prompt once. Settings offers it.
    public func requestHealthAccess() async throws {
        guard let health else { return }
        try await health.requestExtrasAccess()
        var next = preferences; next.healthAccessRequested = true
        try save(next)
    }

    /// True when a preparation could find something: an enabled kind with a reader that can
    /// answer without a prompt. When false the opening does not wait for extras at all.
    public func hasReadableSources(weatherLocation: WeatherLocation?, calendarSelected: Bool) -> Bool {
        preferences.enabled.contains { readable($0, weatherLocation: weatherLocation, calendarSelected: calendarSelected) }
    }

    private func readable(_ kind: MorningExtraKind, weatherLocation: WeatherLocation?, calendarSelected: Bool) -> Bool {
        switch kind {
        case .sleep, .steps: health != nil && preferences.healthAccessRequested
        case .screenTime: screenTime != nil
        case .birthday: birthdays?.isAuthorized == true
        case .weatherChange: weatherOutlook != nil && weatherLocation != nil
        case .calendar: calendarSelected
        }
    }

    /// Reads every enabled, readable source at the same time, each within the deadline, and
    /// composes at most three sentences. Never throws: a failed source is silent.
    public func prepare(now: Date, timeZone: TimeZone, localeIdentifier: String,
                        weatherLocation: WeatherLocation?, temperatureUnit: MorningExtraTemperatureUnit,
                        calendarEvents: CalendarEventsProvider?) async -> MorningExtrasSelection {
        guard let frame = MorningExtrasFrame(now: now, timeZone: timeZone),
              let day = MorningExtrasDay.number(for: now, timeZone: timeZone) else { return .empty }
        let enabled = preferences.enabled
        func wants(_ kind: MorningExtraKind) -> Bool {
            enabled.contains(kind) && readable(kind, weatherLocation: weatherLocation, calendarSelected: calendarEvents != nil)
        }
        let timeout = timeout
        let health = wants(.sleep) || wants(.steps) ? health : nil
        let screenTime = wants(.screenTime) ? screenTime : nil
        let birthdays = wants(.birthday) ? birthdays : nil
        let outlook = wants(.weatherChange) ? weatherOutlook : nil
        let events = wants(.calendar) ? calendarEvents : nil

        let sleepTask = Task { @MainActor () -> MorningExtraFact? in
            guard wants(.sleep), let health else { return nil }
            return await ExtrasDeadline.run(timeout) {
                let read = try await health.sleepSamples(in: DateInterval(start: now.addingTimeInterval(-2 * 86_400), end: now))
                guard case .samples(let values) = read else { return nil }
                return MorningExtrasFacts.sleep(.snapshot(.init(readAt: now, samples: values)), at: now, timeZone: timeZone)
            }
        }
        let days = [frame.yesterday] + frame.previousWeek
        let stepTask = Task { @MainActor () -> MorningExtraFact? in
            guard wants(.steps), let health else { return nil }
            return await ExtrasDeadline.run(timeout) {
                let values = try await health.stepTotals(for: days)
                return values.count == days.count ? MorningExtrasFacts.steps(values) : nil
            }
        }
        let screenTask = Task { @MainActor () -> MorningExtraFact? in
            guard let screenTime else { return nil }
            return await ExtrasDeadline.run(timeout) {
                let values = try await screenTime.screenTimeMinutes(for: days)
                return values.count == days.count ? MorningExtrasFacts.screenTime(values) : nil
            }
        }
        let birthdayTask = Task { @MainActor () -> MorningExtraFact? in
            guard let birthdays else { return nil }
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
            let parts = calendar.dateComponents([.month, .day], from: now)
            guard let month = parts.month, let dayOfMonth = parts.day else { return nil }
            return await ExtrasDeadline.run(timeout) {
                let names = try await birthdays.names(bornOn: month, day: dayOfMonth)
                return names.isEmpty ? nil : .birthdays(names)
            }
        }
        let weatherTask = Task { @MainActor () -> [MorningExtraFact]? in
            guard let outlook, let weatherLocation else { return nil }
            return await ExtrasDeadline.run(timeout) {
                MorningExtrasFacts.weather(try await outlook(weatherLocation, frame), frame: frame, unit: temperatureUnit)
            }
        }
        let calendarTask = Task { @MainActor () -> MorningExtraFact? in
            guard let events else { return nil }
            return await ExtrasDeadline.run(timeout) { MorningExtrasFacts.calendar(try await events(frame), frame: frame) }
        }
        let single = [sleepTask, stepTask, screenTask, birthdayTask, calendarTask]
        let facts = await withTaskCancellationHandler {
            var facts: [MorningExtraFact] = []
            for task in single { if let fact = await task.value { facts.append(fact) } }
            return facts + ((await weatherTask.value) ?? [])
        } onCancel: {
            for task in single { task.cancel() }
            weatherTask.cancel()
        }
        guard !Task.isCancelled else { return .empty }
        return MorningExtrasComposer.compose(facts: facts, preferences: preferences, day: day,
                                             localeIdentifier: localeIdentifier, timeZoneIdentifier: timeZone.identifier)
    }

    /// Records the kinds that were actually presented, for rotation. A failed save only
    /// weakens rotation; it never blocks the morning.
    public func recordSpoken(_ selection: MorningExtrasSelection, now: Date, timeZone: TimeZone) {
        guard !selection.items.isEmpty, let day = MorningExtrasDay.number(for: now, timeZone: timeZone) else { return }
        var next = preferences
        next.recordSpoken(selection.kinds, day: day)
        try? save(next)
    }

    private func save(_ next: MorningExtrasPreferences) throws {
        if let store { try store.save(next) }
        preferences = next
    }

}

/// The first of a read and its deadline, on the main actor like the readers. A late,
/// failed or cancelled read is nil; a late answer has no recipient.
@MainActor
private final class ExtrasDeadline<Value: Sendable> {
    private var continuation: CheckedContinuation<Value?, Never>?
    private var operation: Task<Void, Never>?
    private var timer: Task<Void, Never>?

    static func run(_ timeout: Duration, _ body: @escaping @MainActor () async throws -> Value?) async -> Value? {
        let race = ExtrasDeadline()
        let started = ContinuousClock.now
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                race.continuation = continuation
                race.operation = Task { @MainActor in
                    let value = try? await body()
                    // A synchronous read can hold the main actor past the timer; its answer is
                    // still late and is dropped.
                    race.finish(ContinuousClock.now - started <= timeout ? value : nil)
                }
                race.timer = Task { @MainActor in
                    do { try await Task.sleep(for: timeout) } catch { return }
                    race.finish(nil)
                }
            }
        } onCancel: {
            Task { @MainActor in race.finish(nil) }
        }
    }

    private func finish(_ value: Value?) {
        guard let waiting = continuation else { return }
        continuation = nil
        operation?.cancel(); timer?.cancel()
        operation = nil; timer = nil
        waiting.resume(returning: value)
    }
}

// MARK: - Native readers

/// Contacts birthdays, read-only. Names are returned for one sentence and kept nowhere.
@MainActor
public final class ContactsBirthdayReader: BirthdayProviding {
    public init() {}

    public var isAuthorized: Bool {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        #if os(iOS)
        return status == .authorized || status == .limited
        #else
        return status == .authorized
        #endif
    }

    public func requestAccess() async throws -> Bool {
        guard Bundle.main.object(forInfoDictionaryKey: "NSContactsUsageDescription") is String else { return false }
        return try await CNContactStore().requestAccess(for: .contacts)
    }

    public func names(bornOn month: Int, day: Int) async throws -> [String] {
        guard isAuthorized else { return [] }
        return try await Task.detached(priority: .utility) {
            let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactNicknameKey, CNContactBirthdayKey] as [CNKeyDescriptor]
            let request = CNContactFetchRequest(keysToFetch: keys)
            var names: [String] = []
            try CNContactStore().enumerateContacts(with: request) { contact, stop in
                guard let birthday = contact.birthday, birthday.month == month, birthday.day == day else { return }
                let nickname = contact.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
                let given = contact.givenName.trimmingCharacters(in: .whitespacesAndNewlines)
                let name = nickname.isEmpty ? (given.isEmpty ? contact.familyName : given) : nickname
                if !name.isEmpty { names.append(name) }
                // Every match counts toward "and N others"; this bound only guards memory.
                if names.count >= 1_000 { stop.pointee = true }
            }
            return names
        }.value
    }
}

public enum NativeWeatherOutlook {
    /// One WeatherKit request: daily highs around today, hourly for the rest of today.
    /// WeatherKit dates its days in the city's own time zone, which can be far from the
    /// device's, so the query is two days wider on each side and the days are matched by
    /// position: "today" is the city's day that contains now, "yesterday" the one before it.
    public static func read(_ location: WeatherLocation, frame: MorningExtrasFrame) async throws -> WeatherOutlook {
        let native = CLLocation(latitude: location.latitude, longitude: location.longitude)
        let hourStart = frame.now.addingTimeInterval(-3_600)
        let (daily, hourly) = try await WeatherService.shared.weather(for: native,
            including: .daily(startDate: frame.yesterday.start.addingTimeInterval(-2 * 86_400),
                              endDate: frame.todayEnd.addingTimeInterval(2 * 86_400)),
            .hourly(startDate: hourStart, endDate: frame.todayEnd))
        let highs = MorningExtrasFacts.cityDayHighs(daily.forecast.map {
            (start: $0.date, highCelsius: $0.highTemperature.converted(to: .celsius).value)
        }, now: frame.now)
        let hours = hourly.forecast.map { hour -> WeatherOutlook.Hour in
            let kind: MorningExtraPrecipitation?
            switch hour.precipitation {
            case .none: kind = nil
            case .rain: kind = .rain
            case .snow: kind = .snow
            default: kind = .mixed
            }
            return .init(start: hour.date, chance: hour.precipitationChance, kind: kind)
        }
        return WeatherOutlook(yesterdayHighCelsius: highs.yesterday, todayHighCelsius: highs.today, hours: hours)
    }
}
