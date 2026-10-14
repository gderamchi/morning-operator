import Foundation
import MorningCore
#if os(iOS)
import DeviceActivity
import FamilyControls
// `activitySegments` and the rest of the data reading live in the SwiftUI cross-import overlay.
import SwiftUI
#endif

/// Where Screen Time hours come from: the system, or a synthetic fixture in UI tests.
@MainActor
protocol ScreenTimeSource {
    var access: ScreenTimeAccess { get }
    /// Shows Apple's one-time Screen Time sheet (Continue + Face ID).
    func requestAccess() async throws
    /// Hourly usage from `start` to `end`. Nothing is written anywhere.
    func hours(from start: Date, to end: Date) async throws -> [ScreenTimeHour]
}

enum ScreenTimeAccess: Equatable {
    case notAsked, denied, approvedWithoutData, approved, unavailable
}

enum ScreenTimeReadError: Error {
    case unavailable, timedOut
}

@MainActor
enum ScreenTimeSources {
    static func make() -> any ScreenTimeSource {
        #if DEBUG
        if ScreenTimeFixtureSource.isRequested { return ScreenTimeFixtureSource() }
        #endif
        #if os(iOS)
        return SystemScreenTimeSource()
        #else
        return UnavailableScreenTimeSource()
        #endif
    }
}

struct UnavailableScreenTimeSource: ScreenTimeSource {
    var access: ScreenTimeAccess { .unavailable }
    func requestAccess() async throws { throw ScreenTimeReadError.unavailable }
    func hours(from start: Date, to end: Date) async throws -> [ScreenTimeHour] { throw ScreenTimeReadError.unavailable }
}

#if os(iOS)
/// Screen Time with the App and Website Usage data access (iOS 26.4 or later). On iOS 27 it
/// returns hourly segments with real bundle identifiers and seconds per app
/// (docs/SEAMLESS-LEARNING.md). Only what MORE needs is kept: identifier, seconds, pickups, category.
struct SystemScreenTimeSource: ScreenTimeSource {
    var access: ScreenTimeAccess {
        // App and Website Usage data needs iOS 26.4; asking earlier cannot give it.
        guard #available(iOS 26.4, *) else { return .unavailable }
        let status = AuthorizationCenter.shared.authorizationStatus
        if #available(iOS 26.4, *), status == .approvedWithDataAccess { return .approved }
        switch status {
        case .notDetermined: return .notAsked
        case .denied: return .denied
        case .approved: return .approvedWithoutData
        default: return .notAsked
        }
    }

    func requestAccess() async throws {
        guard #available(iOS 26.4, *) else { throw ScreenTimeReadError.unavailable }
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
    }

    func hours(from start: Date, to end: Date) async throws -> [ScreenTimeHour] {
        guard #available(iOS 26.4, *) else { throw ScreenTimeReadError.unavailable }
        return try await withThrowingTaskGroup(of: [ScreenTimeHour]?.self) { group in
            group.addTask { try await Self.read(from: start, to: end) }
            // The live stream may stay open for updates; the first complete result is enough.
            group.addTask { try await Task.sleep(for: .seconds(45)); return nil }
            defer { group.cancelAll() }
            guard let first = try await group.next(), let hours = first else { throw ScreenTimeReadError.timedOut }
            return hours
        }
    }

    @available(iOS 26.4, *)
    nonisolated private static func read(from start: Date, to end: Date) async throws -> [ScreenTimeHour] {
        // No device filter: this iPhone only, never another device on the same account.
        let filter = DeviceActivityFilter(segment: .hourly(during: DateInterval(start: start, end: end)))
        var hours: [ScreenTimeHour] = []
        for try await data in DeviceActivityData.activityData(filteredBy: filter, using: .live) {
            for await segment in data.activitySegments {
                var apps: [ScreenTimeAppHour] = []
                for await category in segment.categories {
                    let categoryName = category.category.localizedDisplayName
                    for await activity in category.applications {
                        guard let id = activity.application.bundleIdentifier else { continue }
                        apps.append(ScreenTimeAppHour(bundleIdentifier: id, seconds: activity.totalActivityDuration,
                                                      pickups: activity.numberOfPickups, categoryName: categoryName))
                    }
                }
                hours.append(ScreenTimeHour(interval: segment.dateInterval, firstPickup: segment.firstPickup,
                                            longestActivity: segment.longestActivity, apps: apps))
            }
            break
        }
        return hours
    }
}
#endif

#if DEBUG
/// UI tests only (`--ui-testing --ui-testing-screen-time-fixture`): five synthetic weekday
/// mornings with made-up minutes, so the Learn card and its review run without Screen Time.
/// The sheet is skipped; access flips to approved on request.
@MainActor
final class ScreenTimeFixtureSource: ScreenTimeSource {
    static var isRequested: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--ui-testing") && arguments.contains("--ui-testing-screen-time-fixture")
    }

    private(set) var access: ScreenTimeAccess = .notAsked
    func requestAccess() async throws { access = .approved }

    func hours(from start: Date, to end: Date) async throws -> [ScreenTimeHour] {
        let calendar = Calendar.current
        var hours: [ScreenTimeHour] = []
        func at(_ day: Date, _ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        func app(_ id: String, _ minutes: Double, pickups: Int = 0) -> ScreenTimeAppHour {
            ScreenTimeAppHour(bundleIdentifier: id, seconds: minutes * 60, pickups: pickups)
        }
        var day = calendar.startOfDay(for: start)
        var index = 0
        while day < end {
            let evening = at(day, 22)
            hours.append(ScreenTimeHour(interval: DateInterval(start: evening, duration: 3600), firstPickup: at(day, 22, 5),
                                        apps: [app("com.apple.mobilemail", 8)]))
            if let next = calendar.date(byAdding: .day, value: 1, to: day) {
                let minute = [5, 12, 20, 8, 15][index % 5]
                hours.append(ScreenTimeHour(interval: DateInterval(start: at(next, 7), duration: 3600), firstPickup: at(next, 7, minute),
                    apps: [app("com.apple.MobileSMS", 2, pickups: 3), app("com.apple.weather", 1, pickups: 1),
                           app("com.burbn.instagram", 38.0 + Double(index % 3)), app("com.apple.LocalAuthenticationUIService", 1)]))
                hours.append(ScreenTimeHour(interval: DateInterval(start: at(next, 8), duration: 3600), firstPickup: at(next, 8),
                    longestActivity: DateInterval(start: at(next, 8), duration: 12 * 60),
                    apps: [app("com.chess.iphone", 12), app("com.apple.mobilecal", 2)]))
                day = next
            } else { break }
            index += 1
        }
        return hours.filter { $0.interval.end <= end }
    }
}
#endif
