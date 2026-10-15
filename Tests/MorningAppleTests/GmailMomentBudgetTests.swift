import Foundation
import Testing
import MorningCore
@testable import MorningApple

@Suite("Gmail persistent moment budget")
struct GmailMomentBudgetTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func verifiedEmptyOrUnreadReadMayEndBudgetButUnknownSourceCannot() {
        for state: GmailMorningState in [.choosingMailAction, .askingToReply, .completed] {
            #expect(GmailMomentBudgetPolicy.decision(state: state, readOutcome: .read,
                hasUnfinishedIntention: false, hasUncertainRecord: false, workInFlight: false) == .advance(.budgetFinished))
        }
        #expect(GmailMomentBudgetPolicy.decision(state: .askingToReply, readOutcome: .unavailable,
            hasUnfinishedIntention: false, hasUncertainRecord: false, workInFlight: false) == .advance(.unavailable))
        #expect(GmailMomentBudgetPolicy.decision(state: .unavailable, readOutcome: .read,
            hasUnfinishedIntention: false, hasUncertainRecord: false, workInFlight: false) == .advance(.unavailable))
    }

    @Test func deadlineWaitsForProviderDraftingQuestionAndExactNarration() {
        for state: GmailMorningState in [.preparing, .preparingReply, .sending] {
            #expect(GmailMomentBudgetPolicy.decision(state: state, readOutcome: .read,
                hasUnfinishedIntention: false, hasUncertainRecord: false, workInFlight: false) == .waitForWork)
        }
        for state: GmailMorningState in [.askingToReply, .reviewingReply, .reviewingSelfMessage, .completed, .uncertain] {
            #expect(GmailMomentBudgetPolicy.decision(state: state, readOutcome: .read,
                hasUnfinishedIntention: true, hasUncertainRecord: true, workInFlight: true) == .waitForWork)
        }
        #expect(GmailMomentBudgetPolicy.decision(state: .completed, readOutcome: .read,
            hasUnfinishedIntention: false, hasUncertainRecord: false, workInFlight: false) == .advance(.budgetFinished))
    }

    @Test func deadlinePreservesIntentionsDraftsAndUncertainEffects() {
        for state: GmailMorningState in [.askingForIntention, .reviewingReply, .reviewingSelfMessage, .uncertain] {
            #expect(GmailMomentBudgetPolicy.decision(state: state, readOutcome: .read,
                hasUnfinishedIntention: false, hasUncertainRecord: false, workInFlight: false) == .pauseKeepingDialogue)
        }
        #expect(GmailMomentBudgetPolicy.decision(state: .askingToReply, readOutcome: .read,
            hasUnfinishedIntention: true, hasUncertainRecord: false, workInFlight: false) == .pauseKeepingDialogue)
        #expect(GmailMomentBudgetPolicy.decision(state: .askingToReply, readOutcome: .read,
            hasUnfinishedIntention: false, hasUncertainRecord: true, workInFlight: false) == .pauseKeepingDialogue)
        #expect(GmailMomentBudgetPolicy.decision(state: .askingToReply, readOutcome: .read,
            hasUnfinishedIntention: false, hasUncertainRecord: false, workInFlight: false,
            hasOtherDialogue: true) == .pauseKeepingDialogue)
    }

    @MainActor @Test func pauseRestoreAndExtendKeepSameBudgetAndOpenedMoment() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("gmail-budget-\(UUID())")
        defer { try? FileManager.default.removeItem(at: path) }
        let session = UUID(), step = UUID()
        var original = StepTimer(sessionID: session, stepID: step, minutes: 5, at: now)
        original.markOpened(at: now)
        original.pause(at: now.addingTimeInterval(60))
        try StepTimerFile.save(original, directory: path)
        var restored = try #require(StepTimerFile.load(directory: path))
        #expect(restored.remaining(at: now.addingTimeInterval(1_000)) == 240)
        let end = restored.endsAt
        let extended = restored.extend(expectedEnd: end, at: now.addingTimeInterval(1_000))
        #expect(extended == .extended(end.addingTimeInterval(120)))
        restored.resume(at: now.addingTimeInterval(1_000))
        try StepTimerFile.save(restored, directory: path)
        let saved = try #require(StepTimerFile.load(directory: path))
        #expect(saved.belongs(to: session, stepID: step)); #expect(saved.openedAt == original.openedAt)
        #expect(saved.extensionCount == 1); #expect(saved.remaining(at: now.addingTimeInterval(1_000)) == 360)
    }

    @MainActor @Test func expiredBudgetExtensionRestoresTwoMinutesWithoutReopening() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("gmail-budget-end-\(UUID())")
        defer { try? FileManager.default.removeItem(at: path) }
        var timer = StepTimer(sessionID: UUID(), stepID: UUID(), minutes: 1, at: now)
        timer.markOpened(at: now)
        let deadline = now.addingTimeInterval(60)
        let claimed = timer.claimAlert(at: deadline)
        #expect(claimed)
        timer.pause(at: deadline)
        try StepTimerFile.save(timer, directory: path)
        let changed = try #require(StepTimerFile.update(sessionID: timer.sessionID, stepID: timer.stepID, directory: path, {
            $0.extend(expectedEnd: timer.endsAt, at: now.addingTimeInterval(600))
        }))
        var resumed = changed.0
        resumed.resume(at: now.addingTimeInterval(600))
        #expect(resumed.openedAt == timer.openedAt); #expect(resumed.remaining(at: now.addingTimeInterval(600)) == 120)
        #expect(!resumed.hasAlertedCurrentEnd)
        let duplicate = resumed.extend(expectedEnd: timer.endsAt, at: now.addingTimeInterval(600))
        #expect(duplicate == .duplicate)
    }
}
