import SwiftUI
import MorningCore

/// The Learn card: one approval, then a suggestion from the last week of Screen Time minutes.
struct ScreenTimeLearnCard: View {
    @Bindable var store: MorningStore
    var review: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                Label("Learn from Screen Time", systemImage: "hourglass")
                    .font(.title3.weight(.semibold)).foregroundStyle(MorningStyle.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("MORE looks at the minutes you spent in each app over the last week and finds your mornings. Only app names and minutes are kept, on this iPhone. No messages, no screens, no websites.")
                    .font(.subheadline).foregroundStyle(MorningStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if let proposal = store.pendingScreenTimeProposal {
                    Text("Suggestion ready: \(proposal.steps.count) apps from \(proposal.morningsUsed) mornings.")
                        .font(.subheadline.weight(.medium))
                        .accessibilityIdentifier("learn.screenTime.ready")
                    Button { review() } label: {
                        Label("Review suggestion", systemImage: "list.bullet.clipboard")
                    }.buttonStyle(PrimaryButtonStyle())
                        .disabled(store.busy)
                        .accessibilityIdentifier("learn.screenTime.review")
                }
                if store.screenTimeBusy {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Reading your last mornings…").font(.footnote)
                    }.accessibilityIdentifier("learn.screenTime.reading")
                } else {
                    Button { store.learnFromScreenTime() } label: {
                        Label(store.pendingScreenTimeProposal == nil ? "Learn from Screen Time" : "Learn again",
                              systemImage: "sparkles")
                    }
                    .buttonStyle(store.pendingScreenTimeProposal == nil ? AnyButtonStyle(PrimaryButtonStyle()) : AnyButtonStyle(SecondaryButtonStyle()))
                    .disabled(store.busy || !store.storageIsAvailable)
                    .accessibilityIdentifier("learn.screenTime.start")
                }
                if let message = store.screenTimeMessage {
                    Text(message).font(.footnote).foregroundStyle(MorningStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("learn.screenTime.message")
                }
                Text("Apple asks once (Continue, then Face ID). Only one app on this iPhone can hold this access. Nothing changes until you approve.")
                    .font(.footnote).foregroundStyle(MorningStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { store.refreshScreenTimeAccess() }
    }
}

/// Type erasure so the card can switch between the two button styles.
struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView
    init<Style: ButtonStyle>(_ style: Style) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

/// Review of a Screen Time suggestion: leave apps out, change minutes, then approve or keep
/// the current routine. Approving is the only way it becomes the routine.
struct ScreenTimeProposalView: View {
    @Bindable var store: MorningStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            MorningList {
                if let proposal = store.pendingScreenTimeProposal {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Your morning, from Screen Time")
                                .font(.system(.title2, design: .serif, weight: .medium))
                            Text("Your mornings usually start around \(startText(proposal)).")
                                .font(.subheadline).accessibilityIdentifier("screenTimeProposal.start")
                            Text("From \(proposal.morningsUsed) comparable mornings. Screen Time had \(proposal.daysOfData) days.")
                                .font(.subheadline).foregroundStyle(MorningStyle.muted)
                                .accessibilityIdentifier("screenTimeProposal.sources")
                            Text(store.routine == nil ? "Review the apps, then approve when ready."
                                 : "Your current routine stays ready until you approve. Approving replaces it with the apps you keep here.")
                                .font(.caption).foregroundStyle(MorningStyle.muted)
                        }.padding(.vertical, 4)
                    }
                    ForEach(Array(proposal.steps.enumerated()), id: \.element.id) { index, step in
                        Section { stepRow(step, index: index) }
                    }
                    Section {
                        DisclosureGroup("Measured or estimated?") {
                            Text("Measured: Screen Time counted these minutes inside your morning. Estimated: an hour ran past the end of your morning, so its minutes were shared out.")
                                .font(.caption).foregroundStyle(MorningStyle.muted)
                            Text("Screen Time gives minutes per hour, not the order inside an hour. So the order is estimated: the app you open most often from the Lock Screen comes first, then the others by hour, then by minutes.")
                                .font(.caption).foregroundStyle(MorningStyle.muted)
                        }
                    }
                } else {
                    ContentUnavailableView("Suggestion no longer available", systemImage: "hourglass",
                        description: Text("Your routine may have changed. Learn from Screen Time again for a fresh suggestion."))
                        .accessibilityIdentifier("screenTimeProposal.unavailable")
                }
                if let notice = store.notice {
                    Section { Text(notice).font(.caption).foregroundStyle(MorningStyle.muted) }
                }
            }
            .scrollContentBackground(.hidden).background(MorningStyle.background)
            .navigationTitle("Suggested update")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("screenTimeProposal.close")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let proposal = store.pendingScreenTimeProposal {
                    VStack(alignment: .leading, spacing: 10) {
                        if store.sessionActive {
                            Text("Finish or end your current morning before approving an update.")
                                .font(.caption).foregroundStyle(MorningStyle.muted)
                        }
                        HStack(spacing: 12) {
                            Button(store.routine == nil ? "Discard" : "Keep current") {
                                if store.discardPendingScreenTimeProposal() { dismiss() }
                            }
                            .buttonStyle(.glass).controlSize(.large)
                            .disabled(store.busy || !store.storageIsAvailable)
                            .accessibilityIdentifier("screenTimeProposal.keepCurrent")
                            Button {
                                if store.approvePendingScreenTimeProposal() {
                                    dismiss()
                                    store.tab = .today
                                }
                            } label: {
                                Label("Approve update", systemImage: "checkmark").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glassProminent).tint(MorningStyle.controlTint).controlSize(.large)
                            .disabled(store.busy || store.sessionActive || !store.storageIsAvailable
                                      || store.routinePreferencesIssue != nil || proposal.includedSteps.isEmpty)
                            .accessibilityIdentifier("screenTimeProposal.approve")
                        }
                    }.padding(20).background(.regularMaterial)
                }
            }
        }
    }

    @ViewBuilder private func stepRow(_ step: ScreenTimeRoutineProposal.Step, index: Int) -> some View {
        let morningsUsed = store.pendingScreenTimeProposal?.morningsUsed ?? step.morningsSeen
        Toggle(isOn: Binding(get: { step.included }, set: { value in
            store.editPendingScreenTimeProposal { $0.setIncluded(value, stepID: step.id) }
        })) {
            VStack(alignment: .leading, spacing: 5) {
                Text(step.title).font(.headline)
                    .accessibilityIdentifier("screenTimeProposal.step.\(index)")
                Text("Usually \(step.medianMinutes) min, on \(step.morningsSeen) of \(morningsUsed) mornings")
                    .font(.subheadline).foregroundStyle(MorningStyle.muted)
                Text(step.minutesMeasured ? "Minutes measured" : "Minutes estimated")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(step.minutesMeasured ? MorningStyle.green : MorningStyle.muted)
                    .accessibilityIdentifier("screenTimeProposal.label.\(index)")
                if step.isAttentionSink {
                    Label("Long scroll: you could keep this one shorter", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(MorningStyle.accent)
                        .accessibilityIdentifier("screenTimeProposal.scroll.\(index)")
                }
            }
        }
        .tint(MorningStyle.controlTint)
        .accessibilityIdentifier("screenTimeProposal.include.\(index)")
        if step.included {
            Stepper(value: Binding(get: { step.minutes }, set: { value in
                store.editPendingScreenTimeProposal { $0.setMinutes(value, stepID: step.id) }
            }), in: ScreenTimeRoutineProposal.minutesRange) {
                Text("\(step.minutes) min planned").font(.subheadline)
            }
            .accessibilityIdentifier("screenTimeProposal.minutes.\(index)")
        }
    }

    private func startText(_ proposal: ScreenTimeRoutineProposal) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: proposal.timeZoneIdentifier) ?? .current
        let date = calendar.date(bySettingHour: proposal.typicalStartMinuteOfDay / 60,
                                 minute: proposal.typicalStartMinuteOfDay % 60, second: 0, of: Date()) ?? Date()
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }
}
