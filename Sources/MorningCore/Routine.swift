import Foundation

public enum StepKind: String, Codable, CaseIterable, Sendable {
    case briefing, messages, calendar, wellbeing, entertainment, custom
    public var displayName: String { rawValue.capitalized }
}

/// A concrete app-owned operation, separate from an inferred activity category.
/// A nil operation remains manual, including routines decoded from older files.
public enum RoutineStepAutomation: String, Codable, CaseIterable, Sendable {
    case spokenNote, todayCalendar
    public var displayName: String {
        switch self {
        case .spokenNote: "Read this note aloud"
        case .todayCalendar: "Read today's calendar"
        }
    }
}

public struct RoutineStep: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public var title: String
    public var detail: String
    public var kind: StepKind
    public var durationMinutes: Int
    public var isRequired: Bool
    public var automation: RoutineStepAutomation?
    public init(id: UUID = UUID(), title: String, detail: String = "", kind: StepKind = .custom,
                durationMinutes: Int = 5, isRequired: Bool = false, automation: RoutineStepAutomation? = nil) {
        self.id = id; self.title = title; self.detail = detail; self.kind = kind
        self.durationMinutes = max(1, durationMinutes); self.isRequired = isRequired
        self.automation = automation
    }
}

/// A user correction kept separately from inferred preferences.
public struct RoutineStepPreference: Codable, Sendable, Equatable {
    public let stepID: UUID
    public var isRequired: Bool?
    public var durationMinutes: Int?
    public init(stepID: UUID, isRequired: Bool? = nil, durationMinutes: Int? = nil) {
        self.stepID = stepID; self.isRequired = isRequired
        self.durationMinutes = durationMinutes.map { max(1, $0) }
    }
}

public struct RoutineVersion: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public var number: Int
    public var createdAt: Date
    public var sourceLabel: String
    public var steps: [RoutineStep]
    public var isApproved: Bool
    public init(id: UUID = UUID(), number: Int = 1, createdAt: Date = Date(), sourceLabel: String,
                steps: [RoutineStep], isApproved: Bool = false) {
        self.id = id; self.number = max(1, number); self.createdAt = createdAt
        self.sourceLabel = sourceLabel; self.steps = steps; self.isApproved = isApproved
    }
    public var totalDurationMinutes: Int { steps.reduce(0) { $0 + $1.durationMinutes } }
    public func approved() -> RoutineVersion { var copy = self; copy.isApproved = true; return copy }
    /// Explicit edits create a new version needing approval, leaving active sessions unchanged.
    public func revised(steps: [RoutineStep], sourceLabel: String? = nil, at date: Date = Date()) -> RoutineVersion {
        RoutineVersion(number: number + 1, createdAt: date, sourceLabel: sourceLabel ?? self.sourceLabel,
                       steps: steps, isApproved: false)
    }
    /// Inferred proposals retain required rituals and explicit corrections with stable step IDs.
    /// Explicit removal is available through revised(steps:).
    public func proposing(steps proposedSteps: [RoutineStep], preserving preferences: [RoutineStepPreference] = [],
                          sourceLabel: String? = nil, at date: Date = Date()) -> RoutineVersion {
        var result = proposedSteps
        for previous in steps where previous.isRequired {
            if let index = result.firstIndex(where: { $0.id == previous.id }) { result[index].isRequired = true }
            else { result.append(previous) }
        }
        for preference in preferences {
            if !result.contains(where: { $0.id == preference.stepID }),
               let previous = steps.first(where: { $0.id == preference.stepID }) { result.append(previous) }
            guard let index = result.firstIndex(where: { $0.id == preference.stepID }) else { continue }
            if let required = preference.isRequired { result[index].isRequired = required }
            if let minutes = preference.durationMinutes { result[index].durationMinutes = max(1, minutes) }
        }
        return revised(steps: result, sourceLabel: sourceLabel, at: date)
    }
}

public enum DemoFixtures {
    /// Synthetic demonstration data, never a recorded personal morning.
    public static var candidateRoutine: RoutineVersion {
        RoutineVersion(sourceLabel: "Demo fixture — synthetic morning, not observed personal data", steps: [
            RoutineStep(title: "A calm start", detail: "Take a breath. Let your morning begin at your own pace.", kind: .briefing, durationMinutes: 3, automation: .spokenNote),
            RoutineStep(title: "People and messages", detail: "Check in with the people who matter.", kind: .messages, durationMinutes: 5),
            RoutineStep(title: "Make room for the day", detail: "Read today’s events from your connected calendar.", kind: .calendar, durationMinutes: 3, automation: .todayCalendar),
            RoutineStep(title: "A little time to play", detail: "A little chess. A little joy. Keep this time for yourself.", kind: .entertainment, durationMinutes: 8, isRequired: true)
        ])
    }
    public static var routine: RoutineVersion { candidateRoutine.approved() }
}
