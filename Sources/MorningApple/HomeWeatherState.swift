import Foundation

extension WeatherObservationSnapshot {
    /// Home and the spoken briefing share the same current-conditions lifetime.
    public func isCurrent(for selectedLocation: WeatherLocation, at date: Date,
                          maximumAge: TimeInterval = MorningBriefingFreshnessPolicy.standard.weatherMaximumAge) -> Bool {
        guard location == selectedLocation, date.timeIntervalSinceReferenceDate.isFinite,
              maximumAge.isFinite, maximumAge > 0,
              retrievedAt.timeIntervalSinceReferenceDate.isFinite,
              observationAt.timeIntervalSinceReferenceDate.isFinite,
              expiresAt?.timeIntervalSinceReferenceDate.isFinite != false,
              temperatureCelsius.isFinite,
              observationAt <= retrievedAt, retrievedAt <= date, observationAt <= date else { return false }
        let expiry = ([retrievedAt.addingTimeInterval(maximumAge), observationAt.addingTimeInterval(maximumAge)] +
                      [expiresAt].compactMap { $0 }).min()!
        return date < expiry
    }
}
