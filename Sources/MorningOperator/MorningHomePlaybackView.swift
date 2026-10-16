import SwiftUI
import MorningCore
import MorningApple

/// The landscape remains Home. Only spoken passages and a few controls sit over it.
struct MorningHomePlaybackView: View {
    @Bindable var store: MorningStore
    @State private var passages: [Passage] = []
    @State private var showingDetails = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private struct Passage: Identifiable {
        let id = UUID()
        let text: String
    }

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

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(store.currentStep?.title ?? "MORE")
                        .font(.raleway(.subheadline, .medium))
                        .accessibilityIdentifier("morning.currentStep")
                    Spacer(minLength: 0)
                    if let timer = store.activeStepTimer {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(Duration.seconds(timer.remaining(at: context.date).rounded(.up)), format: .time(pattern: .minuteSecond))
                                .font(.raleway(.caption).monospacedDigit())
                                .accessibilityIdentifier("morning.remaining")
                        }
                    }
                }.opacity(0.7)

                ScrollViewReader { reader in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 28) {
                            if passages.isEmpty {
                                Text(verbatim: fallback)
                                    .accessibilityIdentifier("morning.caption")
                            } else {
                                ForEach(passages) { passage in
                                    VStack(alignment: .leading, spacing: 0) {
                                        Color.clear.frame(height: 1).id(passage.id.uuidString).accessibilityHidden(true)
                                        Text(verbatim: passage.text)
                                            .opacity(passage.id == passages.last?.id ? 1 : 0.45)
                                            .accessibilityIdentifier(passage.id == passages.last?.id ? "morning.caption" : "morning.previousCaption")
                                    }
                                }
                            }
                        }
                        .font(.raleway(.title2))
                        .lineSpacing(7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, geometry.size.height * 0.28)
                        .padding(.bottom, geometry.size.height * 0.2)
                        .textSelection(.enabled)
                    }
                    .scrollIndicators(.hidden)
                    .mask {
                        LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.08),
                                               .init(color: .black, location: 0.94), .init(color: .clear, location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                    .accessibilityIdentifier("morning.captions")
                    .onChange(of: passages.last?.id) { _, id in
                        guard let id else { return }
                        let readingPosition = UnitPoint(x: 0.5, y: 0.15)
                        if still { reader.scrollTo(id.uuidString, anchor: readingPosition) }
                        else { withAnimation(.easeOut(duration: 0.24)) { reader.scrollTo(id.uuidString, anchor: readingPosition) } }
                    }
                }

                if let notice = store.notice, notice != store.connectedActionStatus {
                    Text(notice).font(.raleway(.caption)).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("app.notice")
                }
                if store.currentOpening != nil {
                    Button(french ? "Continuer" : "Continue") { store.chooseOpening(.ritual) }
                        .frame(minHeight: 44).accessibilityIdentifier("opening.routine")
                }
                HStack(spacing: 24) {
                    Button {
                        if store.session?.status == .paused { store.resume() } else { store.pause() }
                    } label: {
                        Image(systemName: store.session?.status == .paused ? "play.fill" : "pause.fill")
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .accessibilityLabel(store.session?.status == .paused ? (french ? "Continuer" : "Continue") : "Pause")
                    .accessibilityIdentifier("morning.playback")
                    Spacer(minLength: 0)
                    Button {
                        store.nextTargetStep(sessionID: store.session?.id, stepID: store.currentStep?.id)
                    } label: {
                        Image(systemName: "forward.end").frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .accessibilityLabel(french ? "Suivant" : "Next")
                    .accessibilityIdentifier("morning.next")
                    Menu {
                        if store.activeStepTimer != nil {
                            Button("+2 min") { Task { await store.extendStepTimer() } }
                                .accessibilityIdentifier("morning.extend")
                        }
                        if case let .inAppWeb(url) = store.currentStep?.target {
                            Button(french ? "Ouvrir la page" : "Open page") { store.pendingWebTarget = url }
                                .accessibilityIdentifier("stepTimer.openPage")
                        }
                        Button(french ? "Interagir" : "Interact") { showingDetails = true }
                            .accessibilityIdentifier("morning.details")
                        Button(french ? "Arrêter mon matin" : "Stop my morning", role: .destructive) { store.stop() }
                            .accessibilityIdentifier("morning.stop")
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .accessibilityLabel(french ? "Plus" : "More")
                    .accessibilityIdentifier("morning.more")
                }
                .font(.system(size: 18, weight: .regular)).buttonStyle(.plain)
            }
            .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 12)
            .frame(maxWidth: 640).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: store.speech.captionRevision, initial: true) { _, _ in
            guard let text = store.speech.currentCaption, !text.isEmpty else { return }
            passages.append(Passage(text: text))
            if passages.count > 24 { passages.removeFirst(passages.count - 24) }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .background { passages.removeAll(); showingDetails = false } }
        .sheet(isPresented: $showingDetails) { interaction }
    }

    private var interaction: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let status = store.connectedActionStatus {
                        Text(status).textSelection(.enabled).accessibilityIdentifier("moment.connectedResult")
                    }
                    if store.currentStep?.automation == .gmailInbox { MorningMailMomentView(store: store) }
                    NativeMomentReviewView(store: store)
                    if store.currentSlackContext != nil { SlackMomentReplyView(store: store) }
                    if store.currentGoogleCalendarDayContext != nil { GoogleCalendarDayMomentView(store: store) }
                    if store.currentCalendlyDayContext != nil { CalendlyDayMomentView(store: store) }
                    if store.currentOutlookInboxContext != nil { OutlookInboxMomentView(store: store) }
                    if store.session?.status == .paused,
                       store.currentStep?.automation == .todayCalendar || store.currentStep?.automation == .morningBriefing {
                        Button("Update this recap") { store.updateCurrentBriefing() }
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
