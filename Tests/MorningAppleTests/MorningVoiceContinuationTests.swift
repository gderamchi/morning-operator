import Foundation
import Testing
import MorningCore
@testable import MorningApple

@Suite("Informational voice continuation")
struct MorningVoiceContinuationTests {
    @Test("A complete played answer consumes the interrupted running turn once")
    func playedAnswerContinuesOnce() throws {
        var policy = MorningVoiceContinuationPolicy()
        let context = context(), privacy = UUID(), pause = UUID()
        policy.begin(context: context, privacyGeneration: privacy, pauseRevision: pause, wasRunning: true)
        let ticket = try #require(policy.ticket)
        var playback = DuplexSpeechPlaybackLedger()
        playback.begin(ticket.id)
        _ = playback.scheduled(0, id: ticket.id)
        _ = playback.scheduled(1, id: ticket.id)
        let synthesized = playback.synthesized(id: ticket.id)
        let firstBuffer = playback.played(0, id: ticket.id)
        #expect(!synthesized && !firstBuffer)
        #expect(policy.isCurrent(ticket, context: context, privacyGeneration: privacy, pauseRevision: pause))
        let drained = playback.played(1, id: ticket.id)
        let resumed = consume(&policy, ticket, context: context, privacy: privacy, pause: pause, speechFinished: drained)
        let duplicate = consume(&policy, ticket, context: context, privacy: privacy, pause: pause)
        #expect(resumed && !duplicate && policy.ticket == nil)
    }

    @Test("Explicit pause during inference or audio permanently blocks that answer")
    func explicitPauseWins() throws {
        for duringAudio in [false, true] {
            var policy = MorningVoiceContinuationPolicy()
            let context = context(), privacy = UUID(), onsetPause = UUID(), ownerPause = UUID()
            policy.begin(context: context, privacyGeneration: privacy, pauseRevision: onsetPause, wasRunning: true)
            let ticket = try #require(policy.ticket)
            if duringAudio {
                var playback = DuplexSpeechPlaybackLedger()
                playback.begin(ticket.id); _ = playback.scheduled(0, id: ticket.id)
                _ = playback.synthesized(id: ticket.id); _ = playback.played(0, id: ticket.id)
            }
            #expect(!policy.isCurrent(ticket, context: context, privacyGeneration: privacy, pauseRevision: ownerPause))
            let resumed = consume(&policy, ticket, context: context, privacy: privacy, pause: ownerPause)
            #expect(!resumed)
            #expect(!policy.mayInherit(context: context, privacyGeneration: privacy, pauseRevision: ownerPause))
        }
    }

    @Test("A new utterance invalidates the old answer and keeps only current running intent")
    func replacementTurn() throws {
        var policy = MorningVoiceContinuationPolicy()
        let context = context(), privacy = UUID(), pause = UUID()
        policy.begin(context: context, privacyGeneration: privacy, pauseRevision: pause, wasRunning: true)
        let old = try #require(policy.ticket)
        let inherited = policy.mayInherit(context: context, privacyGeneration: privacy, pauseRevision: pause)
        policy.begin(context: context, privacyGeneration: privacy, pauseRevision: pause, wasRunning: inherited)
        let current = try #require(policy.ticket)
        let late = consume(&policy, old, context: context, privacy: privacy, pause: pause)
        policy.discard(old)
        #expect(!late && policy.ticket == current && current.id != old.id)
        let resumed = consume(&policy, current, context: context, privacy: privacy, pause: pause)
        #expect(resumed)
        policy.begin(context: context, privacyGeneration: privacy, pauseRevision: UUID(), wasRunning: false)
        #expect(!policy.mayInherit(context: context, privacyGeneration: privacy, pauseRevision: pause))
    }

    @Test("Failure, background, dialogs, paused origins and unretained work never auto-resume")
    func recoveryGates() throws {
        for blockedGate in 0..<6 {
            var policy = MorningVoiceContinuationPolicy()
            let context = context(), privacy = UUID(), pause = UUID()
            policy.begin(context: context, privacyGeneration: privacy, pauseRevision: pause, wasRunning: blockedGate != 0)
            let ticket = try #require(policy.ticket)
            let resumed = policy.consume(ticket, context: context, privacyGeneration: privacy, pauseRevision: pause,
                speechFinished: blockedGate != 1, isPaused: blockedGate != 2, isForeground: blockedGate != 3,
                hasPendingDialogue: blockedGate == 4, canResumeRetainedExecution: blockedGate != 5)
            #expect(!resumed && policy.ticket == nil)
        }
    }

    @Test("Privacy, moment replacement and stop reject late completions")
    func staleCompletion() throws {
        var policy = MorningVoiceContinuationPolicy()
        let context = context(), privacy = UUID(), pause = UUID()
        for staleGate in 0..<4 {
            policy.begin(context: context, privacyGeneration: privacy, pauseRevision: pause, wasRunning: true)
            let ticket = try #require(policy.ticket)
            if staleGate == 3 { policy.invalidate() }
            let resumed = policy.consume(ticket, context: staleGate == 0 ? self.context() : (staleGate == 1 ? nil : context),
                privacyGeneration: staleGate == 2 ? UUID() : privacy, pauseRevision: pause, speechFinished: true,
                isPaused: true, isForeground: true, hasPendingDialogue: false, canResumeRetainedExecution: true)
            #expect(!resumed)
        }
    }

    @Test("Only read-only questions qualify; effects and editing keep their review boundary")
    func readOnlyQuestions() {
        for question in ["Pourquoi ce choix ?", "Quand est mon prochain rendez-vous", "Que dit cette page",
                         "Explique ce résultat", "Peux-tu m’expliquer ce résultat", "C’est quoi cette actualité",
                         "What is my next appointment?", "Can you explain the result", "Summarize this article"] {
            #expect(MorningHandsFreeVoicePolicy.isInformationalQuestion(question))
        }
        for request in ["Envoie ce message ?", "Could you please send that?", "Est-ce que tu peux ajouter un rappel ?",
                        "Can you create an event?", "Change the title", "Oui", "Envoie", "Une note à moi-même"] {
            #expect(!MorningHandsFreeVoicePolicy.isInformationalQuestion(request))
        }
    }

    private func context() -> MorningVoiceCommandContext {
        .init(sessionID: UUID(), routineVersionID: UUID(), stepID: UUID())
    }

    private func consume(_ policy: inout MorningVoiceContinuationPolicy, _ ticket: MorningVoiceContinuationTicket,
        context: MorningVoiceCommandContext, privacy: UUID, pause: UUID, speechFinished: Bool = true) -> Bool {
        policy.consume(ticket, context: context, privacyGeneration: privacy, pauseRevision: pause,
            speechFinished: speechFinished, isPaused: true, isForeground: true,
            hasPendingDialogue: false, canResumeRetainedExecution: true)
    }
}
