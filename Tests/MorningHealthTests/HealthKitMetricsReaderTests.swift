import Foundation
import HealthKit
import Testing
import MorningApple
@testable import MorningHealth

@Suite("Expanded HealthKit scope and quantity mapping — no real Health data")
@MainActor
struct HealthKitMetricsReaderTests {
    @Test func authorizationIsExactlySleepAndThreeReadOnlyMeasurements() {
        #expect(HealthKitMetricsReader.readTypes == Set<HKObjectType>([
            HKCategoryType(.sleepAnalysis), HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.restingHeartRate), HKQuantityType(.respiratoryRate)]))
    }

    @Test func quantitiesNormalizeUnitsAndRetainTheAppSourceWithoutInventingATracker() {
        let at = Date(timeIntervalSince1970: 1_791_619_200)
        let fixtures: [(HealthMetric, HKQuantity, Double)] = [
            (.heartRateVariabilitySDNN, HKQuantity(unit: .second(), doubleValue: 0.042), 42),
            (.restingHeartRate, HKQuantity(unit: .count().unitDivided(by: .second()), doubleValue: 1), 60),
            (.respiratoryRate, HKQuantity(unit: .count().unitDivided(by: .minute()), doubleValue: 14), 14)
        ]
        for (metric, quantity, expected) in fixtures {
            let sample = HealthKitMetricsReader.sample(metric: metric, quantity: quantity, start: at, end: at,
                bundleIdentifier: "invalid.example.SYNTHETIC", sourceName: "Synthetic tracker app", productType: "iPhone17,1", wasUserEntered: false)
            #expect(abs(sample.value - expected) < 0.0001 && sample.metric == metric)
            #expect(sample.source.name == "Synthetic tracker app" && sample.source.kind == .thirdPartyApp)
            #expect(sample.start == at && sample.end == at)
        }
    }

    @Test func missingPurposeOrUnavailableDevicePreventsThePermissionPrompt() async {
        let reader = HealthKitMetricsReader(usageDescription: { nil })
        let expected: SleepObservationError = reader.isAvailableOnDevice ? .missingUsageDescription : .unavailableOnDevice
        await #expect(throws: expected) { try await reader.requestReadAccess() }
    }

    @Test(.enabled(if: !HKHealthStore.isHealthDataAvailable(), "Never query a real health data store from these tests."))
    func unavailableMachineReturnsWithoutQueryingAnyMetric() async throws {
        let at = Date(timeIntervalSince1970: 1_791_619_200)
        for metric in HealthMetric.allCases {
            #expect(try await HealthKitMetricsReader().samples(for: metric, in: .init(start: at.addingTimeInterval(-60), end: at)) == .unavailableOnDevice)
        }
    }
}
