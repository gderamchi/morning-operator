import Foundation

@MainActor
private enum UITestObservationLaunch {
    static var handled = false
}

extension MorningStore {
    /// Exercises the real text importer only in an explicitly isolated UI-test workspace.
    /// This synthetic note is never a recording fallback or evidence of screen capture.
    func importUITestObservationIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--ui-testing"),
              arguments.contains("--ui-testing-import-observation"),
              let workspaceID = arguments.first(where: { $0.hasPrefix("--ui-testing-workspace=") })
                .flatMap({ UUID(uuidString: String($0.dropFirst("--ui-testing-workspace=".count))) }),
              !UITestObservationLaunch.handled else { return }
        UITestObservationLaunch.handled = true

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MorningOperatorUITests-\(workspaceID.uuidString)", isDirectory: true)
        let file = directory.appendingPathComponent("UITestSyntheticObservation.txt")
        let text = "[Synthetic UI-test observation]\nI check my calendar, drink water, and enjoy ten minutes of chess."
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try text.write(to: file, atomically: true, encoding: .utf8)
            importObservation(file, suggestRoutineWhenReady: false)
        } catch {
            notice = "Synthetic UI-test observation import failed: \(error.localizedDescription)"
        }
    }
}
