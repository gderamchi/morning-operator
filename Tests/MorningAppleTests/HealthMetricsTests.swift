import Foundation
import Testing
@testable import MorningApple

/// Synthetic fixtures only. No health store, device data or external account.
@Suite("Expanded Health measurements — scope, provenance and freshness", .timeLimit(.minutes(1)), .endsControllerWorkOnCancellation)
@MainActor
struct HealthMetricsTests {
    @Test func latestMeasurementFiltersMalformedFutureWrongTypeAndOldSamples() {
        let rig = MetricsRig(); defer { rig.close() }
        let valid = rig.sample(.heartRateVariabilitySDNN)
        let malformed = [rig.sample(.heartRateVariabilitySDNN, value: .nan),
            rig.sample(.heartRateVariabilitySDNN, at: MetricsRig.now.addingTimeInterval(1)),
            rig.sample(.respiratoryRate), rig.sample(.heartRateVariabilitySDNN, at: MetricsRig.now.addingTimeInterval(-8 * 86_400))]
        let snapshot = HealthMetricSnapshot(metric: .heartRateVariabilitySDNN, readAt: MetricsRig.now, samples: malformed + [valid])
        #expect(snapshot.latest == valid)
        let zero = rig.sample(.heartRateVariabilitySDNN, value: 0)
        #expect(HealthMetricSnapshot(metric: .heartRateVariabilitySDNN, readAt: MetricsRig.now, samples: [zero]).latest == zero)
        #expect(HealthMetricSnapshot(metric: .restingHeartRate, readAt: MetricsRig.now, samples: [rig.sample(.restingHeartRate, value: 0)]).latest == nil)
    }

    @Test func attributedMetricsAloneBecomeVisibleAndSpokenFactsInBothLanguages() throws {
        let rig = MetricsRig(); defer { rig.close() }
        for language in ["en_GB", "fr_FR"] {
            let document = try rig.compose(rig.inputs, locale: language)
            #expect(document.hasUsableFacts && document.healthMetrics.count == 3)
            #expect(document.healthMetrics.allSatisfy { $0.section.status == .fresh && $0.section.sourceLabels == ["Synthetic tracker app"] })
            #expect(document.segments.map(\.source) == [.introduction, .healthMetrics, .healthMetrics, .healthMetrics])
            #expect(document.spokenText.contains("SDNN") && document.spokenText.contains("Synthetic tracker app"))
            #expect(document.spokenText.contains(language == "fr_FR" ? "battements par minute" : "beats per minute"))
            #expect(document.healthMetrics.allSatisfy { $0.observation?.source.kind == .thirdPartyApp })
            for forbidden in ["%", "recovery", "readiness", "récupération", "normal", "healthy"] {
                #expect(!document.spokenText.lowercased().contains(forbidden))
            }
        }
    }

    @Test func measurementAgeAndReadAgeAreIndependentAndStrict() throws {
        let rig = MetricsRig(); defer { rig.close() }
        let old = rig.sample(.restingHeartRate, at: MetricsRig.now.addingTimeInterval(-86_400))
        let older = try rig.compose([.restingHeartRate: .snapshot(.init(metric: .restingHeartRate, readAt: MetricsRig.now, samples: [old]))])
        let section = try #require(older.healthMetrics.first)
        #expect(section.section.status == .stale && section.section.issue == .olderRecord)
        #expect(section.section.statusText.contains("Older measurement") && section.section.statusText.contains("Synthetic tracker app"))
        #expect(section.observation == old && !older.hasUsableFacts && older.spokenText.isEmpty)
        let expiredRead = try rig.compose([.restingHeartRate: .snapshot(.init(metric: .restingHeartRate,
            readAt: MetricsRig.now.addingTimeInterval(-1_800), samples: [old]))])
        #expect(expiredRead.healthMetrics.first?.section.issue == .expired)
        #expect(expiredRead.healthMetrics.first?.observation == nil)
        let fresh = try rig.compose(rig.inputs)
        #expect(fresh.validUntil == MetricsRig.now.addingTimeInterval(1_800))
    }

    @Test func emptyReadsNeverAssertZeroOrAHealthPermissionDecision() throws {
        let rig = MetricsRig(); defer { rig.close() }
        let empty = HealthMetric.allCases.reduce(into: [HealthMetric: HealthMetricBriefingInput]()) {
            $0[$1] = .snapshot(.init(metric: $1, readAt: MetricsRig.now, samples: []))
        }
        let document = try rig.compose(empty)
        #expect(!document.hasUsableFacts && document.spokenText.isEmpty)
        #expect(document.healthMetrics.allSatisfy { $0.section.status == .missing && $0.section.issue == .noRecord && $0.observation == nil })
        #expect(!document.healthMetrics.map { $0.section.statusText }.joined().contains("denied"))
    }

    @Test func sleepOnlySettingsNeverReadMetricsAndExplicitExpansionUsesOnlyTheUnionPrompt() async throws {
        let rig = MetricsRig(); defer { rig.close() }
        try rig.controller.updateSettings(.init(includesHealth: true))
        _ = await rig.controller.refresh(force: true)
        #expect(rig.metrics.calls.isEmpty && rig.metrics.prompts == 0)
        #expect(!rig.controller.settings.includesHealthMetrics)
        #expect(await rig.controller.enableHealth(includeMetrics: true))
        #expect(rig.controller.settings.includesHealth && rig.controller.settings.includesHealthMetrics)
        #expect(rig.metrics.prompts == 1 && rig.sleep.prompts == 0)
        let document = try #require(await rig.controller.refresh())
        #expect(document.healthMetrics.allSatisfy { $0.section.status == .fresh })
        #expect(Set(rig.metrics.calls) == Set(HealthMetric.allCases))
        #expect(rig.controller.permitsPlayback(of: document))
        let saved = try String(contentsOf: rig.directory.appendingPathComponent("briefing-settings.json"), encoding: .utf8)
        #expect(saved.contains("includesHealthMetrics"))
        #expect(!saved.contains("Synthetic tracker app") && !saved.contains("SDNN") && !saved.contains("readAt"))
    }

    @Test func disablingAndBackgroundingRejectLateExpandedPermissionWithoutChangingOtherChoices() async throws {
        for background in [false, true] {
            let rig = MetricsRig(); defer { rig.close() }
            try rig.controller.updateSettings(.init(includesHealth: true))
            rig.metrics.holdPrompt = true
            let attempt = Task { await rig.controller.enableHealth(includeMetrics: true) }
            await rig.metrics.waitForPrompt()
            if background { rig.controller.invalidateHealthForForeground() }
            else { try rig.controller.disableHealth() }
            rig.metrics.releasePrompt()
            #expect(!(await attempt.value))
            #expect(!rig.controller.settings.includesHealthMetrics)
            #expect(rig.controller.settings.includesHealth == background)
            #expect(rig.metrics.calls.isEmpty)
        }
    }

    @Test func oneUnansweredMetricDoesNotLoseTheOtherMeasurementsAtTheCommonDeadline() async throws {
        let rig = MetricsRig(); defer { rig.close() }
        rig.metrics.held = [.respiratoryRate]
        try rig.controller.updateSettings(.init(includesHealth: true, includesHealthMetrics: true))
        let attempt = Task { await rig.controller.refresh() }
        while rig.metrics.calls.count < 3 { await Task.yield() }
        await rig.clock.waitForSleepers()
        while rig.clock.sleeperCount > 1 { await Task.yield() }
        rig.clock.advance(by: .seconds(10))
        let document = try #require(await attempt.value)
        #expect(document.healthMetrics.filter { $0.section.status == .fresh }.count == 2)
        #expect(document.healthMetrics.first(where: { $0.metric == .respiratoryRate })?.section.issue == .notReadable)
        rig.metrics.releaseReads()
        await Task.yield()
        #expect(rig.controller.prepared?.id == document.id)
    }

    @Test func revokedEmptyRereadInvalidatesEarlierAttributedMetricPlayback() async throws {
        let rig = MetricsRig(); defer { rig.close() }
        #expect(await rig.controller.enableHealth(includeMetrics: true))
        let original = try #require(await rig.controller.refresh())
        #expect(rig.controller.permitsPlayback(of: original))
        rig.metrics.empty = true
        let empty = try #require(await rig.controller.refresh(force: true))
        #expect(empty.healthMetrics.allSatisfy { $0.section.issue == .noRecord })
        #expect(!rig.controller.permitsPlayback(of: original))
        rig.metrics.empty = false
        _ = await rig.controller.refresh(force: true)
        #expect(!rig.controller.permitsPlayback(of: original))
        try rig.controller.disableHealth()
        #expect(!rig.controller.settings.includesHealthMetrics && !rig.controller.settings.includesHealth)
        let count = rig.metrics.calls.count
        _ = await rig.controller.refresh(force: true)
        #expect(rig.metrics.calls.count == count)
    }

    @Test func sleepAttributionKeepsActualSourceNamesWithoutChangingTheUnionDuration() throws {
        let at = MetricsRig.now
        let samples = [SleepSample(stage: .asleepCore, start: at.addingTimeInterval(-8 * 3_600), end: at.addingTimeInterval(-3_600),
            sourceID: "invalid.example.tracker", sourceKind: .thirdPartyApp, sourceName: "Synthetic tracker app", sourceProductType: "iPhone17,1")]
        let document = try MorningBriefingComposer.prepare(calendar: .notConfigured, weather: .notConfigured,
            sleep: .snapshot(.init(readAt: at, samples: samples)), for: at, at: at, timeZoneIdentifier: "UTC")
        #expect(document.sleepObservation?.asleepMinutes == 420)
        #expect(document.sleep.sourceLabels == ["Synthetic tracker app"])
        #expect(document.sleepObservation?.sources.first?.name == "Synthetic tracker app")
    }
}

@MainActor
private final class MetricsRig {
    nonisolated static let now = Date(timeIntervalSince1970: 1_791_619_200)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ExpandedHealth-SYNTHETIC-\(UUID())")
    let metrics = MetricsReaderFixture()
    let sleep = MetricsSleepFixture()
    let clock = ManualTestClock()
    lazy var controller = MorningBriefingController(directory: directory, sleep: .init(provider: sleep),
        healthMetrics: .init(provider: metrics), now: { Self.now }, timeZone: { TimeZone(identifier: "UTC")! },
        localeIdentifier: "en_GB", clock: clock).watchedForHangs()
    var inputs: [HealthMetric: HealthMetricBriefingInput] {
        Dictionary(uniqueKeysWithValues: HealthMetric.allCases.map {
            ($0, .snapshot(.init(metric: $0, readAt: Self.now, samples: [sample($0)])))
        })
    }
    func sample(_ metric: HealthMetric, value: Double = 42, at: Date = MetricsRig.now.addingTimeInterval(-300)) -> HealthMetricSample {
        .init(metric: metric, value: value, start: at, end: at,
            source: .init(bundleIdentifier: "invalid.example.SYNTHETIC", name: "Synthetic tracker app", productType: "iPhone17,1"))
    }
    func compose(_ inputs: [HealthMetric: HealthMetricBriefingInput], locale: String = "en_GB") throws -> PreparedMorningBriefing {
        try MorningBriefingComposer.prepare(calendar: .notConfigured, weather: .notConfigured, healthMetrics: inputs,
            for: Self.now, at: Self.now, timeZoneIdentifier: "UTC", localeIdentifier: locale)
    }
    func close() {
        controller.cancelAndClear(); metrics.releasePrompt(); metrics.releaseReads()
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private final class MetricsReaderFixture: HealthMetricsObservationProviding {
    var holdPrompt = false, empty = false
    var held: Set<HealthMetric> = []
    private(set) var prompts = 0
    private(set) var calls: [HealthMetric] = []
    private var prompt: CheckedContinuation<Void, Never>?
    private var promptObservers: [CheckedContinuation<Void, Never>] = []
    private var reads: [CheckedContinuation<HealthMetricReadOutcome, any Error>] = []
    func requestReadAccess() async throws {
        prompts += 1
        if holdPrompt {
            await withCheckedContinuation { continuation in
                prompt = continuation
                let observers = promptObservers; promptObservers = []
                for observer in observers { observer.resume() }
            }
        }
    }
    func samples(for metric: HealthMetric, in interval: DateInterval) async throws -> HealthMetricReadOutcome {
        calls.append(metric)
        if held.contains(metric) { return try await withCheckedThrowingContinuation { reads.append($0) } }
        return .samples(empty ? [] : [.init(metric: metric, value: 42, start: interval.end.addingTimeInterval(-300),
            end: interval.end.addingTimeInterval(-300), source: .init(bundleIdentifier: "invalid.example.SYNTHETIC", name: "Synthetic tracker app"))])
    }
    func waitForPrompt() async {
        if prompt != nil { return }
        await withCheckedContinuation { promptObservers.append($0) }
    }
    func releasePrompt() { let pending = prompt; prompt = nil; pending?.resume() }
    func releaseReads() { let pending = reads; reads = []; for read in pending { read.resume(returning: .samples([])) } }
}

@MainActor
private final class MetricsSleepFixture: SleepObservationProviding {
    private(set) var prompts = 0
    func requestReadAccess() async throws { prompts += 1 }
    func sleepSamples(in interval: DateInterval) async throws -> SleepReadOutcome { .samples([]) }
}
