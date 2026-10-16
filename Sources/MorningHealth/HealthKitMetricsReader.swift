import Foundation
import HealthKit
import MorningApple

/// Explicit expanded read scope. Nothing is written; no recovery score is calculated.
@MainActor
public final class HealthKitMetricsReader: HealthMetricsObservationProviding {
    private let usageDescription: @Sendable () -> String?
    private var store: HKHealthStore?

    public init(usageDescription: @escaping @Sendable () -> String? = {
        Bundle.main.object(forInfoDictionaryKey: HealthKitSleepReader.usageDescriptionKey) as? String
    }) { self.usageDescription = usageDescription }

    public var isAvailableOnDevice: Bool { HKHealthStore.isHealthDataAvailable() }

    /// One union prompt for new connections; existing sleep-only connections upgrade
    /// through this explicit action. A handled prompt says nothing about read permission.
    public func requestReadAccess() async throws {
        try Task.checkCancellation()
        guard isAvailableOnDevice else { throw SleepObservationError.unavailableOnDevice }
        guard let text = usageDescription(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SleepObservationError.missingUsageDescription
        }
        try await healthStore().requestAuthorization(toShare: [], read: Self.readTypes)
        try Task.checkCancellation()
    }

    public func samples(for metric: HealthMetric, in interval: DateInterval) async throws -> HealthMetricReadOutcome {
        try Task.checkCancellation()
        guard isAvailableOnDevice else { return .unavailableOnDevice }
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: [])
        let query = HKSampleQueryDescriptor(predicates: [.quantitySample(type: Self.type(metric), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)])
        let samples = try await query.result(for: healthStore())
        try Task.checkCancellation()
        return .samples(samples.map { Self.sample(metric: metric, quantity: $0.quantity, start: $0.startDate, end: $0.endDate,
            bundleIdentifier: $0.sourceRevision.source.bundleIdentifier, sourceName: $0.sourceRevision.source.name,
            productType: $0.sourceRevision.productType, wasUserEntered: $0.metadata?[HKMetadataKeyWasUserEntered] as? Bool ?? false) })
    }

    nonisolated static var readTypes: Set<HKObjectType> {
        Set([HKCategoryType(.sleepAnalysis)] + HealthMetric.allCases.map { type($0) as HKObjectType })
    }

    nonisolated static func type(_ metric: HealthMetric) -> HKQuantityType {
        switch metric {
        case .heartRateVariabilitySDNN: HKQuantityType(.heartRateVariabilitySDNN)
        case .restingHeartRate: HKQuantityType(.restingHeartRate)
        case .respiratoryRate: HKQuantityType(.respiratoryRate)
        }
    }

    nonisolated static func sample(metric: HealthMetric, quantity: HKQuantity, start: Date, end: Date,
        bundleIdentifier: String, sourceName: String?, productType: String?, wasUserEntered: Bool) -> HealthMetricSample {
        let unit = metric == .heartRateVariabilitySDNN ? HKUnit.secondUnit(with: .milli) : .count().unitDivided(by: .minute())
        return .init(metric: metric, value: quantity.doubleValue(for: unit), start: start, end: end,
            source: .init(bundleIdentifier: bundleIdentifier, name: sourceName, productType: productType, wasUserEntered: wasUserEntered))
    }

    private func healthStore() -> HKHealthStore {
        if let store { return store }
        let created = HKHealthStore(); store = created; return created
    }
}
