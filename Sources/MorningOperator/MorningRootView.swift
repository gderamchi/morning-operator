import SwiftUI
import UniformTypeIdentifiers
import MorningCore
import MorningApple

struct MorningRootView: View {
    @Bindable var store: MorningStore
    @ViewState<Bool> private var showingSettings = false
    @ViewState<Bool> private var showingInvitation = false
    @ViewState<Bool> private var showingLearn = false
    @ViewState<Bool> private var showingRoutineEditor = false
    @ViewState<UUID> private var reviewRootIdentity = UUID()
    @ViewState<Bool> private var resetReviewAfterSettingsDismissal = false
    @ViewState<Bool> private var presentingIntentCapture = false
    @ViewState<Bool> private var pendingObservationReview = false
    @ViewState<Bool> private var testObservedBackground = false
    @ViewState<Bool> private var showingActions = false
    @ViewState<Bool> private var actionTransitionPending = false
    @Environment(\.scenePhase) private var scenePhase

    private var presentedContent: some View {
        TabView(selection: $store.tab) {
            NavigationStack {
                TodayView(store: store, showLearn: { showingLearn = true },
                          reviewObservation: requestObservationReview,
                          showReview: { reviewRootIdentity = UUID(); store.tab = .review }, editRoutine: openRoutineReview,
                          showInvitation: openMorningInvitation, canEditInvitation: !entryIsOccupied)
                    .padding(.bottom, 60)
                    .background(MorningStyle.background)
                    .toolbar(.hidden, for: .navigationBar)
                    .accessibilityHidden(showingActions)
            }
            .toolbar(.hidden, for: .tabBar)
            .tabItem { Label("Morning", systemImage: "sun.horizon") }.tag(MorningTab.today)
            NavigationStack {
                WeeklyReviewView(store: store, onLearn: { showingLearn = true },
                                 onSettings: {
                                     if store.voiceInputBlocksPlayback { store.voiceCommandPresented = true }
                                     else { showingSettings = true }
                                 }, showingRoutineEditor: $showingRoutineEditor)
                    .background(MorningStyle.background)
                    .toolbar { ToolbarItem(placement: .topBarLeading) {
                        Button { store.tab = .today } label: { Image(systemName: "sun.horizon") }
                            .accessibilityLabel("Back to morning").accessibilityIdentifier("morning.home")
                    } }
            }
            .id(reviewRootIdentity)
            .toolbar(.hidden, for: .tabBar)
            .tabItem { Label("Review", systemImage: "circle.grid.2x2") }.tag(MorningTab.review)
        }
        #if os(iOS)
        .toolbar(.hidden, for: .tabBar)
        #endif
        .overlay(alignment: .bottomTrailing) {
            if store.tab == .today {
                GeometryReader { geometry in
                    MorningActionDock(store: store, expanded: $showingActions,
                    transitionPending: $actionTransitionPending, availableHeight: geometry.size.height,
                    edit: openRoutineReview,
                    learn: { showingLearn = true },
                    review: { reviewRootIdentity = UUID(); store.tab = .review },
                    settings: {
                        if store.voiceInputBlocksPlayback { store.voiceCommandPresented = true }
                        else { showingSettings = true }
                    })
                    .padding(.horizontal, 20).padding(.bottom, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
        }
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
        .sheet(isPresented: $showingInvitation, onDismiss: processPendingEntries) {
            MorningInvitationView(service: store.invitation)
                .interactiveDismissDisabled(store.privacyBlocksWork)
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

    private var workspaceContent: some View {
        presentedContent
        .onChange(of: store.dataGeneration) { _, _ in
            showingActions = false
            actionTransitionPending = false
            showingLearn = false; showingRoutineEditor = false; showingInvitation = false
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
            showingInvitation = false
            store.tab = .today
        }
        .onChange(of: store.completionInvitationSessionID) { _, _ in processPendingEntries() }
        .onChange(of: store.session?.id) { _, _ in store.completionSessionChanged() }
        .onChange(of: showingRoutineEditor) { _, showing in if !showing { processPendingEntries() } }
        .onChange(of: showingInvitation) { _, showing in if !showing { processPendingEntries() } }
        .onChange(of: store.tab) { _, value in
            showingActions = false
            if value == .learn { store.tab = .review; showingLearn = true }
            if value == .setup { store.tab = .review; showingSettings = true }
            if value == .captures { store.tab = .review }
            if value != .today { store.stopCompletionInvitation() }
            processPendingEntries()
        }
        .onChange(of: store.speech.voiceIdentifier) { store.saveVoicePreference() }
        .onChange(of: store.readAloud) { store.executionPreferencesChanged() }
        .onChange(of: store.automatic) { store.executionPreferencesChanged() }
    }

    var body: some View {
        workspaceContent
        .onChange(of: store.speech.state) { store.handleSpeechInterruption() }
        .onChange(of: store.automation.status) { store.synchronizeMorningActivity() }
        .onChange(of: scenePhase) { _, phase in
            store.morningActivitySceneChanged(isForeground: phase == .active)
            if phase == .background {
                showingActions = false
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
        .onOpenURL { url in
            guard url.scheme == "more", url.host == "morning", url.path.isEmpty,
                  url.query == nil, url.fragment == nil, !store.privacyBlocksWork else { return }
            // Revealing progress is not a request to start or resume. Keep any
            // unfinished review sheet intact rather than discarding the draft.
            store.tab = .today
        }
        .task { await initializeMorning() }
    }

    private func initializeMorning() async {
        store.morningActivitySceneChanged(isForeground: scenePhase == .active)
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

    private func openMorningInvitation() {
        guard scenePhase == .active, !entryIsOccupied, store.storageIsAvailable else { return }
        showingInvitation = true
    }

    private func openRoutineReview() {
        store.tab = .review
        showingRoutineEditor = true
    }

    private func presentPendingIntentCapture() {
        guard !store.privacyBlocksWork, scenePhase == .active, !presentingIntentCapture, !store.capturePresented, !store.captureVoicePresented, !store.hasPendingSpokenCapture,
              !store.voiceInputBlocksPlayback, !showingSettings, !showingInvitation, !showingActions, !actionTransitionPending,
              !store.morningDetailPresented,
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
              !showingSettings, !showingInvitation, !showingActions, !actionTransitionPending, !showingRoutineEditor, !presentingIntentCapture,
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
        return store.privacyBlocksWork || showingActions || actionTransitionPending || showingSettings || showingInvitation || showingLearn || showingRoutineEditor || presentingIntentCapture ||
            store.capturePresented || store.voiceCommandPresented || store.captureVoicePresented ||
            store.hasPendingSpokenCapture || store.morningDetailPresented || store.observationDetailPresented ||
            store.observationSelectionPresented || store.routineProposalPresented || store.voiceInputBlocksPlayback ||
            store.busy || store.captureBusy || store.calendarBusy || store.hasPendingRecording ||
            recordingBusy || store.invitation.isBusy
    }

    private var recordingCanProcess: Bool {
        !store.privacyBlocksWork && !showingActions && !actionTransitionPending && !showingSettings && !showingInvitation && !showingLearn && !showingRoutineEditor && !presentingIntentCapture &&
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

/// A quiet, movable morning with no scrolling at ordinary phone text sizes.
/// Larger accessibility text and short landscape windows get a scroll fallback rather
/// than clipped controls or shrunken type. Review retains the complete routine.
struct TodayView: View {
    @Bindable var store: MorningStore
    var showLearn: () -> Void
    var reviewObservation: () -> Void
    var showReview: () -> Void
    var editRoutine: () -> Void
    var showInvitation: () -> Void
    var canEditInvitation: Bool
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
            .padding(.top, 0).padding(.bottom, 8)
            .frame(maxWidth: 600).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(MorningLightBackdrop())
        .onChange(of: store.routine?.id) { _, _ in viewingStep = nil }
        .onChange(of: store.dataGeneration) { _, _ in viewingStep = nil; showingNotice = false }
        .onChange(of: viewingStep != nil || showingNotice, initial: true) { _, presented in
            store.morningDetailPresented = presented
        }
        .sheet(item: $viewingStep) { selection in
            NavigationStack {
                if let step = store.routine?.steps.first(where: { $0.id == selection.id }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(step.title).font(.title3.weight(.semibold))
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Goal").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                            Text(goal(for: step)).font(.subheadline)
                        }
                        if let briefing = store.preparedBriefing(for: step) {
                            MorningBriefingDocumentView(document: briefing, operation: step.automation, synthetic: store.usesSyntheticBriefing)
                        } else {
                            Text(step.detail).textSelection(.enabled)
                                .accessibilityIdentifier("run.detail")
                        }
                        if store.session?.status == .paused,
                           store.currentStep?.id == step.id,
                           step.automation == .morningBriefing || step.automation == .todayCalendar {
                            Button("Update this recap") { store.updateCurrentBriefing() }
                                .buttonStyle(.glass).accessibilityIdentifier("briefing.updateCurrent")
                        }
                        if store.session?.status == .paused {
                            Text("Your morning is paused.").font(.caption).foregroundStyle(.secondary)
                                .accessibilityIdentifier("run.detailPaused")
                        }
                        Text("\(step.durationMinutes) min").font(.caption).foregroundStyle(.secondary)
                            .accessibilityLabel("\(step.durationMinutes) minutes planned")
                        if store.sessionActive, store.currentStep?.id == step.id {
                            currentStepCommands
                        }
                        if canArrange, let routine = store.routine,
                           let index = routine.steps.firstIndex(where: { $0.id == step.id }) {
                            let generation = store.dataGeneration
                            Divider().padding(.vertical, 4)
                            Text("Order").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                            HStack(spacing: 12) {
                                if index > 0 {
                                    Button("Move earlier", systemImage: "arrow.up") {
                                        store.moveStep(step.id, onto: routine.steps[index - 1].id,
                                            expectedRoutineID: routine.id, expectedGeneration: generation)
                                    }.accessibilityIdentifier("morning.moveEarlier")
                                }
                                if index + 1 < routine.steps.count {
                                    Button("Move later", systemImage: "arrow.down") {
                                        store.moveStep(step.id, onto: routine.steps[index + 1].id,
                                            expectedRoutineID: routine.id, expectedGeneration: generation)
                                    }.accessibilityIdentifier("morning.moveLater")
                                }
                            }.buttonStyle(.glass).controlSize(.regular)
                            Text("A changed order becomes a draft for you to review.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
                }.navigationTitle("This moment").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { viewingStep = nil } } }
                }
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
                        } else { storedObservationStatus }
                        #else
                        storedObservationStatus
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

    @ViewBuilder private var storedObservationStatus: some View {
        if store.hasPendingRecording {
            SavedRecordingRecoveryView(store: store, onReview: reviewAfterNotice)
        } else { savedObservationReview }
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
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            dateHeader
            if let routine = store.routine {
                if !store.sessionActive { routineHeading(routine, compact: compact) }
                if store.sessionActive { nowPlaying(compact: compact) }
                if store.session?.status == .completed { closingMoment }
                compactTimeline(routine, compact: compact)
                if routine.isSynthetic {
                    Text("Sample morning").font(.caption2).foregroundStyle(.secondary)
                        .padding(.horizontal, 4).accessibilityIdentifier("routine.source")
                        .accessibilityLabel("Sample morning, not your observed activity")
                }
                Spacer(minLength: 4)
                if store.sessionActive { actionArea(routine) }
            } else {
                Spacer(minLength: 12)
                welcome
                HStack(spacing: 12) {
                    Button(action: showLearn) {
                        Label("Learn my morning", systemImage: "record.circle")
                            .padding(.horizontal, 8).padding(.vertical, 8)
                    }.buttonStyle(.glass).accessibilityIdentifier("learn.begin")
                    Button("Try a sample") { store.loadSample() }
                        .font(.subheadline).frame(minHeight: 44)
                        .accessibilityIdentifier("routine.sample")
                }.padding(.top, 14)
                Spacer(minLength: 24)
            }
        }
    }

    private var dateHeader: some View {
        HStack {
            Button(action: showReview) {
                HStack(spacing: 8) {
                    Text(Date.now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                        .font(.caption.weight(.medium))
                    Image(systemName: "chevron.down").font(.caption2.weight(.regular))
                }.foregroundStyle(.primary).frame(minHeight: 44)
            }.buttonStyle(.plain).accessibilityIdentifier("morning.date")
                .accessibilityHint("Review this week and previous mornings")
            Spacer()
            #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(ScreenCaptureKit)
            if #available(iOS 27.0, *), ScreenRecordingService.shared.captureMayBeActive {
                Button { showingNotice = true } label: {
                    Label("MORE · Recording", systemImage: "record.circle.fill").font(.caption.weight(.medium)).foregroundStyle(.red)
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
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "sun.horizon")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(.primary.opacity(0.75)).accessibilityHidden(true)
            Text("Your morning")
                .font(.title2.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text("Show us a little of your morning.\nWe’ll find the rhythm together.")
                .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func routineHeading(_ routine: RoutineVersion, compact: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("morning").font(.title3.weight(.semibold))
                .accessibilityIdentifier("morning.heading")
                .accessibilityValue(store.session?.status == .stopped ? "stopped" : "")
            morningInvitationButton
            if !routine.isApproved {
                Text("Draft").font(.caption2).foregroundStyle(.secondary)
                    .accessibilityIdentifier("morning.draft")
                    .accessibilityLabel("Draft, review before starting")
            }
            Spacer(minLength: 8)
            Text("\(routine.totalDurationMinutes) min").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .accessibilityLabel("\(routine.totalDurationMinutes) minutes planned")
        }.padding(.bottom, 2)
    }

    private var morningInvitationButton: some View {
        // A saved preference or the editor's suggested time is not a registered
        // invitation. Only show the future instant confirmed by the service.
        let scheduled = store.invitation.isScheduled && store.invitation.invitation?.disposition == .enabled
            ? store.invitation.invitation?.scheduledAt : nil
        return TimelineView(.everyMinute) { context in
            let upcoming = scheduled.flatMap { $0 > context.date ? $0 : nil }
            Button(action: showInvitation) {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                    if let upcoming {
                        Text(upcoming.formatted(date: .omitted, time: .shortened)).monospacedDigit()
                    }
                }.font(.caption2).foregroundStyle(.secondary).frame(minWidth: 44, minHeight: 44)
            }.buttonStyle(.plain)
                .accessibilityLabel(upcoming == nil ? "Set morning invitation" : "Edit morning invitation")
                .accessibilityValue(upcoming?.formatted(date: .complete, time: .shortened) ?? "No upcoming invitation")
                .accessibilityIdentifier("morning.invitation")
                .disabled(!canEditInvitation || !store.storageIsAvailable)
        }
    }

    private func goal(for step: RoutineStep) -> String {
        switch step.automation {
        case .spokenNote: "Hear the text you approved for this moment."
        case .todayCalendar: "Review today’s available calendar events."
        case .morningBriefing: "Review the available calendar and weather recap."
        case .savedObservation: "Hear the saved observation you selected."
        case nil: step.kind == .messages ? "Catch up on messages in their app." : "Follow your saved plan for this moment."
        }
    }

    private var currentStepCommands: some View {
        let layout = dynamicType.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            if store.session?.status == .paused {
                Button("Continue", systemImage: "play.fill") { store.resume() }
                    .accessibilityIdentifier("run.detailResume")
            } else {
                Button("Pause", systemImage: "pause.fill") { store.pause() }
                    .accessibilityIdentifier("run.detailPause")
                Button("Next", systemImage: "arrow.right") {
                    viewingStep = nil
                    store.advance()
                }.accessibilityIdentifier("run.detailNext")
            }
            Button("Again", systemImage: "arrow.counterclockwise") { store.readCurrent() }
                .accessibilityIdentifier("run.detailAgain")
        }.buttonStyle(.glass).controlSize(.small)
            .disabled(store.privacyBlocksWork || store.voiceInputBlocksPlayback)
    }

    private var canArrange: Bool {
        !store.sessionActive && !store.busy && !store.privacyBlocksWork && store.storageIsAvailable
    }

    private func compactTimeline(_ routine: RoutineVersion, compact: Bool) -> some View {
        let generation = store.dataGeneration
        let dense = compact || routine.steps.count > 6 || store.sessionActive || terminal
        let spacing: CGFloat = store.sessionActive && compact ? 4 : 7
        return GlassEffectContainer(spacing: 4) {
            VStack(spacing: spacing) {
                if #available(iOS 27.0, macOS 27.0, *) {
                    VStack(spacing: spacing) {
                        ForEach(Array(routine.steps.prefix(10))) { step in
                            momentTile(step, routine: routine, generation: generation, dense: dense)
                        }.reorderable()
                    }
                    .reorderContainer(for: RoutineStep.self, isEnabled: canArrange) { difference in
                        guard store.routine == routine, store.dataGeneration == generation else { return }
                        let selected = Set(difference.sources)
                        guard !selected.isEmpty, selected.count == difference.sources.count,
                              selected.isSubset(of: Set(routine.steps.map(\.id))) else { return }
                        let moving = routine.steps.map(\.id).filter { selected.contains($0) }
                        var remaining = routine.steps.map(\.id).filter { !selected.contains($0) }
                        switch difference.destination.position {
                        case .before(let target):
                            guard let index = remaining.firstIndex(of: target) else { return }
                            remaining.insert(contentsOf: moving, at: index)
                        case .end:
                            // The compact surface shows ten. End means after the
                            // last visible moment, never after hidden moments.
                            let visible = Set(routine.steps.prefix(10).map(\.id))
                            let index = remaining.firstIndex(where: { !visible.contains($0) }) ?? remaining.endIndex
                            remaining.insert(contentsOf: moving, at: index)
                        }
                        store.reorderSteps(remaining, expectedRoutineID: routine.id, expectedGeneration: generation)
                    }
                } else {
                    ForEach(Array(routine.steps.prefix(10))) { step in
                        momentTile(step, routine: routine, generation: generation, dense: dense)
                    }
                }
                if routine.steps.count > 10 {
                    Button("See all \(routine.steps.count) moments", action: editRoutine)
                        .font(.caption).frame(minHeight: 44)
                }
            }
        }
        .id("\(routine.id)-\(generation)-\(canArrange)")
    }

    private func momentTile(_ step: RoutineStep, routine: RoutineVersion, generation: UUID, dense: Bool) -> some View {
        let index = routine.steps.firstIndex(where: { $0.id == step.id }) ?? 0
        let complete = store.session?.completedStepIDs.contains(step.id) == true
        let skipped = store.session?.skippedStepIDs.contains(step.id) == true
        let current = store.sessionActive && store.currentStep?.id == step.id
        let plannedOffset = routine.steps.prefix(index).reduce(0) { $0 + $1.durationMinutes }
        return Button { viewingStep = step } label: {
            HStack(spacing: 13) {
                Image(systemName: complete ? "checkmark" : skipped ? "forward.end" : MorningStyle.symbol(for: step.kind))
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.primary.opacity(complete || skipped ? 0.4 : 0.72)).frame(width: 25)
                Text(step.title).font(.subheadline.weight(.medium))
                    .lineLimit(dynamicType.isAccessibilitySize ? nil : 1)
                Spacer(minLength: 4)
                Text(complete ? "Done" : skipped ? "Skipped" : "+\(plannedOffset)m")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: dense ? 20 : 24))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: dense ? 20 : 24))
        .overlay(RoundedRectangle(cornerRadius: dense ? 20 : 24).strokeBorder(current ? Color.primary.opacity(0.35) : .clear))
        .accessibilityLabel("\(index + 1). \(step.title), \(step.durationMinutes) minutes planned, planned start \(plannedOffset) minutes after Start\(complete ? ", completed" : skipped ? ", skipped" : "")")
        .accessibilityHint(canArrange ? "Opens details. Hold to move this moment." : "Opens details")
        .accessibilityIdentifier("morning.step.\(index)")
        .accessibilityActions {
            if canArrange {
                if index > 0 {
                    Button("Move earlier") {
                        store.moveStep(step.id, onto: routine.steps[index - 1].id, expectedRoutineID: routine.id, expectedGeneration: generation)
                    }
                }
                if index + 1 < routine.steps.count {
                    Button("Move later") {
                        store.moveStep(step.id, onto: routine.steps[index + 1].id, expectedRoutineID: routine.id, expectedGeneration: generation)
                    }
                }
            }
        }
    }

    private func nowPlaying(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: store.session?.status == .paused ? "pause.fill" : "waveform")
                        .accessibilityHidden(true)
                    Text(store.session?.status == .paused ? "Paused" : "Now")
                        .accessibilityIdentifier("run.state").accessibilityValue(store.stateLabel)
                }.font(.caption.weight(.medium)).foregroundStyle(MorningStyle.accent)
                Spacer()
            }
            Text(store.currentStep?.title ?? "Your morning")
                .font(.headline).accessibilityIdentifier("run.step")
            if compact {
                EmptyView()
            } else if store.automatic, !store.automation.message.isEmpty {
                Text(store.automation.message).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(dynamicType.isAccessibilitySize ? nil : compact ? 2 : 3)
            }
        }.padding(compact ? 11 : 14).frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 20))
    }

    private var closingMoment: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.shouldOfferCompletionReflection ? "Save a thought?" : "Morning complete.")
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
                        .buttonStyle(.glass).accessibilityIdentifier("run.resume")
                        .disabled(store.voiceInputBlocksPlayback)
                } else {
                    Button { store.pause() } label: { Label("Pause", systemImage: "pause.fill").frame(maxWidth: .infinity).padding(.vertical, 9) }
                        .buttonStyle(.glass).accessibilityIdentifier("run.pause")
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

/// A system popover keeps presentation ownership explicit while destinations open.
private struct MorningActionDock: View {
    @Bindable var store: MorningStore
    @Binding var expanded: Bool
    @Binding var transitionPending: Bool
    var availableHeight: CGFloat
    var edit: () -> Void
    var learn: () -> Void
    var review: () -> Void
    var settings: () -> Void
    @Namespace private var glassNamespace
    @ViewState<CGFloat> private var actionHeight = 276
    @ViewState<PendingDockAction?> private var pendingAction = nil
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.scenePhase) private var scenePhase

    private struct PendingDockAction {
        let generation: UUID
        let perform: () -> Void
    }

    var body: some View {
        Button { expanded.toggle() } label: {
            Image(systemName: "sun.horizon")
                .font(.system(size: 21, weight: .regular))
                .foregroundStyle(.primary.opacity(0.85))
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Circle())
        .glassEffectID("sunrise", in: glassNamespace)
        .accessibilityLabel("Morning actions")
        .accessibilityValue(expanded ? "Expanded" : "Collapsed")
        .accessibilityIdentifier("morning.actions")
        .disabled(store.privacyBlocksWork || transitionPending)
        .popover(isPresented: $expanded, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button { expanded = false } label: {
                        Image(systemName: "xmark").font(.caption.weight(.semibold)).frame(width: 44, height: 44)
                    }.buttonStyle(.plain).accessibilityLabel("Close morning actions")
                        .accessibilityIdentifier("morning.closeActions")
                }
                ScrollView {
                    actionRows.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { actionHeight = $0 }
                }
                .scrollBounceBehavior(.basedOnSize)
                .accessibilityIdentifier("morning.actionsScroll")
                .frame(height: min(max(44, availableHeight - 126), max(44, actionHeight)))
            }
            .frame(width: dynamicType.isAccessibilitySize ? 320 : 264)
            .presentationCompactAdaptation(.popover)
            .onDisappear { finishSelectedAction() }
        }
        .onChange(of: store.dataGeneration) { _, _ in discardSelectedAction() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { discardSelectedAction() }
        }
    }

    private func finishSelectedAction() {
        let selected = pendingAction
        pendingAction = nil
        defer { transitionPending = false }
        guard let selected, selected.generation == store.dataGeneration,
              scenePhase == .active, !store.privacyBlocksWork, !store.busy else { return }
        // Reserve the destination before releasing pending-entry occupancy.
        selected.perform()
    }

    private func discardSelectedAction() {
        pendingAction = nil
        transitionPending = false
        expanded = false
    }

    private var actionRows: some View {
        VStack(spacing: 0) {
            if let session = store.session, store.sessionActive {
                let intendsResume = session.status == .paused
                action(intendsResume ? "Continue morning" : "Pause morning",
                       symbol: intendsResume ? "play" : "pause", id: "morning.playback") {
                    // Native dismissal can outlive an interruption. Preserve the
                    // displayed command and session, never toggle the latest state.
                    guard store.session?.id == session.id else { return }
                    if intendsResume {
                        guard store.session?.status == .paused else { return }
                        store.resume()
                    } else {
                        guard store.session?.status == .running else { return }
                        store.pause()
                    }
                }
            } else if let routine = store.routine {
                action(routine.isApproved ? "Start my morning" : "Review my morning",
                       symbol: routine.isApproved ? "play" : "checkmark", id: routine.isApproved ? "run.start" : "morning.reviewDraft") {
                    if routine.isApproved { store.start() } else { edit() }
                }
            } else {
                action("Try a sample", symbol: "play", id: "morning.sample") { store.loadSample() }
            }
            action("Update my morning", symbol: "slider.horizontal.3", id: "morning.update", disabled: store.sessionActive || store.routine == nil, edit)
            action("Past mornings", symbol: "calendar", id: "morning.review", review)
            action("Learn my morning", symbol: "record.circle", id: "morning.learn", disabled: store.sessionActive, learn)
            action("Settings", symbol: "gearshape", id: "morning.settings", settings)
        }.padding(8)
    }

    private func action(_ title: String, symbol: String, id: String, disabled: Bool = false,
                        _ perform: @escaping () -> Void) -> some View {
        Button {
            // Keep occupancy through native popover dismissal; execute only if
            // the same local data generation is still foreground and available.
            pendingAction = .init(generation: store.dataGeneration, perform: perform)
            transitionPending = true
            expanded = false
        } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.system(size: 17, weight: .regular)).frame(width: 24)
                Text(title).font(.subheadline.weight(.medium)).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }.foregroundStyle(.primary).padding(.horizontal, 15).padding(.vertical, 13)
                .frame(minHeight: 48).contentShape(RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain).disabled(disabled || store.busy || store.privacyBlocksWork)
            .opacity(disabled ? 0.4 : 1).accessibilityIdentifier(id)
    }
}

/// Light behind the glass, not another card. The system supplies the actual material.
private struct MorningLightBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                MorningStyle.background
                if !reduceTransparency {
                    Ellipse()
                        .fill(Color(red: 0.90, green: 0.70, blue: 0.42).opacity(scheme == .dark ? 0.12 : 0.16))
                        .frame(width: geometry.size.width * 1.3, height: geometry.size.height * 0.50)
                        .blur(radius: 65).offset(x: geometry.size.width * 0.40, y: -geometry.size.height * 0.10)
                    Ellipse()
                        .fill(Color(red: 0.40, green: 0.60, blue: 0.66).opacity(scheme == .dark ? 0.12 : 0.11))
                        .frame(width: geometry.size.width * 1.1, height: geometry.size.height * 0.48)
                        .blur(radius: 70).offset(x: -geometry.size.width * 0.42, y: geometry.size.height * 0.24)
                }
            }
        }.ignoresSafeArea().accessibilityHidden(true).allowsHitTesting(false)
    }
}
