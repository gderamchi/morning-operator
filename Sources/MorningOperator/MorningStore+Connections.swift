import Foundation
import MorningCore
import MorningApple

extension MorningStore {
    @discardableResult
    func handleNativeConnectionURL(_ url: URL) -> Bool {
        guard nativeConnections.handle(url: url) else { return false }
        if let context = nativeStepContext, let outcome = nativeConnections.shortcutOutcomes[.custom],
           outcome.requestID == context.requestID, session?.id == context.sessionID,
           currentStep?.id == context.stepID, !privacyBlocksWork {
            connectedActionStatus = outcome.status == .returned
                ? String(localized: "Shortcut returned. \(outcome.text)")
                : String(localized: "The shortcut did not finish. Check its outcome before running it again.")
            nativeStepContext = nil
        }
        return true
    }
    @discardableResult
    func addAPIAction(connection: ComposioConnection, tool: ComposioTool, argumentsJSON: String) -> Bool {
        guard !privacyBlocksWork, !sessionActive, !busy else { return false }
        guard !ConnectedRoutineActionPolicy.requiresSpokenMailSend(service: connection.service, tool: tool.slug) else {
            notice = ConnectedRoutineActionPolicy.spokenMailSendExplanation
            return false
        }
        let target = RoutineStepTarget.connectedAPI(service: connection.service, connectionID: connection.id,
            tool: tool.slug, argumentsJSON: argumentsJSON)
        let detail: String
        do {
            try target.validateIntegration()
            detail = try ConnectedActionReview.summary(argumentsJSON: argumentsJSON, schema: tool.inputSchema,
                account: connection.accountLabel ?? connection.name)
        } catch { notice = error.localizedDescription; return false }
        let step = RoutineStep(title: tool.name, detail: detail, durationMinutes: 1, target: target)
        if addConnectedStep(step) {
            notice = String(localized: "Action added to your draft. Review and approve the routine before starting.")
            return true
        }
        return false
    }

    func runConnectedAction(service: String, connectionID: String, tool: String, argumentsJSON: String,
                            sessionID: UUID, stepID: UUID) {
        guard !ConnectedRoutineActionPolicy.requiresSpokenMailSend(service: service, tool: tool) else {
            connectedActionStatus = ConnectedRoutineActionPolicy.spokenMailSendExplanation
            notice = connectedActionStatus
            recordExecution(.unavailable)
            if readAloud { speech.speak(ConnectedRoutineActionPolicy.spokenMailSendExplanation) }
            return
        }
        connectedAPITask?.cancel()
        let generation = dataGeneration
        let requestID = IntegrationRequestID.make(sessionID: sessionID, stepID: stepID)
        connectedActionStatus = String(localized: "Requesting the connected service…")
        connectedAPITask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if dataGeneration == generation, session?.id == sessionID, currentStep?.id == stepID {
                    connectedAPITask = nil
                }
            }
            do {
                let connections = try await composio.connections()
                try Task.checkCancellation()
                guard dataGeneration == generation, !privacyBlocksWork, session?.id == sessionID,
                      currentStep?.id == stepID, session?.status == .running else { return }
                guard connections.contains(where: { $0.id == connectionID && $0.service == service && $0.isActive }) else {
                    connectedActionStatus = String(localized: "Reconnect this account in Apps & accounts.")
                    recordExecution(.unavailable)
                    return
                }
                let arguments = try ComposioJSONValue.parseObject(argumentsJSON)
                let result = try await composio.execute(tool: tool, arguments: arguments,
                    connectionID: connectionID, requestID: requestID)
                guard !Task.isCancelled, dataGeneration == generation, !privacyBlocksWork,
                      session?.id == sessionID, currentStep?.id == stepID else { return }
                if result.successful {
                    let summary = try await ConnectedResultNarrator().summarize(result.data, service: service)
                    guard !Task.isCancelled, dataGeneration == generation, !privacyBlocksWork,
                          session?.id == sessionID, currentStep?.id == stepID, session?.status == .running else { return }
                    connectedActionStatus = summary
                    if readAloud { try await speech.speakAndWait(summary) }
                    guard !Task.isCancelled, dataGeneration == generation else { return }
                    if automatic { completeAutomatedStep(sessionID: sessionID, stepID: stepID) }
                    else { recordExecution(.completed) }
                } else {
                    recordExecution(.uncertain)
                    connectedActionStatus = String(localized: "The service did not confirm this action. Check its result before trying again.")
                }
            } catch {
                guard !Task.isCancelled, dataGeneration == generation, !privacyBlocksWork,
                      session?.id == sessionID, currentStep?.id == stepID else { return }
                recordExecution(error is ConnectedResultError ? .unavailable : .uncertain)
                connectedActionStatus = error is ConnectedResultError ? error.localizedDescription
                    : (AppLanguage.isFrench ? "L’action n’est pas confirmée. Vérifiez son résultat avant de la répéter." : "The action is unconfirmed. Check its result before repeating it.")
            }
        }
    }
}
