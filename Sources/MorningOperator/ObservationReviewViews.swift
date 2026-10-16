import SwiftUI
import MorningCore
import MorningApple

/// A transient projection of the current acquisition. Selection retains only a source ID;
/// original OCR and quoted interpretation are always resolved again from the parent value.
@MainActor
struct ObservationClipTimelineView: View {
    @Bindable var store: MorningStore
    let acquisition: ObservationAcquisition
    @ViewState<Bool> private var showingSamples = false
    @ViewState<ObservationMomentSelection?> private var selection = nil

    private var review: ObservationClipReview? { try? ObservationClipReview(acquisition: acquisition) }
    private var prefix: String { "observation.timeline.\(acquisition.id.uuidString)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let review, !review.rows.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(review.timelineOrderIsValid ? String(localized: "Sampled moments", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) : String(localized: "Saved samples", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)).font(.serif(.headline))
                    Text(summary(review))
                        .font(.raleway(.subheadline)).foregroundStyle(MorningStyle.muted)
                        .accessibilityIdentifier("\(prefix).summary")
                    if review.timelineOrderIsValid {
                        Text(sequence(review))
                            .font(.raleway(.subheadline, .medium)).lineLimit(3)
                            .accessibilityIdentifier("\(prefix).sequence")
                        if review.rows.count > 6 {
                            Text("First 6 of \(review.rows.count) sampled moments")
                                .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                        }
                    }
                    if review.timelineOrderIsValid, review.recognizedMomentCount > 0 {
                        Text(returnSummary(review)).font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                            .accessibilityIdentifier("\(prefix).returns")
                    }
                    if let message = interpretationMessage(review) {
                        Text(message).font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                            .accessibilityIdentifier("\(prefix).status")
                    }
                }

                // Keep the identifier on the disclosure's label, not its container: an
                // inherited container identifier can hide the child source buttons in AX.
                DisclosureGroup(isExpanded: $showingSamples) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(review.timelineOrderIsValid ? String(localized: "Activity between these sampled moments is unknown.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) : String(localized: "Original samples in extraction order", bundle: AppLanguage.bundle(), locale: AppLanguage.locale))
                            .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                            .padding(.bottom, 4)
                        ForEach(review.rows) { moment in
                            Button { selection = .init(id: moment.id) } label: {
                                momentRow(moment)
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .ignore)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityLabel("\(observationSampleTime(moment.timeSeconds)), \(momentLabel(moment))")
                            .accessibilityValue(momentCaveat(moment) ?? String(localized: "Sampled screen", bundle: AppLanguage.bundle(), locale: AppLanguage.locale))
                            .accessibilityHint("Shows original text and quoted evidence")
                            .accessibilityIdentifier("\(prefix).point.\(moment.id.uuidString)")
                            if moment.id != review.rows.last?.id { Divider().padding(.leading, 64) }
                        }
                    }.padding(.top, 8)
                } label: {
                    Text("View sampled screens")
                        .font(.raleway(.subheadline, .medium))
                        .accessibilityIdentifier("\(prefix).samples")
                }
                .tint(MorningStyle.accent)

                Text("Labels come from recognition or your review. Samples can miss activity and don't measure time spent, taps, reads or scrolls.")
                    .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
            } else {
                Text(acquisition.videoEvidence == nil ? String(localized: "No sampled recording is attached to this observation.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) : String(localized: "The sampled interpretation can't be displayed. Original evidence remains available below.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale))
                    .font(.raleway(.subheadline)).foregroundStyle(MorningStyle.muted)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .sheet(item: $selection) { selected in
            NavigationStack {
                if let current = review,
                   let moment = current.rows.first(where: { $0.id == selected.id }),
                   let sampleID = moment.samples.first?.id {
                    ObservationSampleSourceView(store: store, acquisitionID: acquisition.id, sampleID: sampleID, managesEntryOccupancy: false)
                } else {
                    ContentUnavailableView("Sample changed", systemImage: "doc.text.magnifyingglass",
                                           description: Text("Return to the observation to review its current evidence."))
                        .navigationTitle("Sampled moment")
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { selection = nil }
                                    .accessibilityIdentifier("observation.sample.close")
                            }
                        }
                }
            }
        }
        .onChange(of: acquisition) { _, updated in
            // Keep an open sample on label edits; its ID resolves the current source.
            if let selection, !(updated.videoEvidence?.frames.contains { $0.id == selection.id } ?? false) {
                self.selection = nil
            }
        }
    }

    private func momentRow(_ moment: ObservationReviewMoment) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(observationSampleTime(moment.timeSeconds))
                .font(.raleway(.caption).monospacedDigit()).foregroundStyle(MorningStyle.muted)
                .frame(minWidth: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(momentLabel(moment)).font(.raleway(.subheadline, .medium)).foregroundStyle(MorningStyle.ink)
                if let caveat = momentCaveat(moment) {
                    Text(caveat).font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.raleway(.caption2, .semibold))
                .foregroundStyle(MorningStyle.muted).accessibilityHidden(true)
        }
        .padding(.vertical, 12).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func summary(_ value: ObservationClipReview) -> String {
        guard value.timelineOrderIsValid else { return String(localized: "\(value.sampleCount) source samples · chronology unresolved", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) }
        return String(localized: "\(value.recognizedMomentCount) of \(value.rows.count) sampled moments labeled · \(value.unknownMomentCount) unresolved", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
    }

    private func sequence(_ value: ObservationClipReview) -> String {
        value.rows.prefix(6).map(momentLabel).joined(separator: " → ")
    }

    private func returnSummary(_ value: ObservationClipReview) -> String {
        let count = value.traceReport?.apps.reduce(0) { $0 + $1.minimumVisibleReturnCount } ?? 0
        if count == 0 { return String(localized: "No return is established by these samples.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) }
        return String(localized: "At least \(count) visible returns in this clip. Gaps may hide others.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
    }

    private func interpretationMessage(_ value: ObservationClipReview) -> String? {
        guard value.timelineOrderIsValid else {
            return String(localized: "Frame times aren't in order. Original samples are shown in extraction order; their chronology is unresolved.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
        }
        let reviewedCount = value.rows.flatMap(\.samples).filter { $0.frameReview != nil }.count
        if reviewedCount > 0 {
            return String(localized: "You reviewed \(reviewedCount) samples. Your labels and unknown choices take priority; original text and model results stay available.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
        }
        switch value.interpretationState {
        case .corrected:
            return String(localized: "Notes were corrected. The earlier screen interpretation was removed; original samples remain.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
        case .invalid:
            return String(localized: "An unsupported interpretation was removed. Original samples remain.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
        case .unclassified:
            return String(localized: "These samples have not been interpreted.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
        case .noVideo:
            return nil
        case .available:
            switch value.classificationStatus {
            case .unavailable: return String(localized: "On-device recognition was unavailable. These samples remain unknown.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
            case .failed: return String(localized: "Recognition did not finish. These samples remain unknown.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
            case .partialFailure: return String(localized: "Some recognition requests failed. Unresolved samples remain visible.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
            case .noEligibleFrames: return String(localized: "No samples had enough complete text for recognition.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
            case .completed, nil: return nil
            }
        }
    }
}

private struct ObservationMomentSelection: Identifiable {
    let id: UUID
}

private func momentLabel(_ moment: ObservationReviewMoment) -> String {
    switch moment.resolution {
    case .recognized: moment.resolvedContext?.displayName ?? String(localized: "Unknown screen", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
    case .ambiguous: String(localized: "Ambiguous screen", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
    case .conflicting: String(localized: "Unresolved at this timestamp", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
    case .unknown: String(localized: "Unknown screen", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
    }
}

private func momentCaveat(_ moment: ObservationReviewMoment) -> String? {
    if moment.samples.count > 1 {
        return String(localized: "\(moment.samples.count) samples share this time; their order is unknown.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
    }
    if moment.hasRequestedTimeFallback { return String(localized: "Requested sample time; exact frame time unavailable.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) }
    guard let frame = moment.samples.first?.frame else { return nil }
    if frame.textWasTruncated { return String(localized: "Text was limited; identity remains unknown.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) }
    switch frame.outcome {
    case .blank: return String(localized: "No readable text", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
    case .decodeFailed: return String(localized: "Frame unavailable", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
    case .ocrFailed: return String(localized: "Text extraction failed", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
    case .observed: return nil
    }
}

private func observationSampleTime(_ seconds: Double, fractionDigits: Int = 1) -> String {
    let scale = fractionDigits == 3 ? 1_000 : 10
    let units = Int((seconds * Double(scale)).rounded())
    // Round the whole value before splitting minutes, avoiding labels such as 00:60.0.
    return String(format: "%02d:%02d.%0*d", units / (60 * scale), (units / scale) % 60,
                  fractionDigits, units % scale)
}

@MainActor
private struct ObservationSampleDetail: View {
    @Bindable var store: MorningStore
    let acquisition: ObservationAcquisition
    let moment: ObservationReviewMoment
    let timelineOrderIsValid: Bool
    @Environment(\.dismiss) private var dismiss
    @ViewState<ScreenReviewSelection?> private var reviewSelection = nil
    @ViewState<SampleNarrationSelection?> private var narrationSelection = nil

    var body: some View {
        MorningList {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                Text(momentLabel(moment)).font(.serif(.headline))
                Text(acquisition.sourceLabel).font(.raleway(.subheadline)).foregroundStyle(MorningStyle.muted)
                if let caveat = momentCaveat(moment) { Text(caveat).font(.raleway(.subheadline)) }
                if !timelineOrderIsValid {
                    Text("Frame times aren't in order. This source's chronology remains unresolved.")
                        .font(.raleway(.subheadline)).foregroundStyle(MorningStyle.muted)
                }
                Text("A visual label is a proposal about what's visible. It doesn't establish which app was open or what you did.")
                    .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                Text("Times are offsets into this recording, rounded to a millisecond.")
                    .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                }.padding(.vertical, 4)
            }
            ForEach(Array(moment.samples.enumerated()), id: \.element.id) { index, sample in
                Section {
                    sampleTime(String(localized: "Requested sample", bundle: AppLanguage.bundle(), locale: AppLanguage.locale), value: observationSampleTime(sample.frame.requestedTimeSeconds, fractionDigits: 3),
                               identifier: "observation.sample.requestedTime.\(sample.id.uuidString)")
                    sampleTime(String(localized: "Actual frame", bundle: AppLanguage.bundle(), locale: AppLanguage.locale), value: sample.frame.actualTimeSeconds.map { observationSampleTime($0, fractionDigits: 3) } ?? String(localized: "Unavailable", bundle: AppLanguage.bundle(), locale: AppLanguage.locale),
                               identifier: "observation.sample.actualTime.\(sample.id.uuidString)")
                    let userReview = acquisition.frameReviews.first { $0.sampleID == sample.id }
                    let originalDecision = acquisition.classification?.decisions.first { $0.sampleID == sample.id }
                    if let userReview {
                        LabeledContent("Your label", value: userReview.label ?? String(localized: "Unknown screen", bundle: AppLanguage.bundle(), locale: AppLanguage.locale))
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Your label")
                            .accessibilityValue(userReview.label ?? String(localized: "Unknown screen", bundle: AppLanguage.bundle(), locale: AppLanguage.locale))
                            .accessibilityIdentifier("observation.sample.userLabel.\(sample.id.uuidString)")
                        Text(userReview.label == nil
                             ? String(localized: "You kept this screen unknown. It is left out of later activity suggestions.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
                             : String(localized: "Your description stays separate from the model's interpretation.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale))
                            .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                    }
                    if case .identified(let context, _) = originalDecision?.evidence {
                        LabeledContent(userReview == nil ? String(localized: "Proposed visual label", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) : String(localized: "Original proposed label", bundle: AppLanguage.bundle(), locale: AppLanguage.locale), value: context.displayName)
                    } else if case .ambiguous = originalDecision?.evidence {
                        Text("The original interpretation supported more than one possible context.")
                            .font(.raleway(.subheadline)).foregroundStyle(MorningStyle.muted)
                    }
                    if let quote = originalDecision?.evidenceQuote ?? userReview?.evidenceQuote ?? sample.quote {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Exact evidence quote").font(.raleway(.caption, .semibold)).foregroundStyle(MorningStyle.muted)
                            Text(quote).font(.raleway(.subheadline)).textSelection(.enabled)
                                .accessibilityIdentifier("observation.sample.quote.\(sample.id.uuidString)")
                        }
                        narrationAction(quote: quote, sampleID: sample.id,
                            identifier: "observation.sample.readMoment.\(sample.id.uuidString)")
                    } else {
                        Text("No original interpretation quote is attached to this sample.")
                            .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                    }
                    if let reviewedQuote = userReview?.evidenceQuote,
                       let originalQuote = originalDecision?.evidenceQuote,
                       !reviewedQuote.utf8.elementsEqual(originalQuote.utf8) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Excerpt you selected").font(.raleway(.caption, .semibold)).foregroundStyle(MorningStyle.muted)
                            Text(reviewedQuote).font(.raleway(.subheadline)).textSelection(.enabled)
                                .accessibilityIdentifier("observation.sample.userQuote.\(sample.id.uuidString)")
                        }
                        narrationAction(quote: reviewedQuote, sampleID: sample.id,
                            identifier: "observation.sample.readReviewedMoment.\(sample.id.uuidString)")
                    }
                    if acquisition.correctedText == nil {
                        Button(userReview == nil ? String(localized: "Correct label", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) : String(localized: "Edit your label", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)) {
                            reviewSelection = .init(id: sample.id, acquisition: acquisition)
                        }
                        .disabled(store.busy || store.sessionActive || !store.storageIsAvailable)
                        .accessibilityIdentifier("observation.sample.correctLabel.\(sample.id.uuidString)")
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Original extracted text").font(.raleway(.caption, .semibold)).foregroundStyle(MorningStyle.muted)
                        Text(sample.frame.text.isEmpty ? String(localized: "No readable text was retained.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) : sample.frame.text)
                            .font(.raleway(.subheadline)).textSelection(.enabled)
                            .accessibilityIdentifier("observation.sample.originalText.\(sample.id.uuidString)")
                    }
                    if sample.frame.textWasTruncated {
                        Text("This text was limited during extraction and cannot support a screen identity.")
                            .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                    }
                    ForEach(Array(sample.frame.warnings.enumerated()), id: \.offset) { _, warning in
                        Text(warning).font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                    }
                } header: {
                    Text(moment.samples.count == 1 ? String(localized: "Source sample", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) : String(localized: "Source sample \(index + 1)", bundle: AppLanguage.bundle(), locale: AppLanguage.locale))
                }
            }
        }
        .scrollContentBackground(.hidden).background(MorningPaper(showsSun: false))
        .navigationTitle("Sampled moment")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }.accessibilityIdentifier("observation.sample.close")
            }
        }
        .sheet(item: $reviewSelection) { selected in
            ObservationScreenReviewView(store: store, acquisition: selected.acquisition, sampleID: selected.id)
        }
        .sheet(item: $narrationSelection) { selected in
            ObservationNarrationView(store: store, observationID: acquisition.id,
                requestedNarration: selected.prepared)
        }
    }

    @ViewBuilder private func narrationAction(quote: String, sampleID: UUID, identifier: String) -> some View {
        if let prepared = try? ObservationNarrationComposer.prepare(acquisition: acquisition,
            frameID: sampleID, quote: quote) {
            Button {
                narrationSelection = .init(prepared: prepared)
            } label: {
                Label("Read this saved moment", systemImage: "speaker.wave.2")
            }
            .buttonStyle(.borderless)
            .disabled(store.busy || store.sessionActive || !store.storageIsAvailable || store.voiceInputBlocksPlayback)
            .accessibilityIdentifier(identifier)
        }
    }

    private func sampleTime(_ title: String, value: String, identifier: String) -> some View {
        LabeledContent(title, value: value)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title).accessibilityValue(value)
            .accessibilityIdentifier(identifier)
    }
}

/// Resolves a weekly citation directly, without waiting for an off-screen List row
/// to mount. Only source IDs survive navigation; edits/deletion replace the view.
struct ObservationSampleSourceView: View {
    @Bindable var store: MorningStore
    let acquisitionID: UUID
    let sampleID: UUID
    var managesEntryOccupancy = true

    var body: some View {
        Group {
            if let acquisition = store.observationArchive.entry(id: acquisitionID),
               let review = try? ObservationClipReview(acquisition: acquisition),
               let moment = review.rows.first(where: { $0.samples.contains { $0.id == sampleID } }) {
                ObservationSampleDetail(store: store, acquisition: acquisition, moment: moment, timelineOrderIsValid: review.timelineOrderIsValid)
            } else {
                ContentUnavailableView("Sample changed", systemImage: "doc.text.magnifyingglass",
                    description: Text("Return to observations to see the current evidence."))
                    .navigationTitle("Sampled moment")
            }
        }
        .onAppear { if managesEntryOccupancy { store.observationDetailPresented = true } }
        .onDisappear { if managesEntryOccupancy { store.observationDetailPresented = false } }
    }
}

private struct ScreenReviewSelection: Identifiable {
    let id: UUID
    let acquisition: ObservationAcquisition
}

/// Keeps the exact prepared reference while presenting, not a mutable selected-line index.
private struct SampleNarrationSelection: Identifiable {
    let id = UUID()
    let prepared: PreparedObservationNarration
}
