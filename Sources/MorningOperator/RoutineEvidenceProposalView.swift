import SwiftUI
import MorningCore
import MorningApple

/// A separately saved suggestion. Reading or dismissing it never replaces the ready routine.
struct RoutineEvidenceProposalView: View {
    @Bindable var store: MorningStore
    /// The presenting view dismisses this sheet before opening the existing Learn sheet.
    var onLearn: () -> Void
    var onEdit: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            MorningList {
                if let proposal = store.pendingRoutineProposal {
                    summary(proposal)
                    if dynamicTypeSize.isAccessibilitySize {
                        Section {
                            delegationExplanation
                            editButton
                            keepCurrentButton
                        }
                    }
                    if proposal.baseRoutineID != nil, let current = store.routine {
                        Section {
                            DisclosureGroup("Compare with current routine") {
                                ForEach(current.steps) { step in
                                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                                        Text(step.title).font(.raleway(.subheadline))
                                        Spacer(minLength: 8)
                                        Text("\(step.durationMinutes) min planned").font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                                    }.padding(.vertical, 4)
                                }
                            }
                        }
                    }
                    if !proposal.omissions.isEmpty {
                        Section {
                            DisclosureGroup("Samples not used (\(proposal.omissions.count))") {
                                Text("These samples weren't used to suggest activities. Missing or unsuitable evidence stays unknown.")
                                    .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                                ForEach(proposal.sourceSnapshots, id: \.acquisitionID) { source in
                                    let omitted = proposal.omissions.filter { $0.acquisitionID == source.acquisitionID }
                                    if !omitted.isEmpty {
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(source.sourceLabel).font(.raleway(.subheadline))
                                            let incomplete = omitted.filter { $0.reason == .unavailableOrTruncatedFrame }.count
                                            let unsupported = omitted.filter { $0.reason == .unsupportedVisualContext }.count
                                            let ownInterface = omitted.filter { $0.reason == .ownInterfaceInFront }.count
                                            let reviewedUnknown = omitted.filter { $0.reason == .explicitlyReviewedUnknown }.count
                                            if reviewedUnknown > 0 { Text("\(reviewedUnknown) samples you kept unknown").font(.raleway(.caption)).foregroundStyle(MorningStyle.muted) }
                                            if incomplete > 0 { Text("\(incomplete) unavailable or incomplete samples").font(.raleway(.caption)).foregroundStyle(MorningStyle.muted) }
                                            if unsupported > 0 { Text("\(unsupported) samples without suitable activity context").font(.raleway(.caption)).foregroundStyle(MorningStyle.muted) }
                                            if ownInterface > 0 { Text("\(ownInterface) samples left out because MORE itself was in front").font(.raleway(.caption)).foregroundStyle(MorningStyle.muted) }
                                        }.padding(.vertical, 5)
                                    }
                                }
                            }
                        }
                    }
                    ForEach(Array(proposal.routine.steps.enumerated()), id: \.element.id) { index, step in
                        Section {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(step.title).font(.serif(.headline))
                                    .accessibilityLabel("Suggested moment \(index + 1)")
                                    .accessibilityValue(step.title)
                                    .accessibilityIdentifier("proposal.step.\(index)")
                                if !briefDetail(step).isEmpty { Text(briefDetail(step)).font(.raleway(.subheadline)).foregroundStyle(MorningStyle.muted) }
                                Text("\(step.durationMinutes) minutes planned")
                                    .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                                Text(step.executionDescription).font(.raleway(.subheadline))
                                if case let .connectedAPI(_, _, _, arguments) = step.target {
                                    Text((try? ConnectedActionReview.summary(argumentsJSON: arguments)) ?? "Review unavailable")
                                        .font(.footnote).fixedSize(horizontal: false, vertical: true)
                                }
                            }.padding(.vertical, 3)
                            if let support = proposal.support.first(where: { $0.stepID == step.id }) {
                                if support.reason == .preservedUserDecision {
                            Label("Kept by your choice", systemImage: "heart")
                                        .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                                } else {
                                    if support.reason == .inferredEvidenceWithUserPreference {
                                        Label("Your saved timing choice", systemImage: "clock.badge.checkmark")
                                            .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                                            .accessibilityIdentifier("proposal.userTiming")
                                    }
                                    DisclosureGroup("Why this suggestion?") {
                                        ForEach(Array(support.citations.enumerated()), id: \.offset) { quoteIndex, citation in
                                            VStack(alignment: .leading, spacing: 8) {
                                                Text("“\(citation.quote)”").font(.raleway(.subheadline)).textSelection(.enabled)
                                                    .accessibilityIdentifier("proposal.quote.\(step.id.uuidString).\(quoteIndex)")
                                                if let source = proposal.sourceSnapshots.first(where: { $0.acquisitionID == citation.acquisitionID }) {
                                                    Text("\(proposalDateLabel(source.observedDate)) · \(citation.sourceLayer.displayName)")
                                                        .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                                                    Text(source.sourceLabel).font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                                                }
                                            }.padding(.vertical, 6)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Section {
                        ForEach(proposal.sourceSnapshots, id: \.acquisitionID) { source in
                            NavigationLink {
                                ObservationHistoryDetail(store: store, observationID: source.acquisitionID,
                                    onLearn: onLearn, managesEntryOccupancy: false)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(source.sourceLabel).font(.raleway(.subheadline))
                                    Text("\(proposalDateLabel(source.observedDate)) · \(source.sourceLayer.displayName)")
                                        .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                                }
                            }.accessibilityIdentifier("proposal.source.\(source.acquisitionID.uuidString)")
                        }
                    } header: { Text("Selected observations") } footer: {
                        Text("Correct a source in Learn to request a new suggestion.")
                    }
                    Section {
                        DisclosureGroup("About this suggestion") {
                            Text("Minutes are planned, not measured averages. Visible words don't prove an action or a repeated habit.")
                                .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                            Text(AppLanguage.isFrench
                                ? "Ajustez cette proposition avant de la confier à MORE. Vos observations sources restent inchangées."
                                : "Adjust this suggestion before delegating it. Your saved source observations stay unchanged.")
                                .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                            if proposal.sourceSnapshots.first?.origin == .synthetic {
                                Text("Sample observations stay separate from your personal habit history.")
                                    .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                            }
                        }
                    }
                } else {
                    ContentUnavailableView("Suggestion no longer available", systemImage: "doc.text.magnifyingglass",
                        description: Text("The observations or your routine may have changed. Choose the mornings again to make a fresh suggestion."))
                        .accessibilityIdentifier("proposal.unavailable")
                }
                if let notice = store.notice {
                    Section { Text(notice).font(.raleway(.caption)).foregroundStyle(MorningStyle.muted) }
                }
            }
            .scrollContentBackground(.hidden).background(MorningPaper(showsSun: false))
            .navigationTitle("Suggested update")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("proposal.close")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let proposal = store.pendingRoutineProposal {
                    VStack(alignment: .leading, spacing: 10) {
                        if dynamicTypeSize.isAccessibilitySize {
                            approveButton(proposal, compact: true)
                        } else {
                            delegationExplanation
                            editButton
                            HStack(spacing: 12) {
                                keepCurrentButton
                                approveButton(proposal, compact: false)
                            }
                        }
                    }.padding(20).background(.regularMaterial)
                }
            }
        }
        .onAppear { store.routineProposalPresented = true }
        .onDisappear { store.routineProposalPresented = false }
    }

    private var delegationExplanation: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppLanguage.isFrench ? "MORE s’occupe des actions présentées ici. Vous pouvez l’interrompre à tout moment." : "MORE takes care of the actions shown here. You can interrupt at any time.")
                .font(.footnote).fixedSize(horizontal: false, vertical: true)
            if store.sessionActive {
                Text("Finish or end your current morning before approving an update.")
                    .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
            }
        }
    }

    private var editButton: some View {
        Button {
            if store.editPendingRoutineProposal() { onEdit(); dismiss() }
        } label: {
            Label(AppLanguage.isFrench ? "Ajuster cette proposition" : "Adjust this suggestion", systemImage: "slider.horizontal.3")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(SecondaryButtonStyle())
        .disabled(store.busy || store.sessionActive || !store.storageIsAvailable || store.routinePreferencesIssue != nil)
        .accessibilityIdentifier("proposal.edit")
    }

    private var keepCurrentButton: some View {
        Button(store.routine == nil ? "Discard" : "Keep current") {
            if store.discardPendingRoutineProposal() { dismiss() }
        }
        .buttonStyle(SecondaryButtonStyle())
        .disabled(store.busy || !store.storageIsAvailable)
        .accessibilityIdentifier("proposal.keepCurrent")
    }

    private func approveButton(_ proposal: EvidenceRoutineProposal, compact: Bool) -> some View {
        Button {
            if store.approvePendingRoutineProposal() { dismiss(); store.tab = .today }
        } label: {
            Label(compact ? (AppLanguage.isFrench ? "Confier à MORE" : "Let MORE do it")
                  : (AppLanguage.isFrench ? "Confier ce matin à MORE" : "Let MORE take care of this morning"), systemImage: "checkmark")
                .frame(maxWidth: .infinity)
        }
        .accessibilityLabel(AppLanguage.isFrench ? "Confier ce matin à MORE" : "Let MORE take care of this morning")
        .buttonStyle(PrimaryButtonStyle())
        .disabled(store.busy || store.sessionActive || !store.storageIsAvailable || store.routinePreferencesIssue != nil || proposal.routine.steps.isEmpty)
        .accessibilityIdentifier("proposal.approve")
    }

    private func summary(_ proposal: EvidenceRoutineProposal) -> some View {
        let dayCount = Set(proposal.sourceSnapshots.map { $0.observedDate.dayKey }).count
        let isSample = proposal.sourceSnapshots.first?.origin == .synthetic
        return Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(isSample ? "Sample morning" : "Your next morning")
                    .font(.serif(.title2, .medium))
                Text("Selected: \(proposal.sourceSnapshots.count) observations across \(dayCount) dated days")
                    .font(.raleway(.subheadline)).foregroundStyle(MorningStyle.muted).accessibilityIdentifier("proposal.sources")
                Text(store.routine == nil ? "Review your moments, then approve when ready."
                     : "Your current routine stays ready until you approve.")
                    .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                if store.usesSyntheticProposalFixture {
                    Text("Synthetic suggestion test — no Apple model call")
                        .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                        .accessibilityIdentifier("proposal.fixtureMode")
                }
            }.padding(.vertical, 4)
        }
    }

    private func briefDetail(_ step: RoutineStep) -> String {
        guard let support = store.pendingRoutineProposal?.support.first(where: { $0.stepID == step.id }),
              support.reason == .inferredEvidence,
              let description = EvidenceDetailText.description(of: step.detail,
                  citing: support.citations.map(\.quote)) else { return step.detail }
        return description.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private func proposalDateLabel(_ value: ObservationObservedDate) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = TimeZone(identifier: value.timeZoneIdentifier)
    return formatter.string(from: value.date)
}
