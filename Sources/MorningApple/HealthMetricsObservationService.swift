import Foundation

/// The app that wrote a sample, with only the hardware metadata HealthKit exposes.
/// A third-party app's product type is not proof of the tracker that measured it.
public struct HealthObservationSource: Sendable, Equatable, Hashable {
    public let bundleIdentifier: String
    public let name: String?
    public let productType: String?
    public let wasUserEntered: Bool
    public var kind: SleepSourceKind {
        .classify(bundleIdentifier: bundleIdentifier, productType: productType, wasUserEntered: wasUserEntered)
    }

    public init(bundleIdentifier: String, name: String? = nil, productType: String? = nil,
                wasUserEntered: Bool = false) {
        self.bundleIdentifier = bundleIdentifier
        let cleaned = name?.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
            .filter { !$0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) }
        self.name = cleaned.flatMap { $0.isEmpty ? nil : String($0.prefix(160)) }
        self.productType = productType
        self.wasUserEntered = wasUserEntered
    }
}

/// Three measurements, not a diagnosis or a derived recovery score.
public enum HealthMetric: String, Sendable, Equatable, Hashable, CaseIterable {
    case heartRateVariabilitySDNN, restingHeartRate, respiratoryRate
}

public struct HealthMetricSample: Sendable, Equatable {
    public let metric: HealthMetric
    /// SDNN in milliseconds; heart and respiratory rates in counts per minute.
    public let value: Double
    public let start: Date
    public let end: Date
    public let source: HealthObservationSource

    public init(metric: HealthMetric, value: Double, start: Date, end: Date, source: HealthObservationSource) {
        self.metric = metric; self.value = value; self.start = start; self.end = end; self.source = source
    }
}

public struct HealthMetricSnapshot: Sendable, Equatable {
    public let metric: HealthMetric
    public let readAt: Date
    public let samples: [HealthMetricSample]

    public init(metric: HealthMetric, readAt: Date, samples: [HealthMetricSample]) {
        self.metric = metric; self.readAt = readAt; self.samples = samples
    }

    /// Latest complete valid sample; equal timestamps use a stable source order.
    /// HealthKit does not disclose the Health app's source-priority resolution.
    public var latest: HealthMetricSample? {
        guard readAt.timeIntervalSinceReferenceDate.isFinite else { return nil }
        return samples.filter {
            $0.metric == metric && $0.value.isFinite && $0.value >= 0 &&
            (metric == .heartRateVariabilitySDNN || $0.value > 0) &&
            $0.start.timeIntervalSinceReferenceDate.isFinite && $0.end.timeIntervalSinceReferenceDate.isFinite &&
            $0.end >= $0.start && $0.end <= readAt &&
            $0.end > readAt.addingTimeInterval(-HealthMetricsObservationService.lookback)
        }.sorted {
            if $0.end != $1.end { return $0.end > $1.end }
            if $0.start != $1.start { return $0.start > $1.start }
            if $0.source.bundleIdentifier != $1.source.bundleIdentifier {
                return $0.source.bundleIdentifier < $1.source.bundleIdentifier
            }
            return $0.value < $1.value
        }.first
    }
}

/// No denied case: an empty read cannot disclose a HealthKit permission decision.
public enum HealthMetricBriefingInput: Sendable, Equatable {
    case excluded, notConnected, unavailableOnDevice, notReadable
    case snapshot(HealthMetricSnapshot)
}

public enum HealthMetricReadOutcome: Sendable, Equatable {
    case unavailableOnDevice
    case samples([HealthMetricSample])
}

@MainActor
public protocol HealthMetricsObservationProviding {
    /// Explicit expanded connection only; the native reader asks for sleep and these three types.
    func requestReadAccess() async throws
    func samples(for metric: HealthMetric, in interval: DateInterval) async throws -> HealthMetricReadOutcome
}

/// Values stay in memory. The controller owns opt-in, deadlines and publication identity.
@MainActor
public final class HealthMetricsObservationService {
    public nonisolated static let lookback: TimeInterval = 7 * 86_400
    private let provider: (any HealthMetricsObservationProviding)?
    public init() { provider = nil }
    public init(provider: any HealthMetricsObservationProviding) { self.provider = provider }
    public var isConnected: Bool { provider != nil }
    public func requestReadAccess() async throws {
        try Task.checkCancellation()
        guard let provider else { throw SleepObservationError.notConnected }
        try await provider.requestReadAccess()
        try Task.checkCancellation()
    }
    public func read(_ metric: HealthMetric, at now: Date) async throws -> HealthMetricBriefingInput {
        try Task.checkCancellation()
        guard let provider else { return .notConnected }
        guard now.timeIntervalSinceReferenceDate.isFinite else { return .notReadable }
        do {
            let result = try await provider.samples(for: metric,
                in: DateInterval(start: now.addingTimeInterval(-Self.lookback), end: now))
            try Task.checkCancellation()
            switch result {
            case .unavailableOnDevice: return .unavailableOnDevice
            case .samples(let samples): return .snapshot(.init(metric: metric, readAt: now, samples: samples))
            }
        } catch {
            try Task.checkCancellation()
            if error is CancellationError { throw error }
            return .notReadable
        }
    }
}

public struct PreparedHealthMetric: Sendable, Equatable, Identifiable {
    public var id: HealthMetric { metric }
    public let metric: HealthMetric
    public let section: MorningBriefingSection
    /// May be older; always inspect section.status and the recorded timestamp.
    public let observation: HealthMetricSample?
}
