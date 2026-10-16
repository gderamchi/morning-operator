import Foundation
import Testing
import MorningCore
@testable import MorningApple

/// Synthetic samples and a held permission response; no HealthKit access.
@Suite("Health connection and revocation lifecycle — fixture reader only", .timeLimit(.minutes(1)), .endsControllerWorkOnCancellation)
@MainActor
struct HealthConnectionLifecycleTests {
    @Test func explicitConnectionSavesOnlyAfterThePromptAndPreservesOtherChoices() async throws {
        let rig = HealthConnectionRig()
        defer { rig.close() }
        let location = try WeatherLocation(latitude: 48, longitude: 2, displayName: "SYNTHETIC_CITY")
        let choices = MorningBriefingSettings(calendarIDs: ["SYNTHETIC_CALENDAR"], weatherLocation: location,
            temperatureUnit: .fahrenheit)
        try rig.controller.updateSettings(choices)
        #expect(!rig.controller.settings.includesHealth && rig.reader.prompts == 0)
        rig.reader.holdsPrompt = true
        let connecting = Task { await rig.controller.enableHealth() }
        await rig.reader.waitForPrompt()
        #expect(rig.controller.isConnectingHealth && !rig.controller.settings.includesHealth)
        #expect(rig.reader.reads == 0, "Preparing permission does not itself fetch health data.")
        rig.reader.finishPrompt()
        #expect(await connecting.value)
        var included = choices; included.includesHealth = true
        #expect(rig.controller.settings == included && !rig.controller.isConnectingHealth)
        #expect(rig.controller.healthConnectionIssue == nil)
        let restored = rig.makeController()
        #expect(restored.settings == included)
    }

    @Test func aHandledPromptAndAnEmptyReadNeverBecomeAGrantedOrDeniedClaim() async throws {
        let rig = HealthConnectionRig()
        defer { rig.close() }
        #expect(await rig.controller.enableHealth())
        let recap = try #require(await rig.controller.refresh())
        #expect(rig.reader.prompts == 1 && rig.reader.reads == 1)
        #expect(recap.sleep.issue == .noRecord && recap.sleepObservation == nil)
        #expect(recap.sleep.statusText == "No sleep record was found since yesterday evening.")
        #expect(rig.controller.settings.includesHealth && rig.controller.healthConnectionIssue == nil)
    }

    @Test func disablingWhileTheSavedChoiceIsStillOffRejectsALatePermissionCompletion() async throws {
        let rig = HealthConnectionRig()
        defer { rig.close() }
        rig.reader.holdsPrompt = true
        let connecting = Task { await rig.controller.enableHealth() }
        await rig.reader.waitForPrompt()
        try rig.controller.disableHealth()
        #expect(!rig.controller.isConnectingHealth && !rig.controller.settings.includesHealth)
        rig.reader.finishPrompt()
        #expect(!(await connecting.value))
        #expect(!rig.controller.settings.includesHealth && rig.reader.reads == 0)
        #expect(rig.controller.healthConnectionIssue == nil)
        _ = await rig.controller.refresh(force: true)
        #expect(rig.reader.reads == 0)
    }

    @Test func concurrentConnectionActionsShareOnePrompt() async throws {
        let rig = HealthConnectionRig()
        defer { rig.close() }
        rig.reader.holdsPrompt = true
        let first = Task { await rig.controller.enableHealth() }
        await rig.reader.waitForPrompt()
        var secondStarted = false
        let second = Task { @MainActor in
            secondStarted = true
            return await rig.controller.enableHealth()
        }
        while !secondStarted { await Task.yield() }
        rig.reader.finishPrompt()
        let firstResult = await first.value, secondResult = await second.value
        #expect(firstResult && secondResult)
        #expect(rig.reader.prompts == 1)
    }

    @Test func backgroundDuringInitialPermissionPreparationRejectsItsLateCompletion() async throws {
        let rig = HealthConnectionRig()
        defer { rig.close() }
        let location = try WeatherLocation(latitude: 48, longitude: 2, displayName: "SYNTHETIC_CITY")
        let choices = MorningBriefingSettings(calendarIDs: ["SYNTHETIC_CALENDAR"], weatherLocation: location)
        try rig.controller.updateSettings(choices)
        rig.reader.holdsPrompt = true
        let connecting = Task { await rig.controller.enableHealth() }
        await rig.reader.waitForPrompt()
        #expect(rig.controller.isConnectingHealth && !rig.controller.settings.includesHealth)
        rig.controller.invalidateHealthForForeground()
        #expect(!rig.controller.isConnectingHealth && rig.controller.settings == choices)
        rig.reader.finishPrompt()
        #expect(!(await connecting.value))
        #expect(rig.controller.settings == choices && rig.controller.prepared == nil)
        #expect(rig.reader.reads == 0 && rig.controller.healthConnectionIssue == nil)
        #expect(rig.makeController().settings == choices, "A backgrounded permission completion must not change durable choices.")
    }

    @Test func forgettingDuringAuthorizationCannotSaveHealthIntoTheNewPrivacyGeneration() async throws {
        let rig = HealthConnectionRig()
        defer { rig.close() }
        rig.reader.holdsPrompt = true
        let connecting = Task { await rig.controller.enableHealth() }
        await rig.reader.waitForPrompt()
        let privacy = LocalDataControl(directory: rig.directory)
        let generation = try #require(try privacy.beginForget().generation)
        // The reset boundary changes even if a caller did not cancel the native prompt.
        try privacy.finishForget(expectedGeneration: generation)
        rig.reader.finishPrompt()
        #expect(!(await connecting.value))
        rig.controller.reloadSettings()
        #expect(!rig.controller.settings.includesHealth && !rig.controller.isConnectingHealth)
        #expect(!FileManager.default.fileExists(atPath: rig.directory.appendingPathComponent("briefing-settings.json").path))
    }

    @Test func failedOrUnavailablePermissionPreparationKeepsHealthOff() async throws {
        for failure in [SleepObservationError.unavailableOnDevice, .missingUsageDescription] {
            let rig = HealthConnectionRig()
            defer { rig.close() }
            rig.reader.promptFailure = failure
            #expect(!(await rig.controller.enableHealth()))
            #expect(!rig.controller.settings.includesHealth && !rig.controller.isConnectingHealth)
            #expect(rig.controller.healthConnectionIssue != nil && rig.reader.reads == 0)
        }
    }

    @Test func languageChangeRelocalizesTheFailureWithoutRetryingOrChangingChoices() async throws {
        let rig = HealthConnectionRig()
        defer { rig.close() }
        rig.reader.promptFailure = .unavailableOnDevice
        #expect(!(await rig.controller.enableHealth()))
        let choices = rig.controller.settings
        #expect(rig.controller.healthConnectionIssue == "Health data is not available on this device.")
        rig.controller.appLanguageDidChange(locale: Locale(identifier: "fr_FR"))
        #expect(rig.controller.healthConnectionIssue == "Les données de Santé ne sont pas disponibles sur cet appareil.")
        rig.controller.appLanguageDidChange(locale: Locale(identifier: "en_GB"))
        #expect(rig.controller.healthConnectionIssue == "Health data is not available on this device.")
        #expect(rig.controller.settings == choices && rig.reader.prompts == 1 && rig.reader.reads == 0)
        #expect(!rig.controller.isConnectingHealth && rig.controller.prepared == nil)
    }

    @Test func languageChangeRejectsALatePermissionCompletionWithoutRequestingAgain() async throws {
        let rig = HealthConnectionRig()
        defer { rig.close() }
        rig.reader.holdsPrompt = true
        let connecting = Task { await rig.controller.enableHealth() }
        await rig.reader.waitForPrompt()
        rig.controller.appLanguageDidChange(locale: Locale(identifier: "fr_FR"))
        rig.reader.finishPrompt()
        #expect(!(await connecting.value))
        #expect(!rig.controller.settings.includesHealth && !rig.controller.isConnectingHealth)
        #expect(rig.reader.prompts == 1 && rig.reader.reads == 0 && rig.controller.healthConnectionIssue == nil)
        #expect(!rig.makeController().settings.includesHealth)
    }

    @Test func returningFromHealthDiscardsSleepAndRequiresANewReadWithoutPrompting() async throws {
        let rig = HealthConnectionRig()
        defer { rig.close() }
        rig.reader.samples = rig.night
        #expect(await rig.controller.enableHealth())
        let before = try #require(await rig.controller.refresh())
        #expect(before.sleep.status == .fresh && rig.controller.permitsPlayback(of: before))
        rig.controller.invalidateHealthForForeground()
        #expect(rig.controller.prepared == nil && !rig.controller.permitsPlayback(of: before))
        // HealthKit returns this same empty result after revoked read permission.
        rig.reader.samples = []
        let after = try #require(await rig.controller.refresh())
        #expect(after.sleep.issue == .noRecord && after.sleepObservation == nil)
        #expect(!rig.controller.permitsPlayback(of: before))
        #expect(rig.reader.reads == 2 && rig.reader.prompts == 1)
        #expect(rig.controller.settings.includesHealth, "An empty read cannot identify revocation.")
    }

    @Test func aForcedEmptyOrFailedReadInvalidatesOldPinnedSleepAndIdenticalValuesPreserveIt() async throws {
        for failed in [false, true] {
            let rig = HealthConnectionRig()
            defer { rig.close() }
            rig.reader.samples = rig.night
            #expect(await rig.controller.enableHealth())
            let pinned = try #require(await rig.controller.refresh())
            _ = await rig.controller.refresh(force: true)
            #expect(rig.controller.permitsPlayback(of: pinned), "Identical fresh data does not replace pinned prose.")
            rig.reader.samples = []; rig.reader.failsRead = failed
            let updated = try #require(await rig.controller.refresh(force: true))
            #expect(updated.sleep.issue == (failed ? .notReadable : .noRecord))
            #expect(!rig.controller.permitsPlayback(of: pinned))
            rig.reader.samples = rig.night; rig.reader.failsRead = false
            _ = await rig.controller.refresh(force: true)
            #expect(!rig.controller.permitsPlayback(of: pinned), "A later result must never reauthorize old text.")
        }
    }
}

@MainActor
private final class HealthConnectionRig {
    nonisolated static let instant = SleepFixtures.date("2026-10-10T08:00:00Z")
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("HealthConnection-SYNTHETIC-\(UUID())")
    let reader = HealthConnectionReader()
    lazy var controller = makeController()
    var night: [SleepSample] {
        [SleepFixtures.sample(.asleepCore, "2026-10-09T23:40:00Z", "2026-10-10T07:00:00Z", source: "SYNTHETIC_SLEEP")]
    }
    func makeController() -> MorningBriefingController {
        MorningBriefingController(directory: directory,
            sleep: SleepObservationService(provider: reader), now: { Self.instant },
            timeZone: { TimeZone(identifier: "UTC")! }, localeIdentifier: "en_GB",
            clock: ManualTestClock()).watchedForHangs()
    }
    func close() {
        controller.cancelAndClear(); reader.finishPrompt()
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private final class HealthConnectionReader: SleepObservationProviding {
    var holdsPrompt = false
    var promptFailure: SleepObservationError?
    var samples: [SleepSample] = []
    var failsRead = false
    private(set) var prompts = 0
    private(set) var reads = 0
    private var pendingPrompt: CheckedContinuation<Void, Never>?
    private var observers: [CheckedContinuation<Void, Never>] = []
    func requestReadAccess() async throws {
        prompts += 1
        if let promptFailure { throw promptFailure }
        if holdsPrompt {
            await withCheckedContinuation { continuation in
                pendingPrompt = continuation
                let current = observers; observers = []
                for observer in current { observer.resume() }
            }
        }
    }
    func sleepSamples(in interval: DateInterval) async throws -> SleepReadOutcome {
        reads += 1
        if failsRead { throw SleepObservationError.unavailableOnDevice }
        return .samples(samples)
    }
    func waitForPrompt() async {
        guard pendingPrompt == nil else { return }
        await withCheckedContinuation { observers.append($0) }
    }
    func finishPrompt() { let pending = pendingPrompt; pendingPrompt = nil; pending?.resume() }
}
