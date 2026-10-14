import SwiftUI
import MorningCore
import MorningApple

/// "Keep raw evidence for…" in Privacy (issue #8). Choosing an age removes nothing:
/// it only lists what is older, for review and explicit confirmation.
struct EvidenceRetentionSection: View {
    @Bindable var store: MorningStore
    @ViewState private var reviewing: EvidenceRemovalReview?

    private struct Choice: Identifiable {
        let days: Int?
        let label: String
        var id: String { days.map(String.init) ?? "off" }
    }

    private var choices: [Choice] {
        [Choice(days: nil, label: String(localized: "Off")),
         Choice(days: 30, label: String(localized: "30 days")),
         Choice(days: 90, label: String(localized: "90 days")),
         Choice(days: 365, label: String(localized: "1 year"))]
    }

    var body: some View {
        Section {
            ForEach(choices) { choice in
                let selected = store.evidenceRetentionDays == choice.days
                Button { store.setEvidenceRetentionDays(choice.days) } label: {
                    HStack(alignment: .firstTextBaseline) {
                        Text(choice.label).foregroundStyle(MorningStyle.ink)
                        Spacer(minLength: 8)
                        if selected {
                            Image(systemName: "checkmark").foregroundStyle(MorningStyle.accent)
                                .accessibilityHidden(true)
                        }
                    }.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!store.canChangeEvidenceRetention)
                .accessibilityLabel(choice.label)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("privacy.retention.option.\(choice.id)")
            }
            if let review = store.evidenceExpiryReview() {
                if review.isEmpty {
                    Text("Nothing is older than this right now.")
                        .font(.subheadline).foregroundStyle(MorningStyle.muted)
                        .accessibilityIdentifier("privacy.retention.nothingDue")
                } else {
                    let count = review.acquisitionIDs.count
                    LabeledContent(String(localized: "Older than this"), value: String(count))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(String(localized: "Older than this"))
                        .accessibilityValue(String(count))
                        .accessibilityIdentifier("privacy.retention.dueCount")
                    Button(String(localized: "Review before removing…")) { reviewing = review }
                        .disabled(store.evidenceRemovalInProgress)
                        .accessibilityIdentifier("privacy.retention.review")
                }
                if !review.unknownAgeAcquisitionIDs.isEmpty {
                    Text("\(review.unknownAgeAcquisitionIDs.count) observations have no saved import date. They are never removed by age.")
                        .font(.footnote).foregroundStyle(MorningStyle.muted)
                        .accessibilityIdentifier("privacy.retention.unknownAge")
                }
            }
            if store.hasPendingEvidenceRemoval, !store.evidenceRemovalInProgress {
                Button(String(localized: "Finish the interrupted removal")) { store.resumeEvidenceRemovalIfNeeded() }
                    .accessibilityIdentifier("privacy.retention.resume")
            }
            if let status = store.evidenceRemovalStatus {
                Text(status).font(.footnote).foregroundStyle(MorningStyle.muted)
                    .accessibilityIdentifier("privacy.retention.status")
            }
        } header: {
            Text("Keep raw evidence for")
        } footer: {
            Text("Off keeps every observation until you remove it. When an age is chosen, nothing is removed until you review the list and confirm. Quotations in a routine you approved and moments you chose to keep stay.")
        }
        .sheet(isPresented: Binding(get: { reviewing != nil }, set: { if !$0 { reviewing = nil } })) {
            if let review = reviewing {
                EvidenceRemovalSheet(store: store, review: review) { _ in }
            }
        }
    }
}

/// "Forget this observation…" on an observation's detail: the same review for one observation.
struct ForgetObservationButton: View {
    @Bindable var store: MorningStore
    let observationID: UUID
    var onForgotten: () -> Void
    @ViewState private var reviewing: EvidenceRemovalReview?
    @ViewState private var forgotten = false

    var body: some View {
        Button(String(localized: "Forget this observation…"), role: .destructive) {
            reviewing = store.forgettingReview(observationID)
        }
        .disabled(store.busy || store.sessionActive || !store.privacyInventoryIsReadable || store.evidenceRemovalInProgress)
        .accessibilityIdentifier("observation.forget")
        .sheet(isPresented: Binding(get: { reviewing != nil }, set: { if !$0 { reviewing = nil } }), onDismiss: {
            guard forgotten else { return }
            forgotten = false
            onForgotten()
        }) {
            if let review = reviewing {
                EvidenceRemovalSheet(store: store, review: review) { forgotten = $0 }
            }
        }
        Text("Shows every copy of it first. Quotations in an unapproved draft go too; what you approved or kept stays.")
            .font(.caption).foregroundStyle(MorningStyle.muted)
    }
}

/// The review the person confirms before anything is removed. Cancel changes nothing.
struct EvidenceRemovalSheet: View {
    @Bindable var store: MorningStore
    @ViewState private var review: EvidenceRemovalReview
    var onFinished: (Bool) -> Void
    @ViewState private var changed = false
    @ViewState private var applying = false
    @ViewState private var failure: String?
    @Environment(\.dismiss) private var dismiss

    init(store: MorningStore, review: EvidenceRemovalReview, onFinished: @escaping (Bool) -> Void) {
        self.store = store
        _review = ViewState(initialValue: review)
        self.onFinished = onFinished
    }

    private var isSingle: Bool { if case .single = review.scope { true } else { false } }

    /// Copies held inside a suggestion that is set aside go with it and are not listed again.
    private var listed: [EvidenceDependentCopy] {
        review.copies.filter { !(review.setsAsidePendingSuggestion && $0.store == .pendingProposal) }
    }
    private var removed: [EvidenceDependentCopy] { listed.filter { $0.disposition == .removed } }
    private var invalidated: [EvidenceDependentCopy] { listed.filter { $0.disposition == .invalidated } }
    private var retained: [EvidenceDependentCopy] { listed.filter { $0.disposition == .separatelyRetained } }

    var body: some View {
        NavigationStack {
            MorningList {
                if changed {
                    Section {
                        Text("Your saved data changed after this list was shown, so nothing was removed. This is the updated list.")
                            .font(.subheadline)
                            .accessibilityIdentifier("retention.changed")
                    }
                }
                Section {
                    Text(headline).font(.title3.weight(.semibold))
                        .accessibilityIdentifier("retention.headline")
                    if case .expiry(let days) = review.scope {
                        Text("Imported before \(Date().addingTimeInterval(Double(-days) * 86_400), format: .dateTime.day().month(.wide).year()).")
                            .font(.subheadline).foregroundStyle(MorningStyle.muted)
                    }
                    Text("Their original text, corrections, sampled screens and screen labels leave MORE on this device. Nothing else is removed unless it is listed below as removed.")
                        .font(.subheadline).foregroundStyle(MorningStyle.muted)
                    countRow(String(localized: "Observations to remove"), review.acquisitionIDs.count, "retention.count.observations")
                    countRow(String(localized: "Quotations removed with them"), removed.count, "retention.count.removed")
                    countRow(String(localized: "Links and suggestions set aside"),
                             invalidated.count + (review.setsAsidePendingSuggestion ? 1 : 0), "retention.count.invalidated")
                    countRow(String(localized: "Copies kept separately"), retained.count, "retention.count.retained")
                }
                if !removed.isEmpty {
                    Section {
                        copyRows(removed, prefix: "retention.removed")
                    } header: { Text("Removed with them") }
                }
                if !invalidated.isEmpty || review.setsAsidePendingSuggestion {
                    Section {
                        if review.setsAsidePendingSuggestion {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Your pending suggestion").font(.subheadline.weight(.medium))
                                Text("It was prepared from what changes here, so it is set aside and has to be worked out again. Your current routine is unchanged by this.")
                                    .font(.caption).foregroundStyle(MorningStyle.muted)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("retention.suggestion")
                        }
                        copyRows(invalidated, prefix: "retention.invalidated")
                    } header: { Text("No longer linked") }
                }
                if !retained.isEmpty {
                    Section {
                        copyRows(retained, prefix: "retention.retained")
                    } header: {
                        Text("Kept separately")
                    } footer: {
                        Text("These stay. Remove them where they live if you want them gone too.")
                    }
                }
                if !review.unknownAgeAcquisitionIDs.isEmpty {
                    Section {
                        Text("\(review.unknownAgeAcquisitionIDs.count) observations have no saved import date. They are never removed by age.")
                            .font(.subheadline)
                            .accessibilityIdentifier("retention.unknownAge")
                    }
                }
                if let failure {
                    Section {
                        Text(failure).font(.subheadline).accessibilityIdentifier("retention.failure")
                    }
                }
            }
            .navigationTitle(isSingle ? String(localized: "Forget this observation?") : String(localized: "Remove old observations?"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                        .disabled(applying)
                        .accessibilityIdentifier("retention.cancel")
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    if applying {
                        ProgressView(String(localized: "Removing…"))
                            .accessibilityIdentifier("retention.progress")
                    }
                    Button(role: .destructive) { confirm() } label: {
                        Text(confirmTitle).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(applying || review.isEmpty)
                    .accessibilityIdentifier("retention.confirm")
                }
                .padding(20).frame(maxWidth: .infinity).background(.regularMaterial)
            }
        }
        .interactiveDismissDisabled(applying)
        .presentationDragIndicator(.visible)
    }

    private var headline: String {
        let count = review.acquisitionIDs.count
        return isSingle ? String(localized: "This observation will be removed.")
            : String(localized: "\(count) observations would be removed.")
    }

    private var confirmTitle: String {
        isSingle ? String(localized: "Forget this observation")
            : String(localized: "Remove \(review.acquisitionIDs.count) observations")
    }

    private func confirm() {
        guard !applying else { return }
        applying = true
        failure = nil
        let confirmed = review
        Task { @MainActor in
            let outcome = await store.applyEvidenceRemoval(confirmed)
            applying = false
            switch outcome {
            case .removed, .cleanupPending:
                onFinished(true)
                dismiss()
            case .changed(let fresh):
                if let fresh {
                    review = fresh
                    changed = true
                } else {
                    failure = String(localized: "There is nothing left to remove here. Nothing was removed.")
                }
            case .notStarted(let message):
                failure = message
            }
        }
    }

    private func countRow(_ title: String, _ value: Int, _ identifier: String) -> some View {
        LabeledContent(title, value: String(value))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title).accessibilityValue(String(value))
            .accessibilityIdentifier(identifier)
    }

    /// Identical copies (the same words for the same reason in the same place, such as
    /// several saved runs) are shown once with their number.
    private func copyRows(_ copies: [EvidenceDependentCopy], prefix: String) -> some View {
        var groups: [(copy: EvidenceDependentCopy, count: Int)] = []
        for copy in copies {
            if let index = groups.firstIndex(where: { $0.copy.store == copy.store && $0.copy.reason == copy.reason
                && $0.copy.quote.map({ Array($0.utf8) }) == copy.quote.map({ Array($0.utf8) }) }) {
                groups[index].count += 1
            } else {
                groups.append((copy, 1))
            }
        }
        return ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
            VStack(alignment: .leading, spacing: 6) {
                Text(place(group.copy.store)).font(.subheadline.weight(.medium))
                if let quote = group.copy.quote {
                    Text("“\(quote)”").font(.subheadline)
                }
                if group.count > 1 {
                    Text("\(group.count) copies").font(.caption).foregroundStyle(MorningStyle.muted)
                }
                Text(group.copy.reason.explanation).font(.caption).foregroundStyle(MorningStyle.muted)
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("\(prefix).\(index)")
        }
    }

    private func place(_ store: EvidenceRetentionStore) -> String {
        switch store {
        case .currentRoutine: String(localized: "Your current routine")
        case .previousRoutine: String(localized: "Your previous routine")
        case .session: String(localized: "The morning saved with your routine")
        case .pendingProposal: String(localized: "Your pending suggestion")
        case .preferenceJournal: String(localized: "A moment you chose to keep")
        case .runHistory: String(localized: "A saved morning")
        }
    }
}
