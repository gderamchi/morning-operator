import Testing
@testable import MorningCore

@Suite("Weather sky drawing parameters — synthetic conditions")
struct MorningWeatherSceneTests {
    @Test func everyConditionProducesFiniteBoundedDrawingParameters() {
        for condition in MorningWeatherCondition.allCases {
            let scene = MorningWeatherScene(condition: condition)
            #expect(scene.condition == condition)
            for value in [scene.cloudCoverage, scene.precipitationIntensity, scene.windIntensity,
                          scene.celestialVisibility, scene.starVisibility] {
                #expect(value.isFinite && (0...1).contains(value), "\(condition): \(value)")
            }
        }
    }

    @Test func cloudsIncreaseFromClearThroughOvercast() {
        let ordered: [MorningWeatherCondition] = [.clear, .mostlyClear, .partlyCloudy, .mostlyCloudy, .cloudy]
        let coverage = ordered.map { MorningWeatherScene(condition: $0).cloudCoverage }
        for (lower, upper) in zip(coverage, coverage.dropFirst()) { #expect(lower < upper) }
        #expect(MorningWeatherScene(condition: .clear).starVisibility == 1)
        #expect(MorningWeatherScene(condition: .cloudy).starVisibility == 0)
    }

    @Test func rainStrengthAndSunShowersRemainDistinct() {
        let drizzle = MorningWeatherScene(condition: .drizzle)
        let rain = MorningWeatherScene(condition: .rain)
        let heavy = MorningWeatherScene(condition: .heavyRain)
        let sun = MorningWeatherScene(condition: .sunShowers)
        #expect(drizzle.precipitation == .rain && rain.precipitation == .rain && heavy.precipitation == .rain)
        #expect(drizzle.precipitationIntensity < rain.precipitationIntensity)
        #expect(rain.precipitationIntensity < heavy.precipitationIntensity)
        #expect(sun.precipitationIntensity > 0 && sun.cloudCoverage < rain.cloudCoverage)
        #expect(sun.celestialVisibility > rain.celestialVisibility)
    }

    @Test func frozenConditionsKeepTheirPrecipitationShapes() {
        #expect(MorningWeatherScene(condition: .freezingDrizzle).precipitation == .freezingRain)
        #expect(MorningWeatherScene(condition: .freezingRain).precipitation == .freezingRain)
        #expect(MorningWeatherScene(condition: .sleet).precipitation == .sleet)
        #expect(MorningWeatherScene(condition: .hail).precipitation == .hail)
        #expect(MorningWeatherScene(condition: .wintryMix).precipitation == .wintryMix)
        let snow = MorningWeatherScene(condition: .snow)
        #expect(snow.precipitation == .snow)
        #expect(MorningWeatherScene(condition: .flurries).precipitationIntensity < snow.precipitationIntensity)
        #expect(MorningWeatherScene(condition: .heavySnow).precipitationIntensity > snow.precipitationIntensity)
        #expect(MorningWeatherScene(condition: .sunFlurries).cloudCoverage < snow.cloudCoverage)
        #expect(MorningWeatherScene(condition: .blizzard).windIntensity > 0)
        #expect(MorningWeatherScene(condition: .blowingSnow).windIntensity > 0)
    }

    @Test func stormsWindAndReducedVisibilityAreExplicit() {
        for condition in [MorningWeatherCondition.isolatedThunderstorms, .scatteredThunderstorms, .thunderstorms, .strongStorms] {
            #expect(MorningWeatherScene(condition: condition).lightning)
        }
        #expect(MorningWeatherScene(condition: .hurricane).windIntensity == 1)
        #expect(MorningWeatherScene(condition: .tropicalStorm).windIntensity > 0.8)
        #expect(MorningWeatherScene(condition: .windy).windIntensity > MorningWeatherScene(condition: .breezy).windIntensity)
        #expect(MorningWeatherScene(condition: .foggy).atmosphere == .fog)
        #expect(MorningWeatherScene(condition: .haze).atmosphere == .haze)
        #expect(MorningWeatherScene(condition: .smoky).atmosphere == .smoke)
        #expect(MorningWeatherScene(condition: .blowingDust).atmosphere == .dust)
        #expect(MorningWeatherScene(condition: .foggy).starVisibility < MorningWeatherScene(condition: .haze).starVisibility)
        // Hot and frigid conditions do not imply rain or snow.
        #expect(MorningWeatherScene(condition: .hot).precipitation == .none)
        #expect(MorningWeatherScene(condition: .frigid).precipitation == .none)
    }

    @Test func measuredCloudCoverWinsWithoutInvalidInputDistortingTheSky() {
        #expect(MorningWeatherScene(condition: .partlyCloudy, cloudCover: 0.63).cloudCoverage == 0.63)
        #expect(MorningWeatherScene(condition: .cloudy, cloudCover: 0).cloudCoverage == 0)
        #expect(MorningWeatherScene(condition: .clear, cloudCover: 1).cloudCoverage == 1)
        let fallback = MorningWeatherScene(condition: .partlyCloudy)
        for invalid in [Double.nan, .infinity, -.infinity, -0.01, 1.01] {
            #expect(MorningWeatherScene(condition: .partlyCloudy, cloudCover: invalid) == fallback)
        }
    }

    @Test func unknownWeatherDoesNotPretendToKnowTheConditions() {
        let scene = MorningWeatherScene(condition: .unknown, cloudCover: 1)
        #expect(scene.condition == .unknown && scene.cloudCoverage == 0)
        #expect(scene.precipitation == .none && scene.precipitationIntensity == 0)
        #expect(scene.atmosphere == .clear && scene.windIntensity == 0 && !scene.lightning)
    }
}
