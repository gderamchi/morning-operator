import Foundation
import MorningCore

/// A deadline may end an observed read. It cannot authorize sending or erase an unfinished dialogue.
public enum GmailMomentBudgetDecision: Sendable, Equatable {
    case waitForWork
    case pauseKeepingDialogue
    case advance(RoutineExecutionRecord.Outcome)
}

public enum GmailMomentBudgetPolicy {
    public static func decision(state: GmailMorningState, readOutcome: GmailMorningReadOutcome,
                                hasUnfinishedIntention: Bool, hasUncertainRecord: Bool,
                                workInFlight: Bool, hasOtherDialogue: Bool = false) -> GmailMomentBudgetDecision {
        if workInFlight || [.preparing, .preparingReply, .sending].contains(state) { return .waitForWork }
        if hasOtherDialogue || hasUncertainRecord || state == .uncertain || hasUnfinishedIntention ||
            [.askingForIntention, .reviewingReply, .reviewingSelfMessage].contains(state) { return .pauseKeepingDialogue }
        // Unavailable includes a failed presentation; a read receipt alone cannot turn that into success.
        if state == .unavailable { return .advance(.unavailable) }
        return .advance(readOutcome == .read ? .budgetFinished : .unavailable)
    }
}
