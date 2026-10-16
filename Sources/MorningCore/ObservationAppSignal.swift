import Foundation

/// Where an app signal for one sampled frame came from. Neither source is a quoted
/// screen text, so signals stay separate from text-based interpretations.
public enum ObservationAppSignalSource: String, Codable, Sendable, CaseIterable {
    /// The person's Shortcuts "App is opened/closed" automation, aligned to the recording clock.
    case shortcut
    /// Distinctive interface phrases of a known app in the frame's screen text.
    case screenText
    /// Apple's on-device model looking at the sampled image; a proposal, not proof.
    case visualModel
}

/// One app attributed to one sampled frame by one source.
public struct ObservationFrameAppSignal: Codable, Sendable, Equatable, Identifiable {
    public let sampleID: UUID
    public let source: ObservationAppSignalSource
    public let app: ObservedApp
    public var id: String { "\(sampleID.uuidString)|\(source.rawValue)" }

    public init(sampleID: UUID, source: ObservationAppSignalSource, app: ObservedApp) {
        self.sampleID = sampleID; self.source = source; self.app = app
    }
}

extension ObservedApp {
    /// The same key namespace as text-based visual contexts, so one app merges across sources.
    public var observationIdentity: ObservationAppIdentity {
        .init(key: "visual-context:\(id)", displayName: displayName)
    }
}

/// Places configured Shortcuts transitions on a native recording's timeline. Only a
/// recording with its own start time can be aligned; imported files cannot.
public enum ShortcutAppAlignment {
    /// An "opened" event older than this, with nothing after it, is not trusted: a missing
    /// "closed" automation would otherwise label everything that follows.
    public static let defaultMaximumStaleness: TimeInterval = 30 * 60

    public static func signals(frames: [ObservationFrameEvidence], recordingStartedAt: Date,
                               events: [AppTransitionEvent],
                               maximumStaleness: TimeInterval = defaultMaximumStaleness) -> [ObservationFrameAppSignal] {
        guard recordingStartedAt.timeIntervalSinceReferenceDate.isFinite, maximumStaleness > 0 else { return [] }
        let ordered = events.sorted { $0.observedAt < $1.observedAt }
        return frames.compactMap { frame in
            guard frame.outcome != .decodeFailed, frame.timeSeconds.isFinite else { return nil }
            let instant = recordingStartedAt.addingTimeInterval(frame.timeSeconds)
            guard let latest = ordered.last(where: { $0.observedAt <= instant }) else { return nil }
            // Simultaneous events cannot be ordered; never pick one of them.
            let tied = ordered.filter { $0.observedAt == latest.observedAt }
            guard tied.count == 1, latest.kind == .entered,
                  instant.timeIntervalSince(latest.observedAt) <= maximumStaleness else { return nil }
            return .init(sampleID: frame.id, source: .shortcut, app: latest.app)
        }
    }
}
