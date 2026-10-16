import Foundation
import MorningApple
import MorningCore

extension MorningStore {
    @discardableResult
    func addOutlookInboxMoment(connection: ComposioConnection, identity: OutlookIdentity) -> Bool {
        guard !privacyBlocksWork, !sessionActive, !busy, connection.isActive, connection.service == "outlook",
              identity.connectionID == connection.id, identity.isCurrent(at: Date()) else { return false }
        do {
            try identity.target.validate()
            let account = identity.target.sourceLabel()
            let detail = AppLanguage.isFrench
                ? "Présenter jusqu’à trois messages non lus dans la boîte de réception de « \(account) », y compris des messages plus anciens. Les aperçus sont limités. Lire un message choisi à votre demande. Aucun message n’est envoyé, déplacé ou marqué comme lu."
                : "Present up to three unread Inbox messages for “\(account)”, including older mail. Previews are limited. Read one selected message when you ask. No messages are sent, moved or marked as read."
            guard addConnectedStep(.init(title: "Outlook · \(account)", detail: detail, kind: .messages,
                                        durationMinutes: 3, target: .outlookInbox(identity.target))) else { return false }
            notice = AppLanguage.isFrench ? "Boîte Outlook ajoutée au brouillon. Relisez et validez votre routine."
                : "Outlook Inbox added to your draft. Review and approve your routine."
            return true
        } catch { notice = OutlookInboxError.invalidIdentity.localizedDescription; return false }
    }

    var currentOutlookInboxContext: MorningExecutionID? {
        guard !privacyBlocksWork, sessionActive, let session, let step = currentStep,
              case .outlookInbox = step.target else { return nil }
        return .init(sessionID: session.id, routineVersionID: session.routine.id, stepID: step.id)
    }
    var currentOutlookInbox: OutlookInboxDocument? {
        guard let context = currentOutlookInboxContext, outlookInboxContext == context,
              outlookInboxPrivacyGeneration == localPrivacyGeneration,
              let source = outlookInboxDocument, source.isCurrent(at: Date()) else { return nil }
        return source
    }
    var currentOutlookMessage: OutlookMessageDocument? {
        guard let source = currentOutlookInbox, let message = outlookMessageDocument,
              message.target == source.target, message.sourceCutoff == source.cutoff,
              source.messages.contains(message.message), message.isCurrent(at: Date()) else { return nil }
        return message
    }

    func runOutlookInbox(_ target: OutlookInboxTarget, sessionID: UUID, stepID: UUID) {
        guard !privacyBlocksWork, let session, session.id == sessionID, session.status == .running,
              session.routine.isApproved, let step = currentStep, step.id == stepID, step.target == .outlookInbox(target),
              let context = currentOutlookInboxContext, outlookAllowsReading else { return }
        if connectedMoment.executionID == context, connectedMoment.isInFlight, connectedAPITask != nil { return }
        if let source = currentOutlookInbox {
            presentOutlookReading(source: source, message: currentOutlookMessage, context: context)
            return
        }
        guard let attempt = connectedMoment.begin(executionID: context, record: currentExecutionRecord) else {
            pauseOutlookForRefresh(); return
        }
        loadOutlookInbox(target, context: context, attempt: attempt)
    }

    func refreshOutlookInbox() {
        guard let context = currentOutlookInboxContext, case let .outlookInbox(target) = currentStep?.target,
              outlookAllowsReading else { return }
        if session?.status == .running { pause() }
        connectedAPITask?.cancel(); connectedAPITask = nil
        clearOutlookInbox(); connectedMoment.clear()
        guard let attempt = connectedMoment.begin(executionID: context, record: nil) else { return }
        loadOutlookInbox(target, context: context, attempt: attempt)
    }

    /// Reuses both the chosen message and the original three previews. No HTTP.
    @discardableResult
    func repeatOutlookReading() -> Bool {
        guard let context = currentOutlookInboxContext else { return false }
        guard outlookAllowsReading else { return true }
        if connectedMoment.executionID == context, connectedAPITask != nil,
           connectedMoment.phase == .preparing || connectedMoment.phase == .dispatching {
            outlookSay(AppLanguage.isFrench ? "La lecture Outlook est encore en cours. Attendez son résultat avant de la relire."
                : "The Outlook reading is still in progress. Wait for its result before reading it again.")
            return true
        }
        guard let source = currentOutlookInbox else { pauseOutlookForRefresh(); return true }
        if session?.status == .running { pause() }
        presentOutlookReading(source: source, message: currentOutlookMessage, context: context)
        return true
    }

    func readOutlookMessage(id: String) {
        guard let context = currentOutlookInboxContext, outlookAllowsReading else { return }
        guard let source = currentOutlookInbox else { pauseOutlookForRefresh(); return }
        guard source.messages.contains(where: { $0.id == id }) else {
            outlookSay(AppLanguage.isFrench ? "Choisissez le premier, le deuxième ou le troisième message présenté."
                : "Choose the first, second or third message that was presented.")
            return
        }
        if session?.status == .running { pause() }
        handsFreeVoice.interruptedRunningSession = false
        connectedAPITask?.cancel(); connectedMoment.clear()
        guard let attempt = connectedMoment.begin(executionID: context, record: nil) else { return }
        let generation = dataGeneration, privacyGeneration = localPrivacyGeneration
        outlookMessageDocument = nil
        connectedActionStatus = AppLanguage.isFrench ? "Lecture du message Outlook choisi…" : "Reading the selected Outlook message…"
        connectedAPITask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if connectedMoment.matches(attempt, executionID: context) { connectedAPITask = nil } }
            do {
                let message = try await OutlookInboxService(service: composio).message(id: id, from: source)
                try Task.checkCancellation()
                guard outlookIsCurrent(context, generation: generation, privacyGeneration: privacyGeneration),
                      currentOutlookInbox == source, connectedMoment.matches(attempt, executionID: context) else { return }
                guard message.isCurrent(at: Date()) else { throw OutlookInboxError.staleSource }
                try receiveOutlookSource(source: source, message: message, context: context, attempt: attempt)
                outlookMessageDocument = message
                await presentOutlookNow(source: source, message: message, context: context, attempt: attempt,
                    generation: generation, privacyGeneration: privacyGeneration)
            } catch {
                outlookFailed(error, context: context, attempt: attempt, generation: generation, privacyGeneration: privacyGeneration)
            }
        }
    }

    @discardableResult
    func handleOutlookInboxUtterance(_ text: String) -> Bool {
        guard currentOutlookInboxContext != nil else { return false }
        let words = MorningHandsFreeVoicePolicy.normalized(text)
        if ["actualise outlook", "actualise ma boite outlook", "actualise mes mails outlook", "refresh outlook", "refresh my outlook inbox"].contains(words) {
            refreshOutlookInbox(); return true
        }
        let choices = [
            ["lis le premier message", "lis le premier mail", "ouvre le premier message", "read the first message", "read the first email", "open the first message", "read message 1"],
            ["lis le deuxieme message", "lis le deuxieme mail", "ouvre le deuxieme message", "read the second message", "read the second email", "open the second message", "read message 2"],
            ["lis le troisieme message", "lis le troisieme mail", "ouvre le troisieme message", "read the third message", "read the third email", "open the third message", "read message 3"]
        ]
        guard let index = choices.firstIndex(where: { $0.contains(words) }) else { return false }
        guard outlookAllowsReading else { return true }
        guard let source = currentOutlookInbox else { pauseOutlookForRefresh(); return true }
        guard source.messages.indices.contains(index) else {
            outlookSay(AppLanguage.isFrench ? "Ce message ne fait pas partie des aperçus reçus. Choisissez un message présenté, ou actualisez Outlook."
                : "That message is not among the received previews. Choose a presented message or refresh Outlook.")
            return true
        }
        readOutlookMessage(id: source.messages[index].id); return true
    }

    func clearOutlookInbox() {
        outlookInboxFreshnessTask?.cancel(); outlookInboxFreshnessTask = nil
        outlookInboxDocument = nil; outlookMessageDocument = nil
        outlookInboxContext = nil; outlookInboxPrivacyGeneration = nil
    }

    func checkOutlookInboxFreshness() {
        guard session?.status == .running, let context = currentOutlookInboxContext,
              outlookInboxContext == context, outlookInboxPrivacyGeneration == localPrivacyGeneration,
              let source = outlookInboxDocument, !source.isCurrent(at: Date()) else { return }
        pauseOutlookForRefresh()
    }

    private var outlookAllowsReading: Bool {
        guard !nativeMoment.isActive, !slackReply.isActive, mailMorning.state != .sending, mailMorning.state != .uncertain,
              currentExecutionRecord?.outcome != .uncertain else {
            outlookSay(AppLanguage.isFrench ? "Terminez ou vérifiez la demande en cours avant de lire Outlook. Une action dont le résultat est inconnu n’est pas relancée."
                : "Finish or verify the current request before reading Outlook. An action with an unknown outcome is not repeated.")
            return false
        }
        return true
    }

    private func loadOutlookInbox(_ target: OutlookInboxTarget, context: MorningExecutionID, attempt: UUID) {
        let generation = dataGeneration, privacyGeneration = localPrivacyGeneration
        outlookInboxContext = context; outlookInboxPrivacyGeneration = privacyGeneration
        connectedAPITask?.cancel()
        connectedActionStatus = AppLanguage.isFrench ? "Lecture des aperçus Outlook de \(target.sourceLabel())…"
            : "Reading Outlook previews for \(target.sourceLabel())…"
        connectedAPITask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if connectedMoment.matches(attempt, executionID: context) { connectedAPITask = nil } }
            do {
                let source = try await OutlookInboxService(service: composio).read(target: target)
                try Task.checkCancellation()
                guard outlookIsCurrent(context, generation: generation, privacyGeneration: privacyGeneration),
                      connectedMoment.matches(attempt, executionID: context) else { return }
                guard source.isCurrent(at: Date()) else { throw OutlookInboxError.staleSource }
                try receiveOutlookSource(source: source, message: nil, context: context, attempt: attempt)
                outlookInboxDocument = source; outlookMessageDocument = nil
                await presentOutlookNow(source: source, message: nil, context: context, attempt: attempt,
                    generation: generation, privacyGeneration: privacyGeneration)
            } catch {
                outlookFailed(error, context: context, attempt: attempt, generation: generation, privacyGeneration: privacyGeneration)
            }
        }
    }

    private func receiveOutlookSource(source: OutlookInboxDocument, message: OutlookMessageDocument?, context: MorningExecutionID, attempt: UUID) throws {
        let result: ComposioJSONValue = .object(["account": .string(source.target.sourceLabel()),
            "source": .string(message?.contextText() ?? source.contextText()), "partial": .bool(source.isPartial)])
        guard connectedMoment.markDispatched(attempt, executionID: context),
              connectedMoment.receive(attempt, executionID: context, service: "outlook", result: result) == .sourceAvailable else { throw OutlookInboxError.invalidResponse }
    }

    private func presentOutlookReading(source: OutlookInboxDocument, message: OutlookMessageDocument?, context: MorningExecutionID) {
        connectedAPITask?.cancel(); connectedMoment.clear()
        guard let attempt = connectedMoment.begin(executionID: context, record: nil) else { return }
        do { try receiveOutlookSource(source: source, message: message, context: context, attempt: attempt) }
        catch { connectedMoment.fail(attempt, executionID: context); pauseOutlookForRefresh(); return }
        let generation = dataGeneration, privacyGeneration = localPrivacyGeneration
        connectedAPITask = Task { @MainActor [weak self] in
            guard let self else { return }
            await presentOutlookNow(source: source, message: message, context: context, attempt: attempt,
                generation: generation, privacyGeneration: privacyGeneration)
            if connectedMoment.matches(attempt, executionID: context) { connectedAPITask = nil }
        }
    }

    private func presentOutlookNow(source: OutlookInboxDocument, message: OutlookMessageDocument?, context: MorningExecutionID,
                                   attempt: UUID, generation: UUID, privacyGeneration: UUID?) async {
        guard outlookIsCurrent(context, generation: generation, privacyGeneration: privacyGeneration),
              connectedMoment.matches(attempt, executionID: context) else { return }
        guard source.isCurrent(at: Date()), message?.isCurrent(at: Date()) != false else {
            connectedMoment.fail(attempt, executionID: context); pauseOutlookForRefresh(); return
        }
        monitorOutlookFreshness(context, generation: generation, privacyGeneration: privacyGeneration)
        var summary = message?.summary() ?? source.summary()
        if message == nil, !source.messages.isEmpty {
            summary += canHearHandsFreeCommands
                ? (AppLanguage.isFrench ? " Dites lis le premier message, le deuxième ou le troisième pour connaître son contenu."
                    : " Say read the first, second or third message to hear its content.")
                : (AppLanguage.isFrench ? " Choisissez un des messages présentés pour lire son contenu."
                    : " Choose one of the presented messages to read its content.")
        }
        guard connectedMoment.present(summary, token: attempt, executionID: context) else {
            connectedMoment.fail(attempt, executionID: context); pauseOutlookForRefresh(); return
        }
        connectedMoment.markPresenting(attempt, executionID: context)
        connectedActionStatus = AppLanguage.isFrench ? "Lecture Outlook reçue pour « \(source.target.sourceLabel()) »."
            : "Outlook reading received for “\(source.target.sourceLabel())”."
        let missingBody = message != nil && message?.bodyText == nil
        guard recordExecution(missingBody ? .unavailable : .completed, confirmedExternalEffect: true) else { pause(); return }
        if missingBody, session?.status == .running {
            connectedMoment.finishPresentation(attempt, executionID: context)
            pause()
            connectedActionStatus = summary + (AppLanguage.isFrench ? " Votre matin est en pause. " : " Your morning is paused. ") + outlookRefreshInstruction
            if readAloud, let connectedActionStatus { speech.speak(connectedActionStatus) }
            return
        }
        do { if readAloud { try await speech.speakAndWait(summary) } }
        catch {
            guard !Task.isCancelled, outlookIsCurrent(context, generation: generation, privacyGeneration: privacyGeneration),
                  connectedMoment.matches(attempt, executionID: context) else { return }
            connectedMoment.finishPresentation(attempt, executionID: context)
            if session?.status == .running { pause() }
            connectedActionStatus = (AppLanguage.isFrench
                ? "Outlook a été lu, mais la présentation vocale n’a pas pu finir. Votre matin est en pause. "
                : "Outlook was read, but the spoken presentation could not finish. Your morning is paused. ") + outlookRefreshInstruction
            return
        }
        guard !Task.isCancelled, outlookIsCurrent(context, generation: generation, privacyGeneration: privacyGeneration),
              connectedMoment.matches(attempt, executionID: context) else { return }
        connectedMoment.finishPresentation(attempt, executionID: context)
        if let timer = activeStepTimer, timer.hasAlertedCurrentEnd { _ = finishAutomatedBudget(timer) }
    }

    private func outlookFailed(_ error: any Error, context: MorningExecutionID, attempt: UUID, generation: UUID, privacyGeneration: UUID?) {
        guard !Task.isCancelled, outlookIsCurrent(context, generation: generation, privacyGeneration: privacyGeneration),
              connectedMoment.matches(attempt, executionID: context) else { return }
        connectedMoment.fail(attempt, executionID: context)
        if session?.status == .running { pause() }
        let reason = (error as? OutlookInboxError)?.localizedDescription ?? OutlookInboxError.unavailable.localizedDescription
        connectedActionStatus = reason + (AppLanguage.isFrench ? " Votre matin est en pause. " : " Your morning is paused. ") + outlookRefreshInstruction
        recordExecution(.unavailable)
        if readAloud, let connectedActionStatus { speech.speak(connectedActionStatus) }
    }

    private func outlookIsCurrent(_ context: MorningExecutionID, generation: UUID, privacyGeneration: UUID?) -> Bool {
        !privacyBlocksWork && dataGeneration == generation && localPrivacyGeneration == privacyGeneration
            && currentOutlookInboxContext == context && outlookInboxContext == context && outlookInboxPrivacyGeneration == privacyGeneration
    }
    private func monitorOutlookFreshness(_ context: MorningExecutionID, generation: UUID, privacyGeneration: UUID?) {
        outlookInboxFreshnessTask?.cancel()
        outlookInboxFreshnessTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
                guard !Task.isCancelled, let self,
                      outlookIsCurrent(context, generation: generation, privacyGeneration: privacyGeneration) else { return }
                checkOutlookInboxFreshness()
                if session?.status != .running { return }
            }
        }
    }
    private func pauseOutlookForRefresh() {
        if session?.status == .running { pause() }
        connectedActionStatus = (AppLanguage.isFrench
            ? "Cette lecture Outlook a expiré ou n’est plus disponible. Votre matin est en pause. "
            : "This Outlook reading expired or is no longer available. Your morning is paused. ") + outlookRefreshInstruction
        if readAloud, let connectedActionStatus { speech.speak(connectedActionStatus) }
    }
    private func outlookSay(_ text: String) {
        connectedActionStatus = text
        if readAloud { speech.speak(text) }
    }
    private var outlookRefreshInstruction: String {
        canHearHandsFreeCommands
            ? (AppLanguage.isFrench ? "Dites actualise Outlook, suivant ou arrête." : "Say refresh Outlook, next or stop.")
            : (AppLanguage.isFrench ? "Utilisez les boutons Actualiser Outlook, Suivant ou Arrêter." : "Use the buttons Refresh Outlook, Next or Stop.")
    }
}
