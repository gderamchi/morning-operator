import Foundation
import MorningApple
import MorningCore

extension MorningStore {
    @discardableResult
    func handleNativeMomentUtterance(_ text: String) async -> Bool {
        guard !Task.isCancelled, !privacyBlocksWork, sessionActive, let session, let step = currentStep else { return false }
        let context = MorningExecutionID(sessionID: session.id, routineVersionID: session.routine.id, stepID: step.id)
        guard nativeMoment.accepts(text, context: context) else { return false }
        mailMorning.revokeReviewPreservingDraft(context: context)
        let generation = dataGeneration
        if session.status == .running { pause() }
        handsFreeVoice.interruptedRunningSession = false
        _ = await nativeMoment.respond(text, context: context)
        guard !Task.isCancelled, !privacyBlocksWork, dataGeneration == generation,
              self.session?.id == context.sessionID, currentStep?.id == context.stepID else { return true }
        refreshNativeActionCount()
        synchronizeMorningActivity()
        return true
    }

    func performNativeMoment(_ action: @escaping @MainActor (NativeMomentConversation, MorningExecutionID) async -> Void) {
        guard !privacyBlocksWork, sessionActive, let session, let step = currentStep else { return }
        let context = MorningExecutionID(sessionID: session.id, routineVersionID: session.routine.id, stepID: step.id)
        mailMorning.revokeReviewPreservingDraft(context: context)
        if session.status == .running { pause() }
        nativeMomentTask?.cancel()
        let generation = dataGeneration
        nativeMomentTask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled, dataGeneration == generation, !privacyBlocksWork,
                  self.session?.id == context.sessionID, currentStep?.id == context.stepID else { return }
            await action(nativeMoment, context)
            guard !Task.isCancelled, dataGeneration == generation, self.session?.id == context.sessionID,
                  currentStep?.id == context.stepID else { return }
            nativeMomentTask = nil
            refreshNativeActionCount()
            synchronizeMorningActivity()
        }
    }

    func confirmedNativeActionCount(for session: RoutineSession) -> Int? {
        if let count = nativeConfirmedActionCounts[session.id] { return count }
        guard let count = try? nativeMoment.confirmedActionCount(for: session) else { return nil }
        return count
    }

    func refreshNativeActionCount(for expected: RoutineSession? = nil) {
        guard let session = expected ?? session, let count = try? nativeMoment.confirmedActionCount(for: session) else { return }
        nativeConfirmedActionCounts[session.id] = count
    }

    func clearNativeMoment(forPrivacy: Bool = false) {
        if forPrivacy { nativeConfirmedActionCounts = [:] } else { refreshNativeActionCount() }
        if nativeMoment.context != nil { speech.stop() }
        nativeMomentTask?.cancel(); nativeMomentTask = nil
        nativeMoment.clear()
    }
}

#if DEBUG
/// Explicit simulator fixture: no EventKit permission request or Apple write is performed.
@MainActor final class NativeMomentUITestProvider: NativeMomentProviding {
    private var writes = 0
    func destination(for kind: CaptureDestination) throws -> NativeMomentDestination {
        .init(id: "synthetic-list", sourceID: "synthetic-account", title: "SYNTHETIC QA", sourceTitle: "SYNTHETIC local fixture", kind: kind)
    }
    func validateDestination(_ destination: NativeMomentDestination) throws {
        guard try self.destination(for: destination.kind) == destination else { throw NativeMomentError.destinationChanged }
    }
    func upcomingReminders() async throws -> [ReminderSummary] {
        [.init(id: "synthetic-reminder", title: "SYNTHETIC appeler le garage", notes: "", dueDate: Date().addingTimeInterval(3_600), listTitle: "SYNTHETIC QA", listID: "synthetic-list", sourceID: "synthetic-account", sourceTitle: "SYNTHETIC local fixture")]
    }
    func perform(_ action: NativeMomentAction) throws -> String {
        writes += 1
        return "synthetic-receipt-\(writes)"
    }
}
#endif
