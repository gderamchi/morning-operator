import SwiftUI
import UniformTypeIdentifiers
import MorningCore
import MorningApple

struct MorningRootView: View {
    @Bindable var store: MorningStore
    @ViewState<Bool> private var showingInvitation = false
    @ViewState<Bool> private var learnAfterRoutineDismissal = false
    @ViewState<UUID> private var reviewRootIdentity = UUID()
    @ViewState<Bool> private var resetReviewAfterSettingsDismissal = false
    @ViewState<Bool> private var presentingIntentCapture = false
    @ViewState<Bool> private var pendingObservationReview = false
    @ViewState<Bool> private var testObservedBackground = false
    @ViewState<Bool> private var showingActions = false
    @ViewState<Bool> private var actionTransitionPending = false
    private enum EntryPresentation: Hashable { case settings, learn, routine, invitation }
    @ViewState<Set<EntryPresentation>> private var activeEntryPresentations = []
    @ViewState<CGFloat> private var dockWidth = 430
    @Environment(\.scenePhase) private var scenePhase

    // No tab bar: Home is the root, and every other destination is a screen pushed on
    // it. These flags keep their old meaning ("that destination is showing").
    private enum HomeRoute: Hashable { case settings, routine, learn, history }
    @ViewState<[HomeRoute]> private var path: [HomeRoute] = []
    @ViewState<Date?> private var sunKick: Date? = nil
    @ViewState<Int> private var sunKicks = 0
    private func route(_ route: HomeRoute) -> Bool { path.contains(route) }
    private func setRoute(_ route: HomeRoute, _ visible: Bool) {
        if visible { if !path.contains(route) { path.append(route) } }
        else if let index = path.firstIndex(of: route) { path.removeSubrange(index...) }
    }
    private var showingSettings: Bool {
        get { route(.settings) } nonmutating set { setRoute(.settings, newValue) }
    }
    private var showingRoutineEditor: Bool {
        get { route(.routine) } nonmutating set { setRoute(.routine, newValue) }
    }
    private var learnPushed: Bool {
        get { route(.learn) } nonmutating set { setRoute(.learn, newValue) }
    }
    private var historyPushed: Bool {
        get { route(.history) } nonmutating set { setRoute(.history, newValue) }
    }
    private var showingLearn: Bool {
        get { learnPushed } nonmutating set { learnPushed = newValue }
    }
    /// Icons only, as in Instagram's bar; the name stays for VoiceOver.
    private func tabIcon(_ title: LocalizedStringKey, systemImage: String, id: String) -> some View {
        Label(title, systemImage: systemImage).labelStyle(.iconOnly).accessibilityIdentifier(id)
    }

    private func show(_ tab: MorningTab, _ visible: Bool) {
        if visible { store.tab = tab } else if store.tab == tab { store.tab = .today }
    }

    private var routineProgress: Double {
        guard let session = store.session, !session.routine.steps.isEmpty else { return 0 }
        return Double(session.completedStepIDs.count) / Double(session.routine.steps.count)
    }

    private var presentedContent: some View {
        NavigationStack(path: Binding(get: { path }, set: { path = $0 })) {
            // Home is the sun on its paper and the greeting. The one control is Settings,
            // top right; Routine is reached from Settings.
            MorningSunHome(routine: store.routine, night: MorningThemeClock.shared.celestial.moon.opacity,
                           step: sunKicks, openSettings: { showingSettings = true },
                           session: store.session, currentStep: store.currentStep,
                           begin: {
                               // An approved routine plays; otherwise begin by learning the morning.
                               if store.routine?.isApproved == true, !store.sessionActive {
                                   if !store.start() { showingLearn = true }
                               } else if !store.sessionActive {
                                   showingLearn = true
                               }
                           },
                           pause: { store.pause() }, resume: { store.resume() }, next: { store.advance() },
                           offersReflection: store.shouldOfferCompletionReflection,
                           voiceBlocked: store.voiceInputBlocksPlayback,
                           speak: { store.openCompletionCapture() }, write: { store.openCapture() },
                           notNow: { store.discardCompletionReflection() })
                // The sky, then the touch layer, both under the text and buttons so those
                // keep their own taps.
                .background {
                    ZStack {
                        MorningSunBackdrop(kick: sunKick, kicks: sunKicks)
                        MorningTouchLight(night: MorningThemeClock.shared.celestial.moon.opacity > 0.5,
                                          onBody: { sunKick = Date(); sunKicks += 1 })
                            .ignoresSafeArea()
                    }
                }
                // Light status bar text over the night sky.
                .toolbarColorScheme(MorningThemeClock.shared.celestial.moon.opacity > 0.5 ? .dark : .light, for: .navigationBar)
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: HomeRoute.self) { route in
                    switch route {
                    case .settings:
                        destinationContent(String(localized: "Settings")) { SetupView(store: store, openRoutine: { showingRoutineEditor = true }) }
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button { showingRoutineEditor = true } label: {
                                        Image(systemName: "list.bullet").frame(width: 44, height: 44)
                                    }
                                    .accessibilityLabel("Your routine").accessibilityIdentifier("morning.review")
                                }
                            }
                    case .routine:
                        RoutineReviewEditor(store: store, onLearn: { showingLearn = true }, showsClose: false)
                    case .learn:
                        destinationContent(String(localized: "Learn my morning"), displayTitle: String(localized: "Learn")) {
                            LearnView(store: store, onClose: { learnPushed = false; if store.routine != nil { showingRoutineEditor = true } })
                        }
                    case .history:
                        WeeklyReviewView(store: store, onLearn: { showingLearn = true },
                                         onSettings: {
                                             if store.voiceInputBlocksPlayback { store.voiceCommandPresented = true }
                                             else { showingSettings = true }
                                         }, showingRoutineEditor: Binding(get: { showingRoutineEditor },
                                                                          set: { showingRoutineEditor = $0 }))
                            .background(MorningStyle.background)
                            .id(reviewRootIdentity)
                    }
                }
        }
        // On the stack, not its first screen, so the status bar clock follows the sky
        // on pushed screens too and turns light at night.
        .preferredColorScheme(MorningThemeClock.shared.celestial.moon.opacity > 0.5 ? .dark : nil)
        .background(MorningPaper(progress: routineProgress))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { dockWidth = $0 }
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
        .foregroundStyle(MorningStyle.ink)
        .font(MorningTheme.Typography.body)
        .sheet(isPresented: $showingInvitation, onDismiss: {
            activeEntryPresentations.remove(.invitation)
            processPendingEntries()
        }) {
            MorningInvitationView(service: store.invitation)
                .interactiveDismissDisabled(store.privacyBlocksWork)
                .onAppear { activeEntryPresentations.insert(.invitation) }
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
            learnAfterRoutineDismissal = false
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
        .onChange(of: store.tab) { _, value in
            showingActions = false
            switch value {
            case .review, .captures: store.tab = .today; historyPushed = true
            case .learn: store.tab = .today; showingLearn = true
            case .setup: store.tab = .today; showingSettings = true
            case .routine: store.tab = .today; showingRoutineEditor = true
            case .today: break
            }
            if value != .today { store.stopCompletionInvitation() }
            processPendingEntries()
        }
        .onChange(of: store.speech.voiceIdentifier) { store.saveVoicePreference() }
        .onChange(of: store.readAloud) { store.executionPreferencesChanged() }
        .onChange(of: store.automatic) { store.executionPreferencesChanged() }
    }

    var body: some View {
        workspaceContent
        .modifier(MorningHaptics(store: store))
        .routineWebStep(store: store)
        .onChange(of: store.speech.state) { store.handleSpeechInterruption() }
        .onChange(of: store.automation.status) { store.synchronizeMorningActivity() }
        .onChange(of: scenePhase) { _, phase in
            store.morningActivitySceneChanged(isForeground: phase == .active)
            if phase == .background {
                showingActions = false
                // Reopening starts the greeting again.
                sunKicks = 0
                sunKick = nil
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--ui-testing") { testObservedBackground = true }
                #endif
                store.discardCompletionReflection()
                store.cancelVoiceCommandTurn()
                if store.session?.status == .running, !store.keepsTimerInBackground { store.pause() }
            } else if phase == .active {
                MorningThemeClock.shared.refresh()
                store.armStepTimer()
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
        .onChange(of: MorningIntentRouter.shared.pendingCommand, initial: true) { _, _ in processPendingEntries() }
        .onChange(of: MorningIntentRouter.shared.pendingStart, initial: true) { _, _ in processPendingEntries() }
        .onChange(of: entryIsOccupied) { _, occupied in
            if occupied { store.stopCompletionInvitation() }
            else { processPendingEntries() }
        }
        .onChange(of: observationReviewCanPresent) { _, ready in if ready { processPendingEntries() } }
        .onChange(of: store.busy) { _, busy in if !busy { processPendingEntries() } }
        .onOpenURL { url in
            let scheme = Bundle.main.object(forInfoDictionaryKey: "MorningURLScheme") as? String ?? "more"
            if let next = StepNavigation.parseNext(url, scheme: scheme) {
                store.tab = .today
                store.nextTargetStep(sessionID: next.sessionID, stepID: next.stepID)
                return
            }
            guard url.scheme == scheme, url.host == "morning", url.path.isEmpty,
                  url.query == nil, url.fragment == nil, !store.privacyBlocksWork else { return }
            // Revealing progress is not a request to start or resume. Keep any
            // unfinished review sheet intact rather than discarding the draft.
            store.tab = .today
        }
        .task { await initializeMorning() }
        .task {
            while !Task.isCancelled {
                MorningThemeClock.shared.refresh()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private func initializeMorning() async {
        store.morningActivitySceneChanged(isForeground: scenePhase == .active)
        store.armStepTimer()
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
        showingRoutineEditor = true
    }

    private func presentPendingIntentCapture() {
        guard !store.privacyBlocksWork, activeEntryPresentations.isEmpty, scenePhase == .active, !presentingIntentCapture, !store.capturePresented, !store.captureVoicePresented, !store.hasPendingSpokenCapture,
              !store.voiceInputBlocksPlayback, !showingSettings, !showingInvitation, !showingActions, !actionTransitionPending,
              !store.morningDetailPresented,
              !showingLearn, !showingRoutineEditor, !learnAfterRoutineDismissal, !store.voiceCommandPresented,
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
        showingLearn = true
    }

    /// Unlike start-entry occupancy, a saved raw recording must not block its own
    /// review. Watch this eligibility separately so closing another detail or
    /// ending a session resumes review even when a failed recording stays pending.
    private var observationReviewCanPresent: Bool {
        guard activeEntryPresentations.isEmpty || (showingLearn && activeEntryPresentations == [.learn]) else { return false }
        guard !store.privacyBlocksWork, scenePhase == .active, !store.busy, !store.sessionActive,
              !showingSettings, !showingInvitation, !showingActions, !actionTransitionPending, !showingRoutineEditor, !learnAfterRoutineDismissal, !presentingIntentCapture,
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
        return store.privacyBlocksWork || !activeEntryPresentations.isEmpty || showingActions || actionTransitionPending || showingSettings || showingInvitation || showingLearn || showingRoutineEditor || learnAfterRoutineDismissal || presentingIntentCapture ||
            store.capturePresented || store.voiceCommandPresented || store.captureVoicePresented ||
            store.hasPendingSpokenCapture || store.morningDetailPresented || store.observationDetailPresented ||
            store.observationSelectionPresented || store.routineProposalPresented || store.voiceInputBlocksPlayback ||
            store.busy || store.captureBusy || store.calendarBusy || store.hasPendingRecording ||
            recordingBusy || store.invitation.isBusy
    }

    private var recordingCanProcess: Bool {
        !store.privacyBlocksWork && activeEntryPresentations.isEmpty && !showingActions && !actionTransitionPending && !showingSettings && !showingInvitation && !showingLearn && !showingRoutineEditor && !learnAfterRoutineDismissal && !presentingIntentCapture &&
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
        if scenePhase == .active, !entryIsOccupied, let command = router.takeCommand() {
            store.performMorningCommand(command)
        }
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
        let waitingNotice = String(localized: "Your morning is waiting. Finish what you're doing here, then MORE can begin.")
        guard destination != .wait else {
            if scenePhase == .active, store.notice == nil { store.notice = waitingNotice }
            return
        }
        if store.notice == waitingNotice { store.notice = nil }
        if Date.now >= request.expiresAt {
            store.notice = String(localized: "Your morning is ready when you are. Tap Start to begin.")
        }
        if let payload = router.invitationPayload {
            do {
                // A learning window's reminder only brings the person to MORE. It never
                // starts the routine, and it cannot start a recording.
                let used = try store.invitation.consume(payload)
                if used == nil || used?.learningTarget != nil { destination = .revealMorning }
            } catch {
                destination = .revealMorning
                store.notice = String(localized: "Your invitation couldn't be saved. Start your morning when you're ready.")
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
        case .learn: showingLearn = true
        default: store.tab = .today
        }
    }

    private func destinationPage<Content: View>(_ title: String, displayTitle: String? = nil,
                                               @ViewBuilder content: () -> Content) -> some View {
        NavigationStack { destinationContent(title, displayTitle: displayTitle, content: content) }
    }

    private func destinationContent<Content: View>(_ title: String, displayTitle: String? = nil,
                                                  @ViewBuilder content: () -> Content) -> some View {
            ScrollView {
                VStack(spacing: 20) {
                    content()
                    if let notice = store.notice { NoticeView(text: notice, dismiss: { store.notice = nil }) }
                }.padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }
            .background(MorningPaper(showsSun: false)).navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityLabel(title)
            .toolbar {
                ToolbarItem(placement: .principal) { Text(displayTitle ?? title).font(MorningTheme.Typography.title) }
            }
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
    @Environment(\.locale) private var locale
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
        .onChange(of: store.routine?.id) { _, _ in viewingStep = nil }
        .onChange(of: store.dataGeneration) { _, _ in viewingStep = nil; showingNotice = false }
        .onChange(of: viewingStep != nil || showingNotice, initial: true) { _, presented in
            store.morningDetailPresented = presented
        }
        .sheet(item: $viewingStep) { selection in
            NavigationStack {
                if let step = store.routine?.steps.first(where: { $0.id == selection.id }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack(alignment: .center, spacing: 14) {
                            MorningDottedIcon(systemName: MorningStyle.symbol(for: step.kind)).frame(width: 26, height: 26)
                                .font(.serif(.title3)).foregroundStyle(MorningStyle.accent)
                                .frame(width: 48, height: 48)
                                .background(MorningStyle.selected, in: Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text(step.title).font(.serif(.title3, .semibold))
                                Text("\(step.durationMinutes) min").font(.raleway(.caption).monospacedDigit())
                                    .foregroundStyle(MorningStyle.muted)
                            }
                        }
                        Text(purpose(for: step)).font(.raleway(.body))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("moment.purpose")
                        if let briefing = store.preparedBriefing(for: step) {
                            MorningBriefingDocumentView(document: briefing, operation: step.automation, synthetic: store.usesSyntheticBriefing)
                        } else if step.automation == .spokenNote || step.automation == .savedObservation {
                            Text(step.detail).font(.raleway(.subheadline)).textSelection(.enabled)
                                .accessibilityIdentifier("run.detail")
                        } else if !step.detail.isEmpty {
                            DisclosureGroup(isFrench ? "Détails enregistrés" : "Saved details") {
                                Text(step.detail).font(.raleway(.subheadline)).foregroundStyle(MorningStyle.muted)
                                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                                    .accessibilityIdentifier("run.detail")
                            }.font(.raleway(.subheadline)).tint(MorningStyle.accent)
                        }
                        if step.automation == nil {
                            Label { Text(step.kind == .messages ? (isFrench ? "Non connecté" : "Not connected") : (isFrench ? "À votre rythme" : "At your pace")) } icon: {
                                MorningDottedIcon(systemName: step.kind == .messages ? "arrow.up.forward.app" : "hand.tap").frame(width: 18, height: 18)
                            }
                                .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                                .accessibilityIdentifier("moment.manual")
                        }
                        if store.session?.status == .paused,
                           store.currentStep?.id == step.id,
                           step.automation == .morningBriefing || step.automation == .todayCalendar {
                            Button("Update this recap") { store.updateCurrentBriefing() }
                                .buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("briefing.updateCurrent")
                        }
                        if store.session?.status == .paused {
                            Text("Your morning is paused.").font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                                .accessibilityIdentifier("run.detailPaused")
                        }
                        if store.sessionActive, store.currentStep?.id == step.id {
                            currentStepCommands
                        }
                        if canArrange, let routine = store.routine,
                           let index = routine.steps.firstIndex(where: { $0.id == step.id }) {
                            let generation = store.dataGeneration
                            HStack(spacing: 12) {
                                Text("Move").font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                                Spacer()
                                if index > 0 {
                                    Button {
                                        store.moveStep(step.id, onto: routine.steps[index - 1].id,
                                            expectedRoutineID: routine.id, expectedGeneration: generation)
                                    } label: { MorningDottedIcon(systemName: "arrow.up").frame(width: 22, height: 22) }
                                        .accessibilityLabel("Move earlier").frame(minWidth: 44, minHeight: 44)
                                        .accessibilityIdentifier("morning.moveEarlier")
                                }
                                if index + 1 < routine.steps.count {
                                    Button {
                                        store.moveStep(step.id, onto: routine.steps[index + 1].id,
                                            expectedRoutineID: routine.id, expectedGeneration: generation)
                                    } label: { MorningDottedIcon(systemName: "arrow.down").frame(width: 22, height: 22) }
                                        .accessibilityLabel("Move later").frame(minWidth: 44, minHeight: 44)
                                        .accessibilityIdentifier("morning.moveLater")
                                }
                            }.buttonStyle(SecondaryButtonStyle())
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
                }.navigationTitle("").navigationBarTitleDisplayMode(.inline)
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
                }.navigationTitle("").navigationBarTitleDisplayMode(.inline)
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
                Label { Text("Review your saved observation") } icon: { MorningDottedIcon(systemName: "text.viewfinder").frame(width: 18, height: 18) }
                    .font(.raleway(.caption, .medium))
            }.buttonStyle(QuietButtonStyle()).accessibilityIdentifier("observation.review")
        }
    }

    private func page(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            dateHeader
            if let routine = store.routine {
                if !store.sessionActive { routineHeading(routine, compact: compact) }
                if let opening = store.currentOpening { MorningOpeningView(store: store, presentation: opening) }
                // The first moment's card waits with the routine: it appears once the
                // opening gives way, by a choice or on its own when hands free (issue #99).
                else if store.sessionActive { nowPlaying(compact: compact) }
                if store.session?.status == .completed { closingMoment }
                compactTimeline(routine, compact: compact)
                if routine.isSynthetic {
                    Text("Sample morning").font(.raleway(.caption2)).foregroundStyle(MorningStyle.muted)
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
                        Label { Text("Learn my morning") } icon: { MorningDottedIcon(systemName: "record.circle").frame(width: 24, height: 24) }
                            .padding(.horizontal, 8).padding(.vertical, 8)
                    }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("learn.begin")
                    Button("Try a sample") { store.loadSample() }
                        .font(.raleway(.subheadline)).frame(minHeight: 44)
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
                        .font(.raleway(.caption, .medium))
                    MorningDottedIcon(systemName: "chevron.down").frame(width: 16, height: 16).font(.raleway(.caption2, .regular))
                }.foregroundStyle(MorningStyle.ink).frame(minHeight: 44).contentShape(Rectangle())
                    .background(MorningStyle.background)
            }.buttonStyle(.plain).accessibilityIdentifier("morning.date")
                .accessibilityHint("Review this week and previous mornings")
            Spacer()
            #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(ScreenCaptureKit)
            if #available(iOS 27.0, *), ScreenRecordingService.shared.captureMayBeActive {
                Button { showingNotice = true } label: {
                    Label { Text("MORE · Recording") } icon: { MorningDottedIcon(systemName: "record.circle.fill").frame(width: 18, height: 18) }.font(.raleway(.caption, .medium)).foregroundStyle(.red)
                }.buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("morning.recording")
            }
            #endif
            if store.busy {
                Button { showingNotice = true } label: { ProgressView().controlSize(.small) }
                    .accessibilityLabel("Understanding your morning. View progress")
            } else if store.notice != nil || store.observationIssue != nil || store.hasPendingRecording {
                Button { showingNotice = true } label: { MorningDottedIcon(systemName: "exclamationmark.circle").frame(width: 24, height: 24).frame(width: 44, height: 44) }
                    .buttonStyle(.plain).accessibilityLabel("Your morning needs attention")
                    .accessibilityIdentifier("morning.attention")
            }
        }
    }

    private var welcome: some View {
        // The morning artwork carries this empty state; Learn and Sample are its actions.
        Color.clear.frame(height: 24).accessibilityHidden(true)
    }

    private func routineHeading(_ routine: RoutineVersion, compact: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(isFrench ? "bonjour" : "good morning").font(MorningTheme.Typography.title)
                .background(MorningStyle.background)
                .accessibilityIdentifier("morning.heading")
                .accessibilityValue(store.session?.status == .stopped ? "stopped" : "")
            morningInvitationButton
            if !routine.isApproved {
                Text("Draft").font(.raleway(.caption2)).foregroundStyle(MorningStyle.muted)
                    .background(MorningStyle.background)
                    .accessibilityIdentifier("morning.draft")
                    .accessibilityLabel("Draft, review before starting")
            }
            Spacer(minLength: 8)
            Text("\(routine.totalDurationMinutes) min").font(.raleway(.caption).monospacedDigit()).foregroundStyle(MorningStyle.muted)
                .background(MorningStyle.background)
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
                    MorningDottedIcon(systemName: "clock").frame(width: 18, height: 18)
                    if let upcoming {
                        Text(upcoming.formatted(date: .omitted, time: .shortened)).monospacedDigit()
                    }
                }.font(.raleway(.caption2)).foregroundStyle(MorningStyle.muted).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    .background(MorningStyle.background)
            }.buttonStyle(.plain)
                .accessibilityLabel(upcoming == nil ? "Set morning invitation" : "Edit morning invitation")
                .accessibilityValue(upcoming?.formatted(date: .complete, time: .shortened) ?? String(localized: "No upcoming invitation"))
                .accessibilityIdentifier("morning.invitation")
                .disabled(!canEditInvitation || !store.storageIsAvailable)
        }
    }

    private var isFrench: Bool { locale.language.languageCode?.identifier == "fr" }

    private func purpose(for step: RoutineStep) -> String {
        func text(_ english: String, _ french: String) -> String { isFrench ? french : english }
        switch step.automation {
        case .spokenNote: return text("Listen to your saved words.", "Écoutez vos mots enregistrés.")
        case .todayCalendar: return text("Hear what’s on your calendar today.", "Écoutez votre programme du jour.")
        case .morningBriefing: return text("Your day ahead, in a few words.", "Votre journée, en quelques mots.")
        case .savedObservation: return text("Listen back to the observation you saved.", "Réécoutez l’observation enregistrée.")
        case nil:
            switch step.kind {
            case .messages:
                return text("Read your messages. Reply in the app.",
                            "Retrouvez vos messages. Répondez dans l’application.")
            case .entertainment:
                return text("Make room for something you enjoy. You choose when to move on.",
                            "Un moment pour ce qui vous plaît. Vous choisissez quand passer à la suite.")
            case .briefing, .calendar:
                return text("See what’s ahead. Check your calendar and weather in their apps.",
                            "Préparez la journée. Consultez le calendrier et la météo dans leurs applications.")
            case .custom, .wellbeing:
                return text("A moment you’ve made room for.",
                            "Un moment que vous avez choisi.")
            }
        }
    }

    private var currentStepCommands: some View {
        let sessionID = store.session?.id
        let stepID = store.currentStep?.id
        let generation = store.dataGeneration
        let current = { store.session?.id == sessionID && store.currentStep?.id == stepID && store.dataGeneration == generation }
        let layout = dynamicType.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            if store.session?.status == .paused {
                Button { if current() { store.resume() } } label: { Label { Text("Continue") } icon: { MorningDottedIcon(systemName: "play.fill").frame(width: 20, height: 20) } }
                    .accessibilityIdentifier("run.detailResume")
            } else {
                Button { if current() { store.pause() } } label: { Label { Text("Pause") } icon: { MorningDottedIcon(systemName: "pause.fill").frame(width: 20, height: 20) } }
                    .accessibilityIdentifier("run.detailPause")
                Button {
                    guard current() else { return }
                    viewingStep = nil
                    store.advance()
                } label: { Label { Text("Next") } icon: { MorningDottedIcon(systemName: "arrow.right").frame(width: 20, height: 20) } }
                    .accessibilityIdentifier("run.detailNext")
            }
            Button { if current() { store.readCurrent() } } label: { Label { Text("Again") } icon: { MorningDottedIcon(systemName: "arrow.clockwise").frame(width: 20, height: 20) } }
                .accessibilityIdentifier("run.detailAgain")
        }.buttonStyle(SecondaryButtonStyle())
            .disabled(store.privacyBlocksWork || store.voiceInputBlocksPlayback)
    }

    private var canArrange: Bool {
        !store.sessionActive && !store.busy && !store.privacyBlocksWork && store.storageIsAvailable
    }

    private func compactTimeline(_ routine: RoutineVersion, compact: Bool) -> some View {
        let generation = store.dataGeneration
        let dense = compact || routine.steps.count > 6 || store.sessionActive || terminal
        let spacing: CGFloat = store.sessionActive && compact ? 4 : 7
        return Group {
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
                        .font(.raleway(.caption)).frame(minHeight: 44)
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
        return Button { viewingStep = step } label: {
            HStack(spacing: 13) {
                MorningDottedIcon(systemName: complete ? "checkmark" : skipped ? "forward.end" : MorningStyle.symbol(for: step.kind)).frame(width: 20, height: 20)
                    .scaledFont(16, relativeTo: .body, weight: .regular)
                    .foregroundStyle(complete || skipped ? MorningStyle.muted : MorningStyle.ink).frame(width: 25)
                Text(step.title).font(.raleway(.subheadline, .medium))
                    .lineLimit(dynamicType.isAccessibilitySize ? nil : 1)
                Spacer(minLength: 4)
                Text("\(step.durationMinutes) min")
                    .font(.raleway(.caption).monospacedDigit()).foregroundStyle(current ? MorningStyle.ink : MorningStyle.muted)
            }
            .foregroundStyle(MorningStyle.ink)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: MorningTheme.Space.radius))
        }
        .buttonStyle(.plain)
        .background(current ? MorningStyle.selected : MorningStyle.surface, in: RoundedRectangle(cornerRadius: MorningTheme.Space.radius))
        .overlay(MorningDottedFrame(cornerRadius: MorningTheme.Space.radius).fill(current ? MorningStyle.ink : MorningStyle.line))
        .accessibilityLabel(complete ? "\(index + 1). \(step.title), \(step.durationMinutes) minutes, completed" : skipped ? "\(index + 1). \(step.title), \(step.durationMinutes) minutes, skipped" : "\(index + 1). \(step.title), \(step.durationMinutes) minutes")
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
                    MorningDottedIcon(systemName: store.session?.status == .paused ? "pause.fill" : "waveform").frame(width: 18, height: 18)
                        .accessibilityHidden(true)
                    Text(store.session?.status == .paused ? "Paused" : "Now")
                        .accessibilityIdentifier("run.state").accessibilityValue(store.stateLabel)
                }.font(.raleway(.caption, .medium)).foregroundStyle(MorningStyle.accent)
                Spacer()
            }
            Text(store.currentStep?.title ?? String(localized: "Your morning"))
                .font(.serif(.headline)).accessibilityIdentifier("run.step")
                .accessibilityValue(store.openingRoutineStartObservation)
            if compact {
                EmptyView()
            } else if store.automatic, !store.automation.message.isEmpty {
                Text(store.automation.message).font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                    .lineLimit(dynamicType.isAccessibilitySize ? nil : compact ? 2 : 3)
            }
        }.padding(compact ? 11 : 14).frame(maxWidth: .infinity, alignment: .leading)
            .background(MorningStyle.surface, in: RoundedRectangle(cornerRadius: MorningTheme.Space.radius))
            .overlay(RoundedRectangle(cornerRadius: MorningTheme.Space.radius).strokeBorder(MorningStyle.line))
    }

    private var closingMoment: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.shouldOfferCompletionReflection ? "Save a thought?" : "Morning complete.")
                .font(.serif(.headline)).accessibilityIdentifier("run.step")
            Text(store.stateLabel).font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                .accessibilityIdentifier("run.state").accessibilityValue(store.stateLabel)
            if store.shouldOfferCompletionReflection {
                if dynamicType.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 14) { reflectionButtons }
                } else { HStack(spacing: 18) { reflectionButtons } }
            }
        }.padding(.vertical, 4)
    }

    @ViewBuilder private var reflectionButtons: some View {
        Button { store.openCompletionCapture() } label: {
            Label { Text("Speak") } icon: { MorningDottedIcon(systemName: "mic").frame(width: 22, height: 22) }
        }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(store.voiceInputBlocksPlayback).accessibilityIdentifier("morning.speakReflection")
        Button { store.openCapture() } label: {
            Label { Text("Write") } icon: { MorningDottedIcon(systemName: "square.and.pencil").frame(width: 20, height: 20) }
        }
            .buttonStyle(.borderless).accessibilityIdentifier("morning.reflect")
        Button("Not now") { store.discardCompletionReflection() }
            .buttonStyle(.borderless).accessibilityIdentifier("morning.dismissReflection")
    }

    @ViewBuilder private func actionArea(_ routine: RoutineVersion) -> some View {
        StepTimerView(store: store)
        if store.sessionActive {
            HStack(spacing: 12) {
                if store.session?.status == .paused {
                    Button { store.resume() } label: { Label { Text("Continue") } icon: { MorningDottedIcon(systemName: "play.fill").frame(width: 22, height: 22) }.frame(maxWidth: .infinity).padding(.vertical, 9) }
                        .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("run.resume")
                        .disabled(store.voiceInputBlocksPlayback)
                } else {
                    Button { store.pause() } label: { Label { Text("Pause") } icon: { MorningDottedIcon(systemName: "pause.fill").frame(width: 22, height: 22) }.frame(maxWidth: .infinity).padding(.vertical, 9) }
                        .buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("run.pause")
                    if !store.automatic || [.waitingForUser, .unavailable, .failed].contains(store.automation.status) {
                        Button { store.advance() } label: { MorningDottedIcon(systemName: "arrow.right").frame(width: 25, height: 25).frame(width: 32, height: 32) }
                            .buttonStyle(PrimaryButtonStyle()).accessibilityLabel("Next moment").accessibilityIdentifier("run.next")
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
                } label: { MorningDottedIcon(systemName: "ellipsis").frame(width: 25, height: 25).frame(width: 32, height: 32) }
                    .buttonStyle(SecondaryButtonStyle()).accessibilityLabel("Morning controls").accessibilityIdentifier("run.controls")
            }.controlSize(.large)
        }
    }
}

struct NoticeView: View {
    let text: String
    let dismiss: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            MorningDottedIcon(systemName: "info.circle").frame(width: 20, height: 20)
            Text(text).font(.raleway(.caption)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: dismiss) { MorningDottedIcon(systemName: "xmark").frame(width: 18, height: 18).padding(5) }.accessibilityLabel("Dismiss message")
        }.foregroundStyle(MorningStyle.muted).padding(16).background(MorningStyle.surface, in: RoundedRectangle(cornerRadius: 18))
            .accessibilityIdentifier("app.notice")
    }
}

/// Four quiet destinations. Playback appears only when the morning sun is opened.
private struct MorningActionDock: View {
    @Bindable var store: MorningStore
    @Binding var expanded: Bool
    @Binding var transitionPending: Bool
    var availableWidth: CGFloat
    var edit: () -> Void
    @ViewState<RoutineVersion?> private var readyRoutine = nil
    @ViewState<UUID?> private var readyGeneration = nil
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var barWidth: CGFloat {
        min(max(0, availableWidth - 40), dynamicType.isAccessibilitySize ? 360 : 286)
    }

    var body: some View {
        VStack(spacing: 10) {
            if expanded {
                actionBar
                    .background(MorningStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(MorningDottedFrame(cornerRadius: 12).fill(MorningStyle.line))
                    .accessibilityAction(.escape) { expanded = false }
            }
            HStack(spacing: 12) {
                Button {
                    expanded.toggle()
                } label: {
                    MorningDockGlyph(symbol: .morning).frame(width: 28, height: 28)
                        .frame(width: 48, height: 48).contentShape(Rectangle())
                }
                .buttonStyle(SunriseTouchStyle())
                .accessibilityLabel("Morning")
                .accessibilityValue(expanded ? "Expanded" : "Collapsed")
                .accessibilityHint("Opens playback controls")
                .accessibilityIdentifier("morning.actions")
                .disabled(store.privacyBlocksWork || transitionPending)
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .foregroundStyle(MorningStyle.ink)
            .background(MorningStyle.background, in: RoundedRectangle(cornerRadius: 10))
            .overlay(MorningDottedFrame(cornerRadius: 10, spacing: 7).fill(MorningStyle.line))
        }
        .frame(maxWidth: 320)
        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: expanded)
        .onChange(of: expanded) { _, open in if !open { clearReadyState() } }
        .onChange(of: store.routine) { _, _ in clearReadyState() }
        .onChange(of: store.sessionActive) { _, active in if active { collapse() } }
        .onChange(of: store.dataGeneration) { _, _ in collapse() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { collapse() } }
    }

    private var actionBar: some View {
        Group {
            if let routine = readyRoutine {
                readyBar(routine)
            } else if dynamicType.isAccessibilitySize || barWidth < 248 {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) { actionItems }.padding(dynamicType.isAccessibilitySize ? 8 : 4)
                }.scrollIndicators(.hidden)
                    .scrollBounceBehavior(.basedOnSize)
                    .accessibilityIdentifier("morning.actionsScroll")
            } else {
                HStack(spacing: 0) { actionItems }.padding(4)
            }
        }.frame(width: readyRoutine != nil ? barWidth : 64,
                height: readyRoutine != nil ? nil : 58)
    }

    @ViewBuilder private var actionItems: some View {
        if let session = store.session, store.sessionActive {
            let intendsResume = session.status == .paused
            action(intendsResume ? String(localized: "Continue") : String(localized: "Pause"), symbol: intendsResume ? .play : .pause,
                   id: "morning.playback") {
                // Honor the displayed command and original session, never toggle
                // whatever state an interruption may have produced meanwhile.
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
            let generation = store.dataGeneration
            action(routine.isApproved ? String(localized: "Play") : String(localized: "Review"),
                   symbol: routine.isApproved ? .play : .review,
                   id: routine.isApproved ? "run.start" : "morning.reviewDraft",
                   keepsExpanded: routine.isApproved) {
                guard store.routine == routine, !store.sessionActive else { return }
                if routine.isApproved {
                    readyRoutine = routine
                    readyGeneration = generation
                } else { edit() }
            }
        } else {
            action(String(localized: "Sample"), symbol: .play, id: "morning.sample") { store.loadSample() }
        }
    }

    private func action(_ title: String, symbol: MorningDockSymbol, id: String, disabled: Bool = false,
                        keepsExpanded: Bool = false, _ perform: @escaping () -> Void) -> some View {
        let generation = store.dataGeneration
        return Button {
            guard generation == store.dataGeneration, scenePhase == .active,
                  !store.privacyBlocksWork, !store.busy, !transitionPending else { return }
            // Establish the destination synchronously before releasing entry
            // occupancy; no timer or delayed closure can reopen a forgotten session.
            transitionPending = true
            perform()
            if !keepsExpanded { expanded = false }
            transitionPending = false
        } label: {
            MorningDockGlyph(symbol: symbol).frame(width: 27, height: 27)
            .foregroundStyle(MorningStyle.ink)
            .frame(minWidth: 54, maxWidth: dynamicType.isAccessibilitySize ? nil : .infinity, minHeight: 48)
            .padding(.horizontal, 3)
            .contentShape(Capsule())
        }.buttonStyle(DockActionTouchStyle())
            .disabled(disabled || store.busy || store.privacyBlocksWork || transitionPending)
            .opacity(disabled ? 0.4 : 1).accessibilityLabel(title).accessibilityIdentifier(id)
    }

    private func readyBar(_ routine: RoutineVersion) -> some View {
        // The question sits above its two answers so neither has to squeeze the other.
        return VStack(spacing: 2) {
            Text(routine.isSynthetic ? "Ready for this sample morning?" : "Ready for your morning?")
                .font(.raleway(.caption, .medium)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("morning.ready")
            HStack(spacing: 28) {
                Button("Cancel") { clearReadyState() }
                    .font(.raleway(.caption)).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("morning.cancelStart")
                Button("Start") {
                    guard readyGeneration == store.dataGeneration, store.routine == routine,
                          routine.isApproved, !store.sessionActive, scenePhase == .active,
                          !store.privacyBlocksWork, !store.busy, !store.voiceInputBlocksPlayback else {
                        clearReadyState()
                        return
                    }
                    transitionPending = true
                    store.start()
                    clearReadyState()
                    expanded = false
                    transitionPending = false
                }.font(.raleway(.subheadline, .semibold)).foregroundStyle(MorningStyle.accent)
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: 48, minHeight: 44)
                    .accessibilityIdentifier("morning.confirmStart")
            }.buttonStyle(.plain)
                .disabled(store.busy || store.privacyBlocksWork || transitionPending || store.voiceInputBlocksPlayback)
        }.padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 2)
    }

    private func clearReadyState() {
        readyRoutine = nil
        readyGeneration = nil
    }

    private func collapse() {
        clearReadyState()
        transitionPending = false
        expanded = false
    }
}

private struct SunriseTouchStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.95 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

private struct DockActionTouchStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.55 : 1)
    }
}

/// Light haptics mark the moments that matter: a morning starts, a morning finishes,
/// a routine is approved. The system skips them when haptics are off.
private struct MorningHaptics: ViewModifier {
    let store: MorningStore
    func body(content: Content) -> some View {
        let completed: Bool = store.session?.status == .completed
        return content
            .sensoryFeedback(.impact, trigger: store.morningStartCount)
            .sensoryFeedback(.success, trigger: completed) { (old: Bool, new: Bool) -> Bool in !old && new }
            .sensoryFeedback(.success, trigger: store.approvalCount)
    }
}

/// The first screen: the sun on its paper, the greeting, and a quiet line of small
/// icons that sketches the morning ahead. Nothing here is a link.
private struct MorningSunHome: View {
    var routine: RoutineVersion?
    /// 0 by day, 1 at night: text and icons turn light over the night sky.
    var night: Double
    /// How many times the sun was touched: the greeting first, then the date, then the question.
    var step: Int
    var openSettings: () -> Void
    var session: RoutineSession?
    var currentStep: RoutineStep?
    /// Plays an approved routine, or opens the onboarding when there is none yet.
    var begin: () -> Void
    var pause: () -> Void
    var resume: () -> Void
    var next: () -> Void
    /// After a saved, finished run: offer to keep a thought about it.
    var offersReflection = false
    var voiceBlocked = false
    var speak: () -> Void = {}
    var write: () -> Void = {}
    var notNow: () -> Void = {}
    private var running: Bool { session?.status == .running || session?.status == .paused }
    /// Today's run reached its last moment. Yesterday's finished run gives way to a new greeting.
    private var finishedToday: Bool {
        guard let done = session?.completedAt else { return false }
        return Calendar.current.isDateInToday(done)
    }
    /// The sun is not an accessibility element, so VoiceOver and UI tests reach the
    /// question without touching it.
    private var questionShown: Bool {
        if step >= 2 || voiceOverEnabled { return true }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") { return true }
        #endif
        return false
    }
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    private var isFrench: Bool { locale.language.languageCode?.identifier == "fr" }
    private var ink: Color { night > 0.5 ? Color(red: 0.93, green: 0.92, blue: 0.97) : MorningStyle.ink }

    var body: some View {
        Group {
        if running, let step = currentStep {
            // A morning in progress: the moment now, and quiet controls.
            VStack(alignment: .leading, spacing: 12) {
                Text(isFrench ? "maintenant" : "now")
                    .font(.raleway(.subheadline, .medium)).opacity(0.7)
                Text(step.title)
                    .font(.custom("DM Serif Display", size: 40, relativeTo: .largeTitle))
                    .accessibilityIdentifier("morning.currentStep")
                Text("\(step.durationMinutes) min").font(.raleway(.subheadline)).opacity(0.7)
                HStack(spacing: 12) {
                    Button(action: session?.status == .paused ? resume : pause) {
                        Image(systemName: session?.status == .paused ? "play.fill" : "pause.fill")
                            .font(.system(size: 18)).frame(width: 30, height: 30)
                    }
                    .buttonStyle(.glass).buttonBorderShape(.circle)
                    .accessibilityLabel(session?.status == .paused ? "Continue" : "Pause")
                    .accessibilityIdentifier("morning.playback")
                    Button(action: next) {
                        Text(isFrench ? "suivant" : "next")
                            .font(.raleway(.body, .semibold))
                            .padding(.horizontal, 18).padding(.vertical, 6)
                    }
                    .buttonStyle(.glass)
                    .accessibilityIdentifier("morning.next")
                }
                .padding(.top, 8)
            }
            .transition(.opacity)
        } else if finishedToday, let session {
            finished(session)
                .transition(.opacity)
        } else {
        // Each line keeps its place, one under the other, but only the latest shows:
        // the greeting, then the date below it, then the question below that.
        VStack(alignment: .leading, spacing: 10) {
            Text(night > 0.5 ? (isFrench ? "bonsoir" : "good evening") : (isFrench ? "bonjour" : "good morning"))
                .font(.custom("DM Serif Display", size: 46, relativeTo: .largeTitle))
                .opacity(step == 0 ? 1 : 0)
                .accessibilityHidden(step != 0)
            Text(isFrench ? "nous sommes \(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))"
                          : "today is \(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))")
                .font(.custom("DM Serif Display", size: 28, relativeTo: .title2))
                .opacity(step == 1 ? 1 : 0)
                .accessibilityHidden(step != 1)
            VStack(alignment: .leading, spacing: 16) {
                Text(isFrench ? "êtes-vous prêt à commencer ?" : "ready to begin?")
                    .font(.custom("DM Serif Display", size: 28, relativeTo: .title2))
                    .accessibilityIdentifier("morning.readyQuestion")
                Button(action: begin) {
                    Text(isFrench ? "commencer" : "begin")
                        .font(.custom("Raleway", size: 17, relativeTo: .body).weight(.semibold))
                        .padding(.horizontal, 22).padding(.vertical, 6)
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("morning.begin")
            }
            .padding(.top, 10)
            .opacity(questionShown ? 1 : 0)
            .allowsHitTesting(questionShown)
            .accessibilityHidden(!questionShown)
        }
        }
        }
        .animation(.easeOut(duration: 0.4), value: running)
        .animation(.easeOut(duration: 0.4), value: finishedToday)
        // Clear of the Settings button.
        .padding(.trailing, 56)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.6), value: step)
        .foregroundStyle(ink)
        // Contain, not combine: the buttons inside stay separate, reachable controls.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("morning.heading")
        .padding(.horizontal, 24).padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .topTrailing) {
            Button(action: openSettings) {
                Image(systemName: "gearshape").font(.system(size: 20, weight: .regular))
                    .foregroundStyle(ink).frame(width: 30, height: 30)
            }
            .buttonStyle(.glass).buttonBorderShape(.circle)
            .contentShape(Rectangle().inset(by: -8))
            .accessibilityLabel("Settings").accessibilityIdentifier("morning.settings")
            .padding(.trailing, 20).padding(.top, 14)
        }
    }

    /// The morning is done: a closing word, what was done and how long it really took.
    private func finished(_ session: RoutineSession) -> some View {
        let moments = session.completedStepIDs.count
        let minutes = max(1, Int(((session.activeDuration(until: session.completedAt ?? .now) ?? 0) / 60).rounded()))
        let summary = "\(moments) moment\(moments == 1 ? "" : "s") · \(minutes) min"
        return VStack(alignment: .leading, spacing: 12) {
            Text(isFrench ? "bonne matinée" : "have a good day")
                .font(.custom("DM Serif Display", size: 46, relativeTo: .largeTitle))
                .accessibilityIdentifier("morning.complete")
            Text(summary).font(.raleway(.subheadline)).opacity(0.7)
                .accessibilityLabel(isFrench ? "\(moments) moments faits en \(minutes) minutes"
                                             : "\(moments) moments done in \(minutes) minutes")
                .accessibilityIdentifier("morning.completeSummary")
            if offersReflection {
                HStack(spacing: 12) {
                    Button(action: speak) {
                        Image(systemName: "mic").font(.system(size: 18)).frame(width: 30, height: 30)
                    }
                    .buttonStyle(.glass).buttonBorderShape(.circle).disabled(voiceBlocked)
                    .accessibilityLabel(isFrench ? "Dire une pensée" : "Speak a thought")
                    .accessibilityIdentifier("morning.speakReflection")
                    Button(action: write) {
                        Text(isFrench ? "noter une pensée" : "note a thought")
                            .font(.raleway(.body, .semibold))
                            .padding(.horizontal, 18).padding(.vertical, 6)
                    }
                    .buttonStyle(.glass)
                    .accessibilityIdentifier("morning.reflect")
                    Button(isFrench ? "plus tard" : "not now", action: notNow)
                        .font(.raleway(.subheadline)).opacity(0.7).frame(minHeight: 44)
                        .accessibilityIdentifier("morning.dismissReflection")
                }
                .padding(.top, 8)
            }
        }
    }

    /// A recognisable little picture for a moment: the app or habit it names first,
    /// then where it opens, then its kind.
    static func icon(for step: RoutineStep) -> String {
        let title = step.title.lowercased()
        let words: [(String, String)] = [
            ("duolingo", "bird"), ("chess", "checkerboard.rectangle"), ("échec", "checkerboard.rectangle"),
            ("gmail", "envelope"), ("mail", "envelope"), ("whatsapp", "message"), ("messenger", "message"),
            ("message", "message"), ("snapchat", "camera"), ("instagram", "camera"), ("tiktok", "play.square"),
            ("youtube", "play.rectangle"), ("netflix", "play.rectangle"), ("spotify", "music.note"),
            ("music", "music.note"), ("musique", "music.note"), ("podcast", "headphones"),
            ("météo", "cloud.sun"), ("weather", "cloud.sun"), ("calend", "calendar"), ("agenda", "calendar"),
            ("actu", "newspaper"), ("news", "newspaper"), ("linkedin", "briefcase"), ("eau", "drop"),
            ("water", "drop"), ("sport", "figure.run"), ("run", "figure.run"), ("yoga", "figure.mind.and.body"),
            ("pensée", "lightbulb"), ("thought", "lightbulb"), ("café", "cup.and.saucer"), ("coffee", "cup.and.saucer")
        ]
        if let match = words.first(where: { title.contains($0.0) }) { return match.1 }
        if case let .externalApp(app, _) = step.target {
            switch app {
            case .messages, .whatsapp: return "message"
            case .mail: return "envelope"
            case .instagram: return "camera"
            case .calendar: return "calendar"
            case .maps: return "map"
            case .safari: return "safari"
            }
        }
        if case .inAppWeb = step.target { return "globe" }
        switch step.kind {
        case .briefing: return "sun.horizon"
        case .messages: return "message"
        case .calendar: return "calendar"
        case .wellbeing: return "heart"
        case .entertainment: return "play.rectangle"
        case .custom: return "leaf"
        }
    }
}

/// The sun's own colours, cream to gold to a hint of rust, as a barely graded page.
private struct MorningSunBackdrop: View {
    var kick: Date? = nil
    var kicks: Int = 0
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let night = MorningThemeClock.shared.celestial.moon.opacity
        ZStack {
            // A plain cream page: the sun and its lines carry the colour.
            (scheme == .dark ? Color(red: 0.16, green: 0.11, blue: 0.09) : Color(red: 1.0, green: 0.97, blue: 0.90))
            // The night sky, deep indigo, lighter towards the horizon.
            LinearGradient(stops: [.init(color: Color(red: 0.05, green: 0.06, blue: 0.15), location: 0),
                                   .init(color: Color(red: 0.13, green: 0.13, blue: 0.29), location: 0.42),
                                   .init(color: Color(red: 0.20, green: 0.17, blue: 0.34), location: 0.5),
                                   .init(color: Color(red: 0.08, green: 0.09, blue: 0.20), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .opacity(night)
            MorningCelestialArtwork(scene: MorningThemeClock.shared.celestial, kick: kick, kicks: kicks)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// A touch on Home leaves light behind: by day a small lens flare with a few sparkles,
/// at night a shooting star crossing from the touch. Purely decorative; never a button.
private struct MorningTouchLight: View {
    var night: Bool
    var onBody: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private struct Burst: Identifiable { let id = UUID(); let point: CGPoint; let start: Date; let night: Bool; let big: Bool }
    @ViewState<[Burst]> private var bursts: [Burst] = []
    @ViewState<Int> private var bodyTaps = 0

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(paused: bursts.isEmpty)) { timeline in
                Canvas { context, size in
                    let now = timeline.date
                    for burst in bursts {
                        let t = now.timeIntervalSince(burst.start)
                        star(context: context, size: size, at: burst.point, t: t)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { point in
                // The sun's (or moon's) disc, where the artwork draws it.
                let scene = MorningThemeClock.shared.celestial
                let diameter = min(geometry.size.width * 0.72, 300) * (night ? 0.82 : 1)
                let full = geometry.frame(in: .global)
                let origin = CGPoint(x: -full.minX, y: -full.minY)
                let screen = CGSize(width: full.width + full.minX, height: full.height + full.minY)
                let body = night ? scene.moon : scene.sun
                let centre = CGPoint(x: origin.x + screen.width * body.centerX, y: origin.y + screen.height * body.centerY)
                let onDisc = hypot(point.x - centre.x, point.y - centre.y) < diameter / 2
                if onDisc { bodyTaps += 1; onBody() }
                guard !reduceMotion, night else { return }
                let now = Date()
                bursts = bursts.filter { now.timeIntervalSince($0.start) < 2.2 }
                    + [Burst(point: onDisc ? centre : point, start: now, night: night, big: onDisc)]
                Task {
                    try? await Task.sleep(for: .seconds(2.3))
                    bursts.removeAll { Date().timeIntervalSince($0.start) >= 2.2 }
                }
            }
        }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.9), trigger: bodyTaps)
        .accessibilityHidden(true)
    }

    private func star(context: GraphicsContext, size: CGSize, at p: CGPoint, t: Double) {
        guard t < 1.6 else { return }
        let travel = min(1, t / 0.9)
        let eased = 1 - pow(1 - travel, 2)
        let length: CGFloat = 260
        let dx: CGFloat = -0.82, dy: CGFloat = 0.57
        let head = CGPoint(x: p.x + dx * length * eased, y: p.y + dy * length * eased)
        let tailLength = 120 * (t < 0.9 ? 1 : max(0, 1 - (t - 0.9) / 0.7))
        let tail = CGPoint(x: head.x - dx * tailLength, y: head.y - dy * tailLength)
        let fade = t < 0.9 ? 1 : max(0, 1 - (t - 0.9) / 0.7)
        var trail = context
        trail.addFilter(.blur(radius: 1.5))
        var line = Path(); line.move(to: tail); line.addLine(to: head)
        trail.stroke(line, with: .linearGradient(Gradient(colors: [.clear, Color(red: 0.85, green: 0.88, blue: 1).opacity(0.95 * fade)]),
                                                  startPoint: tail, endPoint: head), lineWidth: 2.4)
        var glow = context
        glow.addFilter(.blur(radius: 6))
        glow.fill(Path(ellipseIn: CGRect(x: head.x - 7, y: head.y - 7, width: 14, height: 14)), with: .color(.white.opacity(0.9 * fade)))
        context.fill(Path(ellipseIn: CGRect(x: head.x - 2, y: head.y - 2, width: 4, height: 4)), with: .color(.white.opacity(fade)))
        // Faint sparks left behind the head.
        var random = MorningSeededRandom(seed: UInt64(abs(Int(p.x * 13 + p.y * 7))))
        for _ in 0..<8 {
            let along = random.range(0.1, 1.0)
            let sx = tail.x + (head.x - tail.x) * along + random.range(-6, 6)
            let sy = tail.y + (head.y - tail.y) * along + random.range(-6, 6)
            context.fill(Path(ellipseIn: CGRect(x: sx - 0.8, y: sy - 0.8, width: 1.6, height: 1.6)),
                         with: .color(.white.opacity(0.7 * fade * along)))
        }
    }
}
