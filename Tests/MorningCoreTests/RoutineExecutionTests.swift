import Foundation
import Testing
@testable import MorningCore

struct RoutineExecutionTests {
    @Test func oldWebStepsStayManualUntilReviewed() throws {
        let step = RoutineStep(title: "News", target: .inAppWeb(site: WebMorningSite.news.table.startURL))
        let data = try JSONEncoder().encode(step)
        let restored = try JSONDecoder().decode(RoutineStep.self, from: data)
        #expect(restored.webBehavior == nil)
        #expect(restored.webLikesAllowed != true)
    }

    @Test func approvedSnapshotRetainsBehaviorWhileDraftChanges() throws {
        let step = RoutineStep(title: "Stories", target: .inAppWeb(site: WebMorningSite.instagram.table.startURL),
            webBehavior: .watchStories, webLikesAllowed: false)
        let routine = RoutineVersion(sourceLabel: "Personal choice", steps: [step]).approved()
        var session = RoutineSession(routine: routine)
        try session.start()
        var edited = step; edited.webBehavior = .browseFeed; edited.webLikesAllowed = true
        let draft = routine.revised(steps: [edited])
        #expect(session.currentStep?.webBehavior == .watchStories)
        #expect(session.currentStep?.webLikesAllowed == false)
        #expect(!draft.isApproved)
    }

    @Test func inferredRoutineCannotGrantBrowserActionsOrLikes() {
        let candidate = RoutineVersion(sourceLabel: "Untrusted proposal", steps: [
            RoutineStep(title: "Social", target: .inAppWeb(site: WebMorningSite.instagram.table.startURL),
                webBehavior: .browseFeed, webLikesAllowed: true)
        ])
        let draft = RoutineVersion.inferredDraft(from: candidate, preserving: nil)
        #expect(draft.steps[0].target == nil)
        #expect(draft.steps[0].webBehavior == nil)
        #expect(draft.steps[0].webLikesAllowed == nil)
    }

    @Test func executionReceiptRoundTripsOnlyOperationMetadata() throws {
        let receipt = RoutineExecutionRecord(sessionID: UUID(), stepID: UUID(), outcome: .uncertain,
            observedContents: 4, confirmedLikes: 1)
        let data = try JSONEncoder().encode(receipt)
        #expect(try JSONDecoder().decode(RoutineExecutionRecord.self, from: data) == receipt)
        let keys = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(keys.keys) == ["sessionID", "stepID", "outcome", "observedContents", "confirmedLikes", "updatedAt"])
    }

    @Test func confirmedProviderReceiptSurvivesAnUnavailablePresentation() throws {
        let receipt = RoutineExecutionRecord(sessionID: UUID(), stepID: UUID(), outcome: .unavailable,
            confirmedExternalEffect: true)
        let data = try JSONEncoder().encode(receipt)
        let restored = try JSONDecoder().decode(RoutineExecutionRecord.self, from: data)
        #expect(restored.outcome == .unavailable)
        #expect(restored.confirmedExternalEffect == true)
        let keys = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(keys.keys) == ["sessionID", "stepID", "outcome", "observedContents", "confirmedLikes", "confirmedExternalEffect", "updatedAt"])
    }
}
