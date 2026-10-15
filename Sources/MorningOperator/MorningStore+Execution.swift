import Foundation
import MorningCore
import MorningApple

extension MorningStore {
    var executionSummary: String? {
        guard let session else { return nil }
        let records = executionRecords.filter { $0.sessionID == session.id }
        guard !records.isEmpty else { return nil }
        let done = records.filter { $0.outcome == .completed || $0.outcome == .budgetFinished }.count
        let unavailable = records.filter { $0.outcome == .unavailable }.count
        let uncertain = records.filter { $0.outcome == .uncertain }.count
        let contents = records.reduce(0) { $0 + $1.observedContents }
        let likes = records.reduce(0) { $0 + $1.confirmedLikes }
        return AppLanguage.isFrench
            ? "\(done) étapes exécutées · \(unavailable) indisponibles · \(uncertain) à vérifier. \(contents) contenus observés, \(likes) likes confirmés."
            : "\(done) steps performed · \(unavailable) unavailable · \(uncertain) to check. \(contents) contents observed, \(likes) likes confirmed."
    }
    var currentExecutionRecord: RoutineExecutionRecord? {
        guard let session, let step = currentStep else { return nil }
        return executionRecords.last { $0.sessionID == session.id && $0.stepID == step.id }
    }

    @discardableResult
    func recordExecution(_ outcome: RoutineExecutionRecord.Outcome, observed: Int? = nil, likes: Int? = nil) -> Bool {
        guard !privacyBlocksWork, let session, let step = currentStep else { return false }
        let previous = executionRecords
        let old = currentExecutionRecord
        let record = RoutineExecutionRecord(sessionID: session.id, stepID: step.id, outcome: outcome,
            observedContents: observed ?? old?.observedContents ?? 0, confirmedLikes: likes ?? old?.confirmedLikes ?? 0)
        executionRecords.removeAll { $0.sessionID == session.id && $0.stepID == step.id }
        executionRecords.append(record)
        executionRecords = Array(executionRecords.suffix(256))
        guard persist() else { executionRecords = previous; return false }
        return true
    }

    func finishExecutionIfNeeded(skipping: Bool) {
        guard currentExecutionRecord?.outcome == .running || currentExecutionRecord == nil else { return }
        // An explicit Next ends the allotted moment; it does not certify a provider action.
        recordExecution(.skipped)
    }

    func completeAutomatedStep(sessionID: UUID, stepID: UUID) {
        guard !privacyBlocksWork, session?.id == sessionID, currentStep?.id == stepID,
              session?.status == .running, recordExecution(.completed) else { return }
        advance(commandID: stepID)
    }

    var webExecutionPlan: WebMorningExecutionPlan? {
        guard automatic, let session, session.routine.isApproved,
              let step = session.currentStep, let behavior = step.webBehavior,
              case .inAppWeb = step.target else { return nil }
        return WebMorningExecutionPlan(sessionID: session.id, stepID: step.id,
            behavior: behavior, likesAllowed: step.webLikesAllowed == true,
            initialObservedContentCount: currentExecutionRecord?.observedContents ?? 0,
            initialConfirmedLikeCount: currentExecutionRecord?.confirmedLikes ?? 0)
    }

    func receiveWebExecution(_ event: WebMorningExecutionEvent) {
        guard !privacyBlocksWork, session?.id == event.sessionID, currentStep?.id == event.stepID,
              sessionActive else { return }
        webExecutionEvent = event
        let outcome: RoutineExecutionRecord.Outcome
        switch event.state {
        case .running, .waitingForPage: outcome = .running
        case .paused, .cancelled: outcome = .interrupted
        case .needsSignIn, .unavailable: outcome = .unavailable
        case .uncertainAction: outcome = .uncertain
        case .finished: outcome = event.observedContentCount > 0 ? .budgetFinished : .unavailable
        }
        guard recordExecution(outcome, observed: event.observedContentCount, likes: event.confirmedLikeCount) else { pause(); return }
        if !event.spokenText.isEmpty, readAloud, session?.status == .running {
            executionSpeechTask?.cancel()
            executionSpeechTask = Task { [weak self] in
                guard let self else { return }
                try? await speech.speakAndWait(event.spokenText.joined(separator: ". "))
            }
        }
    }

    /// Time ends a budget. Only observed work may be recorded as performed.
    func finishAutomatedBudget(_ timer: StepTimer) -> Bool {
        guard automatic, session?.status == .running, currentStep?.id == timer.stepID,
              session?.id == timer.sessionID, let step = currentStep else { return false }
        if step.automation == .timedMoment {
            guard recordExecution(.budgetFinished) else { pause(); return true }
            advance(commandID: step.id)
            return true
        }
        guard step.webBehavior != nil else { return false }
        let record = currentExecutionRecord
        let performed = (record?.observedContents ?? 0) > 0 &&
            record?.outcome != .uncertain && record?.outcome != .unavailable && record?.outcome != .interrupted
        if performed { guard recordExecution(.budgetFinished) else { pause(); return true } }
        else if record?.outcome != .uncertain { guard recordExecution(.unavailable) else { pause(); return true } }
        advance(skipping: !performed, commandID: step.id)
        return true
    }
}
