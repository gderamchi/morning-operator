import Foundation
import UIKit
import MorningApple
import MorningCore

struct MorningNaturalSpeechConsent: Equatable {
    let generation: UUID
    let sessionID: UUID?
    let routineVersionID: UUID?
    let languageCode: String
}

extension MorningStore {
    var naturalSpeechScope: MorningNaturalSpeechConsent {
        .init(generation: dataGeneration, sessionID: session?.id,
              routineVersionID: session?.routine.id ?? routine?.id, languageCode: AppLanguage.code)
    }

    var hasNaturalSpeechConsent: Bool { naturalSpeechConsent == naturalSpeechScope }
    var hasNaturalSpeechDecision: Bool { hasNaturalSpeechConsent || naturalSpeechDeclined == naturalSpeechScope }

    func configureNaturalSpeech() {
        speech.cloudSpeech = nil
        guard hasNaturalSpeechConsent, !naturalSpeechFailed, !privacyBlocksWork else { return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing"),
           !ProcessInfo.processInfo.arguments.contains("--ui-testing-real-voice-provider") { return }
        #endif
        let scope = naturalSpeechScope
        speech.cloudSpeech = { [weak self] text, gender in
            guard let self else { throw CancellationError() }
            try checkNaturalSpeechScope(scope)
            guard hasNaturalSpeechConsent, !naturalSpeechFailed else { throw CancellationError() }
            let data = try await composio.morningSpeech(text, language: scope.languageCode, voiceGender: gender)
            try checkNaturalSpeechScope(scope)
            guard speech.voiceGender == gender else { throw CancellationError() }
            return data
        }
        speech.externalSpeechFallback = { [weak self] in
            guard let self else { throw CancellationError() }
            try await useAppleVoiceAfterFailure(scope: scope)
        }
    }

    private func checkNaturalSpeechScope(_ scope: MorningNaturalSpeechConsent) throws {
        try Task.checkCancellation()
        guard !privacyBlocksWork, naturalSpeechScope == scope,
              UIApplication.shared.applicationState == .active else { throw CancellationError() }
    }

    /// Only approved app narration may continue. Never replay a tool, request or agent caption.
    private func useAppleVoiceAfterFailure(scope: MorningNaturalSpeechConsent) async throws {
        try checkNaturalSpeechScope(scope)
        naturalSpeechFailed = true
        speech.cloudSpeech = nil
        cloudVoice.onUserText = nil
        cloudVoiceConsentGeneration = nil; cloudVoiceConsentSession = nil
        await cloudVoice.stopAndRelease()
        try checkNaturalSpeechScope(scope)
        speech.externalSpeech = nil; speech.cancelExternalSpeech = nil
        cloudVoiceReleasing = false
        voiceFallbackMessage = AppLanguage.isFrench ? "La voix de secours est activée." : "Backup voice is active."
    }

    func cloudConversationFailed() {
        guard cloudVoiceConsentGeneration != nil, cloudVoiceFallbackTask == nil else { return }
        let scope = naturalSpeechScope
        cloudVoiceFallbackTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { cloudVoiceFallbackTask = nil }
            do {
                try await useAppleVoiceAfterFailure(scope: scope)
                startHandsFreeVoice()
            } catch { }
        }
    }

    func voicePreferenceChanged() {
        stopCloudVoice()
        speech.stop()
        naturalSpeechFailed = false; voiceFallbackMessage = nil
        configureNaturalSpeech()
        saveVoicePreference()
    }

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
        voiceFallbackMessage = nil
        let attempt = UUID(), generation = dataGeneration, sessionID = session?.id
        let languageGeneration = voiceLanguageGeneration
        cloudVoiceStartAttempt = attempt
        defer { if cloudVoiceStartAttempt == attempt { cloudVoiceStartAttempt = nil } }
        func checkCurrentStart() throws {
            try Task.checkCancellation()
            guard cloudVoiceStartAttempt == attempt, dataGeneration == generation,
                  voiceLanguageGeneration == languageGeneration, self.session?.id == sessionID,
                  !privacyBlocksWork, !voiceInputBlocksPlayback, !voiceCommandPresented,
                  !captureVoicePresented, !capturePresented,
                  UIApplication.shared.applicationState == .active else { throw CancellationError() }
        }
        if session?.status == .running { pause() }
        cancelVoiceCommandTurn()
        do {
            await waitForVoiceInputRelease()
            try checkCurrentStart()
            try await handsFreeVoice.stopAndRelease()
            try checkCurrentStart()
            try await speech.stopAndRelease()
            try checkCurrentStart()
            cloudVoiceConsentGeneration = generation
            cloudVoiceConsentSession = sessionID
            cloudVoice.onInterruption = { [weak self] in
                guard let self else { return }
                if self.session?.status == .running { self.pause() }
                else { self.speech.stop() }
            }
            cloudVoice.onUserText = { [weak self] text, turn in
                self?.receiveCloudVoiceOwnerText(text, turn: turn)
            }
            await cloudVoice.start(context: cloudVoiceContext,
                                   language: AppLanguage.isFrench ? "fr" : "en", consented: true,
                                   voiceGender: speech.voiceGender)
            try checkCurrentStart()
            guard cloudVoice.isActive, cloudVoiceConsentGeneration == generation,
                  !privacyBlocksWork, dataGeneration == generation,
                  self.session?.id == sessionID else {
                stopCloudVoice()
                cloudVoiceStartIssue = nil
                voiceFallbackMessage = AppLanguage.isFrench ? "La voix de secours est activée." : "Backup voice is active."
                startHandsFreeVoice()
                return
            }
            let scope = naturalSpeechScope
            speech.externalSpeechFallback = { [weak self] in
                guard let self else { throw CancellationError() }
                try await useAppleVoiceAfterFailure(scope: scope)
            }
            speech.externalSpeech = { [weak self] text in
                guard let self, self.cloudVoice.isActive, !self.privacyBlocksWork,
                      self.cloudVoiceConsentGeneration == self.dataGeneration,
                      self.cloudVoiceConsentSession == self.session?.id else { throw CancellationError() }
                let turn = self.cloudVoice.userTurnID
                await self.cloudVoice.updateContext(self.cloudVoiceContext)
                try Task.checkCancellation()
                guard self.cloudVoice.isActive, !self.privacyBlocksWork,
                      self.cloudVoiceConsentGeneration == self.dataGeneration,
                      self.cloudVoiceConsentSession == self.session?.id,
                      self.cloudVoice.userTurnID == turn else { throw CancellationError() }
                try await self.cloudVoice.narrate(text, forUserTurn: turn)
            }
            speech.cancelExternalSpeech = { [weak self] in self?.cloudVoice.cancelNarration() }
        } catch {
            guard cloudVoiceStartAttempt == attempt else { return }
            stopCloudVoice()
            if !(error is CancellationError) {
                notice = AppLanguage.isFrench ? "Le micro n’a pas pu être libéré. Réessayez." : "The microphone could not be released. Try again."
            }
        }
        #endif
    }

    func stopCloudVoice() {
        cloudVoiceFallbackTask?.cancel(); cloudVoiceFallbackTask = nil
        cloudVoiceStartAttempt = nil
        guard cloudVoice.isActive || cloudVoiceConsentGeneration != nil ||
                speech.externalSpeech != nil || cloudVoiceReleasing else { return }
        cloudVoiceRequestTask?.cancel()
        cloudVoiceMemoryTask?.cancel()
        cloudVoice.onUserText = nil
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
            configureNaturalSpeech()
        }
    }

    /// The SDK microphone callback is the only cloud provenance accepted for
    /// learning. Extraction follows the already selected Apple/OpenAI route;
    /// remembered facts are never added to the ElevenLabs context payload.
    private func receiveCloudVoiceOwnerText(_ text: String?, turn: UUID) {
        cloudVoiceRequestTask?.cancel()
        cloudVoiceMemoryTask?.cancel()
        speech.stop()
        let generation = dataGeneration, sessionID = session?.id
        let languageGeneration = voiceLanguageGeneration
        let modelConfiguration = MoreLanguageModel.shared.configurationID
        guard let text, cloudVoiceTurnIsCurrent(turn, generation: generation, sessionID: sessionID,
            languageGeneration: languageGeneration, modelConfiguration: modelConfiguration) else { return }
        cloudVoiceMemoryTurnID = turn
        cloudVoiceMemoryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if cloudVoiceMemoryTurnID == turn { cloudVoiceMemoryTask = nil; cloudVoiceMemoryTurnID = nil }
            }
            guard !Task.isCancelled, cloudVoiceTurnIsCurrent(turn, generation: generation, sessionID: sessionID,
                languageGeneration: languageGeneration, modelConfiguration: modelConfiguration) else { return }
            await MorePersonalMemory.shared.remember(fromOwnerUtterance: text, whileCurrent: { [weak self] in
                self?.cloudVoiceTurnIsCurrent(turn, generation: generation, sessionID: sessionID,
                    languageGeneration: languageGeneration, modelConfiguration: modelConfiguration) == true
            })
        }
    }

    private func cloudVoiceTurnIsCurrent(_ turn: UUID, generation: UUID, sessionID: UUID?,
                                        languageGeneration: UUID, modelConfiguration: UUID) -> Bool {
        !privacyBlocksWork && cloudVoice.isCurrentUserTurn(turn) && dataGeneration == generation &&
            cloudVoiceConsentGeneration == generation && cloudVoiceConsentSession == sessionID &&
            session?.id == sessionID && voiceLanguageGeneration == languageGeneration &&
            MoreLanguageModel.shared.configurationID == modelConfiguration &&
            UIApplication.shared.applicationState == .active
    }

    /// Uses the existing source-bound dialogues and their explicit send policies.
    /// The cloud tool receives pending only; provider success comes from app narration.
    func acceptCloudVoiceRequest(_ request: String, binding: MorningVoiceCommandContext) -> Bool {
        guard !privacyBlocksWork, cloudVoice.isActive,
              cloudVoiceRequestTask == nil || cloudVoiceRequestTask?.isCancelled == true,
              cloudVoiceConsentGeneration == dataGeneration, cloudVoiceConsentSession == session?.id,
              let turn = cloudVoice.userTurnID, handsFreeContext == binding,
              UIApplication.shared.applicationState == .active else { return false }
        let generation = dataGeneration, sessionID = session?.id
        let languageGeneration = voiceLanguageGeneration
        let modelConfiguration = MoreLanguageModel.shared.configurationID
        let memoryTask = cloudVoiceMemoryTask
        cloudVoiceRequestTurnID = turn
        cloudVoiceRequestTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if cloudVoiceRequestTurnID == turn { cloudVoiceRequestTask = nil; cloudVoiceRequestTurnID = nil }
            }
            guard !Task.isCancelled, handsFreeContext == binding,
                  cloudVoiceTurnIsCurrent(turn, generation: generation, sessionID: sessionID,
                    languageGeneration: languageGeneration, modelConfiguration: modelConfiguration) else { return }
            if handleGoogleCalendarDayUtterance(request) { return }
            if handleCalendlyDayUtterance(request) { return }
            if handleOutlookInboxUtterance(request) { return }
            if await handleSlackUtterance(request) { return }
            if await handleNativeMomentUtterance(request) { return }
            if let handler = handsFreeUtteranceHandler, await handler(request) { return }
            await memoryTask?.value
            guard !Task.isCancelled, handsFreeContext == binding,
                  cloudVoiceTurnIsCurrent(turn, generation: generation, sessionID: sessionID,
                    languageGeneration: languageGeneration, modelConfiguration: modelConfiguration) else { return }
            let answer: String
            do {
                answer = try await handsFreeVoice.conversation.answer(request, context: handsFreeMomentContext,
                    language: voicePreparationLanguage, learnFromOwner: false)
            } catch {
                guard !(error is CancellationError), !Task.isCancelled, handsFreeContext == binding,
                      cloudVoiceTurnIsCurrent(turn, generation: generation, sessionID: sessionID,
                        languageGeneration: languageGeneration, modelConfiguration: modelConfiguration) else { return }
                try? await speech.speakAndWait((error as? MorningVoiceConversationError ?? .failed).moreDescription)
                return
            }
            guard !Task.isCancelled, handsFreeContext == binding,
                  cloudVoiceTurnIsCurrent(turn, generation: generation, sessionID: sessionID,
                    languageGeneration: languageGeneration, modelConfiguration: modelConfiguration) else { return }
            try? await speech.speakAndWait(answer)
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
