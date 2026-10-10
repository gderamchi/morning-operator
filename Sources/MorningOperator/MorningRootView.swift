import SwiftUI
import UniformTypeIdentifiers
import MorningCore
import MorningApple

struct MorningRootView: View {
    @Bindable var store: MorningStore
    @ViewState<Bool> private var showingSettings = false
    @ViewState<Bool> private var showingLearn = false
    @ViewState<Bool> private var showingRoutineEditor = false
    @ViewState<UUID> private var reviewRootIdentity = UUID()
    @ViewState<Bool> private var resetReviewAfterSettingsDismissal = false
    @ViewState<Bool> private var presentingIntentCapture = false
    @ViewState<Bool> private var pendingObservationReview = false
    @ViewState<Bool> private var testObservedBackground = false
    @Environment(\.scenePhase) private var scenePhase

    private var presentedContent: some View {
        TabView(selection: $store.tab) {
            NavigationStack {
                TodayView(store: store, showLearn: { showingLearn = true },
                          reviewObservation: requestObservationReview,
                          showReview: { reviewRootIdentity = UUID(); store.tab = .review }, editRoutine: openRoutineReview)
                    .toolbar(.hidden, for: .navigationBar)
            }
            .tabItem { Label("Morning", systemImage: "sun.horizon") }.tag(MorningTab.today)
            NavigationStack {
                WeeklyReviewView(store: store, onLearn: { showingLearn = true },
                                 onSettings: {
                                     if store.voiceInputBlocksPlayback { store.voiceCommandPresented = true }
                                     else { showingSettings = true }
                                 }, showingRoutineEditor: $showingRoutineEditor)
                    .background(MorningStyle.background)
            }
            .id(reviewRootIdentity)
            .tabItem { Label("Review", systemImage: "circle.grid.2x2") }.tag(MorningTab.review)
        }
        #if os(iOS)
        .tabBarMinimizeBehavior(.onScrollDown)
        #endif
        .background {
            #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(ScreenCaptureKit)
            if #available(iOS 27.0, *) {
                MorningRecordingCoordinator(store: store, canProcessRecording: recordingCanProcess,
                                            onStarted: { showingLearn = false },
                                            onReview: requestObservationReview)
            }
            #endif
        }
        .tint(MorningStyle.accent)
        .sheet(isPresented: $showingSettings, onDismiss: {
            if resetReviewAfterSettingsDismissal {
                resetReviewAfterSettingsDismissal = false
                reviewRootIdentity = UUID()
            }
            processPendingEntries()
        }) {
            detailSheet("Settings") { SetupView(store: store) }
        }
        .sheet(isPresented: $showingLearn, onDismiss: processPendingEntries) {
            detailSheet("Learn my morning") { LearnView(store: store) }
        }
        .sheet(isPresented: $store.capturePresented, onDismiss: captureReviewDismissed) {
            QuickCaptureView(store: store)
        }
        .sheet(isPresented: $store.voiceCommandPresented, onDismiss: {
            store.cancelVoiceCommandTurn()
            processPendingEntries()
        }) { MorningVoiceCommandView(store: store) }
        .sheet(isPresented: $store.captureVoicePresented, onDismiss: {
            store.completionCaptureDismissed(allowReview: scenePhase == .active)
            processPendingEntries()
        }) { MorningCaptureVoiceView(store: store) }
    }

    var body: some View {
        presentedContent
        .onChange(of: store.dataGeneration) { _, _ in
            showingLearn = false; showingRoutineEditor = false
            presentingIntentCapture = false; pendingObservationReview = false
            // Keep the presenting Review stack stable while Privacy is open.
            // Replacing its tab identity during confirmation dismissal can strand
            // the old presentation over a fast cleanup failure. Successful removal
            // resets Review below; pending cleanup keeps Settings non-dismissible.
            if !showingSettings { reviewRootIdentity = UUID() }
        }
        .onChange(of: store.privacyCompletedID) { _, completed in
            guard completed != nil else { return }
            if showingSettings { resetReviewAfterSettingsDismissal = true }
            else { reviewRootIdentity = UUID() }
            showingSettings = false
            store.tab = .today
        }
        .onChange(of: store.completionInvitationSessionID) { _, _ in processPendingEntries() }
        .onChange(of: store.session?.id) { _, _ in store.completionSessionChanged() }
        .onChange(of: showingRoutineEditor) { _, showing in if !showing { processPendingEntries() } }
        .onChange(of: store.tab) { _, value in
            if value == .learn { store.tab = .review; showingLearn = true }
            if value == .setup { store.tab = .review; showingSettings = true }
            if value == .captures { store.tab = .review }
            if value != .today { store.stopCompletionInvitation() }
            processPendingEntries()
        }
        .onChange(of: store.speech.voiceIdentifier) { store.saveVoicePreference() }
        .onChange(of: store.readAloud) { store.executionPreferencesChanged() }
        .onChange(of: store.automatic) { store.executionPreferencesChanged() }
        .onChange(of: store.speech.state) { store.handleSpeechInterruption() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--ui-testing") { testObservedBackground = true }
                #endif
                store.discardCompletionReflection()
                store.cancelVoiceCommandTurn()
                if store.session?.status == .running { store.pause() }
            } else if phase == .active {
                #if DEBUG
                let args = ProcessInfo.processInfo.arguments
                if testObservedBackground, args.contains("--ui-testing"), args.contains("--ui-testing-start-entry-on-return") {
                    testObservedBackground = false
                    MorningIntentRouter.shared.requestStart()
                }
                #endif
                Task { await store.invitation.reconcile(); processPendingEntries() }
                Task { await store.prepareDayIfConfigured() }
            }
        }
        .onChange(of: MorningIntentRouter.shared.pendingCaptureText, initial: true) { _, _ in
            presentPendingIntentCapture()
        }
        .onChange(of: MorningIntentRouter.shared.pendingStart, initial: true) { _, _ in processPendingEntries() }
        .onChange(of: entryIsOccupied) { _, occupied in
            if occupied { store.stopCompletionInvitation() }
            else { processPendingEntries() }
        }
        .onChange(of: observationReviewCanPresent) { _, ready in if ready { processPendingEntries() } }
        .onChange(of: store.busy) { _, busy in if !busy { processPendingEntries() } }
        .task {
            if store.privacyNeedsCleanup {
                showingSettings = true
                if store.privacyHasInterruptedRemoval { await store.forgetLocalData() }
                return
            }
            Task { await store.prepareDayIfConfigured() }
            await store.invitation.reconcile()
            #if DEBUG
            // Explicit isolated fixture entry tests exercise routing, not Siri or
            // notification delivery. They never request notification permission.
            let args = ProcessInfo.processInfo.arguments
            if args.contains("--ui-testing"), args.contains("--ui-testing-start-entry") {
                MorningIntentRouter.shared.requestStart()
            }
            #endif
            processPendingEntries()
        }
    }

    private func openRoutineReview() {
        store.tab = .review
        showingRoutineEditor = true
    }

    private func presentPendingIntentCapture() {
        guard !store.privacyBlocksWork, scenePhase == .active, !presentingIntentCapture, !store.capturePresented, !store.captureVoicePresented, !store.hasPendingSpokenCapture,
              !store.voiceInputBlocksPlayback, !showingSettings,
              !showingLearn, !showingRoutineEditor, !store.voiceCommandPresented,
              !store.observationDetailPresented, !store.observationSelectionPresented, !store.routineProposalPresented,
              let text = MorningIntentRouter.shared.pendingCaptureText else { return }
        presentingIntentCapture = true
        store.openCapture(text: text, source: .siri)
    }

    private func captureReviewDismissed() {
        store.capturePrefill = ""
        store.captureSource = .typed
        if presentingIntentCapture {
            MorningIntentRouter.shared.finishCaptureReview()
            presentingIntentCapture = false
        }
        processPendingEntries()
    }

    private func requestObservationReview() {
        pendingObservationReview = true
        processPendingEntries()
    }

    private func presentPendingObservationReview() {
        guard pendingObservationReview, observationReviewCanPresent else { return }
        // Learn may already be visible because the person opened the saved recording.
        // Consume the request once; don't reopen it after they dismiss it.
        pendingObservationReview = false
        store.tab = .review
        showingLearn = true
    }

    /// Unlike start-entry occupancy, a saved raw recording must not block its own
    /// review. Watch this eligibility separately so closing another detail or
    /// ending a session resumes review even when a failed recording stays pending.
    private var observationReviewCanPresent: Bool {
        guard !store.privacyBlocksWork, scenePhase == .active, !store.busy, !store.sessionActive,
              !showingSettings, !showingRoutineEditor, !presentingIntentCapture,
              !store.capturePresented, !store.voiceCommandPresented, !store.captureVoicePresented,
              !store.hasPendingSpokenCapture, !store.voiceInputBlocksPlayback,
              !store.morningDetailPresented, !store.observationDetailPresented,
              !store.observationSelectionPresented, !store.routineProposalPresented,
              !store.captureBusy, !store.calendarBusy else { return false }
        #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(ScreenCaptureKit)
        if #available(iOS 27.0, *), ScreenRecordingService.shared.isBusy { return false }
        #endif
        return true
    }

    private var entryIsOccupied: Bool {
        var recordingBusy = false
        #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(ScreenCaptureKit)
        if #available(iOS 27.0, *) { recordingBusy = ScreenRecordingService.shared.isBusy }
        #endif
        return store.privacyBlocksWork || showingSettings || showingLearn || showingRoutineEditor || presentingIntentCapture ||
            store.capturePresented || store.voiceCommandPresented || store.captureVoicePresented ||
            store.hasPendingSpokenCapture || store.morningDetailPresented || store.observationDetailPresented ||
            store.observationSelectionPresented || store.routineProposalPresented || store.voiceInputBlocksPlayback ||
            store.busy || store.captureBusy || store.calendarBusy || store.hasPendingRecording ||
            recordingBusy || store.invitation.isBusy
    }

    private var recordingCanProcess: Bool {
        !store.privacyBlocksWork && !showingSettings && !showingLearn && !showingRoutineEditor && !presentingIntentCapture &&
        !store.capturePresented && !store.voiceCommandPresented && !store.captureVoicePresented &&
        !store.hasPendingSpokenCapture && !store.voiceInputBlocksPlayback &&
        !store.morningDetailPresented && !store.observationDetailPresented &&
        !store.observationSelectionPresented && !store.routineProposalPresented &&
        !store.captureBusy && !store.calendarBusy
    }

    private func processPendingEntries() {
        guard !store.privacyBlocksWork else { return }
        // A thought already waiting for review keeps priority over a start request.
        presentPendingIntentCapture()
        presentPendingObservationReview()
        let router = MorningIntentRouter.shared
        guard let request = router.pendingStart else {
            if scenePhase == .active, !entryIsOccupied, store.tab == .today {
                store.speakQueuedCompletionInvitation()
            }
            return
        }
        var destination = MorningEntryPolicy.destination(for: request,
            context: .init(sceneIsActive: scenePhase == .active, isOccupied: entryIsOccupied,
                storageIsAvailable: store.storageIsAvailable, hasRoutine: store.routine != nil,
                routineIsApproved: store.routine?.isApproved == true, sessionStatus: store.session?.status),
            consumedIDs: store.consumedMorningEntryIDs)
        let waitingNotice = "Your morning is waiting. Finish what you're doing here, then MORE can begin."
        guard destination != .wait else {
            if scenePhase == .active, store.notice == nil { store.notice = waitingNotice }
            return
        }
        if store.notice == waitingNotice { store.notice = nil }
        if Date.now >= request.expiresAt {
            store.notice = "Your morning is ready when you are. Tap Start to begin."
        }
        if let payload = router.invitationPayload {
            do {
                if try store.invitation.consume(payload) == nil { destination = .revealMorning }
            } catch {
                destination = .revealMorning
                store.notice = "Your invitation couldn't be saved. Start your morning when you're ready."
            }
        }
        // Acknowledge before navigation changes trigger another view update. The
        // synchronous store transition saves its receipt before executing a step.
        router.finishStart(request.id)
        guard store.handleMorningEntry(request, destination: destination) else {
            store.tab = .today
            return
        }
        switch destination {
        case .reviewDraft: openRoutineReview()
        case .learn: store.tab = .review; showingLearn = true
        default: store.tab = .today
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
            .background(MorningStyle.background).navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("Done") { showingSettings = false; showingLearn = false }
                    .disabled(store.privacyBlocksWork)
            } }
        }.presentationDragIndicator(.visible)
            .interactiveDismissDisabled(store.privacyBlocksWork)
    }
}

/// The everyday surface has no editing and no scrolling at ordinary phone text sizes.
/// Larger accessibility text and short landscape windows get a scroll fallback rather
/// than clipped controls or shrunken type. Review retains the complete routine.
struct TodayView: View {
    @Bindable var store: MorningStore
    var showLearn: () -> Void
    var reviewObservation: () -> Void
    var showReview: () -> Void
    var editRoutine: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicType
    @ViewState<Bool> private var showingNotice = false
    @ViewState<Bool> private var learnAfterNoticeDismissal = false
    @ViewState<RoutineStep?> private var viewingStep = nil
    private var terminal: Bool { store.session?.status == .completed || store.session?.status == .stopped }

    var body: some View {
        GeometryReader { geometry in
            Group {
                if dynamicType.isAccessibilitySize || geometry.size.height < 470 {
                    ScrollView { page(compact: true).padding(.vertical, 12) }
                        .accessibilityIdentifier("morning.accessibleScroll")
                } else {
                    ViewThatFits(in: .vertical) {
                        page(compact: false)
                        page(compact: true)
                        ScrollView { page(compact: true) }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 10).padding(.bottom, 12)
            .frame(maxWidth: 600).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(MorningStyle.background)
        .onChange(of: viewingStep != nil || showingNotice, initial: true) { _, presented in
            store.morningDetailPresented = presented
        }
        .sheet(item: $viewingStep) { step in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(step.title).font(.title2.weight(.semibold))
                        if let briefing = store.preparedBriefing(for: step) {
                            MorningBriefingDocumentView(document: briefing, operation: step.automation, synthetic: store.usesSyntheticBriefing)
                        } else {
                            Text(step.detail).textSelection(.enabled)
                                .accessibilityIdentifier("run.detail")
                        }
                        if store.session?.status == .paused,
                           step.automation == .morningBriefing || step.automation == .todayCalendar {
                            Button("Update this recap") { store.updateCurrentBriefing() }
                                .buttonStyle(.glass).accessibilityIdentifier("briefing.updateCurrent")
                        }
                        if store.session?.status == .paused {
                            Text("Your morning is paused.").font(.caption).foregroundStyle(.secondary)
                                .accessibilityIdentifier("run.detailPaused")
                        }
                        Text("\(step.durationMinutes) minutes planned").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
                }.navigationTitle("This moment").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { viewingStep = nil } } }
            }.presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingNotice, onDismiss: {
            guard learnAfterNoticeDismissal else { return }
            learnAfterNoticeDismissal = false
            reviewObservation()
        }) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let notice = store.notice { Text(notice).textSelection(.enabled) }
                        #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(ScreenCaptureKit)
                        if #available(iOS 27.0, *) {
                            MorningRecordingStatus(store: store, onReview: reviewAfterNotice)
                        } else { savedObservationReview }
                        #else
                        savedObservationReview
                        #endif
                    }.padding(24)
                }.navigationTitle("Your morning").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingNotice = false } } }
            }.presentationDetents([.medium, .large])
        }
    }

    private func reviewAfterNotice() {
        learnAfterNoticeDismissal = true
        showingNotice = false
    }

    /// Reviewing an imported file does not require the native recording framework.
    @ViewBuilder private var savedObservationReview: some View {
        if store.hasImportedObservation {
            Button(action: reviewAfterNotice) {
                Label("Review your saved observation", systemImage: "text.viewfinder")
                    .font(.caption.weight(.medium))
            }.buttonStyle(.glass).padding(8).accessibilityIdentifier("observation.review")
        }
    }

    private func page(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 18) {
            dateHeader
            if let routine = store.routine {
                if !store.sessionActive { routineHeading(routine, compact: compact) }
                if store.sessionActive { nowPlaying(compact: compact) }
                if terminal { closingMoment }
                compactTimeline(routine, compact: compact)
                Spacer(minLength: compact ? 4 : 8)
                if routine.sourceLabel.localizedCaseInsensitiveContains("demo fixture") {
                    Text("Sample morning · not your observed activity")
                        .font(.caption2).foregroundStyle(.secondary).accessibilityIdentifier("routine.source")
                }
                actionArea(routine)
            } else {
                Spacer(minLength: 12)
                welcome
                Spacer(minLength: 16)
                Button(action: showLearn) {
                    Label("Learn my morning", systemImage: "record.circle")
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                }.buttonStyle(.glassProminent).tint(MorningStyle.controlTint).controlSize(.large)
                    .accessibilityIdentifier("learn.begin")
                Button("See how it feels") { store.loadSample() }
                    .font(.subheadline).frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("routine.sample")
            }
        }
    }

    private var dateHeader: some View {
        HStack {
            Button(action: showReview) {
                HStack(spacing: 8) {
                    Text(Date.now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                        .font(.subheadline.weight(.medium))
                    Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                }.foregroundStyle(.primary).frame(minHeight: 44)
            }.buttonStyle(.plain).accessibilityIdentifier("morning.date")
                .accessibilityHint("Review this week and previous mornings")
            Spacer()
            #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(ScreenCaptureKit)
            if #available(iOS 27.0, *), ScreenRecordingService.shared.captureMayBeActive {
                Button { showingNotice = true } label: {
                    Label("Recording", systemImage: "record.circle.fill").font(.caption.weight(.medium)).foregroundStyle(.red)
                }.buttonStyle(.glass).accessibilityIdentifier("morning.recording")
            }
            #endif
            if store.busy {
                Button { showingNotice = true } label: { ProgressView().controlSize(.small) }
                    .accessibilityLabel("Understanding your morning. View progress")
            } else if store.notice != nil || store.observationIssue != nil || store.hasPendingRecording {
                Button { showingNotice = true } label: { Image(systemName: "exclamationmark.circle").frame(width: 44, height: 44) }
                    .buttonStyle(.plain).accessibilityLabel("Your morning needs attention")
                    .accessibilityIdentifier("morning.attention")
            }
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: "sun.horizon")
                .font(.system(size: 56, weight: .ultraLight))
                .foregroundStyle(MorningStyle.accent)
                .frame(width: 104, height: 104)
                .background(MorningStyle.lavender.opacity(0.55), in: Circle())
                .accessibilityHidden(true)
            Text("A little more\nmorning.")
                .font(.system(size: 40, weight: .medium, design: .serif)).tracking(-1)
                .fixedSize(horizontal: false, vertical: true)
            Text("Show MORE a little of your morning.\nWe’ll find the rhythm together.")
                .font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func routineHeading(_ routine: RoutineVersion, compact: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(terminal ? "More room for your day." : "Good morning.")
                    .font(.system(size: compact ? 27 : 32, weight: .medium, design: .serif)).tracking(-0.5)
                if !routine.isApproved {
                    Text("Your first draft is ready to review.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if !terminal {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(routine.totalDurationMinutes) min").font(.title3.weight(.medium)).monospacedDigit()
                    Text("planned").font(.caption2).foregroundStyle(.secondary)
                }.accessibilityElement(children: .combine)
            }
        }.padding(.bottom, compact ? 0 : 4)
    }

    private func compactTimeline(_ routine: RoutineVersion, compact: Bool) -> some View {
        let dense = compact || routine.steps.count > 6 || store.sessionActive || terminal
        return VStack(spacing: dense ? 4 : 8) {
            ForEach(Array(routine.steps.prefix(10).enumerated()), id: \.element.id) { index, step in
                let complete = store.session?.completedStepIDs.contains(step.id) == true
                let skipped = store.session?.skippedStepIDs.contains(step.id) == true
                let current = store.sessionActive && store.currentStep?.id == step.id
                HStack(spacing: 12) {
                    Image(systemName: complete ? "checkmark" : skipped ? "forward.end" : MorningStyle.symbol(for: step.kind))
                        .font(.system(size: dense ? 14 : 17, weight: .medium))
                        .foregroundStyle(MorningStyle.accent).frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(step.title).font(dense ? .subheadline.weight(.medium) : .headline)
                            .lineLimit(dynamicType.isAccessibilitySize ? nil : 1)
                        if !dense {
                            Text(step.detail.components(separatedBy: "\nEvidence:")[0])
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                    Text(complete ? "Done" : skipped ? "Skipped" : "\(step.durationMinutes)m")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14).padding(.vertical, dense ? (store.sessionActive ? 8 : 11) : 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MorningStyle.color(for: step.kind).opacity(complete || skipped ? 0.22 : 0.55),
                            in: RoundedRectangle(cornerRadius: dense ? 14 : 19))
                .overlay(RoundedRectangle(cornerRadius: dense ? 14 : 19).strokeBorder(current ? MorningStyle.accent.opacity(0.7) : .clear))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(index + 1). \(step.title), \(step.durationMinutes) minutes planned\(complete ? ", completed" : skipped ? ", skipped" : "")")
                .accessibilityIdentifier("morning.step.\(index)")
            }
            if routine.steps.count > 10 {
                Button("See all \(routine.steps.count) moments in Review", action: editRoutine)
                    .font(.caption).frame(minHeight: 44)
            }
        }
    }

    private func nowPlaying(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(store.session?.status == .paused ? "Paused" : "Now", systemImage: store.session?.status == .paused ? "pause.fill" : "waveform")
                    .font(.caption.weight(.medium)).foregroundStyle(MorningStyle.accent)
                Spacer()
                Text(store.stateLabel).font(.caption2).foregroundStyle(.secondary)
                    .accessibilityIdentifier("run.state").accessibilityValue(store.stateLabel)
            }
            Text(store.currentStep?.title ?? "Your morning")
                .font(.headline).accessibilityIdentifier("run.step")
            if store.automatic, !store.automation.message.isEmpty {
                Text(store.automation.message).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(dynamicType.isAccessibilitySize ? nil : compact ? 2 : 3)
            } else {
                Text(store.session?.status == .paused ? "Continue when you’re ready." : "At your own pace.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(MorningStyle.lavender.opacity(0.45), in: RoundedRectangle(cornerRadius: 20))
    }

    private var closingMoment: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.session?.status == .completed
                 ? (store.shouldOfferCompletionReflection ? "Anything you’d like to remember?" : "Morning complete.")
                 : "Pick it up when you’re ready.")
                .font(.headline).accessibilityIdentifier("run.step")
            Text(store.stateLabel).font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("run.state").accessibilityValue(store.stateLabel)
            if store.shouldOfferCompletionReflection {
                if dynamicType.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 14) { reflectionButtons }
                } else { HStack(spacing: 18) { reflectionButtons } }
            }
        }.padding(.vertical, 4)
    }

    @ViewBuilder private var reflectionButtons: some View {
        Button("Speak", systemImage: "mic") { store.openCompletionCapture() }
            .buttonStyle(.glassProminent).tint(MorningStyle.controlTint)
            .disabled(store.voiceInputBlocksPlayback).accessibilityIdentifier("morning.speakReflection")
        Button("Write", systemImage: "square.and.pencil") { store.openCapture() }
            .buttonStyle(.borderless).accessibilityIdentifier("morning.reflect")
        Button("Not now") { store.discardCompletionReflection() }
            .buttonStyle(.borderless).accessibilityIdentifier("morning.dismissReflection")
    }

    @ViewBuilder private func actionArea(_ routine: RoutineVersion) -> some View {
        if store.sessionActive {
            HStack(spacing: 12) {
                if store.session?.status == .paused {
                    Button { store.resume() } label: { Label("Continue", systemImage: "play.fill").frame(maxWidth: .infinity).padding(.vertical, 9) }
                        .buttonStyle(.glassProminent).tint(MorningStyle.controlTint).accessibilityIdentifier("run.resume")
                        .disabled(store.voiceInputBlocksPlayback)
                } else {
                    Button { store.pause() } label: { Label("Pause", systemImage: "pause.fill").frame(maxWidth: .infinity).padding(.vertical, 9) }
                        .buttonStyle(.glassProminent).tint(MorningStyle.controlTint).accessibilityIdentifier("run.pause")
                    if !store.automatic || [.waitingForUser, .unavailable, .failed].contains(store.automation.status) {
                        Button { store.advance() } label: { Image(systemName: "arrow.right").frame(width: 32, height: 32) }
                            .buttonStyle(.glass).accessibilityLabel("Next moment").accessibilityIdentifier("run.next")
                    }
                }
                Menu {
                    Button("End morning", systemImage: "stop") { store.stop() }.accessibilityIdentifier("run.stop")
                    Button("Speak a command", systemImage: "mic") { store.openVoiceCommands() }
                        .accessibilityIdentifier("run.speakCommand")
                    Button("About this moment") { viewingStep = store.currentStep }
                        .accessibilityIdentifier("run.about")
                    Toggle("Hands free", isOn: $store.automatic)
                    Button("Next moment") { store.advance() }.disabled(store.session?.status != .running)
                    Button("Skip this moment") { store.advance(skipping: true) }.disabled(store.session?.status != .running)
                    Button("Read aloud") { store.readCurrent() }.disabled(store.voiceInputBlocksPlayback)
                    Button("Save a thought") { store.openCapture() }
                } label: { Image(systemName: "ellipsis").frame(width: 32, height: 32) }
                    .buttonStyle(.glass).accessibilityLabel("Morning controls").accessibilityIdentifier("run.controls")
            }.controlSize(.large)
        } else {
            Button {
                if routine.isApproved { store.start() } else { editRoutine() }
            } label: {
                Label(routine.isApproved ? "Start my morning" : "Review my morning", systemImage: routine.isApproved ? "play.fill" : "arrow.right")
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
            }.buttonStyle(.glassProminent).tint(MorningStyle.controlTint).controlSize(.large).disabled(store.busy)
                .accessibilityIdentifier(routine.isApproved ? "run.start" : "morning.reviewDraft")
            Button("Update my morning", action: editRoutine)
                .font(.subheadline).frame(maxWidth: .infinity, minHeight: 36)
                .accessibilityIdentifier("morning.update")
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
