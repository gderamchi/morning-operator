import EventKit
import Foundation

public struct CalendarEventSummary: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let calendarTitle: String
}

public struct CalendarSnapshot: Sendable, Equatable {
    public let retrievedAt: Date
    public let dayStart: Date
    public let dayEnd: Date
    public let events: [CalendarEventSummary]
}

public enum CalendarObservationError: LocalizedError, Sendable, Equatable {
    case notAuthorized
    case missingUsageDescription
    case invalidDay

    public var errorDescription: String? {
        switch self {
        case .notAuthorized:
            "Calendar reading is not authorized. You can continue without a calendar snapshot."
        case .missingUsageDescription:
            "This build has no calendar permission description. Use a configured app build before enabling calendar access."
        case .invalidDay:
            "The selected calendar day could not be resolved."
        }
    }
}

/// Read-only behavior over EventKit's full-access permission. No event mutation API is exposed.
@MainActor
public final class CalendarObservationService {
    private let store = EKEventStore()

    public init() {}

    public var isAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    /// Call only in response to an explicit Connect Calendar action in a correctly configured app.
    public func requestAccess() async throws {
        if isAuthorized { return }
        guard let description = Bundle.main.object(forInfoDictionaryKey: "NSCalendarsFullAccessUsageDescription") as? String,
              !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw CalendarObservationError.missingUsageDescription }
        guard try await store.requestFullAccessToEvents() else { throw CalendarObservationError.notAuthorized }
    }

    /// Reads the system's local event store. It does not assert that remote calendar sync is current.
    public func snapshot(for day: Date = Date(), calendar: Calendar = .current) throws -> CalendarSnapshot {
        guard isAuthorized else { throw CalendarObservationError.notAuthorized }
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            throw CalendarObservationError.invalidDay
        }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }.map { event in
            CalendarEventSummary(
                id: event.eventIdentifier ?? UUID().uuidString,
                title: event.title ?? "Untitled event",
                start: event.startDate,
                end: event.endDate,
                isAllDay: event.isAllDay,
                calendarTitle: event.calendar.title
            )
        }
        return CalendarSnapshot(retrievedAt: Date(), dayStart: start, dayEnd: end, events: events)
    }
}
