import Foundation
import MorningCore
import MorningApple

/// Learn from Screen Time (docs/SCREEN-TIME-INTEGRATION.md): one approval, then one read of the
/// last week's hourly minutes, turned into a suggestion that waits for review. Its app
/// identifiers, labels, planned minutes and coverage stay in the local workspace; no raw
/// activity stream is logged. Bounded dated aggregates join the local observation archive;
/// the daily display summaries remain in memory for this launch.
extension MorningStore {
    /// Days asked for. How far back the system really answers is measured on each read.
    static let screenTimeDaysRequested = 7

    func refreshScreenTimeAccess() { screenTimeAccess = screenTimeSource.access }

    /// Keep a canceled read owned until its SDK call actually returns. Forget must
    /// wait for this before treating an in-flight authorization or read as stopped.
    var screenTimeReadIsQuiescent: Bool { screenTimeTask == nil }

    func cancelScreenTimeRead() { screenTimeTask?.cancel() }

    func learnFromScreenTime() {
        guard !privacyBlocksWork, storageIsAvailable, !busy, !sessionActive, !voiceInputBlocksPlayback,
              !screenTimeBusy, screenTimeTask == nil else { return }
        screenTimeBusy = true
        screenTimeMessage = nil
        let generation = dataGeneration
        let source = screenTimeSource
        let taskID = UUID()
        screenTimeTaskID = taskID
        screenTimeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.screenTimeTaskID == taskID {
                    self.screenTimeTask = nil
                    self.screenTimeTaskID = nil
                    if self.dataGeneration == generation { self.screenTimeBusy = false }
                }
            }
            do {
                try Task.checkCancellation()
                guard self.dataGeneration == generation, !self.privacyBlocksWork else { return }
                guard source.access != .unavailable else {
                    self.screenTimeMessage = String(localized: "Learning from Screen Time needs iOS 26.4 or later.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
                    return
                }
                if source.access != .approved { try await source.requestAccess() }
                guard !Task.isCancelled, self.dataGeneration == generation, !self.privacyBlocksWork else { return }
                self.refreshScreenTimeAccess()
                guard self.screenTimeAccess == .approved else {
                    self.screenTimeMessage = self.screenTimeAccessExplanation
                    return
                }
                let calendar = Calendar.current
                let end = Date()
                let queryStart = calendar.date(byAdding: .day, value: -Self.screenTimeDaysRequested, to: calendar.startOfDay(for: end)) ?? end
                try Task.checkCancellation()
                let hours = try await source.hours(from: queryStart, to: end)
                guard !Task.isCancelled, self.dataGeneration == generation, !self.privacyBlocksWork else { return }
                var own: Set<String> = []
                if let id = Bundle.main.bundleIdentifier { own.insert(id) }
                let evidence = try ScreenTimeObservationEvidence.make(hours: hours, queryStart: queryStart,
                    now: end, calendar: calendar, ownBundleIdentifiers: own)
                guard self.saveScreenTimeEvidence(evidence) else {
                    self.screenTimeMessage = AppLanguage.isFrench
                        ? "Les agrégats n’ont pas pu être enregistrés. Les sources et la routine précédentes sont conservées."
                        : "The aggregates could not be saved. Your previous sources and routine are retained."
                    return
                }
                self.screenTimeDailyUsage = ScreenTimeDailyUsage.summarize(hours: hours, calendar: calendar, ownBundleIdentifiers: own)
                let learning = ScreenTimeMorningLearner.learn(hours: hours, queryStart: queryStart, now: end,
                                                              calendar: calendar, ownBundleIdentifiers: own)
                self.screenTimeLearning = learning
                let nextMorning = calendar.component(.hour, from: end) < 12 ? end
                    : calendar.date(byAdding: .day, value: 1, to: end) ?? end
                // Apps the owner excluded from suggestions stay out; saved durations are the starting minutes.
                guard var proposal = ScreenTimeRoutineProposal.make(from: learning, nextMorning: nextMorning,
                                                                    baseRoutineID: self.routine?.id, calendar: calendar, now: end),
                      proposal.applyPreferences(self.routinePreferences) else {
                    // An answered refresh supersedes the earlier suggestion even when
                    // no morning qualifies. Preserve it only if the removal cannot save.
                    if self.pendingScreenTimeProposal != nil,
                       !self.discardPendingScreenTimeProposal() { return }
                    self.screenTimeMessage = hours.isEmpty
                        ? (AppLanguage.isFrench
                            ? "Screen Time n’a fourni aucune donnée d’usage pour cette période. Vous pouvez aussi ajouter vos vidéos ou apprendre dans le navigateur."
                            : "Screen Time returned no app-use data for this period. You can also add your videos or learn in the browser.")
                        : String(localized: "Screen Time returned app use, but no complete morning could be identified yet.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
                    return
                }
                if self.savePendingScreenTimeProposal(proposal) {
                    self.screenTimeMessage = nil
                } else if self.notice == nil {
                    self.screenTimeMessage = String(localized: "The suggestion couldn't be saved. Your routine is unchanged.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
                }
            } catch {
                guard !Task.isCancelled, self.dataGeneration == generation, !self.privacyBlocksWork else { return }
                self.refreshScreenTimeAccess()
                self.screenTimeMessage = self.screenTimeAccess == .approved
                    ? String(localized: "Screen Time didn't answer this time. Try again in a moment.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
                    : self.screenTimeAccessExplanation
            }
        }
    }

    var screenTimeAccessExplanation: String {
        switch screenTimeAccess {
        case .approved: String(localized: "Screen Time is connected.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
        case .unavailable: String(localized: "Learning from Screen Time needs iOS 26.4 or later.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
        case .approvedWithoutData: String(localized: "Screen Time was approved without app-use data. Check this build’s capabilities and your device’s eligibility.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
        case .denied: String(localized: "Screen Time access wasn't given. You can allow it in Settings → Screen Time, then try again.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
        case .notAsked: String(localized: "Connect Screen Time to read the app-use data available on this iPhone.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
        }
    }
}

#if DEBUG
extension MorningStore {
    static var screenTimeAutoLearnRequested: Bool { ProcessInfo.processInfo.arguments.contains("--screen-time-learn-auto") }
}
#endif
