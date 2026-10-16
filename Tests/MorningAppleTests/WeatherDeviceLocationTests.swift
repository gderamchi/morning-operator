import CoreLocation
import Foundation
import Testing
import MorningCore
@testable import MorningApple

@Suite("Foreground weather location", .timeLimit(.minutes(1)))
@MainActor
struct WeatherDeviceLocationTests {
    private let instant = Date(timeIntervalSince1970: 1_791_619_200)
    @Test func approximateFreshFixIsEnoughButInvalidOrOldReadingsAreRefused() throws {
        let fix = CLLocation(coordinate: .init(latitude: 48.85, longitude: 2.35), altitude: 0,
            horizontalAccuracy: 1_000, verticalAccuracy: -1, timestamp: instant)
        let result = try WeatherDeviceLocation.validated(fix, at: instant)
        #expect(result.latitude == 48.85)
        for (accuracy, offset) in [(-1.0, 0.0), (5_001.0, 0.0), (100.0, -301.0), (100.0, 61.0)] {
            let invalid = CLLocation(coordinate: fix.coordinate, altitude: 0, horizontalAccuracy: accuracy,
                verticalAccuracy: -1, timestamp: instant.addingTimeInterval(offset))
            #expect(throws: WeatherDeviceLocationError.invalidReading) { try WeatherDeviceLocation.validated(invalid, at: instant) }
        }
    }
    @Test func emptySettingsUseCurrentLocationAndExistingCitiesRemainManual() throws {
        #expect(MorningBriefingSettings().usesCurrentLocation)
        let old = Data(#"{"calendarIDs":[],"weatherLocation":{"latitude":48,"longitude":2,"displayName":"SYNTHETIC city"},"temperatureUnit":"celsius"}"#.utf8)
        let decoded = try JSONDecoder().decode(MorningBriefingSettings.self, from: old)
        #expect(!decoded.usesCurrentLocation)
    }
    @Test func passiveRefreshNeverRequestsPermissionAndDenialNeverReadsGPS() async throws {
        let fixture = DeviceLocationFixture(); fixture.authorization = .denied
        let directory = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let controller = MorningBriefingController(directory: directory, deviceLocation: fixture)
        await controller.resolveCurrentLocationIfNeeded()
        #expect(fixture.permissionRequests == 0)
        #expect(fixture.reads == 0)
        #expect(controller.currentWeatherLocation == nil)
        #expect(controller.locationIssue != nil)
    }
    @Test func currentCoordinatesStayOutOfSettingsAndPrivacyClearRemovesThem() async throws {
        let fixture = DeviceLocationFixture(); fixture.authorization = .authorized
        let directory = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let controller = MorningBriefingController(directory: directory, deviceLocation: fixture)
        #expect(await controller.enableCurrentLocation(requestPermission: false))
        #expect(controller.currentWeatherLocation == fixture.location)
        var settings = controller.settings; settings.temperatureUnit = .fahrenheit
        try controller.updateSettings(settings)
        let saved = try String(contentsOf: directory.appendingPathComponent("briefing-settings.json"), encoding: .utf8)
        #expect(!saved.contains("48.12345"))
        #expect(!saved.contains("SYNTHETIC current fix"))
        controller.cancelAndClear()
        #expect(controller.currentWeatherLocation == nil)
    }
    @Test func unavailableFixIsThrottledButExplicitRetryReadsAgain() async throws {
        let fixture = DeviceLocationFixture(); fixture.authorization = .authorized; fixture.error = .timedOut
        let directory = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let instant = instant
        let controller = MorningBriefingController(directory: directory, deviceLocation: fixture, now: { instant })
        await controller.resolveCurrentLocationIfNeeded()
        await controller.resolveCurrentLocationIfNeeded()
        #expect(fixture.reads == 1)
        fixture.error = nil
        await controller.resolveCurrentLocationIfNeeded(force: true)
        #expect(fixture.reads == 2)
        #expect(controller.currentWeatherLocation == fixture.location)
    }
    @Test func manualCityWinsWhileAnEarlierFixIsPending() async throws {
        let fixture = DeviceLocationFixture(); fixture.authorization = .authorized; fixture.suspend = true
        let directory = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let controller = MorningBriefingController(directory: directory, deviceLocation: fixture)
        let pending = Task { await controller.resolveCurrentLocationIfNeeded() }
        while fixture.reads == 0 { await Task.yield() }
        let city = try WeatherLocation(latitude: 43, longitude: 5, displayName: "SYNTHETIC manual city")
        try controller.updateSettings(.init(weatherLocation: city))
        fixture.finish()
        await pending.value
        #expect(controller.currentWeatherLocation == city)
        #expect(fixture.cancellations > 0)
        fixture.suspend = false
        #expect(await controller.enableCurrentLocation(requestPermission: false))
        #expect(controller.currentWeatherLocation == fixture.location)
        #expect(fixture.reads == 2)
    }
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("MORE-DeviceLocation-\(UUID().uuidString)")
    }
}

@MainActor
private final class DeviceLocationFixture: WeatherDeviceLocationProviding {
    var authorization: WeatherLocationAuthorization = .notDetermined
    var permissionRequests = 0
    var reads = 0
    var cancellations = 0
    var suspend = false
    var error: WeatherDeviceLocationError?
    let location = try! WeatherLocation(latitude: 48.12345, longitude: 2.54321, displayName: "SYNTHETIC current fix")
    private var continuation: CheckedContinuation<Void, Never>?
    func requestAuthorization() async throws -> Bool { permissionRequests += 1; return authorization == .authorized }
    func currentLocation() async throws -> WeatherLocation {
        reads += 1
        if suspend { await withCheckedContinuation { continuation = $0 } }
        if let error { throw error }
        return location
    }
    func cancel() { cancellations += 1 }
    func finish() { continuation?.resume(); continuation = nil }
}
