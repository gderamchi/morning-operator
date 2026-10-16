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
        let actionBoundary: String?
    }

    private struct ActionStatus {
        let text: String
        var hidesOldInstructions = false
        var priority = 2
        var captionBoundary: String? { hidesOldInstructions ? text : nil }
    }

    /// State may change without TTS. Only this exact session/step can supply it;
    /// uncertain effects take precedence over an older dialogue's review/error.
    private var actionStatus: ActionStatus? {
        guard !store.privacyBlocksWork, store.sessionActive, let session = store.session, let step = store.currentStep else { return nil }
        let context = MorningExecutionID(sessionID: session.id, routineVersionID: session.routine.id, stepID: step.id)
        var statuses: [ActionStatus] = []
        let native = store.nativeMoment
        if native.context == context {
            switch native.phase {
            case .writing: statuses.append(.init(text: french ? "Écriture Apple en cours. Attendez son résultat." : "Apple write in progress. Wait for its result.", hidesOldInstructions: true, priority: 3))
            case .uncertain: statuses.append(.init(text: french ? "Le résultat de l’écriture Apple n’est pas confirmé. Vérifiez Rappels ou Calendrier avant une autre tentative." : "The Apple write is unconfirmed. Check Reminders or Calendar before another attempt.", hidesOldInstructions: true, priority: 4))
            case .unavailable: statuses.append(.init(text: french ? "Cette demande Apple est indisponible. Retrouvez les détails dans Interagir." : "This Apple request is unavailable. Open Interact for details.", hidesOldInstructions: true, priority: 0))
            case .completed: statuses.append(.init(text: french ? "Cette demande Apple est terminée." : "This Apple request is finished.", hidesOldInstructions: true, priority: 1))
            case .reviewing, .awaitingConfirmation, .needsDetails, .choosingReminder:
                statuses.append(.init(text: french ? "Une demande Apple attend votre revue ou vos précisions." : "An Apple request is waiting for your review or details."))
            default: break
            }
        }
        if store.currentSlackContext == context, store.slackReply.context == context {
            switch store.slackReply.phase {
            case .sending: statuses.append(.init(text: french ? "Envoi Slack en cours. Attendez son résultat." : "Slack send in progress. Wait for its result.", hidesOldInstructions: true, priority: 3))
            case .uncertain: statuses.append(.init(text: french ? "La publication Slack n’est pas confirmée. Vérifiez le fil avant une autre tentative ; MORE ne la relance pas." : "The Slack post is unconfirmed. Check the thread before another attempt; MORE will not retry it.", hidesOldInstructions: true, priority: 4))
            case .unavailable: statuses.append(.init(text: french ? "Cette demande Slack est indisponible. Retrouvez les détails dans Interagir." : "This Slack request is unavailable. Open Interact for details.", hidesOldInstructions: true, priority: 0))
            case .completed: statuses.append(.init(text: french ? "La réponse Slack a été publiée. Retrouvez les détails dans Interagir." : "The Slack reply was posted. Open Interact for details.", hidesOldInstructions: true, priority: 1))
            case .preparing: statuses.append(.init(text: french ? "Préparation de votre réponse Slack…" : "Preparing your Slack reply…"))
            case .reviewing, .awaitingConfirmation: statuses.append(.init(text: french ? "Une réponse Slack attend vos précisions ou votre relecture." : "A Slack reply is waiting for your details or review."))
            default: break
            }
        }
        if step.automation == .gmailInbox, store.mailMorning.context == context {
            switch store.mailMorning.state {
            case .sending: statuses.append(.init(text: french ? "Envoi du mail en cours. Attendez son résultat." : "Mail send in progress. Wait for its result.", hidesOldInstructions: true, priority: 3))
            case .uncertain: statuses.append(.init(text: french ? "L’envoi du mail n’est pas confirmé. Vérifiez Gmail avant une autre tentative ; MORE ne le relance pas." : "The mail send is unconfirmed. Check Gmail before another attempt; MORE will not retry it.", hidesOldInstructions: true, priority: 4))
            case .unavailable: statuses.append(.init(text: french ? "Cette demande Gmail est indisponible. Retrouvez les détails dans Interagir." : "This Gmail request is unavailable. Open Interact for details.", hidesOldInstructions: true, priority: 0))
            case .completed: statuses.append(.init(text: french ? "Cette demande Gmail est terminée." : "This Gmail request is finished.", hidesOldInstructions: true, priority: 1))
            case .preparingReply: statuses.append(.init(text: french ? "Préparation de votre mail…" : "Preparing your mail…"))
            case .reviewingReply, .reviewingSelfMessage: statuses.append(.init(text: french ? "Un brouillon Gmail attend vos précisions ou votre relecture." : "A Gmail draft is waiting for your details or review."))
            default: break
            }
        }
        return statuses.max { $0.priority < $1.priority }
    }

    private var visiblePassages: [Passage] {
        guard let boundary = actionStatus?.captionBoundary else { return passages }
        return passages.filter { $0.actionBoundary == boundary }
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
                            if visiblePassages.isEmpty, actionStatus?.hidesOldInstructions == true {
                                Color.clear.frame(height: 1).accessibilityHidden(true)
                            } else if visiblePassages.isEmpty {
                                Text(verbatim: fallback)
                                    .accessibilityIdentifier("morning.caption")
                            } else {
                                ForEach(visiblePassages) { passage in
                                    VStack(alignment: .leading, spacing: 0) {
                                        Color.clear.frame(height: 1).id(passage.id.uuidString).accessibilityHidden(true)
                                        Text(verbatim: passage.text)
                                            .opacity(passage.id == visiblePassages.last?.id ? 1 : 0.65)
                                            .accessibilityIdentifier(passage.id == visiblePassages.last?.id ? "morning.caption" : "morning.previousCaption")
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
                    .onChange(of: visiblePassages.last?.id) { _, id in
                        guard let id else { return }
                        let readingPosition = UnitPoint(x: 0.5, y: 0.15)
                        if still { reader.scrollTo(id.uuidString, anchor: readingPosition) }
                        else { withAnimation(.easeOut(duration: 0.24)) { reader.scrollTo(id.uuidString, anchor: readingPosition) } }
                    }
                }

                if let actionStatus {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(actionStatus.text).font(.raleway(.subheadline, .medium))
                            .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("morning.actionStatus")
                        Button(french ? "Interagir" : "Interact") { showingDetails = true }
                            .font(.raleway(.caption)).frame(minHeight: 44)
                            .accessibilityIdentifier("morning.actionDetails")
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
            guard !store.privacyBlocksWork else { passages.removeAll(); return }
            guard let text = store.speech.currentCaption, !text.isEmpty else { return }
            passages.append(Passage(text: text, actionBoundary: actionStatus?.captionBoundary))
            if passages.count > 24 { passages.removeFirst(passages.count - 24) }
        }
        .onChange(of: actionStatus?.captionBoundary) { _, boundary in
            // Keep any fresh result/Q&A caption already delivered in this same
            // render transaction, while retiring the earlier review instruction.
            if let boundary { passages.removeAll { $0.actionBoundary != boundary } }
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
