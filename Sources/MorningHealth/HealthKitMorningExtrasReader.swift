import Foundation
import HealthKit
import MorningApple

// NOT YET RUN AGAINST REAL DATA. Like `HealthKitSleepReader`, this compiles and its rules
// are tested through the protocol, but the prompt, the queries and real samples need a
// signed build with the HealthKit capability on a device.
//
// Neither reading needs an Apple Watch: the iPhone counts steps itself, and an iPhone with
// a Sleep schedule records "in bed" time. A watch adds asleep stages.

/// Sleep analysis and step count, read-only, behind one Health prompt.
@MainActor
public final class HealthKitMorningExtrasReader: MorningHealthExtrasProviding {
    private let sleep: HealthKitSleepReader
    private let usageDescription: @Sendable () -> String?
    private var store: HKHealthStore?

    public init(usageDescription: @escaping @Sendable () -> String? = {
        Bundle.main.object(forInfoDictionaryKey: HealthKitSleepReader.usageDescriptionKey) as? String
    }) {
        self.usageDescription = usageDescription
        sleep = HealthKitSleepReader(usageDescription: usageDescription)
    }

    public func requestReadAccess() async throws { try await requestExtrasAccess() }

    public func requestExtrasAccess() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw SleepObservationError.unavailableOnDevice }
        guard let text = usageDescription(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SleepObservationError.missingUsageDescription
        }
        try await healthStore().requestAuthorization(toShare: [],
            read: [HKCategoryType(.sleepAnalysis), HKQuantityType(.stepCount)])
    }

    public func sleepSamples(in interval: DateInterval) async throws -> SleepReadOutcome {
        try await sleep.sleepSamples(in: interval)
    }

    /// One statistics collection per requested day, anchored at that day's own start (which
    /// can be 01:00 after a midnight clock change), summed with HealthKit's de-duplication
    /// across the phone and a watch. A collection splits a sample that crosses the boundary.
    /// A day with no sample, or a bucket that does not match the day, comes back nil, never 0.
    public func stepTotals(for days: [DateInterval]) async throws -> [Int?] {
        guard HKHealthStore.isHealthDataAvailable() else { return days.map { _ in nil } }
        let type = HKQuantityType(.stepCount)
        var totals: [Int?] = []
        for day in days {
            try Task.checkCancellation()
            let predicate = HKQuery.predicateForSamples(withStart: day.start, end: day.end, options: [])
            let query = HKStatisticsCollectionQueryDescriptor(predicate: .quantitySample(type: type, predicate: predicate),
                options: .cumulativeSum, anchorDate: day.start, intervalComponents: DateComponents(day: 1))
            guard let collection = try? await query.result(for: healthStore()),
                  let statistics = collection.statistics(for: day.start),
                  abs(statistics.startDate.timeIntervalSince(day.start)) < 1,
                  abs(statistics.endDate.timeIntervalSince(day.end)) < 1 else { totals.append(nil); continue }
            totals.append(statistics.sumQuantity().map { Int($0.doubleValue(for: .count()).rounded()) })
        }
        return totals
    }

    private func healthStore() -> HKHealthStore {
        if let store { return store }
        let created = HKHealthStore()
        store = created
        return created
    }
}
