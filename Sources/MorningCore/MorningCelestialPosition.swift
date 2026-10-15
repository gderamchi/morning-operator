import Foundation

/// Decorative positions only. Values describe a drawing in unit screen coordinates;
/// they do not describe measured sky positions, light exposure, or screen brightness.
public struct MorningCelestialPosition: Sendable, Equatable {
    public let centerX: Double
    public let centerY: Double
    public let opacity: Double
}

public struct MorningCelestialScene: Sendable, Equatable {
    public let sun: MorningCelestialPosition
    public let moon: MorningCelestialPosition
}

/// A decorative left-to-right arc between local sunrise and sunset; the crescent
/// follows the same journey at night. Its position is not a lunar ephemeris.
public enum MorningCelestialClock {
    public static func scene(atMinute minute: Double, solar: MorningSolarDay = .fixed) -> MorningCelestialScene {
        let day = solar.validated
        // No invented rise/set when the sun stays above or below the horizon.
        if day.condition != .dayAndNight {
            return MorningCelestialScene(
                sun: .init(centerX: 0.5, centerY: 0.18, opacity: day.condition == .allDay ? 1 : 0),
                moon: .init(centerX: 0.5, centerY: 0.24, opacity: day.condition == .allNight ? 1 : 0))
        }
        let safeMinute = minute.isFinite ? minute : 12 * 60
        let rise = day.sunriseMinute, set = day.sunsetMinute
        let daylight = set - rise
        let nightLength = 1440 - daylight
        let sinceRise = wrap(safeMinute - rise)
        let sinceSet = wrap(safeMinute - set)
        let isDay = sinceRise <= daylight
        let dayProgress = isDay ? sinceRise / daylight : (sinceSet < nightLength / 2 ? 1.0 : 0)
        let nightProgress = !isDay ? sinceSet / nightLength : (sinceRise < daylight / 2 ? 1.0 : 0)
        let distance = isDay ? min(sinceRise, daylight - sinceRise) : -min(sinceSet, nightLength - sinceSet)
        let fade = min(15, min(daylight, nightLength) / 4)
        let visible = smooth((distance + fade) / (2 * fade))
        return MorningCelestialScene(
            sun: position(progress: dayProgress, opacity: visible),
            moon: position(progress: nightProgress, opacity: 1 - visible))
    }

    public static func scene(at date: Date, calendar: Calendar = .current,
                             solar: MorningSolarDay = .fixed) -> MorningCelestialScene {
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        return scene(atMinute: Double(parts.hour ?? 12) * 60 + Double(parts.minute ?? 0)
                     + Double(parts.second ?? 0) / 60, solar: solar)
    }

    /// Pinning a theme in debug previews also pins its artwork to a representative time.
    public static func scene(for phase: MorningDayPhase) -> MorningCelestialScene {
        let minute: Double
        switch phase {
        case .dawn: minute = 6 * 60 + 45
        case .morning: minute = 9 * 60
        case .day: minute = 13 * 60
        case .evening: minute = 18 * 60 + 45
        case .night: minute = 23 * 60
        }
        return scene(atMinute: minute)
    }

    private static func clamp(_ value: Double) -> Double { min(1, max(0, value)) }
    private static func wrap(_ minute: Double) -> Double {
        let value = minute.truncatingRemainder(dividingBy: 1440)
        return value < 0 ? value + 1440 : value
    }
    private static func position(progress: Double, opacity: Double) -> MorningCelestialPosition {
        .init(centerX: 0.12 + 0.76 * progress, centerY: 0.76 - 0.58 * sin(.pi * progress), opacity: opacity)
    }
    private static func smooth(_ value: Double) -> Double {
        let t = clamp(value)
        return t * t * (3 - 2 * t)
    }
}
