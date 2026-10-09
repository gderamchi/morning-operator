import AppIntents
import Foundation
import Observation

/// Foreground intents only enqueue UI requests. A request stays held throughout its review sheet.
/// Nothing here approves a routine, writes to EventKit, or persists captured text.
@MainActor
@Observable
final class MorningIntentRouter {
    static let shared = MorningIntentRouter()
    private(set) var pendingCaptureText: String?
    var startRequested = false

    private init() {}

    func requestCapture(_ text: String) throws {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw MorningIntentError.emptyText }
        guard pendingCaptureText == nil else { throw MorningIntentError.captureWaiting }
        pendingCaptureText = text
    }

    /// Call after this request's sheet has actually dismissed, whether saved or cancelled.
    func finishCaptureReview() {
        pendingCaptureText = nil
    }
}

private enum MorningIntentError: LocalizedError {
    case emptyText, captureWaiting

    var errorDescription: String? {
        switch self {
        case .emptyText: "Add a few words to capture."
        case .captureWaiting: "Review the capture already waiting in Morning Operator, then try again."
        }
    }
}

struct StartMorningIntent: AppIntent {
    static let title: LocalizedStringResource = "Start morning"
    static let description = IntentDescription("Open Morning Operator and request your approved morning routine. A draft still needs your approval in the app.")
    static let supportedModes: IntentModes = .foreground(.immediate)

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        MorningIntentRouter.shared.startRequested = true
        return .result(dialog: "Opening your morning in Morning Operator.")
    }
}

enum MorningIntentCaptureKind: String, AppEnum {
    case thought, dream, reminder, calendar

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Capture kind"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .thought: "Thought", .dream: "Dream", .reminder: "Reminder", .calendar: "Calendar idea"
    ]

    var textPrefix: String {
        switch self {
        case .thought: "Thought"
        case .dream: "Dream"
        case .reminder: "Reminder"
        case .calendar: "Calendar"
        }
    }
}

struct CaptureMorningIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture for my morning"
    static let description = IntentDescription("Open a thought, dream, reminder request or calendar idea for review. This action does not save a reminder or calendar event.")
    static let supportedModes: IntentModes = .foreground(.immediate)

    @Parameter(title: "Kind", default: .thought)
    var kind: MorningIntentCaptureKind

    @Parameter(title: "Text", requestValueDialog: "What would you like to capture?")
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Capture \(\.$text) as a \(\.$kind)")
    }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { throw MorningIntentError.emptyText }
        try MorningIntentRouter.shared.requestCapture("\(kind.textPrefix): \(content)")
        return .result(dialog: "Ready for review in Morning Operator.")
    }
}

struct MorningAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartMorningIntent(),
            phrases: ["Start my morning with \(.applicationName)", "Start \(.applicationName)"],
            shortTitle: "Start morning", systemImageName: "sun.max"
        )
        AppShortcut(
            intent: CaptureMorningIntent(),
            phrases: ["Capture a \(\.$kind) with \(.applicationName)", "Quick capture with \(.applicationName)"],
            shortTitle: "Quick capture", systemImageName: "square.and.pencil"
        )
    }
}
