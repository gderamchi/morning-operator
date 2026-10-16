import Foundation
import MorningApple
import MorningCore

extension MorningStore {
    @discardableResult
    func addCalendlyDay(connection: ComposioConnection, identity: CalendlyIdentity) -> Bool {
        guard !privacyBlocksWork, !sessionActive, !busy, connection.isActive, connection.service == "calendly",
              identity.connectionID == connection.id, identity.isCurrent(at: Date()) else { return false }
        do {
            let target = identity.target
            try target.validate()
            let detail = AppLanguage.isFrench
                ? "Lire les rendez-vous qui commencent aujourd’hui pour « \(identity.userName) », dans le fuseau de cet iPhone. Jusqu’à 25 rendez-vous ; toute lecture partielle est signalée. Aucun rendez-vous n’est créé ou annulé."
                : "Read bookings starting today for “\(identity.userName)” in this iPhone’s time zone. Up to 25 bookings; partial readings are disclosed. No booking is created or cancelled."
            guard addConnectedStep(.init(title: AppLanguage.isFrench ? "Rendez-vous de \(identity.userName)" : "Bookings for \(identity.userName)",
                                        detail: detail, kind: .calendar, durationMinutes: 3, target: .calendlyDay(target))) else { return false }
            notice = AppLanguage.isFrench ? "Rendez-vous ajoutés au brouillon. Relisez et validez votre routine."
                : "Bookings added to your draft. Review and approve your routine."
            return true
        } catch { notice = error.localizedDescription; return false }
    }

    var currentCalendlyDayContext: MorningExecutionID? {
        guard !privacyBlocksWork, sessionActive, let session, let step = currentStep,
              case .calendlyDay = step.target else { return nil }
        return .init(sessionID: session.id, routineVersionID: session.routine.id, stepID: step.id)
    }

    var currentCalendlyDay: CalendlyDayDocument? {
        guard let context = currentCalendlyDayContext, calendlyDayContext == context,
              calendlyDayPrivacyGeneration == localPrivacyGeneration,
              let document = calendlyDayDocument, document.isCurrent(at: Date(), timeZone: .current) else { return nil }
        return document
    }

    func runCalendlyDay(_ target: CalendlyDayTarget, sessionID: UUID, stepID: UUID) {
        guard !privacyBlocksWork, let session, session.id == sessionID, session.status == .running,
              session.routine.isApproved, let step = currentStep, step.id == stepID, step.target == .calendlyDay(target),
              let context = currentCalendlyDayContext else { return }
        if connectedMoment.executionID == context, connectedMoment.isInFlight, connectedAPITask != nil { return }
        if calendlyDayContext == context, let document = currentCalendlyDay,
           let attempt = connectedMoment.beginPresentation(for: context) {
            presentCalendlyDay(document, context: context, attempt: attempt)
            return
        }
        guard let attempt = connectedMoment.begin(executionID: context, record: currentExecutionRecord) else {
            pauseCalendlyDayForRefresh(); return
        }
        loadCalendlyDay(target, context: context, attempt: attempt)
    }

    /// A new bounded read, explicitly requested. No saved action or remote write is repeated.
    func refreshCalendlyDay() {
        guard let context = currentCalendlyDayContext, case let .calendlyDay(target) = currentStep?.target else { return }
        guard !nativeMoment.isActive, !slackReply.isActive else {
            speech.speak(AppLanguage.isFrench ? "Terminez ou annulez la demande en cours avant d’actualiser vos rendez-vous."
                : "Finish or cancel the current request before refreshing your bookings.")
            return
        }
        if session?.status == .running { pause() }
        connectedAPITask?.cancel(); connectedAPITask = nil
        clearCalendlyDay(); connectedMoment.clear()
        guard let attempt = connectedMoment.begin(executionID: context, record: nil) else { return }
        loadCalendlyDay(target, context: context, attempt: attempt)
    }

    @discardableResult
    func repeatCalendlyDay() -> Bool {
        guard let context = currentCalendlyDayContext else { return false }
        guard let document = currentCalendlyDay, let attempt = connectedMoment.beginPresentation(for: context) else {
            pauseCalendlyDayForRefresh(); return true
        }
        if session?.status == .running { pause() }
        presentCalendlyDay(document, context: context, attempt: attempt)
        return true
    }

    @discardableResult
    func handleCalendlyDayUtterance(_ text: String) -> Bool {
        guard currentCalendlyDayContext != nil else { return false }
        let words = MorningHandsFreeVoicePolicy.normalized(text)
        guard ["actualise mes rendez vous", "actualise calendly", "actualise mes reservations", "refresh my bookings", "refresh calendly", "refresh my appointments"].contains(words) else { return false }
        refreshCalendlyDay(); return true
    }

    func clearCalendlyDay() {
        calendlyDayFreshnessTask?.cancel(); calendlyDayFreshnessTask = nil
        calendlyDayDocument = nil; calendlyDayContext = nil; calendlyDayPrivacyGeneration = nil
    }

    /// A retained source cannot keep a running moment current after its day,
    /// zone or freshness window changes. This never dispatches another read.
    func checkCalendlyDayFreshness() {
        guard session?.status == .running, let context = currentCalendlyDayContext,
              calendlyDayContext == context, calendlyDayPrivacyGeneration == localPrivacyGeneration,
              let document = calendlyDayDocument,
              !document.isCurrent(at: Date(), timeZone: .current) else { return }
        pauseCalendlyDayForRefresh()
    }

    private func monitorCalendlyDayFreshness(_ context: MorningExecutionID, generation: UUID, privacyGeneration: UUID?) {
        calendlyDayFreshnessTask?.cancel()
        calendlyDayFreshnessTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
                guard !Task.isCancelled, let self,
                      self.calendlyDayIsCurrent(context, generation: generation, privacyGeneration: privacyGeneration) else { return }
                self.checkCalendlyDayFreshness()
                if self.session?.status != .running { return }
            }
        }
    }

    private func loadCalendlyDay(_ target: CalendlyDayTarget, context: MorningExecutionID, attempt: UUID) {
        let generation = dataGeneration, privacyGeneration = localPrivacyGeneration
        connectedAPITask?.cancel()
        connectedActionStatus = AppLanguage.isFrench ? "Lecture des rendez-vous du jour de \(target.userName)…"
            : "Reading today’s bookings for \(target.userName)…"
        connectedAPITask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if connectedMoment.matches(attempt, executionID: context) { connectedAPITask = nil } }
            do {
                let document = try await CalendlyDayService(service: composio).read(target: target)
                try Task.checkCancellation()
                guard calendlyDayIsCurrent(context, generation: generation, privacyGeneration: privacyGeneration),
                      connectedMoment.matches(attempt, executionID: context) else { return }
                guard document.isCurrent(at: Date(), timeZone: .current) else {
                    connectedMoment.fail(attempt, executionID: context)
                    recordExecution(.unavailable); pauseCalendlyDayForRefresh(); return
                }
                let source: ComposioJSONValue = .object(["account": .string(document.target.userName),
                    "source": .string(document.contextText()), "partial": .bool(document.isPartial)])
                guard connectedMoment.markDispatched(attempt, executionID: context),
                      connectedMoment.receive(attempt, executionID: context, service: "calendly", result: source) == .sourceAvailable else {
                    throw CalendlyDayError.invalidResponse
                }
                calendlyDayDocument = document; calendlyDayContext = context
                calendlyDayPrivacyGeneration = privacyGeneration
                await presentCalendlyDayNow(document, context: context, attempt: attempt,
                    generation: generation, privacyGeneration: privacyGeneration)
            } catch {
                guard !Task.isCancelled, calendlyDayIsCurrent(context, generation: generation, privacyGeneration: privacyGeneration),
                      connectedMoment.matches(attempt, executionID: context) else { return }
                connectedMoment.fail(attempt, executionID: context)
                clearCalendlyDay()
                pause()
                let reason = (error as? CalendlyDayError)?.localizedDescription ?? CalendlyDayError.unavailable.localizedDescription
                connectedActionStatus = reason + (AppLanguage.isFrench ? " Votre matin est en pause. " : " Your morning is paused. ")
                    + calendlyDayRefreshInstruction
                recordExecution(.unavailable)
                if readAloud, let connectedActionStatus { speech.speak(connectedActionStatus) }
            }
        }
    }

    private func presentCalendlyDay(_ document: CalendlyDayDocument, context: MorningExecutionID, attempt: UUID) {
        connectedAPITask?.cancel()
        let generation = dataGeneration, privacyGeneration = localPrivacyGeneration
        connectedAPITask = Task { @MainActor [weak self] in
            guard let self else { return }
            await presentCalendlyDayNow(document, context: context, attempt: attempt,
                generation: generation, privacyGeneration: privacyGeneration)
            if connectedMoment.matches(attempt, executionID: context) { connectedAPITask = nil }
        }
    }

    private func presentCalendlyDayNow(_ document: CalendlyDayDocument, context: MorningExecutionID, attempt: UUID,
                                           generation: UUID, privacyGeneration: UUID?) async {
        guard calendlyDayIsCurrent(context, generation: generation, privacyGeneration: privacyGeneration),
              connectedMoment.matches(attempt, executionID: context) else { return }
        guard document.isCurrent(at: Date(), timeZone: .current) else {
            connectedMoment.fail(attempt, executionID: context)
            pauseCalendlyDayForRefresh(); return
        }
        monitorCalendlyDayFreshness(context, generation: generation, privacyGeneration: privacyGeneration)
        let summary = document.summary()
        guard connectedMoment.present(summary, token: attempt, executionID: context) else { return }
        connectedMoment.markPresenting(attempt, executionID: context)
        connectedActionStatus = AppLanguage.isFrench ? "Lecture de « \(document.target.userName) » reçue."
            : "Reading received from “\(document.target.userName)”."
        guard recordExecution(.completed, confirmedExternalEffect: true) else { pause(); return }
        do { if readAloud { try await speech.speakAndWait(summary) } }
        catch {
            guard !Task.isCancelled, calendlyDayIsCurrent(context, generation: generation, privacyGeneration: privacyGeneration),
                  connectedMoment.matches(attempt, executionID: context) else { return }
            connectedMoment.finishPresentation(attempt, executionID: context)
            if session?.status == .running { pause() }
            connectedActionStatus = (AppLanguage.isFrench
                ? "Les rendez-vous ont été lus, mais leur lecture vocale n’a pas pu finir. Votre matin est en pause. "
                : "The bookings were read, but their spoken presentation could not finish. Your morning is paused. ")
                + (canHearHandsFreeCommands
                    ? (AppLanguage.isFrench ? "Dites répète pour relire ces mêmes informations, ou suivant."
                       : "Say repeat to read the same information, or next.")
                    : (AppLanguage.isFrench ? "Utilisez Relire ces rendez-vous pour retrouver ces informations, ou Suivant."
                       : "Use Read these bookings again for the same information, or Next."))
            return
        }
        guard !Task.isCancelled, calendlyDayIsCurrent(context, generation: generation, privacyGeneration: privacyGeneration),
              connectedMoment.matches(attempt, executionID: context) else { return }
        connectedMoment.finishPresentation(attempt, executionID: context)
        if let timer = activeStepTimer, timer.hasAlertedCurrentEnd { _ = finishAutomatedBudget(timer) }
    }

    private func calendlyDayIsCurrent(_ context: MorningExecutionID, generation: UUID, privacyGeneration: UUID?) -> Bool {
        !privacyBlocksWork && dataGeneration == generation && localPrivacyGeneration == privacyGeneration && currentCalendlyDayContext == context
    }

    private func pauseCalendlyDayForRefresh() {
        if session?.status == .running { pause() }
        connectedActionStatus = AppLanguage.isFrench
            ? "La lecture de vos rendez-vous a expiré ou n’est plus disponible. Votre matin est en pause. " + calendlyDayRefreshInstruction
            : "This booking reading has expired or is no longer available. Your morning is paused. " + calendlyDayRefreshInstruction
        if readAloud, let connectedActionStatus { speech.speak(connectedActionStatus) }
    }

    private var calendlyDayRefreshInstruction: String {
        if canHearHandsFreeCommands {
            return AppLanguage.isFrench ? "Dites actualise mes rendez-vous, suivant ou arrête."
                : "Say refresh my bookings, next, or stop."
        }
        return AppLanguage.isFrench ? "Utilisez les boutons Actualiser mes rendez-vous, Suivant ou Arrêter."
            : "Use the buttons Refresh my bookings, Next or Stop."
    }
}
