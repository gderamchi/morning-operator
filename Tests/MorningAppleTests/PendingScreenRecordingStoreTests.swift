import Foundation
import Testing
@testable import MorningApple

@Suite("Recording recovery storage")
struct PendingScreenRecordingStoreTests {
    @Test func handoffSurvivesReloadAndDoesNotDeleteUntilExplicitRemoval() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = try syntheticRecording()
        defer {
            try? FileManager.default.removeItem(at: directory)
            _ = try? ScreenRecordingFiles.removeIfOwned(source)
        }
        let storage = PendingScreenRecordingStore(directory: directory)
        let saved = try storage.retain(source, interruptionNote: "The system interrupted this recording.")
        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(try Data(contentsOf: saved) == Data("synthetic recording storage test".utf8))
        // A failed or cancelled worker has no cleanup callback: the same single slot remains.
        let reloaded = PendingScreenRecordingStore(directory: directory)
        #expect(try reloaded.recover() == saved)
        #expect(try reloaded.interruptionNote() == "The system interrupted this recording.")
        #expect(try reloaded.retain(saved) == saved)
        try reloaded.remove()
        #expect(try reloaded.recover() == nil)
    }

    @Test func occupiedSlotPreservesBothFilesAndRejectsUnrelatedImport() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let first = try syntheticRecording()
        let second = try syntheticRecording()
        defer {
            try? FileManager.default.removeItem(at: directory)
            _ = try? ScreenRecordingFiles.removeIfOwned(first)
            _ = try? ScreenRecordingFiles.removeIfOwned(second)
        }
        let storage = PendingScreenRecordingStore(directory: directory)
        let saved = try storage.retain(first)
        #expect(throws: PendingScreenRecordingError.anotherRecordingPending) { try storage.retain(second) }
        #expect(FileManager.default.fileExists(atPath: second.path))
        #expect(try storage.recover() == saved)
        let unrelated = directory.appendingPathComponent("user-selected.mp4")
        try Data("user file".utf8).write(to: unrelated)
        #expect(throws: PendingScreenRecordingError.appOwnedRecordingRequired) { try storage.retain(unrelated) }
        try storage.remove()
        #expect(try Data(contentsOf: unrelated) == Data("user file".utf8))
    }

    private func syntheticRecording() throws -> URL {
        try FileManager.default.createDirectory(at: ScreenRecordingFiles.directory, withIntermediateDirectories: true)
        let url = ScreenRecordingFiles.directory.appendingPathComponent("morning-\(UUID().uuidString).mp4")
        // These bytes test storage ownership, not video decoding or successful capture.
        try Data("synthetic recording storage test".utf8).write(to: url)
        return url
    }
}
