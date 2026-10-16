import SwiftUI
import MorningCore
import MorningApple

/// The landscape remains Home. Only spoken passages and a few controls sit over it.
struct MorningHomePlaybackView: View {
    @Bindable var store: MorningStore
    var openSettings: () -> Void
    @State private var displayedCaption: String?
    @State private var showingDetails = false
    @State private var controlsVisible = false
    @State private var controlsInteraction = UUID()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.scenePhase) private var scenePhase

    private var french: Bool { AppLanguage.isFrench }
    private var still: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-reduce-motion") { return true }
        #endif
        return reduceMotion
    }
    private var fallback: String {
        if let opening = store.currentOpening {
            return opening.briefText ?? opening.opening?.displayText
                ?? (french ? "Je prépare votre journée…" : "Preparing your day…")
        }
        return store.connectedActionStatus ?? store.currentStep?.detail ?? ""
    }
    private var caption: String {
        if let notice = store.notice, !notice.isEmpty { return notice }
        if let displayedCaption { return displayedCaption }
        let text = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > 110 else { return text }
        let preview = text.prefix(110)
        let end = preview.lastIndex(where: { $0.isWhitespace }) ?? preview.endIndex
        return String(preview[..<end]) + "…"
    }
    private var controlsLabel: String {
        controlsVisible ? (french ? "Masquer les commandes" : "Hide controls")
            : (french ? "Afficher les commandes" : "Show controls")
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                ScrollView {
                    Text(verbatim: caption)
                        .font(.raleway(.title2)).lineSpacing(7)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 540, minHeight: max(0, geometry.size.height - 160), alignment: .leading)
                        .padding(.horizontal, 28).padding(.vertical, 80)
                        .frame(maxWidth: .infinity)
                        .contentTransition(.opacity)
                        .animation(.easeOut(duration: still ? 0.12 : 0.22), value: caption)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("morning.caption")
                        .accessibilityAction(named: Text(controlsLabel), toggleControls)
                }
                .scrollIndicators(.hidden)
                .contentShape(Rectangle())
                .onTapGesture(perform: toggleControls)
                .accessibilityIdentifier("morning.captions")
                #if DEBUG
                .accessibilityValue(ProcessInfo.processInfo.arguments.contains("--ui-testing")
                    ? "\(store.session?.id.uuidString ?? "")|\(store.currentStep?.id.uuidString ?? "")" : "")
                #endif
                .accessibilityAction(named: Text(controlsLabel), toggleControls)

                if controlsVisible {
                    controls
                        .padding(.horizontal, 28).padding(.bottom, 12)
                        .transition(.opacity)
                }
            }
        }
        .onChange(of: store.speech.captionRevision, initial: true) { _, _ in
            guard let text = store.speech.currentCaption, !text.isEmpty else { return }
            // The spoken step label is metadata; Home shows only its content.
            let prefix = (store.currentStep?.title ?? "") + "."
            displayedCaption = text.hasPrefix(prefix)
                ? String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines) : text
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { displayedCaption = nil; controlsVisible = false; showingDetails = false }
        }
        .onChange(of: AppLanguage.code) { _, _ in displayedCaption = nil; showingDetails = false }
        .onChange(of: showingDetails) { _, presented in
            store.morningDetailPresented = presented
            if presented { store.pause() } else { keepControlsVisible() }
        }
        .onDisappear { store.morningDetailPresented = false }
        .onChange(of: voiceOverEnabled) { _, _ in if controlsVisible { controlsInteraction = UUID() } }
        .task(id: controlsInteraction) {
            guard controlsVisible, !voiceOverEnabled, !showingDetails else { return }
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            guard !Task.isCancelled, !voiceOverEnabled, !showingDetails else { return }
            withAnimation(.easeOut(duration: 0.15)) { controlsVisible = false }
        }
        .sheet(isPresented: $showingDetails) { interaction }
    }

    private func toggleControls() {
        withAnimation(.easeOut(duration: 0.15)) { controlsVisible.toggle() }
        controlsInteraction = UUID()
    }

    private func keepControlsVisible() {
        controlsVisible = true
        controlsInteraction = UUID()
    }

    private var controls: some View {
        VStack(spacing: 12) {
            if store.currentOpening != nil {
                Button(french ? "Continuer" : "Continue") {
                    keepControlsVisible(); store.chooseOpening(.ritual)
                }.frame(minHeight: 44).accessibilityIdentifier("opening.routine")
            }
            HStack(spacing: 24) {
                Button {
                    keepControlsVisible()
                    if store.session?.status == .paused { store.resume() } else { store.pause() }
                } label: {
                    Image(systemName: store.session?.status == .paused ? "play.fill" : "pause.fill")
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel(store.session?.status == .paused ? (french ? "Continuer" : "Continue") : "Pause")
                .accessibilityIdentifier("morning.playback")
                Spacer(minLength: 0)
                Button {
                    keepControlsVisible()
                    store.nextTargetStep(sessionID: store.session?.id, stepID: store.currentStep?.id)
                } label: {
                    Image(systemName: "forward.end").frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel(french ? "Suivant" : "Next")
                .accessibilityIdentifier("morning.next")
                Menu {
                    if let timer = store.activeStepTimer {
                        Button("+2 min") {
                            keepControlsVisible()
                            Task { await store.extendStepTimer(expectedTimer: timer) }
                        }.accessibilityIdentifier("morning.extend")
                    }
                    if case let .inAppWeb(url) = store.currentStep?.target {
                        Button(french ? "Ouvrir la page" : "Open page") {
                            keepControlsVisible(); store.pendingWebTarget = url
                        }.accessibilityIdentifier("stepTimer.openPage")
                    }
                    Button(french ? "Interagir" : "Interact") {
                        keepControlsVisible(); showingDetails = true
                    }.accessibilityIdentifier("morning.details")
                    Button(String(localized: "Settings", bundle: AppLanguage.bundle(), locale: AppLanguage.locale), action: openSettings)
                        .accessibilityIdentifier("morning.settings")
                    Button(french ? "Arrêter mon matin" : "Stop my morning", role: .destructive) { store.stop() }
                        .accessibilityIdentifier("morning.stop")
                } label: {
                    Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .simultaneousGesture(TapGesture().onEnded { keepControlsVisible() })
                .accessibilityLabel(french ? "Plus" : "More")
                .accessibilityIdentifier("morning.more")
            }
            .font(.system(size: 18, weight: .regular)).buttonStyle(.plain)
        }
    }

    private var interaction: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !fallback.isEmpty {
                        Text(fallback).textSelection(.enabled)
                            .accessibilityIdentifier(store.connectedActionStatus == nil ? "moment.instructions" : "moment.connectedResult")
                    }
                    if store.currentStep?.automation == .gmailInbox { MorningMailMomentView(store: store) }
                    NativeMomentReviewView(store: store)
                    if store.currentSlackContext != nil { SlackMomentReplyView(store: store) }
                    if store.currentGoogleCalendarDayContext != nil { GoogleCalendarDayMomentView(store: store) }
                    if store.currentCalendlyDayContext != nil { CalendlyDayMomentView(store: store) }
                    if store.currentOutlookInboxContext != nil { OutlookInboxMomentView(store: store) }
                    if store.session?.status == .paused,
                       store.currentStep?.automation == .todayCalendar || store.currentStep?.automation == .morningBriefing {
                        Button(String(localized: "Update this recap", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)) { store.updateCurrentBriefing() }
                            .disabled(store.nativeMoment.isActive || store.voiceInputBlocksPlayback)
                            .accessibilityIdentifier("briefing.updateCurrent")
                    }
                    Text(store.handsFreeVoiceStatus).font(.caption).accessibilityIdentifier("morning.voiceStatus")
                }.padding(24).frame(maxWidth: 640, alignment: .leading).frame(maxWidth: .infinity)
            }
            .background(MorningPaper(showsSun: false))
            .navigationTitle(store.currentStep?.title ?? "MORE").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button(french ? "Fermer" : "Close") { showingDetails = false }
                    .accessibilityIdentifier("morning.closeDetails")
            } }
        }
        .preferredColorScheme(.light)
    }
}
