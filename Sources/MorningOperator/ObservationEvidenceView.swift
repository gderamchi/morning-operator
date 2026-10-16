import SwiftUI
import MorningCore
import MorningApple

/// Evidence belongs in review, away from the quiet everyday Morning screen.
struct ObservationEvidenceView: View {
    let evidence: ObservationVideoEvidence
    let classification: ObservationContextClassification?
    /// The saved observation, when available, so Shortcuts and image-model apps appear too.
    var acquisition: ObservationAcquisition? = nil
    let isBusy: Bool
    let canAnalyze: Bool
    let analyze: () -> Void

    private var readableCount: Int { evidence.frames.filter(\.canSupportIdentity).count }
    private var appLabels: [UUID: (app: ObservationAppIdentity, provenance: ObservationReviewContextProvenance)] {
        acquisition.map(ObservationAppTimeline.labels(for:)) ?? [:]
    }
    private var report: ObservationTraceReport? {
        guard let classification else { return nil }
        return try? evidence.makeTrace(decisions: classification.decisions).report(maximumSampleGapSeconds: 5)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("A glimpse of this recording", systemImage: "film.stack")
                .font(.raleway(.subheadline, .semibold))
            Text("\(Int(evidence.durationSeconds.rounded())) seconds · \(evidence.frames.count) samples · \(readableCount) with complete text")
                .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                .accessibilityIdentifier("learn.videoEvidence")
            DisclosureGroup("See sampled screens") {
                VStack(alignment: .leading, spacing: 14) {
                    Text("These are occasional views of your screen. They can't count every scroll, prove a message was read, or measure complete app use.")
                    if let acquisition, case let openings = ObservationAppTimeline.openings(for: acquisition), !openings.isEmpty {
                        Text(openings.map(\.app.displayName).joined(separator: " → "))
                            .fontWeight(.medium).foregroundStyle(MorningStyle.ink)
                            .accessibilityIdentifier("learn.visibleContexts")
                        Text("Order of recognized appearances. Unknown samples may hide other activity.")
                    } else if let report, !report.visits.isEmpty {
                        Text(report.visits.map { $0.app.displayName }.joined(separator: " → "))
                            .fontWeight(.medium).foregroundStyle(MorningStyle.ink)
                            .accessibilityIdentifier("learn.visibleContexts")
                        Text("Order of recognized appearances. Unknown samples may hide other activity.")
                    }
                    if let classification {
                        Text(classificationStatus(classification))
                            .accessibilityIdentifier("learn.contextStatus")
                    }
                    Button(classification == nil ? String(localized: "Recognize sampled screens", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) : String(localized: "Try recognizing screens again", bundle: AppLanguage.bundle(), locale: AppLanguage.locale), action: analyze)
                        .buttonStyle(.borderless).foregroundStyle(MorningStyle.accent)
                        .disabled(isBusy || !canAnalyze || readableCount == 0)
                        .accessibilityIdentifier("learn.recognizeScreens")
                    ForEach(evidence.frames) { frame in
                        HStack(alignment: .top, spacing: 12) {
                            Text(timestamp(frame.timeSeconds)).monospacedDigit()
                                .frame(width: 48, alignment: .leading)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(frameLabel(frame)).foregroundStyle(MorningStyle.ink)
                                if frame.textWasTruncated { Text("Text limit reached; identity left unknown.") }
                                if frame.timeBasis == .requestedSamplingTime { Text("Requested time; exact frame time unavailable.") }
                            }
                        }
                    }
                    ForEach(Array(evidence.warnings.enumerated()), id: \.offset) { _, warning in
                        Text(warning)
                    }
                    Text("Uses Apple Intelligence on this device. Editing the observation removes its attached frame evidence and screen interpretation.")
                }.font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 12)
            }.font(.raleway(.subheadline)).tint(MorningStyle.accent)
        }
    }

    private func classificationStatus(_ value: ObservationContextClassification) -> String {
        switch value.status {
        case .noEligibleFrames: String(localized: "No samples have enough usable text to recognize a screen.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
        case .unavailable: String(localized: "On-device screen recognition is unavailable. The saved samples are still here.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
        case .completed: String(localized: "On-device recognition finished. Unclear screens remain unknown.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
        case .partialFailure: String(localized: "Some screens could not be analyzed. Those samples remain unknown.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
        case .failed: String(localized: "Screen recognition did not finish. Samples remain unknown; you can retry.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
        }
    }

    private func frameLabel(_ frame: ObservationFrameEvidence) -> String {
        if let label = appLabels[frame.id] {
            switch label.provenance {
            case .shortcut: return String(localized: "\(label.app.displayName) · Shortcuts")
            case .screenText: return String(localized: "\(label.app.displayName) · screen text")
            case .visualModel: return String(localized: "\(label.app.displayName) · seen in image")
            default: return label.app.displayName
            }
        }
        if let decision = classification?.decisions.first(where: { $0.sampleID == frame.id }) {
            switch decision.evidence {
            case .identified(let app, _): return app.displayName
            case .ambiguous: return String(localized: "Unclear screen", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
            case .unknown: break
            }
        }
        switch frame.outcome {
        case .observed: return classification == nil ? String(localized: "Text found · screen not yet recognized", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) : String(localized: "Unknown screen", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
        case .blank: return String(localized: "No readable text", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
        case .decodeFailed: return String(localized: "Frame unavailable", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
        case .ocrFailed: return String(localized: "Text extraction failed", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
        }
    }

    private func timestamp(_ seconds: Double) -> String {
        String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}
