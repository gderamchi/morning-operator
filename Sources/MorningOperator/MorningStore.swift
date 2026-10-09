import Foundation
import Observation
import MorningCore
import MorningApple

enum MorningTab: String, CaseIterable, Identifiable {
    case today = "Morning", review = "Review", captures = "Notes", learn = "Learn", setup = "Settings"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .today: "sun.horizon"
        case .review: "chart.bar.xaxis"
        case .captures: "square.and.pencil"
        case .learn: "sparkles"
        case .setup: "slider.horizontal.3"
        }
    }
}

private struct WorkspaceSnapshot: Codable, Sendable {
    var schemaVersion = 1
    var routine: RoutineVersion?
    var session: RoutineSession?
    var previousRoutine: RoutineVersion?
    var history: MorningHistory?
    var captures: [QuickCapture]?
    var receipts: [String: String]?
    var sessionTimeZone: String?
    var automatic: Bool?
    var readAloud: Bool?
    var sessionTimingInterrupted: Bool?
    var pendingCaptures: [String: String]?
    var voiceIdentifier: String?
    var observationNotes: String?
    var observationSource: String?
    var consumedMorningEntryIDs: [UUID]?
}

@MainActor @Observable
final class MorningStore {
    var tab: MorningTab = .today
    private(set) var routine: RoutineVersion?
    private(set) var session: RoutineSession?
    private(set) var previousRoutine: RoutineVersion?
    private(set) var notes = ""
    private(set) var observationSaveIssue: String?
    private var observationEditsNeedSave = false
    var notice: String?
    private(set) var busy = false
    private(set) var progress = 0.0
    private(set) var analysisStatus = ""
    private(set) var observationIssue: String?
    private(set) var pendingRecordingURL: URL?
    private(set) var pendingRecordingShouldAutoProcess = false
    private var pendingRecordingInterruption: String?
    private(set) var calendarSnapshot: CalendarSnapshot?
    private(set) var calendarBusy = false
    var readAloud = true
    var automatic = true
    var capturePresented = false
    var capturePrefill = ""
    var captureSource: QuickCaptureSource = .typed
    private(set) var captureBusy = false
    private(set) var history = MorningHistory()
    private(set) var captures: [QuickCapture] = []
    private(set) var receipts: [String: String] = [:]
    private(set) var pendingCaptures: [String: String] = [:]
    private var sessionTimingInterrupted = false
    private var sessionTimeZone = TimeZone.current.identifier
    let reminders = ReminderService()
    @ObservationIgnored private lazy var stepExecutor = MorningAppStepExecutor(speech: speech, calendar: calendar)
    @ObservationIgnored lazy var automation = MorningAutomationCoordinator(executor: stepExecutor)
    let intelligence = AppleIntelligenceService()
    let speech = SpeechCoordinator()
    let voiceCommands = MorningVoiceCommandListener()
    let invitation: MorningInvitationService
    private(set) var consumedMorningEntryIDs: [UUID] = []
    var storageIsAvailable: Bool { snapshotRecoveryError == nil }
    var voiceCommandPresented = false
    var morningDetailPresented = false
    private(set) var voiceCommandPreparing = false
    private(set) var voiceCommandFeedback: String?
    @ObservationIgnored private var voiceCommandTask: Task<Void, Never>?
    @ObservationIgnored private var voiceCommandAttempt: UUID?
    private var voiceCommandDeduplicator = MorningVoiceCommandDeduplicator()
    var voiceInputBlocksPlayback: Bool {
        voiceCommandPreparing || voiceCommands.isBusy || voiceCommands.needsAudioRelease
    }
    private let media = MediaObservationService()
    private let calendar = CalendarObservationService()
    private var notesSourceLabel = "Your written observation"
    private let snapshot: AtomicJSONFile<WorkspaceSnapshot>
    private let recordingRecovery: PendingScreenRecordingStore
    @ObservationIgnored private var snapshotRecoveryError: String?
    private var analysisTask: Task<Void, Never>?

    init() {
        let fixtureMode = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        let directory: URL
        if fixtureMode {
            let suppliedID = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--ui-testing-workspace=") }
                .flatMap { UUID(uuidString: String($0.dropFirst("--ui-testing-workspace=".count))) }
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("MorningOperatorUITests-\((suppliedID ?? UUID()).uuidString)")
        } else if let override = ProcessInfo.processInfo.environment["MORNING_OPERATOR_DATA_DIR"] {
            directory = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("MorningOperator", isDirectory: true)
        }
        snapshot = AtomicJSONFile(url: directory.appendingPathComponent("workspace.json"))
        recordingRecovery = PendingScreenRecordingStore(directory: directory)
        invitation = MorningInvitationService(directory: directory)
        defer { connectRecordingRecovery() }
        do {
            pendingRecordingURL = try recordingRecovery.recover()
            if pendingRecordingURL != nil {
                observationIssue = "Your saved recording is still on this device. Retry understanding it, or discard it."
                do { pendingRecordingInterruption = try recordingRecovery.interruptionNote() }
                catch { pendingRecordingInterruption = "The recording's coverage note could not be restored; its completeness is unknown." }
            }
        } catch {
            observationIssue = "Recording recovery needs attention: \(error.localizedDescription)"
        }
        let seedFixture = fixtureMode && !ProcessInfo.processInfo.arguments.contains("--ui-testing-empty-workspace")
        if seedFixture && !FileManager.default.fileExists(atPath: directory.appendingPathComponent("workspace.json").path) {
            routine = DemoFixtures.candidateRoutine
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-ten-moments") {
                let titles = ["A calm start", "The weather", "Today's calendar", "Your reminders", "People and messages",
                              "A little reading", "Make some tea", "A moment to move", "A little time to play", "One thought for later"]
                let kinds: [StepKind] = [.briefing, .briefing, .calendar, .custom, .messages,
                                         .entertainment, .custom, .wellbeing, .entertainment, .custom]
                routine = RoutineVersion(sourceLabel: "Demo fixture — synthetic ten-moment morning", steps:
                    titles.enumerated().map { index, title in
                        RoutineStep(title: title, detail: "Synthetic layout example.",
                                    kind: kinds[index], durationMinutes: 2)
                    })
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-approved") { routine = routine?.approved() }
            automatic = false
            readAloud = false
        } else if FileManager.default.fileExists(atPath: directory.appendingPathComponent("workspace.json").path) {
            do {
                let saved = try snapshot.load()
                guard saved.schemaVersion == 1 else {
                    snapshotRecoveryError = "This saved routine uses a newer format. Your file has been kept intact."
                    notice = snapshotRecoveryError
                    return
                }
                routine = saved.routine
                session = saved.session
                previousRoutine = saved.previousRoutine
                history = saved.history ?? MorningHistory()
                captures = saved.captures ?? []
                receipts = saved.receipts ?? [:]
                sessionTimeZone = saved.sessionTimeZone ?? TimeZone.current.identifier
                automatic = saved.automatic ?? true
                readAloud = saved.readAloud ?? true
                speech.voiceIdentifier = saved.voiceIdentifier
                notes = saved.observationNotes ?? ""
                notesSourceLabel = saved.observationSource ?? "Your written observation"
                sessionTimingInterrupted = saved.sessionTimingInterrupted ?? false
                pendingCaptures = saved.pendingCaptures ?? [:]
                consumedMorningEntryIDs = saved.consumedMorningEntryIDs ?? []
                if !pendingCaptures.isEmpty { notice = "A previous Apple app save was interrupted. Check Calendar or Reminders before adding that item again." }
                if session?.status == .running {
                    sessionTimingInterrupted = true
                    try session?.pause()
                    notice = "Your previous morning is paused. Resume when you're ready."
                    persist()
                }
            } catch {
                let message = "Couldn't restore your saved workspace: \(error.localizedDescription)"
                snapshotRecoveryError = message
                notice = "\(message) Your existing file is protected from changes."
            }
        }
    }

    var hasImportedObservation: Bool { !notes.isEmpty && notesSourceLabel != "Your written observation" }
    var hasPendingRecording: Bool { pendingRecordingURL != nil }
    var canStartRecording: Bool { !busy && !sessionActive && !hasPendingRecording }

    var totalMinutes: Int { routine?.steps.reduce(0) { $0 + $1.durationMinutes } ?? 0 }
    var stateLabel: String { session?.status.rawValue ?? (routine?.isApproved == true ? "ready" : "review") }
    var currentStep: RoutineStep? { session?.currentStep }
    var sessionActive: Bool { session?.status == .running || session?.status == .paused }
    var modelSummary: String { intelligence.capabilitySummary }

    func loadSample() {
        guard !sessionActive, !busy else {
            notice = "Finish or stop this morning before changing the routine."
            return
        }
        installCandidate(DemoFixtures.candidateRoutine)
        tab = .today
        notice = "Sample routine loaded. Review and edit it before starting. This is demo data, not learned behavior."
        persist()
    }

    @discardableResult
    func approve() -> Bool {
        guard let routine, !busy, !sessionActive else { return false }
        guard !routine.steps.isEmpty else { notice = "Add at least one step before approving."; return false }
        let savedPrevious = previousRoutine
        let savedSession = session
        self.routine = routine.approved()
        previousRoutine = nil
        session = self.routine.map { RoutineSession(routine: $0) }
        notice = "Routine approved. You're ready for your first morning."
        guard persist() else {
            self.routine = routine
            previousRoutine = savedPrevious
            session = savedSession
            return false
        }
        return true
    }

    func updateSteps(_ steps: [RoutineStep]) {
        guard let routine, !sessionActive, !busy else { return }
        if routine.isApproved { previousRoutine = routine }
        self.routine = routine.revised(steps: steps, sourceLabel: routine.sourceLabel)
        session = nil
        notice = "Changes saved as a new draft. Review and approve when ready."
        persist()
    }

    @discardableResult
    func start(entryID: UUID? = nil) -> Bool {
        guard let routine, !busy, !voiceInputBlocksPlayback else { return false }
        if let entryID, consumedMorningEntryIDs.contains(entryID) { return false }
        // Revealing an already running morning must not dispatch its speech again.
        if session?.status == .running { return true }
        let previousEntryIDs = consumedMorningEntryIDs
        do {
            if session?.status == .paused { try session?.resume() }
            else if session?.status != .running {
                archiveTerminalSession()
                sessionTimeZone = TimeZone.current.identifier
                sessionTimingInterrupted = false
                session = RoutineSession(routine: routine)
                try session?.start()
            }
            notice = nil
            if let entryID { rememberMorningEntry(entryID) }
            guard persist() else {
                consumedMorningEntryIDs = previousEntryIDs
                pauseAfterSaveFailure()
                return false
            }
            runCurrentIfEnabled()
            return true
        } catch { notice = error.localizedDescription; return false }
    }

    /// This receipt and a starting/resuming transition share workspace.json. A
    /// notification's separate durable consumption is intentionally at-most-once:
    /// if a save fails after consumption, the person uses the ordinary Start button.
    @discardableResult
    func handleMorningEntry(_ request: MorningEntryRequest, destination: MorningEntryDestination) -> Bool {
        guard destination != .wait else { return false }
        if destination == .start || destination == .resume { return start(entryID: request.id) }
        guard !consumedMorningEntryIDs.contains(request.id), storageIsAvailable else { return true }
        let previous = consumedMorningEntryIDs
        rememberMorningEntry(request.id)
        guard persist() else { consumedMorningEntryIDs = previous; return false }
        return true
    }

    private func rememberMorningEntry(_ id: UUID) {
        consumedMorningEntryIDs = Array((consumedMorningEntryIDs + [id]).suffix(64))
    }

    func pause() {
        cancelVoiceCommandTurn()
        automation.cancel()
        do { try session?.pause(); speech.stop(); notice = nil; persist() }
        catch { notice = error.localizedDescription }
    }

    func resume() {
        guard !voiceInputBlocksPlayback else { return }
        do {
            try session?.resume(); notice = nil
            guard persist() else { pauseAfterSaveFailure(); return }
            runCurrentIfEnabled()
        }
        catch { notice = error.localizedDescription }
    }

    func advance(skipping: Bool = false, commandID: UUID = UUID()) {
        guard !voiceInputBlocksPlayback else { return }
        automation.cancel()
        do {
            try session?.advance(skipping: skipping, commandID: commandID)
            speech.stop()
            notice = nil
            if session?.status == .completed {
                notice = "Morning complete. Your progress is saved on this device."
            }
            archiveTerminalSession()
            guard persist() else { pauseAfterSaveFailure(); return }
            if session?.status != .completed { runCurrentIfEnabled() }
        } catch { notice = error.localizedDescription }
    }

    func stop() {
        cancelVoiceCommandTurn()
        automation.cancel()
        speech.stop()
        do { try session?.stop(); archiveTerminalSession(); notice = nil; persist() }
        catch { notice = error.localizedDescription }
    }

    func readCurrent() {
        guard !voiceInputBlocksPlayback, let step = currentStep else { return }
        automation.cancel()
        speech.speak("\(step.title). \(step.detail)")
    }

    func openVoiceCommands() {
        guard sessionActive else { return }
        if session?.status == .running { pause() }
        voiceCommandFeedback = nil
        voiceCommandPresented = true
    }

    private var voiceContext: MorningVoiceCommandContext? {
        guard sessionActive, let session, let step = session.currentStep else { return nil }
        return .init(sessionID: session.id, routineVersionID: session.routine.id, stepID: step.id)
    }

    func listenForCommand(language: MorningVoiceCommandLanguage) {
        guard !voiceInputBlocksPlayback, session?.status == .paused, let context = voiceContext else { return }
        voiceCommandPreparing = true
        voiceCommandFeedback = nil
        let attempt = UUID()
        voiceCommandAttempt = attempt
        voiceCommandTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if voiceCommandAttempt == attempt {
                    voiceCommandPreparing = false
                    voiceCommandAttempt = nil
                    voiceCommandTask = nil
                }
            }
            do {
                try await speech.stopAndRelease()
                try Task.checkCancellation()
                guard voiceContext == context else { throw CancellationError() }
                let result = try await voiceCommands.listen(context: context, language: language)
                try Task.checkCancellation()
                guard let current = voiceContext,
                      let command = voiceCommandDeduplicator.consume(result, currentContext: current),
                      !voiceCommands.isBusy, !voiceCommands.needsAudioRelease else { throw CancellationError() }
                // Mic release is confirmed before any command can request new speech.
                voiceCommandPreparing = false
                try session?.applyVoiceCommand(command: command, commandID: result.id)
                archiveTerminalSession()
                guard persist() else { pauseAfterSaveFailure(); return }
                voiceCommandFeedback = "Heard: \(result.transcript)"
                voiceCommandPresented = false
                if command == .repeatStep { readCurrent() }
                else if session?.status == .running { runCurrentIfEnabled() }
            } catch {
                voiceCommandFeedback = error is CancellationError
                    ? "Listening stopped. Your morning is still paused." : error.localizedDescription
            }
        }
    }

    func cancelVoiceCommandTurn() {
        guard voiceInputBlocksPlayback else { return }
        voiceCommandTask?.cancel()
        Task { [weak self] in
            guard let self else { return }
            do { try await voiceCommands.cancel() }
            catch { voiceCommandFeedback = error.localizedDescription }
        }
    }

    func refreshCapabilities() { intelligence.refreshCapabilities() }

    func connectCalendar() {
        guard !calendarBusy else { return }
        calendarBusy = true
        Task { [weak self] in
            guard let self else { return }
            defer { calendarBusy = false }
            do {
                try await calendar.requestAccess()
                calendarSnapshot = try calendar.snapshot()
                notice = "Today's schedule was read from the local calendar store. No events were changed."
            } catch { notice = error.localizedDescription }
        }
    }

    func readCalendar() {
        guard !voiceInputBlocksPlayback, let snapshot = calendarSnapshot else { return }
        guard Calendar.current.isDateInToday(snapshot.dayStart) else {
            notice = "This schedule is from an earlier day. Refresh it before reading."
            return
        }
        let events = snapshot.events.prefix(5).map { event in
            let time = event.isAllDay ? "All day" : event.start.formatted(date: .omitted, time: .shortened)
            return "\(time), \(event.title)."
        }.joined(separator: " ")
        speech.speak(events.isEmpty ? "There are no events in today's local calendar snapshot." : "Here's your schedule. \(events)")
    }

    func analyzeNotes() {
        let input = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty, !busy, !sessionActive else { return }
        guard saveObservationEdits() else { return }
        let source = notesSourceLabel
        beginAnalysis()
        analysisTask = Task { [weak self] in
            guard let self else { return }
            await self.createCandidate(text: input, source: source)
        }
    }

    /// Returns true only after accepting ownership or starting an ordinary file import.
    /// The recorder must keep its ready URL until this returns true.
    @discardableResult
    func importObservation(_ url: URL, suggestRoutineWhenReady: Bool = false) -> Bool {
        let ownedRecording = ScreenRecordingFiles.isOwnedRecording(url) || recordingRecovery.owns(url)
        let selectedURL: URL
        if ownedRecording {
            guard retainRecording(url, interruptionNote: nil, automaticallyProcess: false),
                  let retainedURL = pendingRecordingURL else { return false }
            selectedURL = retainedURL
        } else {
            selectedURL = url
        }
        guard !busy, !sessionActive else {
            if ownedRecording {
                observationIssue = "Your recording is saved. Finish the current activity, then retry understanding it."
                return true
            }
            notice = "Finish the current activity before importing another observation."
            return false
        }
        // Save current corrections before a new import can replace the latest observation.
        // An app-owned recording has already been retained even if this write fails.
        guard saveObservationEdits() else { return ownedRecording }
        beginAnalysis()
        analysisStatus = "Reading your selected observation…"
        let interruptionNote = ownedRecording ? pendingRecordingInterruption : nil
        analysisTask = Task { [weak self] in
            guard let self else { return }
            let granted = selectedURL.startAccessingSecurityScopedResource()
            defer { if granted { selectedURL.stopAccessingSecurityScopedResource() } }
            do {
                let visibleText = try await media.extractText(from: selectedURL) { [weak self] fraction in
                    self?.progress = fraction
                }
                let extracted = interruptionNote.map { "[Recording coverage: \($0)]\n\n\(visibleText)" } ?? visibleText
                try Task.checkCancellation()
                notes = extracted
                notesSourceLabel = ownedRecording ? "Your explicitly shared screen recording" : "Selected file: \(selectedURL.lastPathComponent)"
                progress = 1
                guard persist() else {
                    busy = false
                    observationIssue = notice ?? "The extracted text could not be saved. Your recording is kept for retry."
                    return
                }
                if ownedRecording {
                    do {
                        try recordingRecovery.remove()
                        pendingRecordingURL = nil
                        pendingRecordingInterruption = nil
                    } catch {
                        busy = false
                        observationIssue = "Your extracted text is saved, but the temporary recording could not be removed. You can discard it below. \(error.localizedDescription)"
                        return
                    }
                }
                if suggestRoutineWhenReady, intelligence.isAvailable {
                    await createCandidate(text: extracted, source: notesSourceLabel)
                } else {
                    busy = false
                    notice = "Observation loaded. Review or trim the extracted text, then choose Suggest a routine."
                }
            } catch {
                finishAnalysis(error: error)
                observationIssue = notice
            }
        }
        return true
    }

    func retryPendingRecording() {
        guard let pendingRecordingURL, !busy, !sessionActive else { return }
        pendingRecordingShouldAutoProcess = false
        importObservation(pendingRecordingURL, suggestRoutineWhenReady: true)
    }

    /// Stages a finalized clip independently of scene visibility, app work, or routine state.
    /// OCR is started by the foreground coordinator; recovered clips require an explicit Retry.
    @discardableResult
    func retainFinalizedRecording(_ url: URL, interruptionNote: String? = nil) -> Bool {
        retainRecording(url, interruptionNote: interruptionNote, automaticallyProcess: true)
    }

    private func retainRecording(_ url: URL, interruptionNote: String?, automaticallyProcess: Bool) -> Bool {
        if let pendingRecordingURL, pendingRecordingURL.standardizedFileURL != url.standardizedFileURL {
            observationIssue = "Retry or discard your saved recording before adding another one."
            return false
        }
        let coverageNote = recordingRecovery.owns(url) ? pendingRecordingInterruption : interruptionNote
        do {
            let retainedURL = try recordingRecovery.retain(url, interruptionNote: coverageNote)
            pendingRecordingInterruption = coverageNote
            pendingRecordingShouldAutoProcess = automaticallyProcess
            pendingRecordingURL = retainedURL
            observationIssue = nil
            return true
        } catch {
            observationIssue = "Your recording has not been imported or discarded. \(error.localizedDescription)"
            return false
        }
    }

    private func connectRecordingRecovery() {
        #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(ScreenCaptureKit)
        if #available(iOS 27.0, *) {
            let recording = ScreenRecordingService.shared
            recording.onRecordingFinalized = { [weak self] url, interruptionNote in
                self?.retainFinalizedRecording(url, interruptionNote: interruptionNote) ?? false
            }
            if recording.hasRecordingToReview, let url = recording.recordedURL,
               retainFinalizedRecording(url, interruptionNote: recording.recordingInterruption) {
                _ = recording.takeRecording()
            }
        }
        #endif
    }

    func discardPendingRecording() {
        guard !busy, pendingRecordingURL != nil else { return }
        do {
            try recordingRecovery.remove()
            pendingRecordingURL = nil
            pendingRecordingShouldAutoProcess = false
            pendingRecordingInterruption = nil
            observationIssue = nil
            notice = "Saved recording discarded. Any previously saved observation text remains available."
        } catch {
            observationIssue = "The saved recording could not be removed. \(error.localizedDescription)"
        }
    }

    func dismissObservationIssue() {
        observationIssue = nil
    }

    /// Editing keeps the original import/source context. The UI binds to this live value,
    /// so a later lifecycle save cannot restore a stale copy over newly imported text.
    func updateObservationNotes(_ text: String) {
        guard !busy, !sessionActive, text != notes else { return }
        notes = text
        observationEditsNeedSave = true
    }

    /// Flush on explicit editing/lifecycle boundaries, not on every keystroke or load.
    /// Failed writes keep the current text and dirty state available for retry.
    @discardableResult
    func saveObservationEdits() -> Bool {
        guard observationEditsNeedSave else { return true }
        return persist()
    }

    func clearObservation() {
        guard !busy else { return }
        notes = ""
        notesSourceLabel = "Your written observation"
        observationEditsNeedSave = true
        persist()
    }

    func cancelAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
        // Retain busy until the worker acknowledges cancellation, so a second model run cannot overlap.
        analysisStatus = "Stopping analysis…"
    }

    func useManualRoutine() {
        guard !sessionActive, !busy else { notice = "Stop this morning before creating another routine."; return }
        installCandidate(RoutineVersion(number: 1, sourceLabel: "Created by you", steps: [
            RoutineStep(title: "A calm start", detail: "Review what matters today.", kind: .briefing, durationMinutes: 3, isRequired: true, automation: .spokenNote)
        ], isApproved: false))
        tab = .today
        persist()
    }

    func restorePreviousRoutine() {
        guard !busy, !sessionActive, let previousRoutine else { return }
        routine = previousRoutine
        session = RoutineSession(routine: previousRoutine)
        self.previousRoutine = nil
        notice = "Your previous approved routine is restored."
        persist()
    }

    private func installCandidate(_ candidate: RoutineVersion) {
        if let routine, routine.isApproved { previousRoutine = routine }
        var draft = candidate
        draft.number = (routine?.number ?? 0) + 1
        draft.isApproved = false
        routine = draft
        session = nil
    }

    private func beginAnalysis() {
        guard !sessionActive, !busy else { return }
        busy = true
        progress = 0
        notice = nil
        observationIssue = nil
        analysisStatus = "Finding the meaningful steps…"
    }

    private func createCandidate(text: String, source: String) async {
        do {
            analysisStatus = "Apple Intelligence is shaping your routine…"
            let candidate = try await intelligence.analyze(text: text, sourceLabel: source)
            try Task.checkCancellation()
            installCandidate(RoutineVersion.inferredDraft(from: candidate, preserving: routine))
            busy = false
            progress = 1
            tab = .today
            notice = "Here's a first interpretation. Edit anything that doesn't fit, then approve it."
            persist()
        } catch { finishAnalysis(error: error) }
    }

    private func finishAnalysis(error: Error) {
        busy = false
        progress = 0
        notice = error is CancellationError ? "Analysis stopped. Your existing routine is unchanged." : error.localizedDescription
        if hasPendingRecording || hasImportedObservation { observationIssue = notice }
    }

    func saveVoicePreference() { persist() }

    func executionPreferencesChanged() {
        automation.cancel()
        speech.stop()
        guard persist() else { pauseAfterSaveFailure(); return }
        runCurrentIfEnabled()
    }

    func openCapture(text: String = "", source: QuickCaptureSource = .typed) {
        capturePrefill = text
        captureSource = source
        capturePresented = true
    }

    @discardableResult
    func saveCapture(kind: QuickCaptureKind, text: String, date: Date?, duration: Int = 30,
                     saveToSystem: Bool, id: UUID) async -> Bool {
        guard !captureBusy else { return false }
        guard pendingCaptures[id.uuidString] == nil else {
            notice = "This save has an unconfirmed outcome. Check the Apple app before trying again."
            return false
        }
        captureBusy = true
        defer { captureBusy = false }
        do {
            let capture = try QuickCapture(id: id, kind: kind, text: text, requestedDate: date, source: captureSource)
            if saveToSystem {
                if kind == .reminder {
                    try ReminderDraft(title: text, dueDate: date, notifyAtDueTime: date != nil).validate()
                } else if kind == .calendarIdea {
                    guard let date else { notice = "Choose a date and time for the calendar event."; return false }
                    try CalendarEventDraft(title: text, startDate: date,
                        endDate: date.addingTimeInterval(Double(duration) * 60)).validate()
                }
            }
            // A retry after a known successful write must never create a duplicate system item.
            if saveToSystem && receipts[id.uuidString] == nil {
                let receipt: EventKitWriteReceipt
                switch kind {
                case .reminder:
                    try await reminders.requestReminderAccess()
                    pendingCaptures[id.uuidString] = "Reminders"
                    upsertCapture(capture)
                    guard persist() else { pendingCaptures[id.uuidString] = nil; return false }
                    receipt = try reminders.createReminder(from: ReminderDraft(title: text, dueDate: date,
                        notifyAtDueTime: date != nil))
                case .calendarIdea:
                    guard let date else { notice = "Choose a date and time for the calendar event."; return false }
                    try await reminders.requestCalendarWriteAccess()
                    pendingCaptures[id.uuidString] = "Calendar"
                    upsertCapture(capture)
                    guard persist() else { pendingCaptures[id.uuidString] = nil; return false }
                    receipt = try reminders.createCalendarEvent(from: CalendarEventDraft(title: text,
                        startDate: date, endDate: date.addingTimeInterval(Double(duration) * 60)))
                default: notice = "Choose a reminder or calendar event to save to Apple apps."; return false
                }
                receipts[id.uuidString] = receipt.id
                pendingCaptures[id.uuidString] = nil
            }
            upsertCapture(capture)
            notice = saveToSystem ? "Saved in Apple \(kind == .reminder ? "Reminders" : "Calendar") and your notes." : "Saved on this device."
            let saved = persist()
            if !saved && saveToSystem {
                notice = "Apple saved this item, but the local receipt could not be saved. Check Apple \(kind == .reminder ? "Reminders" : "Calendar") before trying again."
            }
            // A completed external write dismisses the draft even if the local disk write failed.
            return saved || saveToSystem
        } catch {
            notice = pendingCaptures[id.uuidString] == nil ? error.localizedDescription :
                "The Apple app save could not be confirmed. Check it before retrying. \(error.localizedDescription)"
            return false
        }
    }

    private func upsertCapture(_ capture: QuickCapture) {
        if let index = captures.firstIndex(where: { $0.id == capture.id }) { captures[index] = capture }
        else { captures.insert(capture, at: 0) }
    }

    func daySummary(_ date: Date) -> MorningDaySummary? {
        try? history.day(containing: date)
    }

    var weekSummary: SevenDaySummary? { try? history.sevenDaySummary(endingOn: Date()) }

    private func runCurrentIfEnabled() {
        guard !voiceInputBlocksPlayback else { return }
        guard let session, session.status == .running else { return }
        if automatic {
            stepExecutor.spokenEnabled = readAloud
            automation.runCurrentStep(in: session) { [weak self] context in
                guard let self, self.session?.id == context.executionID.sessionID,
                      self.session?.currentStep?.id == context.executionID.stepID,
                      self.session?.status == .running else { return }
                self.advance(commandID: context.commandID)
            }
        } else if readAloud { readCurrent() }
    }

    func handleSpeechInterruption() {
        guard session?.status == .running, speech.state == .paused else { return }
        let message = speech.lastError ?? "Audio was interrupted. Continue when you're ready."
        pause()
        notice = message
    }

    private func pauseAfterSaveFailure() {
        automation.cancel()
        speech.stop()
        if session?.status == .running { try? session?.pause() }
        // Preserve the disk-error message and do not dispatch another action.
    }

    private func archiveTerminalSession() {
        guard let session, session.status == .completed || session.status == .stopped else { return }
        do {
            history.upsert(try MorningRunRecord(session: session, timeZoneIdentifier: sessionTimeZone,
                isSynthetic: session.routine.sourceLabel.localizedCaseInsensitiveContains("demo fixture"),
                timingInterrupted: sessionTimingInterrupted))
        } catch { notice = "This morning could not be added to history: \(error.localizedDescription)" }
    }

    @discardableResult
    private func persist() -> Bool {
        if let snapshotRecoveryError {
            notice = "\(snapshotRecoveryError) Your existing file is protected; new changes cannot be saved until it can be restored."
            if observationEditsNeedSave { observationSaveIssue = notice }
            return false
        }
        do {
            try snapshot.save(WorkspaceSnapshot(routine: routine, session: session, previousRoutine: previousRoutine,
                history: history, captures: captures, receipts: receipts, sessionTimeZone: sessionTimeZone,
                automatic: automatic, readAloud: readAloud, sessionTimingInterrupted: sessionTimingInterrupted,
                pendingCaptures: pendingCaptures, voiceIdentifier: speech.voiceIdentifier,
                observationNotes: notes.isEmpty ? nil : notes, observationSource: notes.isEmpty ? nil : notesSourceLabel,
                consumedMorningEntryIDs: consumedMorningEntryIDs))
            observationEditsNeedSave = false
            if let observationSaveIssue, notice == observationSaveIssue { notice = nil }
            observationSaveIssue = nil
            return true
        } catch {
            notice = "Your change is in memory, but saving failed: \(error.localizedDescription)"
            if observationEditsNeedSave { observationSaveIssue = notice }
            return false
        }
    }
}
