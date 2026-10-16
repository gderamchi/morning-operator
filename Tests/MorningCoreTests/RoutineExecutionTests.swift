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

    @Test func unreadableDerivedBrowserProgressKeepsTheApprovedRoutineAndBlocksThisMoment() throws {
        struct Workspace: Codable { let routine: RoutineVersion; let records: [RoutineExecutionRecord] }
        let routine = RoutineVersion(createdAt: Date(timeIntervalSince1970: 1_000), sourceLabel: "My morning",
            steps: [RoutineStep(title: "Water", durationMinutes: 2)]).approved()
        let original = RoutineExecutionRecord(sessionID: UUID(), stepID: UUID(), outcome: .uncertain,
            observedContents: 4, confirmedLikes: 1, confirmedExternalEffect: true,
            updatedAt: Date(timeIntervalSince1970: 2_000))
        let saved = try JSONEncoder().encode(Workspace(routine: routine, records: [original]))
        let object = try #require(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        let record = try #require((object["records"] as? [[String: Any]])?.first)
        let invalid: [Any] = [NSNull(), "wrong type", ["observedCount": 4, "keys": ["raw page content"]],
            ["observedCount": 4, "keys": [], "isAvailable": NSNull()]]
        for badProgress in invalid {
            var brokenRecord = record, brokenWorkspace = object
            brokenRecord["webContentProgress"] = badProgress
            brokenWorkspace["records"] = [brokenRecord]
            let restored = try JSONDecoder().decode(Workspace.self, from: JSONSerialization.data(withJSONObject: brokenWorkspace))
            #expect(restored.routine == routine && restored.routine.isApproved)
            let kept = try #require(restored.records.first)
            #expect(kept.sessionID == original.sessionID && kept.stepID == original.stepID)
            #expect(kept.observedContents == 4 && kept.confirmedLikes == 1 && kept.confirmedExternalEffect == true)
            #expect(kept.outcome == .uncertain && kept.updatedAt == original.updatedAt)
            var progress = try #require(kept.webContentProgress)
            #expect(!progress.isAvailable && progress.observedCount == 4)
            #expect(throws: WebMorningContentProgress.ProgressError.invalidState) {
                try progress.observe(site: .reddit, fingerprint: "another item")
            }
            let again = try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(restored))
            #expect(again.routine == routine && again.records == restored.records)
            #expect(again.records.first?.webContentProgress?.isAvailable == false)
        }
    }

    @Test func progressWrittenBeforeTheAvailabilityMarkerStaysAvailableAndLegacyRecordsStayDistinct() throws {
        var progress = WebMorningContentProgress()
        try progress.observe(site: .reddit, fingerprint: "same item")
        let record = RoutineExecutionRecord(sessionID: UUID(), stepID: UUID(), outcome: .interrupted,
            observedContents: 1, webContentProgress: progress)
        let data = try JSONEncoder().encode(record)
        #expect(!String(decoding: data, as: UTF8.self).contains("isAvailable"))
        let restored = try JSONDecoder().decode(RoutineExecutionRecord.self, from: data)
        var retained = try #require(restored.webContentProgress)
        #expect(retained.isAvailable)
        let isNew = try retained.observe(site: .reddit, fingerprint: "same item")
        #expect(!isNew && retained.observedCount == 1)
        let legacy = RoutineExecutionRecord(sessionID: UUID(), stepID: UUID(), outcome: .interrupted, observedContents: 7)
        #expect(try JSONDecoder().decode(RoutineExecutionRecord.self, from: JSONEncoder().encode(legacy)).webContentProgress == nil)
        var newMoment = WebMorningContentProgress()
        #expect(newMoment.isAvailable)
        try newMoment.observe(site: .reddit, fingerprint: "same item")
        #expect(newMoment.observedCount == 1)
    }
}
