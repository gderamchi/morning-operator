import Foundation
import MorningCore

/// Learn from Screen Time (docs/SEAMLESS-LEARNING.md): one approval, then one read of the
/// last week's hourly minutes, turned into a suggestion that waits for review. Only app
/// names and minutes are kept, in the workspace on this phone; nothing is logged.
extension MorningStore {
    /// Days asked for. How far back the system really answers is measured on each read.
    static let screenTimeDaysRequested = 7

    func refreshScreenTimeAccess() { screenTimeAccess = screenTimeSource.access }

    func learnFromScreenTime() {
        guard !privacyBlocksWork, storageIsAvailable, !screenTimeBusy else { return }
        screenTimeBusy = true
        screenTimeMessage = nil
        let generation = dataGeneration
        let source = screenTimeSource
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if self.dataGeneration == generation { self.screenTimeBusy = false } }
            do {
                if source.access != .approved { try await source.requestAccess() }
                self.refreshScreenTimeAccess()
                guard self.screenTimeAccess == .approved else {
                    self.screenTimeMessage = String(localized: "Screen Time access wasn't given. You can allow it in Settings → Screen Time, then try again.")
                    return
                }
                let calendar = Calendar.current
                let end = Date()
                let queryStart = calendar.date(byAdding: .day, value: -Self.screenTimeDaysRequested, to: calendar.startOfDay(for: end)) ?? end
                let hours = try await source.hours(from: queryStart, to: end)
                guard self.dataGeneration == generation, !self.privacyBlocksWork else { return }
                var own: Set<String> = []
                if let id = Bundle.main.bundleIdentifier { own.insert(id) }
                let learning = ScreenTimeMorningLearner.learn(hours: hours, queryStart: queryStart, now: end,
                                                              calendar: calendar, ownBundleIdentifiers: own)
                let nextMorning = calendar.component(.hour, from: end) < 12 ? end
                    : calendar.date(byAdding: .day, value: 1, to: end) ?? end
                guard let proposal = ScreenTimeRoutineProposal.make(from: learning, nextMorning: nextMorning,
                                                                    baseRoutineID: self.routine?.id, calendar: calendar, now: end) else {
                    self.screenTimeMessage = learning.earliestData == nil
                        ? String(localized: "Screen Time has no app minutes on this iPhone yet. Try again tomorrow morning.")
                        : String(localized: "Screen Time had \(learning.daysOfData) days, but no complete morning with app use was found yet. Try again tomorrow.")
                    return
                }
                if self.savePendingScreenTimeProposal(proposal) {
                    self.screenTimeMessage = nil
                } else if self.notice == nil {
                    self.screenTimeMessage = String(localized: "The suggestion couldn't be saved. Your routine is unchanged.")
                }
            } catch {
                self.refreshScreenTimeAccess()
                self.screenTimeMessage = self.screenTimeAccess == .approved
                    ? String(localized: "Screen Time didn't answer this time. Try again in a moment.")
                    : String(localized: "Screen Time access wasn't given. You can allow it in Settings → Screen Time, then try again.")
            }
        }
    }

    #if DEBUG
    /// Debug launch argument `--screen-time-learn-auto`: open Learn and start at once, so a
    /// tethered build can be checked without taps (Apple's sheet still needs the owner).
    static var screenTimeAutoLearnRequested: Bool { ProcessInfo.processInfo.arguments.contains("--screen-time-learn-auto") }

    #endif
}
