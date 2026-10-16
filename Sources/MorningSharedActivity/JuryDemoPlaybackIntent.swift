#if MORE_JURY_DEMO
import AppIntents
import Foundation

/// LiveActivityIntent executes in the app process. The session binding rejects
/// an old island's button after the person starts a different morning.
@MainActor
enum JuryDemoPlaybackControls {
    static var receive: ((String, String) -> Bool)?
}

struct JuryDemoPlaybackIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Control morning"
    static let supportedModes: IntentModes = .background
    @Parameter(title: "Session") var session: String
    @Parameter(title: "Command") var command: String
    init() { session = ""; command = "" }
    init(sessionID: UUID, command: String) {
        session = sessionID.uuidString; self.command = command
    }
    @MainActor func perform() async throws -> some IntentResult {
        guard UUID(uuidString: session) != nil,
              ["pause", "stop", "next"].contains(command) else { return .result() }
        _ = JuryDemoPlaybackControls.receive?(session, command)
        return .result()
    }
}
#endif
