/// Provider-independent current conditions. Unknown weather adds no invented effects.
public enum MorningWeatherCondition: String, CaseIterable, Sendable {
    case unknown
    case blizzard, blowingDust, blowingSnow, breezy, clear, cloudy, drizzle, flurries
    case foggy, freezingDrizzle, freezingRain, frigid, hail, haze, heavyRain, heavySnow
    case hot, hurricane, isolatedThunderstorms, mostlyClear, mostlyCloudy, partlyCloudy
    case rain, scatteredThunderstorms, sleet, smoky, snow, strongStorms, sunFlurries
    case sunShowers, thunderstorms, tropicalStorm, windy, wintryMix
}

public enum MorningWeatherPrecipitation: Sendable {
    case none, rain, freezingRain, snow, sleet, hail, wintryMix
}

public enum MorningWeatherAtmosphere: Sendable {
    case clear, haze, fog, smoke, dust
}

/// Art direction, not a forecast: strengths are normalized drawing parameters.
/// The solar clock controls day/night independently, including when weather is unavailable.
public struct MorningWeatherScene: Sendable, Equatable {
    public let condition: MorningWeatherCondition
    public let cloudCoverage: Double
    public let precipitation: MorningWeatherPrecipitation
    public let precipitationIntensity: Double
    public let atmosphere: MorningWeatherAtmosphere
    public let windIntensity: Double
    public let lightning: Bool

    /// Clouds soften the sun/moon without removing the clock's central reference.
    public var celestialVisibility: Double {
        max(0.22, 1 - cloudCoverage * 0.68 - atmosphericVeil * 0.3)
    }

    /// Apply this only to the night sky; daytime never introduces stars.
    public var starVisibility: Double {
        max(0, 1 - cloudCoverage * 1.12) * (1 - atmosphericVeil)
    }

    public init(condition: MorningWeatherCondition, cloudCover: Double? = nil) {
        self.condition = condition
        var clouds = 0.0
        var precipitation = MorningWeatherPrecipitation.none
        var intensity = 0.0
        var atmosphere = MorningWeatherAtmosphere.clear
        var wind = 0.0
        var lightning = false

        switch condition {
        case .unknown, .clear, .hot, .frigid: break
        case .mostlyClear: clouds = 0.14
        case .partlyCloudy: clouds = 0.4
        case .mostlyCloudy: clouds = 0.72
        case .cloudy: clouds = 0.98
        case .drizzle:
            clouds = 0.82; precipitation = .rain; intensity = 0.2
        case .rain:
            clouds = 0.88; precipitation = .rain; intensity = 0.55
        case .heavyRain:
            clouds = 1; precipitation = .rain; intensity = 1
        case .sunShowers:
            clouds = 0.35; precipitation = .rain; intensity = 0.35
        case .freezingDrizzle:
            clouds = 0.82; precipitation = .freezingRain; intensity = 0.2
        case .freezingRain:
            clouds = 0.92; precipitation = .freezingRain; intensity = 0.65
        case .flurries:
            clouds = 0.68; precipitation = .snow; intensity = 0.2
        case .sunFlurries:
            clouds = 0.3; precipitation = .snow; intensity = 0.2
        case .snow:
            clouds = 0.88; precipitation = .snow; intensity = 0.55
        case .heavySnow:
            clouds = 1; precipitation = .snow; intensity = 1
        case .blowingSnow:
            clouds = 0.7; precipitation = .snow; intensity = 0.4; wind = 0.8
        case .blizzard:
            clouds = 1; precipitation = .snow; intensity = 1; wind = 1
        case .sleet:
            clouds = 0.9; precipitation = .sleet; intensity = 0.6
        case .hail:
            clouds = 0.92; precipitation = .hail; intensity = 0.7
        case .wintryMix:
            clouds = 0.9; precipitation = .wintryMix; intensity = 0.6
        case .isolatedThunderstorms:
            clouds = 0.5; precipitation = .rain; intensity = 0.45; lightning = true
        case .scatteredThunderstorms:
            clouds = 0.7; precipitation = .rain; intensity = 0.55; lightning = true
        case .thunderstorms:
            clouds = 0.92; precipitation = .rain; intensity = 0.75; wind = 0.5; lightning = true
        case .strongStorms:
            clouds = 1; precipitation = .rain; intensity = 1; wind = 0.85; lightning = true
        case .tropicalStorm:
            clouds = 1; precipitation = .rain; intensity = 0.9; wind = 0.9
        case .hurricane:
            clouds = 1; precipitation = .rain; intensity = 1; wind = 1
        case .breezy: wind = 0.35
        case .windy: wind = 0.7
        case .foggy: atmosphere = .fog
        case .haze: atmosphere = .haze
        case .smoky: atmosphere = .smoke
        case .blowingDust: atmosphere = .dust; wind = 0.7
        }

        // An unknown provider condition remains neutral, even if it reports cloud cover.
        if condition != .unknown, let cloudCover, cloudCover.isFinite, (0...1).contains(cloudCover) {
            clouds = cloudCover
        }
        cloudCoverage = clouds
        self.precipitation = precipitation
        precipitationIntensity = intensity
        self.atmosphere = atmosphere
        windIntensity = wind
        self.lightning = lightning
    }

    private var atmosphericVeil: Double {
        switch atmosphere {
        case .clear: 0
        case .haze: 0.35
        case .fog: 0.8
        case .smoke, .dust: 0.6
        }
    }
}
