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
        let target = RoutineStepTarget.connectedAPI(service: connection.service, connectionID: connection.id,
            tool: tool.slug, argumentsJSON: argumentsJSON)
        do { try target.validateIntegration() }
        catch { notice = error.localizedDescription; return false }
        let step = RoutineStep(title: tool.name, detail: String(localized: "Action · \(connection.name)"),
            durationMinutes: 1, target: target)
        if addConnectedStep(step) {
            notice = String(localized: "Action added to your draft. Review and approve the routine before starting.")
            return true
        }
        return false
    }

    func runConnectedAction(service: String, connectionID: String, tool: String, argumentsJSON: String,
                            sessionID: UUID, stepID: UUID) {
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
                    return
                }
                let arguments = try ComposioJSONValue.parseObject(argumentsJSON)
                let result = try await composio.execute(tool: tool, arguments: arguments,
                    connectionID: connectionID, requestID: requestID)
                guard !Task.isCancelled, dataGeneration == generation, !privacyBlocksWork,
                      session?.id == sessionID, currentStep?.id == stepID else { return }
                if result.successful {
                    connectedActionStatus = try result.data?.prettyPrintedJSON() ?? String(localized: "The service returned successfully.")
                } else {
                    connectedActionStatus = String(localized: "The service did not confirm this action. Check its result before trying again.")
                }
            } catch {
                guard !Task.isCancelled, dataGeneration == generation, !privacyBlocksWork,
                      session?.id == sessionID, currentStep?.id == stepID else { return }
                connectedActionStatus = error.localizedDescription
            }
        }
    }
}
