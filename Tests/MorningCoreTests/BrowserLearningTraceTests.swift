import Foundation
import Testing
@testable import MorningCore

@Suite("Bounded semantic browser lessons")
struct BrowserLearningTraceTests {
    @Test("Only known route families establish categories; unread and prose never do")
    func knownRoutes() {
        let examples: [(WebMorningSite, String, WebMorningBehavior?)] = [
            (.instagram, "https://www.instagram.com/", .browseFeed),
            (.instagram, "https://www.instagram.com/stories/person/123/", .watchStories),
            (.instagram, "https://www.instagram.com/reels/", .watchVideos),
            (.instagram, "https://www.instagram.com/direct/inbox/", nil),
            (.instagram, "https://www.instagram.com/person/?title=stories", nil),
            (.instagram, "https://www.instagram.com/accounts/login/", nil),
            (.youtube, "https://m.youtube.com/shorts/123", .watchVideos),
            (.youtube, "https://www.youtube.com/watch?v=stories", nil),
            (.reddit, "https://www.reddit.com/r/swift/", .browseFeed),
            (.reddit, "https://www.reddit.com/r/swift/comments/123/private/", nil),
            (.news, "https://www.lemonde.fr/", .readHeadlines),
            (.news, "https://www.lemonde.fr/article/private-title", nil),
            (.whatsapp, "https://web.whatsapp.com/", nil),
            (.gmail, "https://mail.google.com/mail/u/0/#inbox", nil)
        ]
        for (site, address, expected) in examples {
            #expect(BrowserRhythmPolicy.behavior(site: site, url: URL(string: address)) == expected)
        }
    }

    @Test("Invalid, reordered and cross-service segments never become a trace")
    func bounds() throws {
        #expect(BrowserLearningSegment(behavior: .browseFeed, startSeconds: .nan, endSeconds: 1, gestures: 1) == nil)
        #expect(BrowserLearningSegment(behavior: .browseFeed, startSeconds: 2, endSeconds: 1, gestures: 1) == nil)
        #expect(BrowserLearningSegment(behavior: .browseFeed, startSeconds: 0, endSeconds: 1, gestures: 0) == nil)
        let first = try segment(.browseFeed, 1, 3)
        let second = try segment(.watchStories, 4, 8)
        #expect(BrowserLearningTrace(site: .instagram, durationSeconds: 7, segments: [first, second]) == nil)
        #expect(BrowserLearningTrace(site: .instagram, durationSeconds: 9, segments: [second, first]) == nil)
        #expect(BrowserLearningTrace(site: .news, durationSeconds: 9, segments: [first]) == nil)
        #expect(BrowserLearningTrace(site: .whatsapp, durationSeconds: 9, segments: [try segment(.readUnread, 1, 3)]) == nil)
        #expect(BrowserLearningTrace(site: .instagram, durationSeconds: 9, segments: Array(repeating: first, count: 17)) == nil)
    }

    @Test("Cumulative segments preserve their prefix and cannot lend another site a category")
    func cumulative() throws {
        var accumulator = BrowserRhythmAccumulator(site: .instagram)
        let totals = try #require(BrowserRhythmTotals(distance: 200, movingSeconds: 2, scrollBursts: 2, clicks: 2))
        let first = try segment(.browseFeed, 0, 2)
        var updated = accumulator.update(totals, segments: [first])
        #expect(updated)
        updated = accumulator.update(totals, segments: [try segment(.browseFeed, 0, 3), try segment(.watchStories, 4, 5)])
        #expect(updated)
        updated = accumulator.update(totals, segments: [try segment(.watchVideos, 0, 3), try segment(.watchStories, 4, 5)])
        #expect(!updated)
        updated = accumulator.update(totals, segments: [])
        #expect(!updated)
        updated = accumulator.update(totals, segments: [try segment(.browseFeed, 0, 3), try segment(.readUnread, 4, 5)])
        #expect(!updated)
        #expect(accumulator.summary(durationSeconds: 6).learningTrace?.segments.map(\.behavior) == [.browseFeed, .watchStories])
    }

    @Test("Archive coding revalidates segments; candidate sanitizes all unrelated effects")
    func roundTripAndProposal() throws {
        let trace = try #require(BrowserLearningTrace(site: .instagram, durationSeconds: 20,
            segments: [try segment(.watchStories, 1, 8)]))
        #expect(try JSONDecoder().decode(BrowserLearningTrace.self, from: JSONEncoder().encode(trace)) == trace)
        let bad = Data(#"{"site":"instagram","durationSeconds":20,"segments":[{"behavior":"readUnread","startSeconds":1,"endSeconds":8,"gestures":2}]}"#.utf8)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(BrowserLearningTrace.self, from: bad) }
        let hostile = RoutineStep(title: "Observed", isRequired: true, automation: .savedObservation,
            target: .inAppWeb(site: URL(string: "https://evil.example")!), webBehavior: .readUnread, webLikesAllowed: true)
        let candidate = trace.applying(to: hostile, segment: 0)
        #expect(candidate.automation == nil && candidate.observationReference == nil && !candidate.isRequired)
        #expect(candidate.target == .inAppWeb(site: WebMorningSite.instagram.table.startURL))
        #expect(candidate.webBehavior == .watchStories && candidate.webLikesAllowed == false)
        #expect(RoutineExecutionSuggestion.isBoundedSuggestion(candidate))
    }

    private func segment(_ behavior: WebMorningBehavior, _ start: Double, _ end: Double) throws -> BrowserLearningSegment {
        try #require(BrowserLearningSegment(behavior: behavior, startSeconds: start, endSeconds: end, gestures: 2))
    }
}
