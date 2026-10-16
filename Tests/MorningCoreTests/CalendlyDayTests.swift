import Foundation
import Testing
@testable import MorningCore

@Suite("Calendly approved identity and appointments starting today")
struct CalendlyDayTests {
    private let paris = TimeZone(identifier: "Europe/Paris")!
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private func target() throws -> CalendlyDayTarget { try .init(connectionID: "ca_synthetic", userURI: "https://api.calendly.com/users/actual-user", userName: "Actual owner") }
    private func event(_ id: Int, name: String = "Appointment") throws -> CalendlyDayEvent {
        try .init(uri: "https://api.calendly.com/scheduled_events/event-\(id)", name: name,
                  start: date("2026-03-29T10:00:00Z"), end: date("2026-03-29T11:00:00Z"), locationKind: .video)
    }

    @Test func runtimeDayUsesPhoneDSTAndUTCQueryBoundsIncludeExactlyMidnight() throws {
        let spring = try CalendlyDayWindow(at: date("2026-03-29T10:00:00Z"), timeZone: paris)
        #expect(spring.end.timeIntervalSince(spring.start) == 23 * 3_600)
        #expect(spring.minStartTime == "2026-03-28T22:59:59Z" && spring.maxStartTime == "2026-03-29T22:00:00Z")
        let autumn = try CalendlyDayWindow(at: date("2026-10-25T12:00:00Z"), timeZone: paris)
        #expect(autumn.end.timeIntervalSince(autumn.start) == 25 * 3_600)
        let next = try CalendlyDayWindow(at: spring.end, timeZone: paris)
        #expect(next.start == spring.end && next != spring)
        #expect(try CalendlyDayWindow(at: spring.start, timeZone: TimeZone(identifier: "America/Los_Angeles")!).start != spring.start)
    }

    @Test func targetPersistsOnlyRealScopedIdentityAndRejectsUntrustedURIs() throws {
        let selected = try target(), encoded = try JSONEncoder().encode(selected)
        #expect(try JSONDecoder().decode(CalendlyDayTarget.self, from: encoded) == selected)
        let text = String(decoding: encoded, as: UTF8.self)
        #expect(!text.contains("timeZone") && !text.contains("start_time") && !text.contains("email"))
        for uri in ["me", "https://evil.invalid/users/actual-user", "https://api.calendly.com/organizations/actual-user",
                    "https://api.calendly.com/users/actual-user?other=1", "https://api.calendly.com/users/actual-user/", "https://api.calendly.com/users/%2e%2e"] {
            #expect(throws: (any Error).self) { try CalendlyDayTarget(connectionID: "ca_synthetic", userURI: uri, userName: "Named") }
        }
        #expect(throws: (any Error).self) { try CalendlyDayTarget(connectionID: "ca_synthetic", userURI: selected.userURI, userName: "\n") }
    }

    @Test func routineTargetRoundTripRetainsItsSelectionButPortableImportDoesNotAcquireIt() throws {
        let selected = try target(), operation = RoutineStepTarget.calendlyDay(selected)
        try operation.validateIntegration()
        let bytes = try JSONEncoder().encode(operation)
        #expect(try JSONDecoder().decode(RoutineStepTarget.self, from: bytes) == operation)
        #expect(operation.integrationRoute == .api && operation.isConnectedAction && operation.destination == .connectedService)
        let step = RoutineStep(title: "Calendly", kind: .calendar, durationMinutes: 3, target: operation)
        let routine = RoutineVersion(sourceLabel: "SYNTHETIC identity selection", steps: [step], isApproved: true)
        let pinned = RoutineSession(routine: routine)
        #expect(try JSONDecoder().decode(RoutineSession.self, from: JSONEncoder().encode(pinned)).routine.steps[0].target == operation)
        var preferences = RoutinePreferenceJournal()
        try preferences.upsert(RoutinePreference(target: step, presence: .keep, durationMinutes: 5))
        let restoredPreferences = try JSONDecoder().decode(RoutinePreferenceJournal.self, from: JSONEncoder().encode(preferences))
        let kept = try restoredPreferences.reconcile(steps: []).steps
        #expect(kept[0].target == operation && kept[0].durationMinutes == 5)
        let portable = try PortableRoutineDocument(routine: routine, detail: .includeDetails)
        let encoded = try portable.encoded(), imported = try PortableRoutineDocument.decode(encoded).importedDraft(replacing: nil)
        #expect(imported.steps[0].target == nil && imported.steps[0].automation == nil && !imported.isApproved)
        #expect(!String(decoding: encoded, as: UTF8.self).contains(selected.userURI))
        let bad = Data("{\"kind\":\"calendlyDay\",\"account\":{\"connectionID\":\"ca_synthetic\",\"userURI\":\"me\",\"userName\":\"Named\"}}".utf8)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(RoutineStepTarget.self, from: bad) }
    }

    @Test func summariesUseSingularPluralAndNeverTurnPartialEmptyIntoEmptyDay() throws {
        let at = date("2026-03-29T10:00:00Z"), window = try CalendlyDayWindow(at: at, timeZone: paris)
        let one = try CalendlyDayDocument(target: target(), window: window, receivedAt: at, events: [event(1)], isPartial: false)
        #expect(one.summary(french: true).contains("Un rendez-vous a été lu") && one.summary(french: false).contains("One appointment was read"))
        let many = try CalendlyDayDocument(target: target(), window: window, receivedAt: at, events: (0..<4).map { try event($0) }, isPartial: true, excludedCount: 1, cancelledCount: 1)
        #expect(many.summary(french: true).contains("4 rendez-vous ont été lus") && many.summary(french: true).contains("Un autre rendez-vous reste"))
        #expect(many.summary(french: false).contains("One cancelled appointment") && many.summary(french: false).contains("One result outside today"))
        let partial = try CalendlyDayDocument(target: target(), window: window, receivedAt: at, events: [], isPartial: true)
        let empty = try CalendlyDayDocument(target: target(), window: window, receivedAt: at, events: [], isPartial: false)
        #expect(partial.summary(french: false).contains("More appointments may follow") && !partial.summary(french: false).contains("No Calendly appointments start today"))
        #expect(empty.summary(french: false).contains("No Calendly appointments start today"))
    }

    @Test func readingExpiresOnAgeDayAndZoneAndCannotIncludeYesterdayStarts() throws {
        let at = date("2026-03-29T10:00:00Z"), window = try CalendlyDayWindow(at: at, timeZone: paris)
        let doc = try CalendlyDayDocument(target: target(), window: window, receivedAt: at, events: [], isPartial: false)
        #expect(doc.isCurrent(at: at.addingTimeInterval(300), timeZone: paris))
        #expect(!doc.isCurrent(at: at.addingTimeInterval(301), timeZone: paris) && !doc.isCurrent(at: at.addingTimeInterval(-1), timeZone: paris))
        #expect(!doc.isCurrent(at: at, timeZone: TimeZone(identifier: "Asia/Tokyo")!))
        let nearEnd = try CalendlyDayDocument(target: target(), window: window, receivedAt: window.end.addingTimeInterval(-1), events: [], isPartial: false)
        #expect(!nearEnd.isCurrent(at: window.end, timeZone: paris))
        let yesterday = try CalendlyDayEvent(uri: "https://api.calendly.com/scheduled_events/previous-day", name: "Started yesterday", start: window.start.addingTimeInterval(-3_600), end: window.start.addingTimeInterval(3_600))
        #expect(throws: (any Error).self) { try CalendlyDayDocument(target: target(), window: window, receivedAt: at, events: [yesterday], isPartial: false) }
        #expect(throws: (any Error).self) { try CalendlyDayDocument(target: target(), window: window, receivedAt: at, events: [], isPartial: false, excludedCount: Int.max, cancelledCount: Int.max) }
    }

    @Test func sourceIsBoundedAsEncodedJSONAndLongNamesAreExplicitExcerpts() throws {
        let at = date("2026-03-29T10:00:00Z"), window = try CalendlyDayWindow(at: at, timeZone: paris)
        let events = try (0..<25).map { try event($0, name: String(repeating: "🌱", count: 300)) }
        let doc = try CalendlyDayDocument(target: target(), window: window, receivedAt: at, events: events, isPartial: true)
        #expect(doc.summary(french: false).count < 1_800 && doc.summary(french: true).count < 1_800)
        #expect(doc.summary(french: false).contains("22 other appointments remain") && doc.summary(french: false).contains("abbreviated"))
        let context = doc.contextText(french: false)
        #expect(try JSONEncoder().encode(context).count < 22_500)
        #expect(context.contains("truncated") && !context.contains("scheduled_events/") && !context.contains("Actual owner"))
        let clean = try event(30, name: "\"\\\u{0001}private title")
        #expect(!clean.name.contains("\u{0001}"))
    }

    @Test func overnightEndKeepsItsDateInSpeechAndFullSource() throws {
        let at = date("2026-03-29T10:00:00Z"), window = try CalendlyDayWindow(at: at, timeZone: paris)
        let appointment = try CalendlyDayEvent(uri: "https://api.calendly.com/scheduled_events/overnight", name: "Overnight",
            start: date("2026-03-29T23:00:00+02:00"), end: date("2026-03-30T01:00:00+02:00"))
        let doc = try CalendlyDayDocument(target: target(), window: window, receivedAt: at, events: [appointment], isPartial: false)
        #expect(doc.summary(french: false).contains("30 Mar 01:00") && doc.contextText(french: false).contains("2026-03-29T23:00:00Z"))
    }
}
