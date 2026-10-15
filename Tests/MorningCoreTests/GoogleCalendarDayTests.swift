import Foundation
import Testing
@testable import MorningCore

@Suite("Google Calendar runtime day and approved target")
struct GoogleCalendarDayTests {
    private let paris = TimeZone(identifier: "Europe/Paris")!
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private func target() throws -> GoogleCalendarDayTarget { try .init(connectionID: "ca_synthetic", calendarID: "real-calendar@example.invalid", calendarName: "Personal calendar") }

    @Test func phoneDaysUseCalendarArithmeticAcrossBothDSTChanges() throws {
        let spring = try GoogleCalendarDayWindow(at: date("2026-03-29T12:00:00Z"), timeZone: paris)
        #expect(spring.end.timeIntervalSince(spring.start) == 23 * 3_600)
        #expect(spring.timeMin == "2026-03-29T00:00:00+01:00" && spring.timeMax == "2026-03-30T00:00:00+02:00")
        let autumn = try GoogleCalendarDayWindow(at: date("2026-10-25T12:00:00Z"), timeZone: paris)
        #expect(autumn.end.timeIntervalSince(autumn.start) == 25 * 3_600)
        #expect(autumn.timeMin == "2026-10-25T00:00:00+02:00" && autumn.timeMax == "2026-10-26T00:00:00+01:00")
        let next = try GoogleCalendarDayWindow(at: spring.end, timeZone: paris)
        #expect(next.start == spring.end && next != spring)
        let losAngeles = try GoogleCalendarDayWindow(at: spring.start, timeZone: TimeZone(identifier: "America/Los_Angeles")!)
        #expect(losAngeles.start != spring.start)
    }

    @Test func targetRoundTripsWithoutFrozenDatesAndRejectsAliasesOrForgedKinds() throws {
        let selected = try target(), action = RoutineStepTarget.googleCalendarDay(selected)
        let encoded = try JSONEncoder().encode(action), text = String(decoding: encoded, as: UTF8.self)
        #expect(try JSONDecoder().decode(RoutineStepTarget.self, from: encoded) == action)
        #expect(!text.contains("timeMin") && !text.contains("timeZone") && !text.contains("argumentsJSON"))
        #expect(action.destination == .connectedService && action.integrationRoute == .api && action.isConnectedAction)
        #expect(RoutineStep(title: "Calendar", target: action).executionDescription.contains("25"))
        for id in ["", "primary", "ca_other", " personal@example.invalid", "bad\ncalendar"] {
            #expect(throws: (any Error).self) { try GoogleCalendarDayTarget(connectionID: "ca_synthetic", calendarID: id, calendarName: "Named") }
            let bad = Data("{\"kind\":\"googleCalendarDay\",\"calendar\":{\"connectionID\":\"ca_synthetic\",\"calendarID\":\"\(id.replacingOccurrences(of: "\n", with: "\\n"))\",\"calendarName\":\"Named\"}}".utf8)
            #expect(throws: (any Error).self) { try JSONDecoder().decode(RoutineStepTarget.self, from: bad) }
        }
        #expect(throws: (any Error).self) { try JSONDecoder().decode(RoutineStepTarget.self, from: Data("{\"kind\":\"futureCalendar\"}".utf8)) }
    }

    @Test func primaryLabelSurvivesApprovalStorageAndOldSelectionsRemainUnchanged() throws {
        let oldJSON = Data("{\"connectionID\":\"ca_synthetic\",\"calendarID\":\"real-calendar@example.invalid\",\"calendarName\":\"Personal calendar\"}".utf8)
        let old = try JSONDecoder().decode(GoogleCalendarDayTarget.self, from: oldJSON)
        #expect(old.isPrimary == nil && old.sourceLabel(french: false) == "Personal calendar")
        let now = date("2026-03-29T10:00:00Z")
        for primary in [false, true] {
            let selected = try GoogleCalendarDayTarget(connectionID: old.connectionID, calendarID: old.calendarID,
                calendarName: old.calendarName, isPrimary: primary)
            let routine = RoutineVersion(sourceLabel: "Synthetic selection", steps: [RoutineStep(title: "Calendar", target: .googleCalendarDay(selected))], isApproved: true)
            let restored = try JSONDecoder().decode(RoutineVersion.self, from: JSONEncoder().encode(routine))
            #expect(restored.isApproved && restored.steps[0].target == .googleCalendarDay(selected))
            let doc = try GoogleCalendarDayDocument(target: selected, window: .init(at: now, timeZone: paris), receivedAt: now, events: [], isPartial: false)
            #expect(doc.summary(french: false).contains("primary calendar") == primary)
            #expect(doc.summary(french: true).contains("calendrier principal") == primary)
            #expect(!selected.sourceLabel(french: false).contains(selected.calendarID))
        }
        #expect(try JSONDecoder().decode(GoogleCalendarDayTarget.self, from: JSONEncoder().encode(old)) == old)
    }

    @Test func pinnedSessionAndRetainedPreferencesPreserveSelectionButPortableImportIsManual() throws {
        let selection = try target(), action = RoutineStepTarget.googleCalendarDay(selection)
        let step = RoutineStep(title: "My work calendar", kind: .calendar, durationMinutes: 3, target: action)
        let routine = RoutineVersion(sourceLabel: "Synthetic calendar target", steps: [step], isApproved: true)
        let session = RoutineSession(routine: routine)
        let restored = try JSONDecoder().decode(RoutineSession.self, from: JSONEncoder().encode(session))
        #expect(restored.routine.steps[0].target == action)
        var journal = RoutinePreferenceJournal()
        try journal.upsert(RoutinePreference(target: step, presence: .keep, durationMinutes: 5))
        let saved = try JSONDecoder().decode(RoutinePreferenceJournal.self, from: JSONEncoder().encode(journal))
        let kept = try saved.reconcile(steps: []).steps
        #expect(kept.count == 1 && kept[0].target == action && kept[0].durationMinutes == 5)
        let exported = try PortableRoutineDocument(routine: routine, detail: .includeDetails)
        let data = try exported.encoded(), imported = try PortableRoutineDocument.decode(data).importedDraft(replacing: nil)
        #expect(!String(decoding: data, as: UTF8.self).contains(selection.calendarID))
        #expect(imported.steps[0].target == nil && imported.steps[0].automation == nil && !imported.isApproved)
    }

    @Test func freshnessExpiresOnAgeDayAndPhoneZoneAndEmptyPartialIsNeverEmptyDayClaim() throws {
        let at = date("2026-03-29T10:00:00Z"), window = try GoogleCalendarDayWindow(at: at, timeZone: paris)
        let full = try GoogleCalendarDayDocument(target: target(), window: window, receivedAt: at, events: [], isPartial: false)
        #expect(full.isCurrent(at: at.addingTimeInterval(300), timeZone: paris))
        #expect(!full.isCurrent(at: at.addingTimeInterval(301), timeZone: paris))
        #expect(!full.isCurrent(at: at.addingTimeInterval(-1), timeZone: paris))
        #expect(!full.isCurrent(at: at, timeZone: TimeZone(identifier: "Asia/Tokyo")!))
        let nearMidnight = window.end.addingTimeInterval(-1)
        let late = try GoogleCalendarDayDocument(target: target(), window: window, receivedAt: nearMidnight, events: [], isPartial: false)
        #expect(!late.isCurrent(at: window.end, timeZone: paris))
        let partial = try GoogleCalendarDayDocument(target: target(), window: window, receivedAt: at, events: [], isPartial: true)
        #expect(partial.summary(french: false).contains("There may be more") && !partial.summary(french: false).contains("No events scheduled"))
        #expect(full.summary(french: false).contains("No events scheduled"))
    }

    @Test func allDayDatesStayExactAndCancellationCoverageIsDisclosed() throws {
        let at = date("2026-03-29T10:00:00Z")
        let event = try GoogleCalendarDayEvent(id: "event", title: "Source trip", schedule: .allDay(startDate: "2026-03-29", endDate: "2026-03-31"), isTentative: true)
        let doc = try GoogleCalendarDayDocument(target: target(), window: .init(at: at, timeZone: paris), receivedAt: at, events: [event], isPartial: true, cancelledCount: 1)
        #expect(doc.events[0].schedule == .allDay(startDate: "2026-03-29", endDate: "2026-03-31"))
        #expect(doc.summary(french: false).contains("All day") && doc.summary(french: false).contains("tentative"))
        #expect(doc.summary(french: false).contains("1 cancelled") && doc.summary(french: false).contains("Partial reading"))
        #expect(throws: (any Error).self) { try GoogleCalendarDayEvent(id: "bad", title: "Invalid date", schedule: .allDay(startDate: "2026-02-30", endDate: "2026-03-01")) }
    }

    @Test func overnightEventsKeepBothDatesInSpeechAndFullSource() throws {
        let at = date("2026-03-29T10:00:00Z")
        let previous = try GoogleCalendarDayEvent(id: "overnight-from-yesterday", title: "Yesterday overnight", schedule: .timed(start: date("2026-03-28T23:00:00+01:00"), end: date("2026-03-29T01:00:00+01:00")))
        let next = try GoogleCalendarDayEvent(id: "overnight-to-tomorrow", title: "Tonight overnight", schedule: .timed(start: date("2026-03-29T23:00:00+02:00"), end: date("2026-03-30T01:00:00+02:00")))
        let doc = try GoogleCalendarDayDocument(target: target(), window: .init(at: at, timeZone: paris), receivedAt: at, events: [previous, next], isPartial: false)
        let spoken = doc.summary(french: false), source = doc.contextText(french: false)
        #expect(spoken.contains("28 Mar 23:00") && spoken.contains("29 Mar 01:00") && spoken.contains("30 Mar 01:00"))
        #expect(source.contains("2026-03-28T23:00:00+01:00") && source.contains("2026-03-30T01:00:00+02:00"))
    }

    @Test func quotedAndControlHeavySourceStaysWithinEncodedContextLimit() throws {
        let at = date("2026-03-29T10:00:00Z")
        let events = try (0..<25).map { i in
            try GoogleCalendarDayEvent(id: "event-\(i)", title: String(repeating: "\"\\\u{0001}", count: 100),
                schedule: .allDay(startDate: "2026-03-29", endDate: "2026-03-30"), location: String(repeating: "/\"\\", count: 100))
        }
        let doc = try GoogleCalendarDayDocument(target: target(), window: .init(at: at, timeZone: paris), receivedAt: at, events: events, isPartial: false)
        let context = doc.contextText(french: false)
        #expect(try JSONEncoder().encode(context).count <= 22_500)
        #expect(context.contains("truncated") && !context.contains("\u{0001}"))
        #expect(doc.summary(french: false).count <= 1_800)
    }
}
