import Foundation

public enum PendingScreenRecordingError: LocalizedError, Sendable, Equatable {
    case appOwnedRecordingRequired
    case anotherRecordingPending
    case unreadableRecording

    public var errorDescription: String? {
        switch self {
        case .appOwnedRecordingRequired: "Only a recording created by this app can enter recording recovery."
        case .anotherRecordingPending: "Retry or discard the saved recording before adding another one."
        case .unreadableRecording: "The saved recording cannot be opened. It has not been overwritten."
        }
    }
}

/// One local recovery slot. Moving a finalized recording here preserves it across launches;
/// nothing is removed merely because processing, cancellation, or persistence fails.
/// The caller explicitly removes it after saving extracted text, or when the person discards it.
public struct PendingScreenRecordingStore: Sendable {
    private let directory: URL
    public var recordingURL: URL { directory.appendingPathComponent("pending-screen-recording.mp4") }
    private var metadataURL: URL { directory.appendingPathComponent("recording-info.json") }

    private struct Metadata: Codable { var interruptionNote: String? }

    public init(directory: URL) {
        self.directory = directory.appendingPathComponent("RecordingRecovery", isDirectory: true)
    }

    public func owns(_ url: URL) -> Bool {
        url.isFileURL && url.standardizedFileURL == recordingURL.standardizedFileURL
    }

    public func recover() throws -> URL? {
        guard FileManager.default.fileExists(atPath: recordingURL.path) else { return nil }
        let values = try recordingURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw PendingScreenRecordingError.unreadableRecording
        }
        return recordingURL
    }

    public func interruptionNote() throws -> String? {
        guard FileManager.default.fileExists(atPath: metadataURL.path) else { return nil }
        return try JSONDecoder().decode(Metadata.self, from: Data(contentsOf: metadataURL)).interruptionNote
    }

    @discardableResult
    public func retain(_ url: URL, interruptionNote: String? = nil) throws -> URL {
        if owns(url), let existing = try recover() { return existing }
        guard ScreenRecordingFiles.isOwnedRecording(url) else {
            throw PendingScreenRecordingError.appOwnedRecordingRequired
        }
        guard try recover() == nil else { throw PendingScreenRecordingError.anotherRecordingPending }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw PendingScreenRecordingError.unreadableRecording
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        var localDirectory = directory
        var protection = URLResourceValues()
        protection.isExcludedFromBackup = true
        try localDirectory.setResourceValues(protection)
        // Metadata is committed first; a crash after the move still has its coverage note.
        // It stores no absolute source path, only a plain-language interruption description.
        try JSONEncoder().encode(Metadata(interruptionNote: interruptionNote)).write(to: metadataURL, options: .atomic)
        // moveItem refuses an existing destination, so an overlapping handoff cannot replace it.
        try FileManager.default.moveItem(at: url, to: recordingURL)
        return recordingURL
    }

    public func remove() throws {
        if try recover() != nil { try FileManager.default.removeItem(at: recordingURL) }
        // A leftover generic coverage note must not turn a removed video into a phantom retry.
        if FileManager.default.fileExists(atPath: metadataURL.path) { try? FileManager.default.removeItem(at: metadataURL) }
    }
}
