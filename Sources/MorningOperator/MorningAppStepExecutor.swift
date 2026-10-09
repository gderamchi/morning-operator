import Foundation
import MorningCore
import MorningApple

/// Only concrete, supported actions can report completion to the session runner.
@MainActor
final class MorningAppStepExecutor: MorningStepExecuting {
    let speech: SpeechCoordinator
    let calendar: CalendarObservationService
    var spokenEnabled = true

    init(speech: SpeechCoordinator, calendar: CalendarObservationService) {
        self.speech = speech
        self.calendar = calendar
    }

    func execute(step: RoutineStep, context: MorningStepContext) async throws -> MorningStepOutcome {
        switch step.automation {
        case .spokenNote:
            guard spokenEnabled else { return .needsUser("Read at your pace, then tap Next.") }
            try await speech.speakAndWait("\(step.title). \(step.detail)")
        case .todayCalendar:
            guard calendar.isAuthorized else { return .needsUser("Connect Calendar in Settings for a spoken schedule.") }
            guard spokenEnabled else { return .needsUser("Turn on spoken guidance to hear your calendar.") }
            let snapshot = try calendar.snapshot()
            let events = snapshot.events.prefix(8).map { event in
                "\(event.isAllDay ? "All day" : event.start.formatted(date: .omitted, time: .shortened)), \(event.title)."
            }.joined(separator: " ")
            try await speech.speakAndWait(events.isEmpty ? "Your calendar has no events today." : "Here's your day. \(events)")
        case nil:
            return .needsUser("Enjoy this moment. Tap Next when you're ready.")
        }
        try Task.checkCancellation()
        return .completed
    }

    func cancel(context: MorningStepContext) { speech.stop() }
}
