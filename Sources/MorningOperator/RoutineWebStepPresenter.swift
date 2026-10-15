import SwiftUI
import MorningCore
import MorningApple

/// A web moment uses the same persisted timer and guarded Next request as an app
/// moment. Reopening its page never starts a second budget.
private struct RoutineWebStepPresenter: ViewModifier {
    @Bindable var store: MorningStore

    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: Binding(
            get: { store.pendingWebTarget != nil },
            set: { if !$0 { closePage() } }
        )) {
            if let url = store.pendingWebTarget,
               let site = WebMorningSite(url: url),
               let step = store.currentStep,
               let timer = store.activeStepTimer,
               let session = store.session {
                let executionID = MorningExecutionID(sessionID: session.id, routineVersionID: session.routine.id, stepID: step.id)
                let controller = store.routineWebMoment.controller(for: executionID, site: site, initialURL: url)
                WebMorningView(site: site, minutes: step.durationMinutes, initialURL: url,
                    isStepActive: store.session?.status == .running,
                    stepEndsAt: timer.endsAt, timerPausedAt: timer.pausedAt,
                    onExtend: { Task { await store.extendStepTimer(expectedTimer: timer) } },
                    onNext: { store.nextTargetStep(sessionID: timer.sessionID, stepID: timer.stepID) },
                    executionPlan: store.webExecutionPlan,
                    onExecutionEvent: { [weak store] event in store?.receiveWebExecution(event) },
                    executionIsAuthorized: { [weak store] in
                        guard let store else { return false }
                        return !store.privacyBlocksWork && store.session?.id == timer.sessionID &&
                        store.currentStep?.id == timer.stepID && store.session?.status == .running && store.automatic
                    },
                    executionCanAdvance: { [weak store] in
                        guard let store else { return false }
                        return !store.speech.isSpeaking && !store.voiceInputBlocksPlayback
                    },
                    onPause: { store.pause() }, onResume: { store.resume() },
                    retainedController: controller,
                    onClose: closePage)
                    .id(step.id)
            } else {
                VStack(spacing: 24) {
                    MorningDottedIcon(systemName: "globe").frame(width: 48, height: 48)
                        .accessibilityHidden(true)
                    Text("Page unavailable").font(.raleway(.subheadline)).foregroundStyle(MorningStyle.muted)
                    Button { store.pendingWebTarget = nil } label: {
                        MorningDottedIcon(systemName: "xmark").frame(width: 24, height: 24).frame(width: 44, height: 44)
                    }.accessibilityLabel("Close").buttonStyle(.plain)
                }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(MorningPaper(showsSun: false)).foregroundStyle(MorningStyle.ink)
            }
        }
    }
    private func closePage() {
        if store.webExecutionPlan != nil, store.session?.status == .running { store.pause() }
        store.pendingWebTarget = nil
    }
}

extension View {
    func routineWebStep(store: MorningStore) -> some View {
        modifier(RoutineWebStepPresenter(store: store))
    }
}
