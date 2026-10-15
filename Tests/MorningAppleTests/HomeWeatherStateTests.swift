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
