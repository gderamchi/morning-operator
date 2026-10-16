import Foundation
import UIKit
import MorningApple
import MorningCore

extension MorningStore {
    var cloudVoiceContext: MorningCloudVoiceContext {
        .init(binding: handsFreeContext, stepTitle: currentStep?.title ?? "",
              sessionState: session?.status.rawValue ?? "no_active_morning")
    }

    /// Consent belongs to the current session identity (including none) and privacy generation.
    func startCloudVoice() async {
        #if MORE_JURY_DEMO
        cloudVoiceStartIssue = AppLanguage.isFrench
            ? "Cette démo utilise sa propre conversation."
            : "This demo uses its own conversation."
        return
        #else
        guard !privacyBlocksWork, !cloudVoiceReleasing,
              UIApplication.shared.applicationState == .active else { return }
        cloudVoiceStartIssue = nil
        let generation = dataGeneration, sessionID = session?.id
        if session?.status == .running { pause() }
        cancelVoiceCommandTurn()
        do {
            await waitForVoiceInputRelease()
            try Task.checkCancellation()
            guard !voiceInputBlocksPlayback, !voiceCommandPresented,
                  !captureVoicePresented, !capturePresented else { throw MorningCloudVoiceError.unavailable }
            try await handsFreeVoice.stopAndRelease()
            try await speech.stopAndRelease()
            guard !Task.isCancelled, !privacyBlocksWork, dataGeneration == generation,
                  self.session?.id == sessionID, !voiceInputBlocksPlayback,
                  !voiceCommandPresented, !captureVoicePresented, !capturePresented,
                  UIApplication.shared.applicationState == .active else { return }
            cloudVoiceConsentGeneration = generation
            cloudVoiceConsentSession = sessionID
            cloudVoice.onInterruption = { [weak self] in
                guard let self else { return }
                if self.session?.status == .running { self.pause() }
                else { self.speech.stop() }
            }
            await cloudVoice.start(context: cloudVoiceContext,
                                   language: AppLanguage.isFrench ? "fr" : "en", consented: true)
            guard cloudVoice.isActive, cloudVoiceConsentGeneration == generation,
                  !privacyBlocksWork, dataGeneration == generation,
                  self.session?.id == sessionID else {
                let issue = cloudVoice.errorMessage
                stopCloudVoice()
                cloudVoiceStartIssue = issue
                return
            }
            speech.externalSpeech = { [weak self] text in
                guard let self, self.cloudVoice.isActive, !self.privacyBlocksWork,
                      self.cloudVoiceConsentGeneration == self.dataGeneration,
                      self.cloudVoiceConsentSession == self.session?.id else { throw CancellationError() }
                await self.cloudVoice.updateContext(self.cloudVoiceContext)
                try Task.checkCancellation()
                guard self.cloudVoice.isActive, !self.privacyBlocksWork,
                      self.cloudVoiceConsentGeneration == self.dataGeneration,
                      self.cloudVoiceConsentSession == self.session?.id else { throw CancellationError() }
                try await self.cloudVoice.narrate(text)
            }
            speech.cancelExternalSpeech = { [weak self] in self?.cloudVoice.cancelNarration() }
        } catch {
            stopCloudVoice()
            notice = AppLanguage.isFrench ? "Le micro n’a pas pu être libéré. Réessayez." : "The microphone could not be released. Try again."
        }
        #endif
    }

    func stopCloudVoice() {
        guard cloudVoice.isActive || cloudVoiceConsentGeneration != nil ||
                speech.externalSpeech != nil || cloudVoiceReleasing else { return }
        cloudVoiceRequestTask?.cancel()
        if session?.status == .running { pause() }
        cloudVoiceConsentGeneration = nil; cloudVoiceConsentSession = nil
        speech.stop()
        cloudVoice.stop()
        guard !cloudVoiceReleasing else { return }
        cloudVoiceReleasing = true
        Task { [weak self] in
            guard let self else { return }
            await cloudVoice.stopAndRelease()
            speech.externalSpeech = nil; speech.cancelExternalSpeech = nil
            cloudVoiceReleasing = false
        }
    }

    /// Uses the existing source-bound dialogues and their explicit send policies.
    /// The cloud tool receives pending only; provider success comes from app narration.
    func acceptCloudVoiceRequest(_ request: String, binding: MorningVoiceCommandContext) -> Bool {
        guard !privacyBlocksWork, cloudVoice.isActive, cloudVoiceRequestTask == nil,
              cloudVoiceConsentGeneration == dataGeneration, cloudVoiceConsentSession == session?.id,
              handsFreeContext == binding, UIApplication.shared.applicationState == .active else { return false }
        let generation = dataGeneration
        cloudVoiceRequestTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { cloudVoiceRequestTask = nil }
            guard !Task.isCancelled, !privacyBlocksWork, dataGeneration == generation,
                  handsFreeContext == binding, cloudVoice.isActive else { return }
            if handleGoogleCalendarDayUtterance(request) { return }
            if handleCalendlyDayUtterance(request) { return }
            if handleOutlookInboxUtterance(request) { return }
            if await handleSlackUtterance(request) { return }
            if await handleNativeMomentUtterance(request) { return }
            if let handler = handsFreeUtteranceHandler, await handler(request) { return }
            guard !Task.isCancelled, dataGeneration == generation, handsFreeContext == binding,
                  cloudVoice.isActive else { return }
            try? await speech.speakAndWait(AppLanguage.isFrench
                ? "Cette action n’est pas disponible dans le moment actuel. Vous pouvez continuer votre matin ou préciser votre demande."
                : "That action is not available in the current moment. You can continue your morning or clarify the request.")
        }
        return true
    }

    func applyCloudVoiceControl(_ action: MorningCloudVoiceControl,
                               binding: MorningVoiceCommandContext) async throws -> String {
        guard !privacyBlocksWork, cloudVoice.isActive, !Task.isCancelled,
              cloudVoiceConsentGeneration == dataGeneration,
              cloudVoiceConsentSession == session?.id, handsFreeContext == binding,
              UIApplication.shared.applicationState == .active else { throw CancellationError() }
        switch action {
        case .pause:
            if session?.status == .running { pause() }
            guard session?.status == .paused, notice == nil else { throw MorningCloudVoiceError.unavailable }
        case .resume:
            if session?.status == .paused { resume() }
            guard session?.status == .running else { throw MorningCloudVoiceError.unavailable }
        case .next, .skip:
            nextTargetStep(sessionID: binding.sessionID, stepID: binding.stepID, skipping: action == .skip)
            guard currentStep?.id != binding.stepID else { throw MorningCloudVoiceError.unavailable }
        case .stop:
            stop()
            guard !sessionActive else { throw MorningCloudVoiceError.unavailable }
        case .extendTwoMinutes:
            guard activeStepTimer != nil else { throw MorningCloudVoiceError.unavailable }
            await extendStepTimer()
            guard notice == nil else { throw MorningCloudVoiceError.unavailable }
        }
        if cloudVoice.isActive { await cloudVoice.updateContext(cloudVoiceContext) }
        return "The requested routine control is confirmed. Current state: \(session?.status.rawValue ?? "stopped")."
    }
}
