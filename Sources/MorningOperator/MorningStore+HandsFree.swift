import Foundation
import MorningCore
import MorningApple
import UIKit

extension MorningStore {
    var handsFreeVoiceActive: Bool { handsFreeVoice.isActive }
    var handsFreeVoiceStatus: String { handsFreeVoice.message }

    var handsFreeContext: MorningVoiceCommandContext? {
        guard sessionActive, let session, let step = currentStep else { return nil }
        return .init(sessionID: session.id, routineVersionID: session.routine.id, stepID: step.id)
    }

    /// No extra turn button: the approved morning owns listening until it ends,
    /// leaves the foreground, or the person switches it off.
    func startHandsFreeVoice() {
        guard !privacyBlocksWork, automatic, sessionActive, !voiceInputBlocksPlayback,
              !voiceCommandPresented, !captureVoicePresented,
              UIApplication.shared.applicationState == .active else { return }
        #if DEBUG
        // Simulator UI tests exercise typed controls separately from real microphone
        // acceptance; they must not silently simulate successful recognition.
        if ProcessInfo.processInfo.arguments.contains("--ui-testing"),
           !ProcessInfo.processInfo.arguments.contains("--ui-testing-real-microphone") { return }
        #endif
        let language: MorningVoiceCommandLanguage = handsFreeUsesFrench ? .french : .english
        handsFreeVoice.start(language: language, speech: speech, context: { [weak self] in
            self?.handsFreeContext
        }, onSpeech: { [weak self] in
            guard let self, !privacyBlocksWork else { return }
            handsFreeVoice.momentContext = handsFreeMomentContext
            // Capture the context first. Pausing cancels a pending narration/step
            // completion before it can advance under the person's interruption.
            if session?.status == .running {
                handsFreeVoice.interruptedRunningSession = true
                pause()
            } else { speech.stop() }
        }, onUtterance: { [weak self] utterance in
            await self?.receiveHandsFreeUtterance(utterance)
        })
    }

    func stopHandsFreeVoice() { handsFreeVoice.stop() }
    func suspendHandsFreeVoice() { handsFreeVoice.stop() }

    /// Await this inside the existing manual command/capture Task before it
    /// activates its microphone. Merely presenting a sheet is not a release barrier.
    func prepareForManualVoiceInput() async throws {
        try await handsFreeVoice.stopAndRelease()
        try Task.checkCancellation()
    }

    /// Called only for a final locally recognized utterance. Both recognition and
    /// a delayed conversational answer remain pinned to the same session/step.
    func receiveHandsFreeUtterance(_ utterance: MorningHandsFreeUtterance) async {
        guard !privacyBlocksWork, !Task.isCancelled, handsFreeContext == utterance.context,
              !voiceInputBlocksPlayback else { return }
        if let control = MorningHandsFreeVoicePolicy.control(in: utterance.text) {
            let words = MorningHandsFreeVoicePolicy.normalized(utterance.text)
            // In a prepared-reply dialogue, Repeat reads that reply and Continue
            // can decline it. Stop/Pause/Next always retain session-level priority.
            if control == .session(.repeatStep) || words == "continue" || words == "continuer" {
                if let handler = handsFreeUtteranceHandler, await handler(utterance.text) { return }
                guard !Task.isCancelled, handsFreeContext == utterance.context else { return }
            }
            switch control {
            case .session(.pause):
                if session?.status == .running { pause() }
                speakHandsFree(french: "Votre matin est en pause. Dites reprends pour continuer.",
                    english: "Your morning is paused. Say resume to continue.")
            case .session(.resume):
                if session?.status == .paused { resume() }
            case .session(.next), .session(.skip):
                let skipping = control == .session(.skip)
                nextTargetStep(sessionID: utterance.context.sessionID, stepID: utterance.context.stepID, skipping: skipping)
            case .session(.repeatStep): readCurrent()
            case .session(.stop): stop()
            case .extend:
                guard activeStepTimer != nil else {
                    speakHandsFree(french: "Ce moment n'a pas de durée en cours. Dites reprends ou suivant.",
                        english: "This moment has no active timer. Say resume or next.")
                    return
                }
                await extendStepTimer()
                guard !Task.isCancelled, handsFreeContext == utterance.context else { return }
                if session?.status == .paused, handsFreeVoice.interruptedRunningSession { resume() }
                speakHandsFree(french: "Deux minutes ajoutées.", english: "Two minutes added.")
            }
            handsFreeVoice.interruptedRunningSession = false
            return
        }
        if let handler = handsFreeUtteranceHandler, await handler(utterance.text) { return }
        guard !Task.isCancelled, handsFreeContext == utterance.context else { return }
        let context = handsFreeVoice.momentContext.isEmpty ? handsFreeMomentContext : handsFreeVoice.momentContext
        do {
            let answer = try await handsFreeVoice.conversation.answer(utterance.text, context: context)
            guard !Task.isCancelled, !privacyBlocksWork, handsFreeContext == utterance.context else { return }
            speech.speak(answer)
        } catch {
            guard !Task.isCancelled, !privacyBlocksWork, handsFreeContext == utterance.context else { return }
            if error as? MorningVoiceConversationError == .unavailable {
                speakHandsFree(french: "La conversation locale n'est pas disponible sur cet appareil. Vous pouvez dire suivant, pause, reprends, répète, encore deux minutes ou arrête.",
                    english: MorningVoiceConversationError.unavailable.localizedDescription)
            } else {
                speakHandsFree(french: "Je n'ai pas pu préparer de réponse. Réessayez ou dites reprends pour continuer.",
                    english: MorningVoiceConversationError.failed.localizedDescription)
            }
        }
    }

    private var handsFreeMomentContext: String {
        guard let session, let step = currentStep else { return "" }
        var parts = ["Current moment: \(step.title)", "Approved description: \(step.detail)",
                     "Session state: \(session.status.rawValue)"]
        if let document = preparedBriefing(for: step),
           document.isCurrent(at: Date(), timeZoneIdentifier: TimeZone.current.identifier) {
            parts.append("Verified current source information: \(document.spokenText)")
        }
        if let document = currentOpening?.document,
           document.isCurrent(at: Date(), timeZoneIdentifier: TimeZone.current.identifier) {
            parts.append("Verified opening information: \(document.spokenText)")
        }
        return String(parts.joined(separator: "\n").prefix(8_000))
    }

    private func speakHandsFree(french: String, english: String) {
        guard !privacyBlocksWork else { return }
        speech.speak(handsFreeUsesFrench ? french : english)
    }

    private var handsFreeUsesFrench: Bool {
        guard speech.voiceIdentifier != nil, let language = speech.selectedVoice?.language else { return AppLanguage.isFrench }
        return language.hasPrefix("fr")
    }
}
