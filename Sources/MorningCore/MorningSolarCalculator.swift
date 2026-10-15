import Foundation

extension MorningSolarDay {
    /// Local estimate, including refraction, with no network or location access.
    /// The supplied calendar's time zone is used for both events, including DST.
    /// NOAA approximation: https://gml.noaa.gov/grad/solcalc/solareqns.PDF
    public static func calculate(for date: Date, latitude: Double, longitude: Double,
                                 calendar: Calendar = .current) -> MorningSolarDay? {
        guard date.timeIntervalSinceReferenceDate.isFinite,
              latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        var local = Calendar(identifier: .gregorian)
        local.timeZone = calendar.timeZone
        guard let ordinal = local.ordinality(of: .day, in: .year, for: date),
              let year = local.range(of: .day, in: .year, for: date) else { return nil }
        let gamma = 2 * Double.pi / Double(year.count) * Double(ordinal - 1)
        let equation = 229.18 * (0.000075 + 0.001868 * cos(gamma) - 0.032077 * sin(gamma)
            - 0.014615 * cos(2 * gamma) - 0.040849 * sin(2 * gamma))
        let declination = 0.006918 - 0.399912 * cos(gamma) + 0.070257 * sin(gamma)
            - 0.006758 * cos(2 * gamma) + 0.000907 * sin(2 * gamma)
            - 0.002697 * cos(3 * gamma) + 0.00148 * sin(3 * gamma)
        let radians = latitude * .pi / 180
        let cosine = cos(90.833 * .pi / 180) / (cos(radians) * cos(declination))
            - tan(radians) * tan(declination)
        if cosine < -1 { return .init(sunriseMinute: 0, sunsetMinute: 1440, condition: .allDay) }
        if cosine > 1 { return .init(sunriseMinute: 0, sunsetMinute: 0, condition: .allNight) }
        let angle = acos(cosine) * 180 / .pi
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = local.dateComponents([.year, .month, .day], from: date)
        guard let midnightUTC = utc.date(from: components) else { return nil }
        let start = local.startOfDay(for: date)
        func wallMinute(_ utcMinute: Double) -> Double {
            let event = midnightUTC.addingTimeInterval(utcMinute * 60)
            let days = local.dateComponents([.day], from: start, to: local.startOfDay(for: event)).day ?? 0
            let time = local.dateComponents([.hour, .minute, .second], from: event)
            return Double(days * 1440 + (time.hour ?? 0) * 60 + (time.minute ?? 0))
                + Double(time.second ?? 0) / 60
        }
        return .init(sunriseMinute: wallMinute(720 - 4 * (longitude + angle) - equation),
                     sunsetMinute: wallMinute(720 - 4 * (longitude - angle) - equation))
    }
}
