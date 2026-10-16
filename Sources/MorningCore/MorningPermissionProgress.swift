import Foundation

/// Each system prompt gets its own explanation, including speech and microphone.
public enum MorningPermission: String, Codable, Sendable, CaseIterable {
    case location, calendar, reminders, screenTime, speech, microphone, notifications, alarms
}

/// Stores only which explanations the person has handled, never private source
/// data or a guessed system authorization. Denial and skipping are valid choices.
public struct MorningPermissionProgress: Codable, Sendable, Equatable {
    public private(set) var completed: Set<MorningPermission>
    public init(completed: Set<MorningPermission> = []) { self.completed = completed }
    public func pending(supported: [MorningPermission]) -> [MorningPermission] {
        var seen = Set<MorningPermission>()
        return supported.filter { !completed.contains($0) && seen.insert($0).inserted }
    }
    public mutating func resolve(_ permission: MorningPermission) { completed.insert(permission) }
}
