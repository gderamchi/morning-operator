import Foundation
import XCTest

/// Opt-in control of two separately installed native fixture apps. Root captures the movie
/// independently. This truth attachment is for scoring; it must not be fed to extraction.
@MainActor
final class ObservationBenchmarkTests: XCTestCase {
    func testNativeFixtureTransitionsAndVisibleEffects() throws {
        guard ProcessInfo.processInfo.environment["MO_OBSERVATION_BENCHMARK"] == "1" else {
            throw XCTSkip("Set MO_OBSERVATION_BENCHMARK=1 to control the installed synthetic fixture apps.")
        }
        let requestedVariant = ProcessInfo.processInfo.environment["MO_OBSERVATION_BENCHMARK_VARIANT"] ?? "baseline"
        guard ["baseline", "heldout"].contains(requestedVariant) else {
            throw BenchmarkFailure.precondition("Unknown benchmark variant; no fixture navigation was attempted.")
        }
        let inbox = Fixture(app: XCUIApplication(bundleIdentifier: "com.gibouu.morningoperator.fixture.inbox"),
                            name: "Cedar Mail", key: "fixture.inbox", detailKind: "Synthetic message")
        let calendar = Fixture(app: XCUIApplication(bundleIdentifier: "com.gibouu.morningoperator.fixture.calendar"),
                               name: "Lumen Calendar", key: "fixture.calendar", detailKind: "Synthetic event")
        let first = requestedVariant == "heldout" ? calendar : inbox
        let second = requestedVariant == "heldout" ? inbox : calendar
        var truth = BenchmarkTruth(variant: requestedVariant)
        defer { attachTruth(truth) }

        do {
            truth.record(kind: "manifest", outcome: "declared", fixture: nil, start: truth.stamp(),
                note: "Synthetic native apps; planned sequence \(first.key) → \(second.key) → \(first.key), one upward gesture per app, one detail in the first app. Forty-five seconds of explicit holds. Movie is captured independently; timestamps are test-runner system uptime, not assumed movie time zero.")
            try launch(first, truth: &truth)
            try hold(first, seconds: 7, page: "list", truth: &truth)
            try scrollOnce(first, truth: &truth)
            try hold(first, seconds: 7, page: "list", truth: &truth)
            try openObservedDetail(first, truth: &truth)
            try hold(first, seconds: 7, page: "detail", truth: &truth)
            try returnToList(first, truth: &truth)
            try hold(first, seconds: 3, page: "list", truth: &truth)
            try launch(second, truth: &truth)
            try hold(second, seconds: 7, page: "list", truth: &truth)
            try scrollOnce(second, truth: &truth)
            try hold(second, seconds: 7, page: "list", truth: &truth)
            try activate(first, truth: &truth)
            try hold(first, seconds: 7, page: "list", truth: &truth)
            truth.record(kind: "benchmarkComplete", outcome: "verified", fixture: first, start: truth.stamp(),
                         note: "Both issued upward gestures had independently observed row movement. Detail visibility and A→B→A foreground postconditions were verified. No read-intent or exact app-use duration claim is made.")
        } catch {
            truth.record(kind: "benchmarkFailure", outcome: "failed", fixture: nil, start: truth.stamp(),
                         note: String(describing: error))
            throw error
        }
    }

    private func launch(_ fixture: Fixture, truth: inout BenchmarkTruth) throws {
        let start = truth.stamp()
        fixture.app.launch()
        truth.record(kind: "launchAttempt", outcome: "issued", fixture: fixture, start: start)
        try verifyList(fixture)
        truth.record(kind: "foregroundObserved", outcome: "verified", fixture: fixture, start: start,
                     afterRows: rows(in: fixture), postconditions: ["runningForeground", "heading=\(fixture.name)", "listVisible"])
        attachScreen(fixture, name: "\(fixture.key)-launched")
    }

    private func activate(_ fixture: Fixture, truth: inout BenchmarkTruth) throws {
        let start = truth.stamp()
        fixture.app.activate()
        truth.record(kind: "activationAttempt", outcome: "issued", fixture: fixture, start: start)
        try verifyList(fixture)
        truth.record(kind: "foregroundReturnObserved", outcome: "verified", fixture: fixture, start: start,
                     afterRows: rows(in: fixture), postconditions: ["runningForeground", "heading=\(fixture.name)", "listVisible"])
        attachScreen(fixture, name: "\(fixture.key)-returned")
    }

    private func scrollOnce(_ fixture: Fixture, truth: inout BenchmarkTruth) throws {
        try verifyList(fixture)
        let list = fixture.app.scrollViews["benchmark.list"]
        let before = rows(in: fixture)
        guard before.count >= 2 else { throw BenchmarkFailure.precondition("Fewer than two visible fixture rows before scroll.") }
        let frame = list.frame
        let refreshed = fixture.app.scrollViews["benchmark.list"]
        guard refreshed.exists, refreshed.isHittable, refreshed.frame == frame else {
            throw BenchmarkFailure.precondition("Fixture list changed before the gesture; no scroll was attempted.")
        }
        let start = truth.stamp()
        refreshed.swipeUp()
        truth.record(kind: "gestureAttempt", outcome: "issued", fixture: fixture, start: start,
                     targetID: "benchmark.list", beforeRows: before, note: "Exactly one upward swipe; no retry or fallback gesture.")
        try verifyList(fixture)
        let after = rows(in: fixture)
        let commonMoved = before.contains { old in
            after.contains { new in new.id == old.id && abs(new.minY - old.minY) > 8 }
        }
        let changedSet = Set(before.map(\.id)) != Set(after.map(\.id))
        let observedMovement = after.count >= 2 && (commonMoved || changedSet)
        truth.record(kind: "scrollPostcondition", outcome: observedMovement ? "verified" : "unconfirmed", fixture: fixture,
                     start: start, targetID: "benchmark.list", beforeRows: before, afterRows: after,
                     postconditions: observedMovement ? ["visibleRowsOrTheirPositionsChanged", "listStillVisible"] : [],
                     note: "The attempted gesture and observed row movement are separate records; screen position is in accessibility points.")
        attachScreen(fixture, name: "\(fixture.key)-after-one-scroll")
        guard observedMovement else { throw BenchmarkFailure.postcondition("The one issued swipe had no verified row movement.") }
    }

    private func openObservedDetail(_ fixture: Fixture, truth: inout BenchmarkTruth) throws {
        try verifyList(fixture)
        let list = fixture.app.scrollViews["benchmark.list"]
        guard let row = rows(in: fixture).first(where: { $0.minY >= Double(list.frame.minY) + 8 && $0.maxY <= Double(list.frame.maxY) - 8 }) else {
            throw BenchmarkFailure.precondition("No fully visible known fixture row to open; no guessed tap.")
        }
        let target = fixture.app.buttons[row.id]
        guard target.exists, target.isHittable, abs(Double(target.frame.minY) - row.minY) < 1 else {
            throw BenchmarkFailure.precondition("The selected fixture row moved before its detail tap.")
        }
        let start = truth.stamp()
        target.tap()
        truth.record(kind: "detailTapAttempt", outcome: "issued", fixture: fixture, start: start, targetID: row.id)
        let kind = fixture.app.staticTexts["benchmark.detail.kind"]
        let title = fixture.app.staticTexts["benchmark.detail.title"]
        let itemID = String(row.id.suffix(2))
        guard kind.waitForExistence(timeout: 4), kind.isHittable,
              kind.label == "\(fixture.detailKind) \(itemID)", title.exists, title.isHittable,
              fixture.app.buttons["benchmark.back"].isHittable else {
            throw BenchmarkFailure.postcondition("The selected synthetic item's detail was not visibly verified.")
        }
        try requireNoPrompt(fixture)
        truth.record(kind: "detailVisible", outcome: "verified", fixture: fixture, start: start, targetID: row.id,
                     postconditions: ["detailKind=\(kind.label)", "detailTitle=\(title.label)", "backButtonVisible"],
                     note: "Visible detail is not evidence that a person mentally read it.")
        attachScreen(fixture, name: "\(fixture.key)-detail-\(itemID)")
    }

    private func returnToList(_ fixture: Fixture, truth: inout BenchmarkTruth) throws {
        try requireNoPrompt(fixture)
        let back = fixture.app.buttons["benchmark.back"]
        guard back.exists, back.isHittable else { throw BenchmarkFailure.precondition("Known fixture Back button is unavailable.") }
        let start = truth.stamp()
        back.tap()
        truth.record(kind: "backTapAttempt", outcome: "issued", fixture: fixture, start: start, targetID: "benchmark.back")
        try verifyList(fixture)
        guard !fixture.app.staticTexts["benchmark.detail.kind"].isHittable else {
            throw BenchmarkFailure.postcondition("Detail remained visible after Back.")
        }
        truth.record(kind: "listReturnObserved", outcome: "verified", fixture: fixture, start: start,
                     afterRows: rows(in: fixture), postconditions: ["listVisible", "detailNotVisible"])
    }

    private func hold(_ fixture: Fixture, seconds: TimeInterval, page: String, truth: inout BenchmarkTruth) throws {
        try requireNoPrompt(fixture)
        let target = page == "list" ? fixture.app.scrollViews["benchmark.list"] : fixture.app.scrollViews["benchmark.detail"]
        guard fixture.app.state == .runningForeground, target.exists, target.isHittable else {
            throw BenchmarkFailure.precondition("Fixture page was not visible before the bounded hold.")
        }
        let start = truth.stamp()
        Thread.sleep(forTimeInterval: seconds)
        try requireNoPrompt(fixture)
        guard fixture.app.state == .runningForeground, target.exists, target.isHittable else {
            throw BenchmarkFailure.postcondition("Fixture page was not visible after the bounded hold.")
        }
        truth.record(kind: "boundedHold", outcome: "verifiedEndpoints", fixture: fixture, start: start,
                     targetID: "benchmark.\(page)", postconditions: ["runningForegroundAtBothEndpoints", "\(page)VisibleAtBothEndpoints"],
                     note: "Requested hold \(seconds) seconds; endpoint observations do not assert unseen intermediate behavior or actual reading.")
    }

    private func verifyList(_ fixture: Fixture) throws {
        guard fixture.app.wait(for: .runningForeground, timeout: 6) else {
            throw BenchmarkFailure.postcondition("\(fixture.name) did not become the foreground application.")
        }
        try requireNoPrompt(fixture)
        let heading = fixture.app.staticTexts["benchmark.heading"]
        let list = fixture.app.scrollViews["benchmark.list"]
        guard heading.waitForExistence(timeout: 4), heading.isHittable, heading.label.contains(fixture.name),
              list.exists, list.isHittable else {
            throw BenchmarkFailure.postcondition("The named app heading and its list are not visibly established.")
        }
    }

    private func rows(in fixture: Fixture) -> [RowEvidence] {
        let list = fixture.app.scrollViews["benchmark.list"]
        guard list.exists else { return [] }
        return fixture.app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "benchmark.row."))
            .allElementsBoundByIndex.filter { $0.exists && $0.isHittable && $0.frame.intersects(list.frame) }
            .map { RowEvidence(id: $0.identifier, minY: Double($0.frame.minY), maxY: Double($0.frame.maxY)) }
            .sorted { $0.minY == $1.minY ? $0.id < $1.id : $0.minY < $1.minY }
    }

    private func requireNoPrompt(_ fixture: Fixture) throws {
        guard fixture.app.alerts.count == 0, fixture.app.sheets.count == 0,
              XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.count == 0 else {
            throw BenchmarkFailure.precondition("An unexpected prompt appeared; no prompt was accepted or dismissed.")
        }
    }

    private func attachScreen(_ fixture: Fixture, name: String) {
        let attachment = XCTAttachment(screenshot: fixture.app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attachTruth(_ truth: BenchmarkTruth) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let lines = try truth.events.map { String(decoding: try encoder.encode($0), as: UTF8.self) }.joined(separator: "\n") + "\n"
            let attachment = XCTAttachment(data: Data(lines.utf8), uniformTypeIdentifier: "public.plain-text")
            attachment.name = "observation-benchmark-\(truth.variant)-ground-truth.jsonl"
            attachment.lifetime = .keepAlways
            add(attachment)
        } catch { XCTFail("Could not encode the independently observed benchmark truth: \(error)") }
    }
}

private struct Fixture {
    let app: XCUIApplication
    let name: String
    let key: String
    let detailKind: String
}

private enum BenchmarkFailure: Error {
    case precondition(String), postcondition(String)
}

private struct RowEvidence: Codable {
    let id: String
    let minY: Double
    let maxY: Double
}

private struct BenchmarkStamp: Codable {
    let systemUptimeSeconds: Double
    let elapsedSeconds: Double
    let wallClockUTC: String
}

private struct BenchmarkEvent: Codable {
    let schemaVersion: Int
    let runID: UUID
    let variant: String
    let sequence: Int
    let kind: String
    let outcome: String
    let appKey: String?
    let appName: String?
    let targetID: String?
    let before: BenchmarkStamp
    let after: BenchmarkStamp
    let beforeRows: [RowEvidence]
    let afterRows: [RowEvidence]
    let observedVisiblePostconditions: [String]
    let note: String?
}

@MainActor
private struct BenchmarkTruth {
    let runID = UUID()
    let variant: String
    let originUptime = ProcessInfo.processInfo.systemUptime
    var events: [BenchmarkEvent] = []

    func stamp() -> BenchmarkStamp {
        let uptime = ProcessInfo.processInfo.systemUptime
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return .init(systemUptimeSeconds: uptime, elapsedSeconds: uptime - originUptime,
                     wallClockUTC: formatter.string(from: Date()))
    }

    mutating func record(kind: String, outcome: String, fixture: Fixture?, start: BenchmarkStamp,
                         targetID: String? = nil, beforeRows: [RowEvidence] = [], afterRows: [RowEvidence] = [],
                         postconditions: [String] = [], note: String? = nil) {
        events.append(.init(schemaVersion: 1, runID: runID, variant: variant, sequence: events.count,
                            kind: kind, outcome: outcome, appKey: fixture?.key, appName: fixture?.name,
                            targetID: targetID, before: start, after: stamp(), beforeRows: beforeRows,
                            afterRows: afterRows, observedVisiblePostconditions: postconditions, note: note))
    }
}
