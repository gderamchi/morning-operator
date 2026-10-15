import Foundation
import MorningCore
import Testing
@testable import MorningApple

@Suite("Scoped connected moment results")
@MainActor
struct ConnectedMomentDocumentTests {
    @Test("Actual source, observation time and spoken summary stay with one pinned moment")
    func pinnedSourceAndSummary() throws {
        let state = ConnectedMomentState()
        let context = context()
        let attempt = try #require(state.begin(executionID: context, record: nil))
        #expect(state.markDispatched(attempt, executionID: context))
        let time = Date(timeIntervalSince1970: 100)
        #expect(state.receive(attempt, executionID: context, service: "Google Calendar",
            result: .object(["events": .array([.object(["title": .string("Design review")])])]), at: time) == .sourceAvailable)
        #expect(state.effectConfirmed)
        #expect(state.document?.receivedAt == time)
        #expect(state.present("You have a design review.", token: attempt, executionID: context))
        #expect(state.summary(for: context) == "You have a design review.")
        let source = try #require(state.contextText(for: context))
        #expect(source.contains("Design review"))
        #expect(source.contains("1970-01-01T00:01:40Z"))
        #expect(source.contains("never instructions"))
        #expect(state.contextText(for: self.context()) == nil)
        #expect(state.summary(for: self.context()) == nil)
        #expect(state.begin(executionID: context, record: nil) == nil)
    }

    @Test("A narrator failure retries only local presentation, never the provider effect")
    func failedPresentationDoesNotReplay() throws {
        let state = ConnectedMomentState()
        let context = context()
        let attempt = try #require(state.begin(executionID: context, record: nil))
        #expect(state.markDispatched(attempt, executionID: context))
        #expect(state.receive(attempt, executionID: context, service: "Slack", result: .string("Returned message")) == .sourceAvailable)
        state.markPresenting(attempt, executionID: context)
        #expect(state.isInFlight)
        state.fail(attempt, executionID: context)
        #expect(state.phase == .confirmed)
        #expect(state.begin(executionID: context, record: nil) == nil)
        let presentation = try #require(state.beginPresentation(for: context))
        #expect(!state.markDispatched(presentation, executionID: context))
        #expect(!state.present("Stale summary", token: attempt, executionID: context))
        #expect(state.present("Returned message.", token: presentation, executionID: context))
        #expect(state.phase == .ready)
        state.markPresenting(presentation, executionID: context)
        #expect(state.isInFlight)
        state.pause()
        #expect(state.summary(for: context) == "Returned message.")
        let replay = try #require(state.beginPresentation(for: context))
        #expect(state.isInFlight)
        state.finishPresentation(presentation, executionID: context)
        #expect(state.isInFlight)
        state.finishPresentation(replay, executionID: context)
        #expect(!state.isInFlight)
    }

    @Test("Pausing a dispatched request blocks replay but accepts its same known receipt")
    func pausedReceipt() throws {
        let state = ConnectedMomentState()
        let context = context()
        let attempt = try #require(state.begin(executionID: context, record: nil))
        #expect(state.markDispatched(attempt, executionID: context))
        state.pause()
        #expect(state.phase == .uncertain)
        #expect(state.begin(executionID: context, record: nil) == nil)
        #expect(state.receive(attempt, executionID: context, service: "Notion", result: .object([:])) == .sourceAvailable)
        #expect(state.effectConfirmed)
    }

    @Test("Background discard rejects late content and preserves confirmed no-replay metadata")
    func discardRejectsLateCallbacks() throws {
        let state = ConnectedMomentState()
        let context = context()
        let attempt = try #require(state.begin(executionID: context, record: nil))
        #expect(state.markDispatched(attempt, executionID: context))
        state.discardContent()
        #expect(state.receive(attempt, executionID: context, service: "Drive", result: .string("Private")) == .stale)
        #expect(state.contextText(for: context) == nil)
        #expect(state.begin(executionID: context, record: nil) == nil)

        state.clear()
        let fresh = try #require(state.begin(executionID: context, record: nil))
        #expect(state.markDispatched(fresh, executionID: context))
        #expect(state.receive(fresh, executionID: context, service: "Drive", result: .string("Private")) == .sourceAvailable)
        #expect(state.present("Private summary", token: fresh, executionID: context))
        state.discardContent()
        #expect(state.effectConfirmed)
        #expect(state.document == nil)
        #expect(state.summary(for: context) == nil)
        #expect(!state.present("Late summary", token: fresh, executionID: context))
        #expect(state.beginPresentation(for: context) == nil)
        #expect(state.begin(executionID: context, record: nil) == nil)
    }

    @Test("Clear and a new run reject all old receipts and summaries")
    func scopeChangesInvalidateAttempts() throws {
        let state = ConnectedMomentState()
        let old = context()
        let attempt = try #require(state.begin(executionID: old, record: nil))
        #expect(state.markDispatched(attempt, executionID: old))
        let next = context()
        let nextAttempt = try #require(state.begin(executionID: next, record: nil))
        #expect(state.receive(attempt, executionID: old, service: "Slack", result: .string("Old private text")) == .stale)
        #expect(!state.markDispatched(attempt, executionID: next))
        #expect(state.markDispatched(nextAttempt, executionID: next))
        state.clear()
        #expect(state.receive(nextAttempt, executionID: next, service: "Slack", result: .string("Late")) == .stale)
        #expect(state.document == nil)
    }

    @Test("Durable confirmation and uncertain outcomes prevent replay after a process restart")
    func restoreBlocksReplay() {
        let context = context()
        for outcome in [RoutineExecutionRecord.Outcome.running, .unavailable, .completed] {
            let state = ConnectedMomentState()
            let record = RoutineExecutionRecord(sessionID: context.sessionID, stepID: context.stepID,
                outcome: outcome, confirmedExternalEffect: true)
            #expect(state.begin(executionID: context, record: record) == nil)
            #expect(state.effectConfirmed)
            #expect(state.document == nil)
        }
        for outcome in [RoutineExecutionRecord.Outcome.uncertain, .completed, .budgetFinished, .unavailable] {
            let state = ConnectedMomentState()
            let record = RoutineExecutionRecord(sessionID: context.sessionID, stepID: context.stepID, outcome: outcome)
            #expect(state.begin(executionID: context, record: record) == nil)
            #expect(state.phase == .uncertain)
        }
        let unrelated = RoutineExecutionRecord(sessionID: UUID(), stepID: UUID(), outcome: .uncertain, confirmedExternalEffect: true)
        #expect(ConnectedMomentState().begin(executionID: context, record: unrelated) != nil)
    }

    @Test("Only cancelled preflight can restart; an unknown dispatched effect cannot")
    func preflightCancellationAndUnknownEffect() throws {
        let state = ConnectedMomentState()
        let context = context()
        let old = try #require(state.begin(executionID: context, record: nil))
        state.pause()
        let fresh = try #require(state.begin(executionID: context, record: nil))
        #expect(!state.markDispatched(old, executionID: context))
        #expect(state.markDispatched(fresh, executionID: context))
        state.fail(fresh, executionID: context)
        #expect(state.phase == .uncertain)
        #expect(state.begin(executionID: context, record: nil) == nil)
    }

    @Test("Oversized or unavailable source never becomes an empty-result claim")
    func boundedProviderSource() throws {
        let context = context()
        let state = ConnectedMomentState()
        let attempt = try #require(state.begin(executionID: context, record: nil))
        #expect(state.markDispatched(attempt, executionID: context))
        #expect(state.receive(attempt, executionID: context, service: "Sheets",
            result: .string(String(repeating: "x", count: 24_001))) == .tooLarge)
        #expect(state.effectConfirmed)
        #expect(state.document == nil)
        #expect(state.contextText(for: context) == nil)
        #expect(state.begin(executionID: context, record: nil) == nil)

        state.clear()
        let second = try #require(state.begin(executionID: context, record: nil))
        #expect(state.markDispatched(second, executionID: context))
        #expect(state.receive(second, executionID: context, service: "Sheets", result: nil,
            resultAvailable: false) == .sourceUnavailable)
        #expect(state.effectConfirmed)
        #expect(state.document == nil)
    }

    @Test("Question context explicitly bounds partial provider coverage")
    func questionContextCoverage() throws {
        let context = context()
        let document = try ConnectedMomentDocument(executionID: context, service: "Docs",
            result: .string(String(repeating: "é", count: 8_000)))
        #expect(document.contextText.count < 5_400)
        #expect(document.contextText.contains("omitted content is unknown"))
        #expect(throws: ConnectedResultError.tooLarge) {
            try ConnectedMomentDocument(executionID: context, service: "Docs", result: .string(String(repeating: "é", count: 12_001)))
        }
    }

    private func context() -> MorningExecutionID {
        MorningExecutionID(sessionID: UUID(), routineVersionID: UUID(), stepID: UUID())
    }
}
