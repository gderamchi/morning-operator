import Foundation
import MorningApple
import MorningCore

extension MorningStore {
    @discardableResult
    func addGoogleCalendarDay(connection: ComposioConnection, choice: GoogleCalendarChoice) -> Bool {
        guard !privacyBlocksWork, !sessionActive, !busy, connection.isActive, connection.service == "googlecalendar" else { return false }
        do {
            let target = try choice.target(connectionID: connection.id)
            let label = target.sourceLabel()
            let detail = AppLanguage.isFrench
                ? "Lire la journée dans « \(label) ». Les dates seront recalculées chaque matin dans le fuseau de cet iPhone. MORE lit au plus 25 événements et indique si la lecture est partielle. Aucun événement n’est créé ou modifié."
                : "Read today in “\(label)”. Dates are recalculated each morning in this iPhone’s time zone. MORE reads up to 25 events and discloses a partial reading. No event is created or changed."
            guard addConnectedStep(.init(title: label, detail: detail, kind: .calendar, durationMinutes: 3,
                                        target: .googleCalendarDay(target))) else { return false }
            notice = AppLanguage.isFrench ? "Calendrier ajouté au brouillon. Relisez et validez votre routine."
                : "Calendar added to your draft. Review and approve your routine."
            return true
        } catch { notice = error.moreDescription; return false }
    }

    var currentGoogleCalendarDayContext: MorningExecutionID? {
        guard !privacyBlocksWork, sessionActive, let session, let step = currentStep,
              case .googleCalendarDay = step.target else { return nil }
        return .init(sessionID: session.id, routineVersionID: session.routine.id, stepID: step.id)
    }

    var currentGoogleCalendarDay: GoogleCalendarDayDocument? {
        guard let context = currentGoogleCalendarDayContext, googleCalendarDayContext == context,
              googleCalendarDayPrivacyGeneration == localPrivacyGeneration,
              let document = googleCalendarDayDocument, document.isCurrent(at: Date(), timeZone: .current) else { return nil }
        return document
    }

    func runGoogleCalendarDay(_ target: GoogleCalendarDayTarget, sessionID: UUID, stepID: UUID) {
        guard !privacyBlocksWork, let session, session.id == sessionID, session.status == .running,
              session.routine.isApproved, let step = currentStep, step.id == stepID, step.target == .googleCalendarDay(target),
              let context = currentGoogleCalendarDayContext else { return }
        if connectedMoment.executionID == context, connectedMoment.isInFlight, connectedAPITask != nil { return }
        if googleCalendarDayContext == context, let document = currentGoogleCalendarDay,
           let attempt = connectedMoment.beginPresentation(for: context) {
            presentGoogleCalendarDay(document, context: context, attempt: attempt)
            return
        }
        guard let attempt = connectedMoment.begin(executionID: context, record: currentExecutionRecord) else {
            pauseGoogleCalendarDayForRefresh(); return
        }
        loadGoogleCalendarDay(target, context: context, attempt: attempt)
    }

    /// A new bounded read, explicitly requested. No saved action or remote write is repeated.
    func refreshGoogleCalendarDay() {
        guard let context = currentGoogleCalendarDayContext, case let .googleCalendarDay(target) = currentStep?.target else { return }
        guard !nativeMoment.isActive, !slackReply.isActive else {
            speech.speak(AppLanguage.isFrench ? "Terminez ou annulez la demande en cours avant d’actualiser le calendrier."
                : "Finish or cancel the current request before refreshing the calendar.")
            return
        }
        if session?.status == .running { pause() }
        connectedAPITask?.cancel(); connectedAPITask = nil
        clearGoogleCalendarDay(); connectedMoment.clear()
        guard let attempt = connectedMoment.begin(executionID: context, record: nil) else { return }
        loadGoogleCalendarDay(target, context: context, attempt: attempt)
    }

    @discardableResult
    func repeatGoogleCalendarDay() -> Bool {
        guard let context = currentGoogleCalendarDayContext else { return false }
        guard let document = currentGoogleCalendarDay, let attempt = connectedMoment.beginPresentation(for: context) else {
            pauseGoogleCalendarDayForRefresh(); return true
        }
        if session?.status == .running { pause() }
        presentGoogleCalendarDay(document, context: context, attempt: attempt)
        return true
    }

    @discardableResult
    func handleGoogleCalendarDayUtterance(_ text: String) -> Bool {
        guard currentGoogleCalendarDayContext != nil else { return false }
        let words = MorningHandsFreeVoicePolicy.normalized(text)
        guard ["actualise ce calendrier", "actualise mon calendrier", "actualise ma journee", "refresh this calendar", "refresh my calendar", "refresh my day"].contains(words) else { return false }
        refreshGoogleCalendarDay(); return true
    }

    func clearGoogleCalendarDay() {
        googleCalendarDayFreshnessTask?.cancel(); googleCalendarDayFreshnessTask = nil
        googleCalendarDayDocument = nil; googleCalendarDayContext = nil; googleCalendarDayPrivacyGeneration = nil
    }

    /// A retained source cannot keep a running moment current after its day,
    /// zone or freshness window changes. This never dispatches another read.
    func checkGoogleCalendarDayFreshness() {
        guard session?.status == .running, let context = currentGoogleCalendarDayContext,
              googleCalendarDayContext == context, googleCalendarDayPrivacyGeneration == localPrivacyGeneration,
              let document = googleCalendarDayDocument,
              !document.isCurrent(at: Date(), timeZone: .current) else { return }
        pauseGoogleCalendarDayForRefresh()
    }

    private func monitorGoogleCalendarDayFreshness(_ context: MorningExecutionID, generation: UUID, privacyGeneration: UUID?) {
        googleCalendarDayFreshnessTask?.cancel()
        googleCalendarDayFreshnessTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
                guard !Task.isCancelled, let self,
                      self.googleCalendarDayIsCurrent(context, generation: generation, privacyGeneration: privacyGeneration) else { return }
                self.checkGoogleCalendarDayFreshness()
                if self.session?.status != .running { return }
            }
        }
    }

    private func loadGoogleCalendarDay(_ target: GoogleCalendarDayTarget, context: MorningExecutionID, attempt: UUID) {
        let generation = dataGeneration, privacyGeneration = localPrivacyGeneration
        connectedAPITask?.cancel()
        connectedActionStatus = AppLanguage.isFrench ? "Lecture de votre journée dans \(target.sourceLabel())…"
            : "Reading today in \(target.sourceLabel())…"
        connectedAPITask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if connectedMoment.matches(attempt, executionID: context) { connectedAPITask = nil } }
            do {
                let document = try await GoogleCalendarDayService(service: composio).read(target: target)
                try Task.checkCancellation()
                guard googleCalendarDayIsCurrent(context, generation: generation, privacyGeneration: privacyGeneration),
                      connectedMoment.matches(attempt, executionID: context) else { return }
                guard document.isCurrent(at: Date(), timeZone: .current) else {
                    connectedMoment.fail(attempt, executionID: context)
                    recordExecution(.unavailable); pauseGoogleCalendarDayForRefresh(); return
                }
                let source: ComposioJSONValue = .object(["calendar": .string(document.target.sourceLabel()),
                    "source": .string(document.contextText()), "partial": .bool(document.isPartial)])
                guard connectedMoment.markDispatched(attempt, executionID: context),
                      connectedMoment.receive(attempt, executionID: context, service: "googlecalendar", result: source) == .sourceAvailable else {
                    throw GoogleCalendarDayError.invalidResponse
                }
                googleCalendarDayDocument = document; googleCalendarDayContext = context
                googleCalendarDayPrivacyGeneration = privacyGeneration
                await presentGoogleCalendarDayNow(document, context: context, attempt: attempt,
                    generation: generation, privacyGeneration: privacyGeneration)
            } catch {
                guard !Task.isCancelled, googleCalendarDayIsCurrent(context, generation: generation, privacyGeneration: privacyGeneration),
                      connectedMoment.matches(attempt, executionID: context) else { return }
                connectedMoment.fail(attempt, executionID: context)
                clearGoogleCalendarDay()
                pause()
                let reason = (error as? GoogleCalendarDayError)?.moreDescription ?? GoogleCalendarDayError.unavailable.moreDescription
                connectedActionStatus = reason + (AppLanguage.isFrench ? " Votre matin est en pause. " : " Your morning is paused. ")
                    + googleCalendarDayRefreshInstruction
                recordExecution(.unavailable)
                if readAloud, let connectedActionStatus { speech.speak(connectedActionStatus) }
            }
        }
    }

    private func presentGoogleCalendarDay(_ document: GoogleCalendarDayDocument, context: MorningExecutionID, attempt: UUID) {
        connectedAPITask?.cancel()
        let generation = dataGeneration, privacyGeneration = localPrivacyGeneration
        connectedAPITask = Task { @MainActor [weak self] in
            guard let self else { return }
            await presentGoogleCalendarDayNow(document, context: context, attempt: attempt,
                generation: generation, privacyGeneration: privacyGeneration)
            if connectedMoment.matches(attempt, executionID: context) { connectedAPITask = nil }
        }
    }

    private func presentGoogleCalendarDayNow(_ document: GoogleCalendarDayDocument, context: MorningExecutionID, attempt: UUID,
                                           generation: UUID, privacyGeneration: UUID?) async {
        guard googleCalendarDayIsCurrent(context, generation: generation, privacyGeneration: privacyGeneration),
              connectedMoment.matches(attempt, executionID: context) else { return }
        guard document.isCurrent(at: Date(), timeZone: .current) else {
            connectedMoment.fail(attempt, executionID: context)
            pauseGoogleCalendarDayForRefresh(); return
        }
        monitorGoogleCalendarDayFreshness(context, generation: generation, privacyGeneration: privacyGeneration)
        let summary = document.summary()
        guard connectedMoment.present(summary, token: attempt, executionID: context) else { return }
        connectedMoment.markPresenting(attempt, executionID: context)
        connectedActionStatus = AppLanguage.isFrench ? "Lecture de « \(document.target.sourceLabel()) » reçue."
            : "Reading received from “\(document.target.sourceLabel())”."
        guard recordExecution(.completed, confirmedExternalEffect: true) else { pause(); return }
        do { if readAloud { try await speech.speakAndWait(summary) } }
        catch {
            guard !Task.isCancelled, googleCalendarDayIsCurrent(context, generation: generation, privacyGeneration: privacyGeneration),
                  connectedMoment.matches(attempt, executionID: context) else { return }
            connectedMoment.finishPresentation(attempt, executionID: context)
            if session?.status == .running { pause() }
            connectedActionStatus = (AppLanguage.isFrench
                ? "Le calendrier a été lu, mais sa lecture vocale n’a pas pu finir. Votre matin est en pause. "
                : "The calendar was read, but its spoken presentation could not finish. Your morning is paused. ")
                + (canHearHandsFreeCommands
                    ? (AppLanguage.isFrench ? "Dites répète pour relire ces mêmes informations, ou suivant."
                       : "Say repeat to read the same information, or next.")
                    : (AppLanguage.isFrench ? "Utilisez Relire cette journée pour retrouver ces informations, ou Suivant."
                       : "Use Read this day again for the same information, or Next."))
            return
        }
        guard !Task.isCancelled, googleCalendarDayIsCurrent(context, generation: generation, privacyGeneration: privacyGeneration),
              connectedMoment.matches(attempt, executionID: context) else { return }
        connectedMoment.finishPresentation(attempt, executionID: context)
        if let timer = activeStepTimer, timer.hasAlertedCurrentEnd { _ = finishAutomatedBudget(timer) }
    }

    private func googleCalendarDayIsCurrent(_ context: MorningExecutionID, generation: UUID, privacyGeneration: UUID?) -> Bool {
        !privacyBlocksWork && dataGeneration == generation && localPrivacyGeneration == privacyGeneration && currentGoogleCalendarDayContext == context
    }

    private func pauseGoogleCalendarDayForRefresh() {
        if session?.status == .running { pause() }
        connectedActionStatus = AppLanguage.isFrench
            ? "La lecture de ce calendrier a expiré ou n’est plus disponible. Votre matin est en pause. " + googleCalendarDayRefreshInstruction
            : "This calendar reading has expired or is no longer available. Your morning is paused. " + googleCalendarDayRefreshInstruction
        if readAloud, let connectedActionStatus { speech.speak(connectedActionStatus) }
    }

    private var googleCalendarDayRefreshInstruction: String {
        if canHearHandsFreeCommands {
            return AppLanguage.isFrench ? "Dites actualise ce calendrier, suivant ou arrête."
                : "Say refresh this calendar, next, or stop."
        }
        return AppLanguage.isFrench ? "Utilisez les boutons Actualiser ce calendrier, Suivant ou Arrêter."
            : "Use the buttons Refresh this calendar, Next or Stop."
    }
}
