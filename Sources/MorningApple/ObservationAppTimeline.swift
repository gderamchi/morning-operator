import Foundation
import MorningCore

/// When an app came into view in one recording, from the same projection as review:
/// the person's label, then Shortcuts timing, then quoted screen text, then the image model.
public struct ObservationAppOpening: Identifiable, Sendable, Equatable {
    public let sampleID: UUID
    public let app: ObservationAppIdentity
    public let timeSeconds: Double
    /// Present only for recordings made in MORE, which keep their own start time.
    public let wallClock: Date?
    public let provenance: ObservationReviewContextProvenance
    public var id: UUID { sampleID }
}

public enum ObservationAppTimeline {
    /// One entry each time the recognized app changes. Unknown screens neither end nor
    /// start an app, so "Messages, unknown, Messages" stays one opening.
    public static func openings(for acquisition: ObservationAcquisition) -> [ObservationAppOpening] {
        guard let clip = try? ObservationClipReview(acquisition: acquisition), clip.timelineOrderIsValid else { return [] }
        let start = acquisition.recordingContext?.startedAt
        var result: [ObservationAppOpening] = []
        for row in clip.rows {
            guard row.resolution == .recognized, let app = row.resolvedContext, let sample = row.samples.first else { continue }
            if result.last?.app.key == app.key { continue }
            result.append(.init(sampleID: sample.id, app: app, timeSeconds: row.timeSeconds,
                                wallClock: start?.addingTimeInterval(row.timeSeconds), provenance: sample.provenance))
        }
        return result
    }

    /// The effective app and source for each sampled frame, for per-sample lists.
    public static func labels(for acquisition: ObservationAcquisition) -> [UUID: (app: ObservationAppIdentity, provenance: ObservationReviewContextProvenance)] {
        guard let clip = try? ObservationClipReview(acquisition: acquisition) else { return [:] }
        var labels: [UUID: (app: ObservationAppIdentity, provenance: ObservationReviewContextProvenance)] = [:]
        for row in clip.rows where row.resolution == .recognized {
            guard let app = row.resolvedContext else { continue }
            for sample in row.samples { labels[sample.id] = (app, sample.provenance) }
        }
        return labels
    }
}
