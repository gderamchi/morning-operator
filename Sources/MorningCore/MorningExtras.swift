import Foundation

// Short morning extras: a few facts people find useful but rarely check, said in five to
// ten seconds after the opening's own facts. This file is pure: it reads nothing, saves
// nothing and speaks nothing. Readers live in MorningApple; the app decides when to ask.
//
// The rules that protect what is said:
// - No data is silence. A fact that was not read, was not permitted or found no record is
//   simply absent; it is never said as zero.
// - Numbers are said in the unit they were measured in, converted only where a unit choice
//   exists (temperature), and a temperature *difference* is converted without the +32 offset.
// - Clock times are written in the time zone the caller passes (the device's, like the briefing).

/// One kind of extra. The person turns each on or off in Settings → Your day.
public enum MorningExtraKind: String, Codable, Sendable, CaseIterable {
    case sleep, steps, screenTime, weatherChange, calendar, birthday

    /// On until the person turns them off. The others need a choice first.
    public static let defaultEnabled: Set<MorningExtraKind> = [.sleep, .steps, .weatherChange]

    /// Facts about today that are worth saying whenever they exist. They are not rotated:
    /// a clash at 10:00 is as useful on Tuesday as it was on Monday.
    public var isTimely: Bool {
        switch self {
        case .calendar, .birthday: true
        case .sleep, .steps, .screenTime, .weatherChange: false
        }
    }
}

public enum MorningExtraTemperatureUnit: String, Codable, Sendable, CaseIterable {
    case celsius, fahrenheit
}

public enum MorningExtraPrecipitation: String, Codable, Sendable, CaseIterable {
    case rain, snow, mixed
}

/// One fact a reader produced. Values only: no source object, no sample, no identifier.
public enum MorningExtraFact: Sendable, Equatable {
    /// Time recorded as asleep since yesterday evening, in whole minutes.
    case sleptMinutes(Int)
    /// Only "in bed" was recorded since yesterday evening (an iPhone sleep schedule without a
    /// watch records this). Time in bed is said as time in bed, never as sleep.
    case inBedMinutes(Int)
    /// Steps on yesterday's local day, with the mean of the seven days before it when enough of
    /// those days have a record. Days without a record are left out of the mean, not counted as zero.
    case steps(yesterday: Int, weeklyAverage: Int?)
    /// Screen time on yesterday's local day, in minutes, with the mean of the week before it.
    case screenTime(yesterdayMinutes: Int, weeklyAverageMinutes: Int?)
    /// Today's forecast high minus yesterday's, in degrees Celsius, as read. The sentence
    /// converts the difference into the person's unit.
    case temperatureChange(celsiusDelta: Double, unit: MorningExtraTemperatureUnit)
    /// Precipitation is likely later today from `from`, or already in the current hour when nil.
    case precipitation(MorningExtraPrecipitation, from: Date?)
    /// Two events of today that overlap; `at` is the start of the later one.
    case calendarConflict(first: String, second: String, at: Date)
    /// Two consecutive events of today with a short gap; `at` is the start of the second.
    case tightGap(minutes: Int, first: String, second: String, at: Date)
    /// Contacts whose birthday is today. Names are spoken, never stored.
    case birthdays([String])

    public var kind: MorningExtraKind {
        switch self {
        case .sleptMinutes, .inBedMinutes: .sleep
        case .steps: .steps
        case .screenTime: .screenTime
        case .temperatureChange, .precipitation: .weatherChange
        case .calendarConflict, .tightGap: .calendar
        case .birthdays: .birthday
        }
    }
}

/// What the person chose and what was said on which day. Saved in `morning-extras.json`:
/// kinds and day numbers only, never a value, a name or a sentence.
public struct MorningExtrasPreferences: Codable, Sendable, Equatable {
    public var enabled: Set<MorningExtraKind>
    /// True once the person answered Apple's Health prompt from Settings. Until then sleep and
    /// steps are not read at all, so the opening never waits on a source that cannot answer.
    public var healthAccessRequested: Bool
    /// For each kind, the local day number (see `MorningExtrasDay`) on which it was last said.
    public var lastSpokenDay: [String: Int]

    public init(enabled: Set<MorningExtraKind> = MorningExtraKind.defaultEnabled,
                healthAccessRequested: Bool = false, lastSpokenDay: [String: Int] = [:]) {
        self.enabled = enabled
        self.healthAccessRequested = healthAccessRequested
        self.lastSpokenDay = lastSpokenDay
    }

    private enum CodingKeys: String, CodingKey { case enabled, healthAccessRequested, lastSpokenDay }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // An unknown kind from a later build is dropped, not a reason to lose every choice.
        let names = try values.decode([String].self, forKey: .enabled)
        enabled = Set(names.compactMap(MorningExtraKind.init(rawValue:)))
        healthAccessRequested = try values.decodeIfPresent(Bool.self, forKey: .healthAccessRequested) ?? false
        let days = try values.decodeIfPresent([String: Int].self, forKey: .lastSpokenDay) ?? [:]
        lastSpokenDay = days.filter { MorningExtraKind(rawValue: $0.key) != nil }
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(enabled.map(\.rawValue).sorted(), forKey: .enabled)
        try values.encode(healthAccessRequested, forKey: .healthAccessRequested)
        try values.encode(lastSpokenDay, forKey: .lastSpokenDay)
    }

    /// Records that these kinds were said on `day`. Nothing else changes.
    public mutating func recordSpoken(_ kinds: [MorningExtraKind], day: Int) {
        for kind in kinds { lastSpokenDay[kind.rawValue] = day }
    }
}

/// A local calendar day as a whole number, so "said yesterday" survives travel and DST.
public enum MorningExtrasDay {
    /// The year, month and day on the wall clock of `timeZone`, counted as days since
    /// 1 January 2001. Two instants on the same local date give the same number.
    public static func number(for date: Date, timeZone: TimeZone) -> Int? {
        guard date.timeIntervalSinceReferenceDate.isFinite else { return nil }
        var local = Calendar(identifier: .gregorian); local.timeZone = timeZone
        let parts = local.dateComponents([.year, .month, .day], from: date)
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        guard let midnight = utc.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day)) else { return nil }
        return Int((midnight.timeIntervalSinceReferenceDate / 86_400).rounded(.down))
    }
}

public struct MorningExtraItem: Sendable, Equatable, Identifiable {
    public let kind: MorningExtraKind
    public let text: String
    public var id: String { kind.rawValue }
}

public struct MorningExtrasSelection: Sendable, Equatable {
    public let items: [MorningExtraItem]
    public var kinds: [MorningExtraKind] { items.map(\.kind) }
    public var text: String { items.map(\.text).joined(separator: " ") }
    /// The estimate the budget was checked against, in seconds.
    public let estimatedSeconds: Double
    /// The local day (see `MorningExtrasDay`) these sentences are about. "Today" and
    /// "yesterday" are true only on that day; a caller drops them on another day.
    public let day: Int?
    /// The time zone its clock times are written in.
    public let timeZoneIdentifier: String?
    public init(items: [MorningExtraItem], estimatedSeconds: Double, day: Int? = nil, timeZoneIdentifier: String? = nil) {
        self.items = items; self.estimatedSeconds = estimatedSeconds; self.day = day
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    /// True only on the same local day and in the same time zone it was prepared for.
    public func isCurrent(day: Int?, timeZoneIdentifier: String) -> Bool {
        self.day != nil && self.day == day && self.timeZoneIdentifier == timeZoneIdentifier
    }
    public static let empty = MorningExtrasSelection(items: [], estimatedSeconds: 0)

    /// The same selection without one kind, for a caller that cannot present it (for example
    /// weather without its required attribution). The budget only shrinks.
    public func removing(_ kind: MorningExtraKind) -> MorningExtrasSelection {
        let kept = items.filter { $0.kind != kind }
        return .init(items: kept, estimatedSeconds: kept.reduce(0) { $0 + MorningExtrasComposer.estimatedSeconds($1.text) },
                     day: day, timeZoneIdentifier: timeZoneIdentifier)
    }
}

public enum MorningExtrasComposer {
    public static let maximumItems = 3
    /// The whole set is kept under this many seconds of speech.
    public static let speechBudgetSeconds: Double = 10
    /// A calm system voice says about 2.5 words a second. Numbers count as the words they become.
    public static let wordsPerSecond: Double = 2.5
    /// A temperature change is worth saying from this many degrees Celsius (9 °F).
    public static let notableCelsiusDelta: Double = 5
    /// Two events closer than this many minutes make a tight gap.
    public static let tightGapMinutes = 10
    /// The step comparison says "close to" within this share of the mean.
    public static let closeShare: Double = 0.1

    /// Deterministic: same facts, choices, history and day give the same sentences.
    ///
    /// 1. Facts whose kind is off, or whose values are not plausible, are dropped.
    /// 2. Each kind keeps one fact, the most useful one it supplied.
    /// 3. Facts are scored: a priority per kind, more when a value is notable, less when a
    ///    rotated kind was said yesterday or the day before. Timely kinds are never rotated.
    /// 4. The best are taken in score order while there are fewer than three and the estimate
    ///    stays within ten seconds. A fact that alone would break the budget is skipped.
    public static func compose(facts: [MorningExtraFact], preferences: MorningExtrasPreferences,
                               day: Int, localeIdentifier: String, timeZoneIdentifier: String) -> MorningExtrasSelection {
        guard let zone = TimeZone(identifier: timeZoneIdentifier) else { return .empty }
        let phrases = MorningExtrasPhrases(french: Locale(identifier: localeIdentifier).language.languageCode?.identifier == "fr",
                                           locale: Locale(identifier: localeIdentifier), timeZone: zone)
        var best: [MorningExtraKind: (fact: MorningExtraFact, score: Double)] = [:]
        for fact in facts where preferences.enabled.contains(fact.kind) {
            guard let base = score(fact) else { continue }
            if let current = best[fact.kind], current.score >= base { continue }
            best[fact.kind] = (fact, base)
        }
        let ranked = best.map { kind, entry -> (MorningExtraKind, MorningExtraFact, Double) in
            (kind, entry.fact, entry.score - rotationPenalty(kind, preferences: preferences, day: day))
        }.sorted { lhs, rhs in
            lhs.2 != rhs.2 ? lhs.2 > rhs.2 : MorningExtraKind.allCases.firstIndex(of: lhs.0)! < MorningExtraKind.allCases.firstIndex(of: rhs.0)!
        }
        var items: [MorningExtraItem] = []
        var seconds: Double = 0
        for (kind, fact, _) in ranked where items.count < maximumItems {
            guard let text = phrases.sentence(fact) else { continue }
            let cost = estimatedSeconds(text)
            guard seconds + cost <= speechBudgetSeconds else { continue }
            items.append(.init(kind: kind, text: text))
            seconds += cost
        }
        return .init(items: items, estimatedSeconds: seconds, day: day, timeZoneIdentifier: timeZoneIdentifier)
    }

    public static func estimatedSeconds(_ text: String) -> Double {
        let words = text.split { $0.isWhitespace }.count
        return Double(words) / wordsPerSecond
    }

    /// Nil when the fact cannot be said truthfully: empty, negative, not finite or not notable.
    static func score(_ fact: MorningExtraFact) -> Double? {
        switch fact {
        case .calendarConflict(let first, let second, _):
            return valid(first) && valid(second) ? 100 : nil
        case .tightGap(let minutes, let first, let second, _):
            return valid(first) && valid(second) && (0..<tightGapMinutes).contains(minutes) ? 95 : nil
        case .precipitation(_, let from):
            return from.map { $0.timeIntervalSinceReferenceDate.isFinite } ?? true ? 90 : nil
        case .birthdays(let names):
            return names.contains(where: valid) ? 85 : nil
        case .temperatureChange(let delta, _):
            guard delta.isFinite, abs(delta) >= notableCelsiusDelta, abs(delta) < 60 else { return nil }
            return 70 + min(abs(delta), 20)
        case .sleptMinutes(let minutes), .inBedMinutes(let minutes):
            guard minutes > 0, minutes < 24 * 60 else { return nil }
            if case .inBedMinutes = fact { return 55 }
            return 60
        case .steps(let yesterday, let average):
            guard yesterday > 0, yesterday < 200_000, average.map({ $0 > 0 && $0 < 200_000 }) ?? true else { return nil }
            guard let average else { return 45 }
            return notable(Double(yesterday), Double(average)) ? 65 : 50
        case .screenTime(let minutes, let average):
            guard minutes > 0, minutes <= 24 * 60, average.map({ $0 > 0 && $0 <= 24 * 60 }) ?? true else { return nil }
            guard let average else { return 40 }
            return notable(Double(minutes), Double(average)) ? 55 : 42
        }
    }

    private static func notable(_ value: Double, _ average: Double) -> Bool {
        abs(value - average) / average >= 0.25
    }

    private static func valid(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func rotationPenalty(_ kind: MorningExtraKind, preferences: MorningExtrasPreferences, day: Int) -> Double {
        guard !kind.isTimely, let last = preferences.lastSpokenDay[kind.rawValue] else { return 0 }
        switch day - last {
        case 1: return 40
        case 2: return 20
        default: return 0
        }
    }
}

/// English and French sentences, explicit like the opening's phrases: the language is the
/// briefing's, whatever the device language, and every sentence is testable on any toolchain.
struct MorningExtrasPhrases {
    let french: Bool
    let locale: Locale
    let timeZone: TimeZone

    func sentence(_ fact: MorningExtraFact) -> String? {
        switch fact {
        case .sleptMinutes(let minutes):
            return french ? "Vous avez dormi \(duration(minutes)) cette nuit." : "You slept \(duration(minutes)) last night."
        case .inBedMinutes(let minutes):
            return french ? "Temps au lit cette nuit : \(duration(minutes))." : "Time in bed last night: \(duration(minutes))."
        case .steps(let yesterday, let average):
            let count = number(yesterday)
            let head = french ? "Hier : \(count) pas" : "Yesterday: \(count) \(yesterday == 1 ? "step" : "steps")"
            guard let average else { return head + "." }
            let difference = yesterday - average
            if Double(abs(difference)) <= Double(average) * MorningExtrasComposer.closeShare {
                return french ? "\(head), proche de votre moyenne sur 7 jours." : "\(head), close to your 7-day average."
            }
            let rounded = number(roundedSteps(abs(difference)))
            if french {
                return "\(head), environ \(rounded) de \(difference > 0 ? "plus" : "moins") que votre moyenne sur 7 jours."
            }
            return "\(head), about \(rounded) \(difference > 0 ? "more" : "fewer") than your 7-day average."
        case .screenTime(let minutes, let average):
            let head = french ? "Temps d’écran hier : \(duration(minutes))" : "Screen time yesterday: \(duration(minutes))"
            guard let average else { return head + "." }
            let difference = minutes - average
            if Double(abs(difference)) <= Double(average) * MorningExtrasComposer.closeShare {
                return french ? "\(head), proche de votre moyenne de la semaine." : "\(head), close to your weekly average."
            }
            if french {
                return "\(head), \(duration(abs(difference))) de \(difference > 0 ? "plus" : "moins") que votre moyenne de la semaine."
            }
            return "\(head), \(duration(abs(difference))) \(difference > 0 ? "more" : "less") than your weekly average."
        case .temperatureChange(let celsiusDelta, let unit):
            // A difference converts by the scale factor only: 10 °C warmer is 18 °F warmer, not 50.
            let delta = unit == .fahrenheit ? celsiusDelta * 9 / 5 : celsiusDelta
            let degrees = Int(abs(delta).rounded())
            guard degrees > 0 else { return nil }
            let symbol = unit == .fahrenheit ? "°F" : "°C"
            if french {
                return "Maximum du jour : \(degrees) \(symbol) de \(delta > 0 ? "plus" : "moins") qu’hier."
            }
            return "Today’s high is \(degrees) \(symbol) \(delta > 0 ? "warmer" : "colder") than yesterday’s."
        case .precipitation(let kind, let from):
            let noun: String
            switch kind {
            case .rain: noun = french ? "Pluie probable" : "Rain likely"
            case .snow: noun = french ? "Neige probable" : "Snow likely"
            case .mixed: noun = french ? "Précipitations probables" : "Precipitation likely"
            }
            guard let from else { return french ? "\(noun) dès maintenant." : "\(noun) now." }
            return french ? "\(noun) à partir de \(time(from))." : "\(noun) from \(time(from))."
        case .calendarConflict(let first, let second, let at):
            return french ? "Agenda : « \(first) » et « \(second) » se chevauchent à \(time(at))."
                : "Calendar: \(first) and \(second) overlap at \(time(at))."
        case .tightGap(let minutes, let first, let second, let at):
            let gap = minutes == 0 ? (french ? "aucune pause" : "no break") : (french ? "\(minutes) min" : "\(minutes) \(minutes == 1 ? "minute" : "minutes")")
            return french ? "Agenda : \(gap) entre « \(first) » et « \(second) » à \(time(at))."
                : "Calendar: \(gap) between \(first) and \(second) at \(time(at))."
        case .birthdays(let all):
            let names = all.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            guard let first = names.first else { return nil }
            if names.count == 1 {
                return french ? "C’est l’anniversaire \(of(first)) aujourd’hui." : "It’s \(first)’s birthday today."
            }
            if names.count == 2 {
                return french ? "Anniversaires aujourd’hui : \(first) et \(names[1])."
                    : "Birthdays today: \(first) and \(names[1])."
            }
            let others = names.count - 2
            return french ? "Anniversaires aujourd’hui : \(first), \(names[1]) et \(others) autre\(others > 1 ? "s" : "")."
                : "Birthdays today: \(first), \(names[1]) and \(others) \(others > 1 ? "others" : "other")."
        }
    }

    /// "7 hours 20 minutes", "45 minutes", "1 hour".
    func duration(_ minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        func unit(_ value: Int, _ en: String, _ fr: String) -> String {
            french ? "\(value) \(fr)\(value > 1 ? "s" : "")" : "\(value) \(en)\(value == 1 ? "" : "s")"
        }
        if hours == 0 { return unit(rest, "minute", "minute") }
        if rest == 0 { return unit(hours, "hour", "heure") }
        return "\(unit(hours, "hour", "heure")) \(unit(rest, "minute", "minute"))"
    }

    func number(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale; formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// A step difference is approximate: to the nearest hundred from a hundred, to ten from
    /// ten, exact below ten.
    func roundedSteps(_ value: Int) -> Int {
        guard value >= 10 else { return value }
        let step = value >= 100 ? 100 : 10
        return max(step, Int((Double(value) / Double(step)).rounded()) * step)
    }

    func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale; formatter.timeZone = timeZone
        formatter.dateStyle = .none; formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// French elides "de" before a vowel or a mute h: "d’Anna", "de Paul".
    private func of(_ name: String) -> String {
        let first = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: locale).first
        return "aeiouyh".contains(first ?? "x") ? "d’\(name)" : "de \(name)"
    }
}
