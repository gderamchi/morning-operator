import SwiftUI
import UniformTypeIdentifiers
import MorningCore

struct MorningRootView: View {
    @Bindable var store: MorningStore
    @ViewState<Bool> private var showingSettings = false
    @ViewState<Bool> private var showingLearn = false
    @ViewState<Bool> private var presentingIntentCapture = false
    @Environment(\.scenePhase) private var scenePhase
    private let tabs: [MorningTab] = [.today, .review, .captures]

    var body: some View {
        TabView(selection: $store.tab) {
            ForEach(tabs) { tab in
                NavigationStack {
                    content(tab)
                        .background(MorningStyle.background)
                        .toolbar {
                            ToolbarItem(placement: .primaryAction) {
                                Button { showingSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                                    .accessibilityLabel("Settings").accessibilityIdentifier("navigation.setup")
                            }
                        }
                }
                .tabItem { Label(tab.rawValue, systemImage: tab.symbol) }.tag(tab)
            }
        }
        .tint(MorningStyle.accent)
        .sheet(isPresented: $showingSettings, onDismiss: presentPendingIntentCapture) {
            detailSheet("Settings") { SetupView(store: store) }
        }
        .sheet(isPresented: $showingLearn, onDismiss: presentPendingIntentCapture) {
            detailSheet("Learn my morning") { LearnView(store: store) }
        }
        .sheet(isPresented: $store.capturePresented, onDismiss: captureReviewDismissed) {
            QuickCaptureView(store: store)
        }
        .onChange(of: store.tab) { _, value in
            if value == .learn { store.tab = .today; showingLearn = true }
            if value == .setup { store.tab = .today; showingSettings = true }
        }
        .onChange(of: store.speech.voiceIdentifier) { store.saveVoicePreference() }
        .onChange(of: store.readAloud) { store.executionPreferencesChanged() }
        .onChange(of: store.automatic) { store.executionPreferencesChanged() }
        .onChange(of: store.speech.state) { store.handleSpeechInterruption() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, store.session?.status == .running { store.pause() }
        }
        .onChange(of: MorningIntentRouter.shared.pendingCaptureText, initial: true) { _, _ in
            presentPendingIntentCapture()
        }
        .onChange(of: MorningIntentRouter.shared.startRequested, initial: true) { _, requested in
            if requested {
                MorningIntentRouter.shared.startRequested = false
                store.tab = .today
                if store.routine?.isApproved == true { store.start() }
                else { store.notice = "Review and approve your routine before starting with Siri." }
            }
        }
    }

    private func presentPendingIntentCapture() {
        guard !presentingIntentCapture, !store.capturePresented, !showingSettings, !showingLearn,
              let text = MorningIntentRouter.shared.pendingCaptureText else { return }
        presentingIntentCapture = true
        store.openCapture(text: text, source: .siri)
    }

    private func captureReviewDismissed() {
        if presentingIntentCapture {
            MorningIntentRouter.shared.finishCaptureReview()
            presentingIntentCapture = false
        }
        // A Siri request received during a typed draft waits until that draft is dismissed.
        presentPendingIntentCapture()
    }

    @ViewBuilder private func content(_ tab: MorningTab) -> some View {
        switch tab {
        case .today: TodayView(store: store, showLearn: { showingLearn = true })
        case .review: WeeklyReviewView(store: store)
        case .captures: CapturesView(store: store)
        default: EmptyView()
        }
    }

    private func detailSheet<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    content()
                    if let notice = store.notice { NoticeView(text: notice, dismiss: { store.notice = nil }) }
                }.padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }
                .background(MorningStyle.background).navigationTitle(title)
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingSettings = false; showingLearn = false }
                } }
        }
        .presentationDragIndicator(.visible)
        #if os(macOS)
        .frame(minWidth: 540, idealWidth: 640, minHeight: 650)
        #endif
    }
}

struct TodayView: View {
    @Bindable var store: MorningStore
    var showLearn: () -> Void
    @ViewState<Int> private var dayOffset = 0
    @ViewState<RoutineStep?> private var editingStep = nil
    @ViewState<Bool> private var editing = false
    @ViewState<Bool> private var exporting = false
    private var date: Date { Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date() }
    private var day: MorningDaySummary? { store.daySummary(date) }
    private var historical: MorningRunRecord? { day?.runs.last }
    private var visibleRoutine: RoutineVersion? { dayOffset == 0 ? store.routine : historical?.routine }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header.id("morning.top")
                    dayStrip
                    if dayOffset == 0 {
                        if let routine = store.routine {
                            if store.sessionActive { currentMoment }
                            else if store.session?.status == .completed || store.session?.status == .stopped { terminalMoment }
                            else { overview(routine) }
                            timeline(routine, historical: nil)
                            if !store.sessionActive {
                                HStack {
                                    Button { showLearn() } label: { Label("Learn & refine", systemImage: "sparkles") }.accessibilityIdentifier("learn.refine")
                                    Spacer()
                                    Button { store.openCapture() } label: { Label("A thought?", systemImage: "square.and.pencil") }
                                }.font(.subheadline).buttonStyle(.borderless)
                            }
                        } else { welcome }
                    } else if let historical {
                        historyOverview(historical)
                        timeline(historical.routine, historical: historical)
                    } else {
                        EmptyMoment(symbol: "sun.haze", title: "A little space in your story.",
                            detail: "No morning was recorded on this day. Your history will grow as you use your routine.")
                        Button("Back to today") { dayOffset = 0 }.buttonStyle(SecondaryButtonStyle())
                    }
                    if let notice = store.notice { NoticeView(text: notice, dismiss: { store.notice = nil }) }
                }
                .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 24)
                .frame(maxWidth: 680).frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if dayOffset == 0, let routine = store.routine { runDock(routine) }
            }
            .simultaneousGesture(DragGesture(minimumDistance: 55).onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                dayOffset = min(0, max(-6, dayOffset + (value.translation.width < 0 ? 1 : -1)))
            })
            .sheet(item: $editingStep) { step in
                StepEditor(step: step, onSave: { edited in
                    var steps = store.routine?.steps ?? []
                    if let index = steps.firstIndex(where: { $0.id == edited.id }) { steps[index] = edited }
                    else { steps.append(edited) }
                    store.updateSteps(steps); editingStep = nil
                }, onDelete: {
                    store.updateSteps((store.routine?.steps ?? []).filter { $0.id != step.id }); editingStep = nil
                })
            }
            .fileExporter(isPresented: $exporting, document: visibleRoutine.map(RoutineExportDocument.init),
                          contentType: .json, defaultFilename: "Morning-Routine") { result in
                if case .failure(let error) = result { store.notice = error.localizedDescription }
            }
            .onChange(of: store.routine?.id) { _, _ in
                scrollProxy.scrollTo("morning.top", anchor: .top)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("MORNING OPERATOR", systemImage: "sun.horizon").font(.caption2.weight(.semibold)).tracking(1.6)
                Spacer()
                Text(date.formatted(.dateTime.month(.abbreviated).year())).font(.caption).foregroundStyle(.secondary)
            }.foregroundStyle(MorningStyle.accent)
            Text(dayOffset == 0 ? (store.routine == nil ? "Your morning,\na little lighter." : "A morning for you.") : date.formatted(.dateTime.weekday(.wide)))
                .font(.system(.largeTitle, design: .serif, weight: .medium)).tracking(-0.7)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var dayStrip: some View {
        HStack(spacing: 4) {
            ForEach(-6...0, id: \.self) { offset in
                let d = Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
                Button { dayOffset = offset } label: {
                    VStack(spacing: 10) {
                        Text(d.formatted(.dateTime.weekday(.narrow))).font(.caption)
                        Text(d.formatted(.dateTime.day())).font(.body.weight(dayOffset == offset ? .semibold : .regular))
                        Circle().fill((store.daySummary(d)?.runCount ?? 0) > 0 ? MorningStyle.accent : .clear).frame(width: 4, height: 4)
                    }.foregroundStyle(dayOffset == offset ? .primary : .secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(dayOffset == offset ? MorningStyle.lavender : .clear, in: RoundedRectangle(cornerRadius: 22))
                }.buttonStyle(.plain)
                    .accessibilityLabel(d.formatted(date: .complete, time: .omitted))
                    .accessibilityAddTraits(dayOffset == offset ? .isSelected : [])
                    .accessibilityIdentifier("history.day.\(offset)")
            }
        }
    }

    private func overview(_ routine: RoutineVersion) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "sun.max.fill").font(.title2)
                    .foregroundStyle(Color(red: 0.76, green: 0.47, blue: 0.21))
                    .frame(width: 48, height: 48).background(MorningStyle.paleOrange, in: Circle())
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(store.totalMinutes) min · \(routine.steps.count) moments").font(.headline)
                    Text(routine.isApproved ? "Planned around what matters to you." : "A first draft. Make it yours.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            if routine.sourceLabel.localizedCaseInsensitiveContains("demo fixture") {
                Label("Sample routine · not observed behavior", systemImage: "sparkles")
                    .font(.caption).foregroundStyle(MorningStyle.accent).accessibilityIdentifier("routine.source")
            }
            if store.previousRoutine != nil && !routine.isApproved {
                Button("Restore previous routine") { store.restorePreviousRoutine() }
                    .font(.caption).accessibilityIdentifier("routine.restore")
            }
        }.padding(20).background(MorningStyle.surface, in: RoundedRectangle(cornerRadius: 24))
    }

    private var terminalMoment: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Label(store.session?.status == .completed ? "A morning well spent." : "Take your time.",
                      systemImage: store.session?.status == .completed ? "checkmark.circle" : "pause.circle")
                    .font(.title3.weight(.medium)).accessibilityIdentifier("run.step")
                Text(store.stateLabel).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("run.state").accessibilityValue(store.stateLabel)
                Text("Your progress is saved. See Review for your week.").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private var currentMoment: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(store.session?.status == .paused ? "Paused" : "Your moment", systemImage: store.session?.status == .paused ? "pause.fill" : "waveform")
                    .font(.caption.weight(.semibold)).foregroundStyle(MorningStyle.accent)
                Spacer()
                Text(store.stateLabel).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("run.state").accessibilityValue(store.stateLabel)
            }
            Text(store.currentStep?.title ?? "Take your time").font(.title2.weight(.medium)).accessibilityIdentifier("run.step")
            Text(store.currentStep?.detail ?? "").font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
            if store.automatic, !store.automation.message.isEmpty {
                Text(store.automation.message).font(.caption).foregroundStyle(.secondary)
            }
            ProgressView(value: store.session?.progress ?? 0).tint(MorningStyle.accent)
            HStack {
                Toggle("Hands free", isOn: $store.automatic).toggleStyle(.switch).font(.caption)
                Spacer()
                MorningAudioRoutePicker().frame(width: 44, height: 44)
            }
        }.padding(22).background(MorningStyle.lavender.opacity(0.7), in: RoundedRectangle(cornerRadius: 28))
    }

    private func historyOverview(_ record: MorningRunRecord) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: "Your morning, remembered")
                Text(MorningStyle.duration(record.activeDurationSeconds)).font(.system(.largeTitle, design: .rounded))
                Text("\(record.completedStepCount) of \(record.totalStepCount) moments completed · \(record.skippedStepCount) skipped")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("Routine time excludes pauses. This is not a measure of app usage.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func timeline(_ routine: RoutineVersion, historical: MorningRunRecord?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(historical == nil ? "Your flow" : "The flow you followed").font(.title3.weight(.semibold))
                Spacer()
                if historical == nil && !store.sessionActive {
                    Button(editing ? "Done" : "Edit") { editing.toggle() }.font(.subheadline)
                        .disabled(store.busy)
                }
                Menu {
                    Button("Export routine", systemImage: "square.and.arrow.up") { exporting = true }
                    if historical == nil { Button("Learn from an observation", systemImage: "sparkles", action: showLearn) }
                } label: { Image(systemName: "ellipsis").frame(width: 36, height: 36) }
                .accessibilityLabel("Routine options")
            }
            VStack(spacing: 10) {
                ForEach(Array(routine.steps.enumerated()), id: \.element.id) { index, step in
                    timelineRow(step, index: index, routine: routine, historical: historical)
                }
            }
            if editing && historical == nil && !store.sessionActive {
                Button { editingStep = RoutineStep(title: "", detail: "", kind: .custom, durationMinutes: 5) }
                label: { Label("Add a moment", systemImage: "plus") }.buttonStyle(SecondaryButtonStyle())
            }
            Text(historical == nil ? "Times show your planned rhythm. You can always pause or skip." : "Saved with the routine version used that morning.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func timelineRow(_ step: RoutineStep, index: Int, routine: RoutineVersion, historical: MorningRunRecord?) -> some View {
        let minutes = routine.steps.prefix(index).reduce(0) { $0 + $1.durationMinutes }
        let completed = historical?.completedStepIDs.contains(step.id) ?? store.session?.completedStepIDs.contains(step.id) ?? false
        let skipped = historical?.skippedStepIDs.contains(step.id) ?? store.session?.skippedStepIDs.contains(step.id) ?? false
        let current = historical == nil && store.sessionActive && store.currentStep?.id == step.id
        return HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 8) {
                Text(minutes == 0 ? "Start" : "+\(minutes)m").font(.caption2.monospacedDigit()).foregroundStyle(.secondary).frame(width: 42)
                RoundedRectangle(cornerRadius: 2).fill(MorningStyle.line).frame(width: 2).frame(maxHeight: .infinity)
            }.padding(.top, 18)
            Button { editingStep = step } label: {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: completed ? "checkmark" : skipped ? "forward.end" : MorningStyle.symbol(for: step.kind))
                        .font(.system(size: 19, weight: .medium)).frame(width: 28, height: 30)
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(step.title).font(.headline)
                            Spacer(minLength: 3)
                            if current { Circle().fill(MorningStyle.accent).frame(width: 7, height: 7) }
                        }
                        Text(timelineDetail(step.detail)).font(.subheadline).foregroundStyle(.secondary).lineLimit(editing ? nil : 2)
                        HStack(spacing: 8) {
                            Text("\(step.durationMinutes) min").font(.caption.weight(.medium))
                            if step.isRequired { Text("· Keep this ritual").font(.caption) }
                            if completed || skipped { Text(completed ? "· Done" : "· Skipped").font(.caption) }
                        }.foregroundStyle(.secondary)
                    }
                }.foregroundStyle(.primary).padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(MorningStyle.color(for: step.kind).opacity(completed || skipped ? 0.45 : 1), in: RoundedRectangle(cornerRadius: 24))
                    .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(current ? MorningStyle.accent : .clear, lineWidth: 1.5))
            }.buttonStyle(.plain).disabled(historical != nil || store.sessionActive || store.busy)
                .accessibilityIdentifier("routine.step.\(index)")
            if editing && historical == nil && !store.sessionActive {
                VStack {
                    Button { moveStep(index, by: -1) } label: { Image(systemName: "chevron.up").frame(width: 32, height: 40) }
                        .disabled(index == 0).accessibilityLabel("Move \(step.title) earlier")
                    Button { moveStep(index, by: 1) } label: { Image(systemName: "chevron.down").frame(width: 32, height: 40) }
                        .disabled(index == routine.steps.count - 1).accessibilityLabel("Move \(step.title) later")
                }.buttonStyle(.borderless)
            }
        }.fixedSize(horizontal: false, vertical: true)
    }

    private func timelineDetail(_ detail: String) -> String {
        // Older generated drafts appended evidence to their detail. Keep that full text in
        // the editor/export, while the timeline presents only the activity description.
        guard let metadata = detail.range(of: "\nEvidence:") else { return detail }
        return String(detail[..<metadata.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func moveStep(_ index: Int, by delta: Int) {
        guard var steps = store.routine?.steps, steps.indices.contains(index + delta) else { return }
        steps.swapAt(index, index + delta); store.updateSteps(steps)
    }

    private func runDock(_ routine: RoutineVersion) -> some View {
        VStack(spacing: 9) {
            if store.sessionActive {
                HStack(spacing: 14) {
                    if store.session?.status == .paused {
                        Button { store.resume() } label: { Label("Continue", systemImage: "play.fill").frame(maxWidth: .infinity) }
                            .buttonStyle(.glassProminent).tint(MorningStyle.controlTint).accessibilityIdentifier("run.resume")
                    } else {
                        Button { store.pause() } label: { Image(systemName: "pause.fill").frame(width: 28, height: 28) }
                            .buttonStyle(.glass).accessibilityLabel("Pause").accessibilityIdentifier("run.pause")
                        Button { store.advance() } label: { Label("Next", systemImage: "arrow.right").frame(maxWidth: .infinity) }
                            .buttonStyle(.glassProminent).tint(MorningStyle.controlTint).accessibilityIdentifier("run.next")
                    }
                    Menu {
                        Button("Skip this moment") { store.advance(skipping: true) }.disabled(store.session?.status != .running)
                        Button("Read aloud") { store.readCurrent() }
                        Button("End morning") { store.stop() }.accessibilityIdentifier("run.stop")
                    } label: { Image(systemName: "ellipsis").frame(width: 28, height: 28) }.buttonStyle(.glass)
                        .accessibilityLabel("Morning controls").accessibilityIdentifier("run.controls")
                }.controlSize(.large)
            } else {
                Button {
                    if routine.isApproved { store.start() } else { store.approve() }
                } label: {
                    Label(routine.isApproved ? "OK, here we go" : "This feels like me",
                          systemImage: routine.isApproved ? "play.fill" : "checkmark")
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                }.buttonStyle(.glassProminent).tint(MorningStyle.controlTint).controlSize(.large).disabled(store.busy)
                    .accessibilityIdentifier(routine.isApproved ? "run.start" : "routine.approve")
            }
        }.padding(.horizontal, 24).padding(.vertical, 12).frame(maxWidth: 680)
            .frame(maxWidth: .infinity).background(MorningStyle.background.opacity(0.92))
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "sun.horizon.fill").font(.system(size: 52, weight: .light)).foregroundStyle(MorningStyle.accent)
                    .padding(.top, 12).accessibilityHidden(true)
                Text("Less handling.\nMore morning.").font(.system(.largeTitle, design: .serif, weight: .medium))
                Text("The briefing. The messages. That game of chess. Let's make space for the things you care about.")
                    .font(.body).foregroundStyle(.secondary)
                Button(action: showLearn) { Label("Learn my morning", systemImage: "sparkles").frame(maxWidth: .infinity) }
                    .buttonStyle(.glassProminent).tint(MorningStyle.controlTint).controlSize(.large).accessibilityIdentifier("learn.begin")
            }.padding(26).background(MorningStyle.lavender.opacity(0.65), in: RoundedRectangle(cornerRadius: 30))
            HStack {
                Button("Build it myself") { store.useManualRoutine() }
                Spacer()
                Button("Explore a sample") { store.loadSample() }.accessibilityIdentifier("routine.sample")
            }.font(.subheadline).buttonStyle(.borderless)
            Label("A private little ritual. Saved on your device.", systemImage: "lock")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct NoticeView: View {
    let text: String
    let dismiss: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle")
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: dismiss) { Image(systemName: "xmark").padding(5) }.accessibilityLabel("Dismiss message")
        }.foregroundStyle(.secondary).padding(16).background(MorningStyle.surface, in: RoundedRectangle(cornerRadius: 18))
            .accessibilityIdentifier("app.notice")
    }
}

struct RoutineExportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    let routine: RoutineVersion
    init(_ routine: RoutineVersion) { self.routine = routine }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        routine = try JSONDecoder().decode(RoutineVersion.self, from: data)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return FileWrapper(regularFileWithContents: try encoder.encode(routine))
    }
}
