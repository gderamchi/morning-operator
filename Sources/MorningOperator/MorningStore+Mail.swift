import Foundation
import MorningApple
import MorningCore

extension MorningStore {
    /// Capture an in-flight send before cancellation/background clears its private
    /// dialogue. The durable recap must preserve an unconfirmed external effect.
    func preserveMailExecutionBeforeInterruption() {
        guard let session, let step = currentStep,
              mailMorning.context?.sessionID == session.id, mailMorning.context?.stepID == step.id else { return }
        mailMorning.cancel()
        if let outcome = mailMorning.interruptedExecutionOutcome { recordExecution(outcome) }
    }

    func beginMailMorning() {
        guard !privacyBlocksWork, let session, session.status == .running,
              let step = session.currentStep, step.automation == .gmailInbox else { return }
        let context = MorningExecutionID(sessionID: session.id, routineVersionID: session.routine.id, stepID: step.id)
        handsFreeUtteranceHandler = { [weak self] text in await self?.handleMailUtterance(text) ?? false }
        if mailMorning.context == context {
            if mailMorning.isAwaitingResponse {
                connectedActionStatus = mailMorning.message
                return
            }
            if mailMorning.isCompleted {
                updateMailMorning(context: context)
                return
            }
            if [.preparing, .preparingReply, .sending].contains(mailMorning.state), connectedAPITask != nil { return }
        }
        let generation = dataGeneration
        let privacyGeneration = (try? LocalDataControl(directory: LocalDataControl.defaultDirectory).status())?.generation
        guard recordExecution(.running) else { return }
        connectedActionStatus = AppLanguage.isFrench ? "Je prépare vos mails…" : "Preparing your mail…"
        connectedAPITask?.cancel()
        connectedAPITask = Task { @MainActor [weak self] in
            guard let self else { return }
            await mailMorning.begin(context: context, generation: privacyGeneration)
            guard !Task.isCancelled, dataGeneration == generation, !privacyBlocksWork,
                  self.session?.id == context.sessionID, currentStep?.id == context.stepID else { return }
            connectedAPITask = nil
            updateMailMorning(context: context)
        }
    }

    func handleMailUtterance(_ text: String) async -> Bool {
        guard !privacyBlocksWork, let session, let step = session.currentStep, step.automation == .gmailInbox else { return false }
        let context = MorningExecutionID(sessionID: session.id, routineVersionID: session.routine.id, stepID: step.id)
        guard mailMorning.context == context, mailMorning.isAwaitingResponse else { return false }
        let generation = dataGeneration
        // Barge-in paused this same session. Resume state without redispatching
        // the mail step, or we would fetch/announce the Inbox over the reply.
        if session.status == .paused, handsFreeVoice.interruptedRunningSession { resumeForNext() }
        handsFreeVoice.interruptedRunningSession = false
        await mailMorning.respond(text, context: context)
        guard !Task.isCancelled, dataGeneration == generation, !privacyBlocksWork,
              self.session?.id == context.sessionID, currentStep?.id == context.stepID else { return true }
        updateMailMorning(context: context)
        return true
    }

    private func updateMailMorning(context: MorningExecutionID) {
        connectedActionStatus = mailMorning.message
        switch mailMorning.state {
        case .completed:
            if let outcome = mailMorning.completedExecutionOutcome, outcome != .completed {
                guard recordExecution(outcome) else { return }
                advance(skipping: true, commandID: context.stepID)
            } else {
                completeAutomatedStep(sessionID: context.sessionID, stepID: context.stepID)
            }
        case .uncertain:
            recordExecution(.uncertain)
        case .unavailable:
            recordExecution(.unavailable)
        default: break
        }
        synchronizeMorningActivity()
    }
}
