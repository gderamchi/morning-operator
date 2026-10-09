import Foundation
import MorningCore

/// Use the shared actor as the authoritative writer in the application process.
/// Each operation reloads the separate journal; it never replaces workspace.json.
public actor AppTransitionLogStore {
    public static let shared = AppTransitionLogStore()
    private let file: AtomicJSONFile<AppTransitionHistory>

    public init(directory: URL? = nil) {
        file = AtomicJSONFile(url: (directory ?? Self.defaultDirectory()).appendingPathComponent("app-transitions.json"))
    }

    @discardableResult
    public func record(app: ObservedApp, kind: AppTransitionKind, observedAt: Date = .now,
                       eventID: UUID = UUID(), timeZoneIdentifier: String = TimeZone.current.identifier) throws -> Bool {
        let event = try AppTransitionEvent(id: eventID, app: app, kind: kind,
            observedAt: observedAt, timeZoneIdentifier: timeZoneIdentifier)
        var history = try load()
        // A retried action can arrive later or after a time-zone change. Preserve the
        // original observation for its stable ID, and serialize this check with the save.
        if let prior = history.events.first(where: { $0.id == eventID }) {
            guard prior.app == app, prior.kind == kind else { throw AppTransitionError.conflictingEventID }
            return false
        }
        guard try history.append(event) else { return false }
        try file.save(history)
        return true
    }

    public func events() throws -> [AppTransitionEvent] { try load().events }

    public func summary(for date: Date, timeZoneIdentifier: String = TimeZone.current.identifier) throws -> AppTransitionDaySummary {
        try load().summary(for: date, timeZoneIdentifier: timeZoneIdentifier)
    }

    /// Removes only this activity journal. Configured Shortcuts can log new events afterward.
    /// Clearing does not require decoding the file, so a corrupt journal can also be removed.
    public func clear() throws {
        guard file.url.isFileURL else { throw PersistenceError.fileURLRequired }
        if FileManager.default.fileExists(atPath: file.url.path) {
            try FileManager.default.removeItem(at: file.url)
        }
    }

    private func load() throws -> AppTransitionHistory {
        guard FileManager.default.fileExists(atPath: file.url.path) else { return try AppTransitionHistory() }
        // Corrupt or newer data must fail rather than be silently overwritten.
        return try file.load()
    }

    private static func defaultDirectory() -> URL {
        let process = ProcessInfo.processInfo
        if process.arguments.contains("--ui-testing") {
            let suppliedID = process.arguments.first { $0.hasPrefix("--ui-testing-workspace=") }
                .flatMap { UUID(uuidString: String($0.dropFirst("--ui-testing-workspace=".count))) }
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("MorningOperatorUITests-\((suppliedID ?? UUID()).uuidString)")
        }
        if let path = process.environment["MORNING_OPERATOR_DATA_DIR"] {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MorningOperator", isDirectory: true)
    }
}
