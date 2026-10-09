import AVFoundation
import Foundation
import ImageIO
import MorningCore
import UniformTypeIdentifiers
import Vision

public struct MediaObservation: Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, Equatable { case image, video, text }
    public let kind: Kind
    public let text: String
    public let sampledFrameCount: Int
    public let durationSeconds: Double?
    public let warnings: [String]
    /// Present only for videos. Every requested frame survives here before notes deduplication.
    public let videoEvidence: ObservationVideoEvidence?
    public var hasRecognizedText: Bool {
        videoEvidence?.hasRecognizedText ?? !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public enum MediaObservationError: LocalizedError, Sendable, Equatable {
    case localFileRequired
    case unsupportedFormat
    case fileTooLarge
    case unreadableImage
    case unreadableText
    case invalidVideoDuration
    case videoTooLong(maximumMinutes: Int)
    case noRecognizableText

    public var errorDescription: String? {
        switch self {
        case .localFileRequired: "Choose a local file using the import picker."
        case .unsupportedFormat: "Choose a screenshot, a video, or a UTF-8 text/Markdown file."
        case .fileTooLarge: "This file exceeds the prototype's 512 MB limit. Export a shorter recording first."
        case .unreadableImage: "This image could not be decoded. Try a PNG or JPEG screenshot."
        case .unreadableText: "This text file could not be read as UTF-8, or exceeds the 32,000-character import limit."
        case .invalidVideoDuration: "This video has no readable finite duration. Try another recording."
        case .videoTooLong(let maximum): "Choose a recording shorter than \(maximum) minutes for this prototype."
        case .noRecognizableText: "No readable screen text was found. The image may be blank, protected, or too small. You can describe the routine in your own words."
        }
    }
}

/// Reads only the explicitly supplied file. Frames and OCR remain in memory; nothing is uploaded.
public actor MediaObservationService {
    public typealias ProgressHandler = @MainActor @Sendable (Double) -> Void
    public static let maximumFileBytes = 512 * 1_024 * 1_024
    // Allow a minute of writer/stop finalization around the longest 30-minute recording preset.
    public static let maximumVideoSeconds = ObservationVideoEvidence.maximumDurationSeconds
    public static let maximumFrames = ObservationVideoEvidence.maximumFrames

    public init() {}

    public func extractText(from url: URL, progress: ProgressHandler? = nil) async throws -> String {
        let observation = try await extract(from: url, progress: progress)
        guard observation.hasRecognizedText else { throw MediaObservationError.noRecognizableText }
        return observation.text
    }

    public func extract(from url: URL, progress: ProgressHandler? = nil) async throws -> MediaObservation {
        guard url.isFileURL else { throw MediaObservationError.localFileRequired }
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer { if hasSecurityScope { url.stopAccessingSecurityScopedResource() } }
        try Task.checkCancellation()
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else { throw MediaObservationError.localFileRequired }
        guard (values.fileSize ?? Int.max) <= Self.maximumFileBytes else { throw MediaObservationError.fileTooLarge }
        await progress?(0)
        // LaunchServices metadata may be unavailable in a test runner or restricted process.
        // File access/size checks still apply; decoders validate any extension-based fallback.
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            ?? UTType(filenameExtension: url.pathExtension)
        let extensionName = url.pathExtension.lowercased()

        if type?.conforms(to: .image) == true || ["png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "gif", "bmp"].contains(extensionName) {
            let text = try await recognizeText(in: Self.thumbnail(from: url))
            guard !text.isEmpty else { throw MediaObservationError.noRecognizableText }
            await progress?(1)
            return MediaObservation(
                kind: .image,
                text: "[User-selected screenshot; one moment, not a confirmed habit]\n\(text)",
                sampledFrameCount: 1, durationSeconds: nil, warnings: [], videoEvidence: nil
            )
        }
        if type?.conforms(to: .movie) == true || type?.conforms(to: .video) == true || ["mp4", "mov", "m4v"].contains(extensionName) {
            return try await extractVideo(from: url, progress: progress)
        }
        if type?.conforms(to: .plainText) == true || ["txt", "md", "markdown"].contains(extensionName) {
            guard (values.fileSize ?? Int.max) <= 256_000 else { throw MediaObservationError.unreadableText }
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8), text.count <= 32_000 else {
                throw MediaObservationError.unreadableText
            }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw MediaObservationError.noRecognizableText
            }
            try Task.checkCancellation()
            await progress?(1)
            return MediaObservation(kind: .text, text: text, sampledFrameCount: 0, durationSeconds: nil, warnings: [], videoEvidence: nil)
        }
        throw MediaObservationError.unsupportedFormat
    }

    private func extractVideo(from url: URL, progress: ProgressHandler?) async throws -> MediaObservation {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw MediaObservationError.invalidVideoDuration }
        guard duration <= Self.maximumVideoSeconds else {
            throw MediaObservationError.videoTooLong(maximumMinutes: Int(Self.maximumVideoSeconds / 60))
        }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1_920, height: 1_920)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.2, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.2, preferredTimescale: 600)
        defer { generator.cancelAllCGImageGeneration() }

        let times = FrameSampling.timestamps(duration: duration, maximumFrames: Self.maximumFrames)
        var builder = try VideoObservationBuilder(durationSeconds: duration)
        for (index, seconds) in times.enumerated() {
            try Task.checkCancellation()
            let sampleID = UUID()
            let decoded: (image: CGImage, actualSeconds: Double)
            do {
                let frame = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
                decoded = (frame.image, frame.actualTime.seconds)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                try builder.append(id: sampleID, requestedTimeSeconds: seconds, actualTimeSeconds: nil, outcome: .decodeFailed)
                await progress?(Double(index + 1) / Double(times.count))
                continue
            }
            let text: String
            do {
                text = try await recognizeText(in: decoded.image)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                try builder.append(id: sampleID, requestedTimeSeconds: seconds,
                                   actualTimeSeconds: decoded.actualSeconds, outcome: .ocrFailed)
                await progress?(Double(index + 1) / Double(times.count))
                continue
            }
            try builder.append(id: sampleID, requestedTimeSeconds: seconds, actualTimeSeconds: decoded.actualSeconds,
                               outcome: text.isEmpty ? .blank : .observed, text: text)
            await progress?(Double(index + 1) / Double(times.count))
        }
        try Task.checkCancellation()
        let evidence = try builder.finish()
        return MediaObservation(
            kind: .video,
            text: evidence.renderedText,
            sampledFrameCount: evidence.decodedFrameCount,
            durationSeconds: duration,
            warnings: evidence.warnings,
            videoEvidence: evidence
        )
    }

    private func recognizeText(in image: CGImage) async throws -> String {
        try Task.checkCancellation()
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true
        let observations = try await request.perform(on: image)
        try Task.checkCancellation()
        return observations.sorted { left, right in
            let leftRow = Int((left.topLeft.y * 80).rounded())
            let rightRow = Int((right.topLeft.y * 80).rounded())
            if leftRow != rightRow { return leftRow > rightRow }
            return left.topLeft.x < right.topLeft.x
        }.compactMap { observation -> String? in
            guard let candidate = observation.topCandidates(1).first, candidate.confidence >= 0.25 else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return text
        }.joined(separator: "\n")
    }

    private static func thumbnail(from url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1_920
              ] as CFDictionary)
        else { throw MediaObservationError.unreadableImage }
        return image
    }
}

enum FrameSampling {
    /// At most one sample every two seconds until the cap; then evenly cover the full video.
    static func timestamps(duration: Double, maximumFrames: Int) -> [Double] {
        guard duration.isFinite, duration > 0, maximumFrames > 0 else { return [] }
        let count = min(maximumFrames, max(1, Int(ceil(min(duration, 86_400) / 2))))
        guard count > 1 else { return [0] }
        let last = max(0, duration - min(0.1, duration / 2))
        return (0..<count).map { last * Double($0) / Double(count - 1) }
    }

    static func timestampLabel(_ seconds: Double) -> String {
        let value = max(0, min(seconds.isFinite ? seconds : 0, 86_400))
        return String(format: "%02d:%04.1f", Int(value) / 60, value.truncatingRemainder(dividingBy: 60))
    }
}
