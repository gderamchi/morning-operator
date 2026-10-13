import Foundation
import Testing
@testable import MorningApple

@Suite("City suggestion fragments — fake source only")
@MainActor
struct CitySuggestionLookupTests {
    @Test func failedFragmentIsAskedAgainInsteadOfReusingOlderResults() async throws {
        let source = SuggestionSourceFixture()
        let lookup = source.lookup()
        let first = Task { try await lookup.wait(for: "Pa") }
        await until { source.started == ["Pa"] }
        lookup.succeeded()
        try await first.value
        try await lookup.wait(for: "Pa")
        #expect(source.started == ["Pa"], "A completed fragment is reused.")

        let failing = Task { try await lookup.wait(for: "To") }
        await until { source.started == ["Pa", "To"] }
        lookup.failed(URLError(.notConnectedToInternet))
        await #expect(throws: URLError.self) { try await failing.value }
        #expect(source.discards == 1, "A failed source is discarded with its older results.")

        let retry = Task { try await lookup.wait(for: "To") }
        await until { source.started == ["Pa", "To", "To"] }
        lookup.succeeded()
        try await retry.value
    }

    @Test func cancelledFragmentIsNotTreatedAsCompleted() async throws {
        let source = SuggestionSourceFixture()
        let lookup = source.lookup()
        let cancelled = Task { try await lookup.wait(for: "To") }
        await until { source.started == ["To"] }
        cancelled.cancel()
        await #expect(throws: CancellationError.self) { try await cancelled.value }

        var returned = false
        let again = Task { try await lookup.wait(for: "To"); returned = true }
        await settle()
        #expect(!returned, "Results are not attributed to a fragment the source has not completed.")
        #expect(source.started == ["To"], "A fragment still in flight is not sent twice.")
        lookup.succeeded()
        try await again.value
        #expect(returned)
    }

    @Test func resetForgetsTheFragmentAndEndsAPendingWait() async throws {
        let source = SuggestionSourceFixture()
        let lookup = source.lookup()
        let first = Task { try await lookup.wait(for: "Pa") }
        await until { source.started == ["Pa"] }
        lookup.succeeded()
        try await first.value

        let pending = Task { try await lookup.wait(for: "Par") }
        await until { source.started == ["Pa", "Par"] }
        lookup.reset()
        await #expect(throws: CancellationError.self) { try await pending.value }
        #expect(source.discards == 1)

        let afterReset = Task { try await lookup.wait(for: "Pa") }
        await until { source.started == ["Pa", "Par", "Pa"] }
        lookup.succeeded()
        try await afterReset.value
    }

    /// Waits for main-actor work that is already scheduled; no timers are involved.
    private func until(_ condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async {
        for _ in 0..<10_000 where !condition() { await Task.yield() }
        #expect(condition(), sourceLocation: sourceLocation)
    }

    private func settle() async {
        for _ in 0..<100 { await Task.yield() }
    }
}

@MainActor
private final class SuggestionSourceFixture {
    private(set) var started: [String] = []
    private(set) var discards = 0
    func lookup() -> CitySuggestionLookup {
        CitySuggestionLookup(start: { [self] in started.append($0) }, discard: { [self] in discards += 1 })
    }
}
