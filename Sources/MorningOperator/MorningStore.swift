import Foundation
import Observation
import MorningCore
import MorningApple

enum MorningTab: String, CaseIterable, Identifiable {
    case today = "Today", learn = "Learn", setup = "Setup"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .today: "sun.max"
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
}

@MainActor @Observable
final class MorningStore {
    var tab: MorningTab = .today
    private(set) var routine: RoutineVersion?
    private(set) var session: RoutineSession?
    private(set) var previousRoutine: RoutineVersion?
    var notes = ""
    var notice: String?
    private(set) var busy = false
    private(set) var progress = 0.0
    private(set) var analysisStatus = ""
    private(set) var calendarSnapshot: CalendarSnapshot?
    private(set) var calendarBusy = false
    var readAloud = false
    let intelligence = AppleIntelligenceService()
    let speech = SpeechCoordinator()
    private let media = MediaObservationService()
    private let calendar = CalendarObservationService()
    private var notesSourceLabel = "Your written observation"
    private let snapshot: AtomicJSONFile<WorkspaceSnapshot>
    private var analysisTask: Task<Void, Never>?

    init() {
        let fixtureMode = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        let directory: URL
        if fixtureMode {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("MorningOperatorUITests-\(UUID().uuidString)")
        } else if let override = ProcessInfo.processInfo.environment["MORNING_OPERATOR_DATA_DIR"] {
            directory = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("MorningOperator", isDirectory: true)
        }
        snapshot = AtomicJSONFile(url: directory.appendingPathComponent("workspace.json"))
        if fixtureMode {
            routine = DemoFixtures.candidateRoutine
        } else if FileManager.default.fileExists(atPath: directory.appendingPathComponent("workspace.json").path) {
            do {
                let saved = try snapshot.load()
                guard saved.schemaVersion == 1 else {
                    notice = "This saved routine uses a newer format. Your file has been kept intact."
                    return
                }
                routine = saved.routine
                session = saved.session
                previousRoutine = saved.previousRoutine
                if session?.status == .running {
                    try session?.pause()
                    notice = "Your previous morning is paused. Resume when you're ready."
                    persist()
                }
            } catch {
                notice = "Couldn't restore your last routine: \(error.localizedDescription)"
            }
        }
    }

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

    func approve() {
        guard let routine, !busy, !sessionActive else { return }
        guard !routine.steps.isEmpty else { notice = "Add at least one step before approving."; return }
        self.routine = routine.approved()
        previousRoutine = nil
        session = self.routine.map { RoutineSession(routine: $0) }
        notice = "Routine approved. You're ready for your first morning."
        persist()
    }

    func updateSteps(_ steps: [RoutineStep]) {
        guard let routine, !sessionActive, !busy else { return }
        if routine.isApproved { previousRoutine = routine }
        self.routine = routine.revised(steps: steps, sourceLabel: routine.sourceLabel)
        session = nil
        notice = "Changes saved as a new draft. Review and approve when ready."
        persist()
    }

    func start() {
        guard let routine, !busy else { return }
        do {
            if session?.status == .paused { try session?.resume() }
            else if session?.status != .running {
                session = RoutineSession(routine: routine)
                try session?.start()
            }
            notice = nil
            persist()
            speakCurrentIfEnabled()
        } catch { notice = error.localizedDescription }
    }

    func pause() {
        do { try session?.pause(); speech.pause(); notice = nil; persist() }
        catch { notice = error.localizedDescription }
    }

    func resume() {
        do { try session?.resume(); notice = nil; persist(); speakCurrentIfEnabled() }
        catch { notice = error.localizedDescription }
    }

    func advance(skipping: Bool = false) {
        do {
            try session?.advance(skipping: skipping)
            speech.stop()
            notice = nil
            if session?.status == .completed {
                notice = "Morning complete. Your progress is saved on this device."
            }
            persist()
            if session?.status != .completed { speakCurrentIfEnabled() }
        } catch { notice = error.localizedDescription }
    }

    func stop() {
        speech.stop()
        do { try session?.stop(); notice = nil; persist() }
        catch { notice = error.localizedDescription }
    }

    func readCurrent() {
        guard let step = currentStep else { return }
        speech.speak("\(step.title). \(step.detail)")
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
        guard let snapshot = calendarSnapshot else { return }
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
        beginAnalysis()
        analysisTask = Task { [weak self] in
            guard let self else { return }
            await self.createCandidate(text: input, source: self.notesSourceLabel)
        }
    }

    func importObservation(_ url: URL) {
        guard !busy, !sessionActive else { return }
        beginAnalysis()
        analysisStatus = "Reading your selected observation…"
        analysisTask = Task { [weak self] in
            guard let self else { return }
            let granted = url.startAccessingSecurityScopedResource()
            defer { if granted { url.stopAccessingSecurityScopedResource() } }
            do {
                let extracted = try await media.extractText(from: url) { [weak self] fraction in
                    self?.progress = fraction
                }
                try Task.checkCancellation()
                notes = extracted
                notesSourceLabel = "Selected file, reviewed by you: \(url.lastPathComponent)"
                busy = false
                progress = 1
                notice = "Observation loaded. Review or trim the extracted text, then choose Find my routine."
            } catch {
                finishAnalysis(error: error)
            }
        }
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
            RoutineStep(title: "A calm start", detail: "Review what matters today.", kind: .briefing, durationMinutes: 3, isRequired: true)
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
        analysisStatus = "Finding the meaningful steps…"
    }

    private func createCandidate(text: String, source: String) async {
        do {
            analysisStatus = "Apple Intelligence is shaping your routine…"
            let candidate = try await intelligence.analyze(text: text, sourceLabel: source)
            try Task.checkCancellation()
            installCandidate(candidate)
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
    }

    private func speakCurrentIfEnabled() { if readAloud { readCurrent() } }

    private func persist() {
        do { try snapshot.save(WorkspaceSnapshot(routine: routine, session: session, previousRoutine: previousRoutine)) }
        catch { notice = "Your change is in memory, but saving failed: \(error.localizedDescription)" }
    }
}
