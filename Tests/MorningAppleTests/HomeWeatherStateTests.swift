import Foundation
import Testing
import MorningApple

@Suite("Home weather admission")
struct HomeWeatherStateTests {
    @Test func requiresSelectedCityCurrentTimestampsAndBothThirtyMinuteLimits() throws {
        let now = Date(timeIntervalSince1970: 1_791_619_200)
        let city = try WeatherLocation(latitude: 48, longitude: 2, displayName: "Synthetic town")
        let elsewhere = try WeatherLocation(latitude: 45, longitude: 5, displayName: "Another synthetic town")
        let snapshot = try observation(city: city, retrievedAt: now, observationAt: now.addingTimeInterval(-60))
        #expect(snapshot.isCurrent(for: city, at: now))
        #expect(!snapshot.isCurrent(for: elsewhere, at: now))
        #expect(!snapshot.isCurrent(for: city, at: now.addingTimeInterval(-1)))
        #expect(snapshot.isCurrent(for: city, at: now.addingTimeInterval(1_739)))
        #expect(!snapshot.isCurrent(for: city, at: now.addingTimeInterval(1_740)))
        #expect(!snapshot.isCurrent(for: city, at: Date(timeIntervalSince1970: .nan)))
        #expect(!snapshot.isCurrent(for: city, at: now, maximumAge: .infinity))
    }

    @Test func honorsProviderExpiryAndRejectsObservationAfterRetrieval() throws {
        let now = Date(timeIntervalSince1970: 1_791_619_200)
        let city = try WeatherLocation(latitude: 48, longitude: 2, displayName: "Synthetic town")
        let snapshot = try observation(city: city, retrievedAt: now, observationAt: now,
                                       expiresAt: now.addingTimeInterval(120))
        #expect(snapshot.isCurrent(for: city, at: now.addingTimeInterval(119)))
        #expect(!snapshot.isCurrent(for: city, at: now.addingTimeInterval(120)))
        let future = try observation(city: city, retrievedAt: now, observationAt: now.addingTimeInterval(1))
        #expect(!future.isCurrent(for: city, at: now.addingTimeInterval(2)))
    }

    @Test func sceneReceivesAllAvailableDrawingMeasurements() throws {
        let now = Date(timeIntervalSince1970: 1_791_619_200)
        let city = try WeatherLocation(latitude: 48, longitude: 2, displayName: "Synthetic town")
        let attribution = try WeatherAttributionInfo(legalURL: URL(string: "https://example.invalid/legal")!,
            combinedMarkLightURL: URL(string: "https://example.invalid/light")!,
            combinedMarkDarkURL: URL(string: "https://example.invalid/dark")!, serviceName: "Synthetic Weather")
        let snapshot = try WeatherObservationSnapshot(location: city, retrievedAt: now, observationAt: now,
            temperatureCelsius: 18, conditionDescription: "Synthetic rain", symbolName: "cloud.rain",
            attribution: attribution, condition: .rain, cloudCover: 0.63,
            windSpeedMetersPerSecond: 10, windGustMetersPerSecond: 18, windDirectionDegrees: 90,
            precipitationIntensityMillimetersPerHour: 3, humidity: 0.8, visibilityMeters: 2_000,
            apparentTemperatureCelsius: 15, uvIndex: 2, pressureHectopascals: 1_004, isDaylight: true)
        let scene = snapshot.scene
        #expect(scene.cloudCoverage == 0.63 && scene.precipitationIntensity == 0.5)
        #expect(scene.windIntensity == 0.5 && scene.windGustIntensity == 0.9)
        #expect(scene.windDirectionDegrees == 90 && scene.windHorizontalDirection == -1)
        #expect(scene.atmosphericVeil > 0.7 && scene.humidity == 0.8)
        #expect(scene.apparentTemperatureCelsius == 15 && scene.uvIndex == 2)
        #expect(scene.pressureHectopascals == 1_004 && scene.isDaylight == true)
    }

    private func observation(city: WeatherLocation, retrievedAt: Date, observationAt: Date,
                             expiresAt: Date? = nil) throws -> WeatherObservationSnapshot {
        let attribution = try WeatherAttributionInfo(legalURL: URL(string: "https://example.invalid/legal")!,
            combinedMarkLightURL: URL(string: "https://example.invalid/light")!,
            combinedMarkDarkURL: URL(string: "https://example.invalid/dark")!, serviceName: "Synthetic Weather")
        return try WeatherObservationSnapshot(location: city, retrievedAt: retrievedAt, observationAt: observationAt,
            temperatureCelsius: 18, conditionDescription: "Synthetic rain", symbolName: "cloud.rain",
            attribution: attribution, expiresAt: expiresAt, condition: .rain)
    }
}
