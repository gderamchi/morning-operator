import Foundation
import MorningCore
import MorningApple

/// How a confirmed removal ended, for the screen that asked for it.
enum EvidenceRemovalOutcome: Equatable {
    /// Saved without the observations, and nothing is left to clean up.
    case removed(count: Int)
    /// The saved data changed after the review was shown. The new review is shown
    /// and confirmed again; nil when there is nothing left to remove.
    case changed(EvidenceRemovalReview?)
    /// Nothing was removed.
    case notStarted(String)
    /// Saved without the observations; leftover temporary copies need another try.
    case cleanupPending(String)
}

/// Evidence retention and forgetting one observation (issue #8).
///
/// Order, like full forgetting: the review is worked out again from the current data and
/// compared with the one the person confirmed; any running analysis is waited for first;
/// a durable marker is written before anything changes; the workspace is saved without
/// the observations in one atomic write; only then are leftover temporary save files
/// removed; the marker goes last. An interruption at any point resumes on the next launch,
/// and only an unchanged plan is ever applied without a new confirmation.
///
/// An archived observation is text in the workspace file. The app-owned recording is
/// already removed once its text is saved, and a recording waiting for Retry is not an
/// archived observation, so there is no per-observation media file to unlink here.
extension MorningStore {
    var evidenceRetentionWorkspace: EvidenceRetentionWorkspace {
        .init(archive: observationArchive, currentRoutine: routine, previousRoutine: previousRoutine,
              session: session, pendingProposal: pendingRoutineProposal,
              preferences: routinePreferencesIssue == nil ? routinePreferences : nil, history: history)
    }

    /// The expiry review while "Keep raw evidence for…" is on. Nil when it is Off.
    func evidenceExpiryReview(now: Date = Date()) -> EvidenceRemovalReview? {
        guard let days = evidenceRetentionDays, privacyInventoryIsReadable else { return nil }
        return .expiry(maximumAgeDays: days, in: evidenceRetentionWorkspace, now: now)
    }

    /// The review for forgetting one observation. Nil when it is no longer saved.
    func forgettingReview(_ acquisitionID: UUID) -> EvidenceRemovalReview? {
        guard privacyInventoryIsReadable else { return nil }
        return .forgetting(acquisitionID, in: evidenceRetentionWorkspace)
    }

    var canChangeEvidenceRetention: Bool { privacyInventoryIsReadable && !evidenceRemovalInProgress }

    /// Turning expiry on or changing its age removes nothing: it only changes what is offered for review.
    func setEvidenceRetentionDays(_ days: Int?) {
        guard canChangeEvidenceRetention, days != evidenceRetentionDays,
              days.map(EvidenceRemovalReview.maximumAgeChoices.contains) ?? true else { return }
        let old = evidenceRetentionDays
        evidenceRetentionDays = days
        if saveEvidenceRetentionSetting() {
            evidenceRemovalStatus = nil
        } else {
            evidenceRetentionDays = old
            evidenceRemovalStatus = String(localized: "This setting couldn't be saved. Nothing was removed.")
        }
    }

    /// Applies a removal the person confirmed. Never applies a review shown earlier
    /// to changed data: it is worked out again and compared first.
    func applyEvidenceRemoval(_ confirmed: EvidenceRemovalReview) async -> EvidenceRemovalOutcome {
        guard !evidenceRemovalInProgress else {
            return .notStarted(String(localized: "A removal is already in progress. Nothing more was removed."))
        }
        evidenceRemovalInProgress = true
        defer { evidenceRemovalInProgress = false }
        if busy {
            // Analysis may hold one of these observations and save it back when it ends.
            evidenceRemovalStatus = String(localized: "Waiting for the current analysis to finish…")
            await waitForRunningAnalysis()
        }
        let outcome = removeConfirmed(confirmed)
        evidenceRemovalStatus = Self.status(for: outcome)
        return outcome
    }

    /// Called once at launch, and again from Privacy when cleanup needs another try.
    func resumeEvidenceRemovalIfNeeded() {
        let url = evidenceRemovalMarkerURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        // An unreadable workspace or a pending full removal: leave the marker for later.
        guard !privacyBlocksWork, storageIsAvailable, !evidenceRemovalInProgress else { return }
        let marker: EvidenceRemovalMarker
        do {
            marker = try AtomicJSONFile<EvidenceRemovalMarker>(url: url, maximumBytes: 64 * 1_024).load()
        } catch {
            // Without the record it is unknown what was confirmed. Nothing more is removed.
            try? removeEvidenceRemovalMarker()
            evidenceRemovalStatus = String(localized: "An interrupted removal couldn't be read, so nothing more was removed. Review your observations again.")
            return
        }
        switch marker.resumption(in: evidenceRetentionWorkspace) {
        case .finishCleanup:
            do {
                try removeLeftoverSaveFiles()
                try removeEvidenceRemovalMarker()
                evidenceRemovalStatus = String(localized: "The removal you confirmed has finished.")
            } catch {
                evidenceRemovalStatus = Self.cleanupMessage(error)
            }
        case .apply(let review):
            evidenceRemovalInProgress = true
            defer { evidenceRemovalInProgress = false }
            let outcome = commit(review, now: marker.confirmedAt)
            evidenceRemovalStatus = Self.status(for: outcome)
        case .abandon:
            try? removeEvidenceRemovalMarker()
            evidenceRemovalStatus = String(localized: "A removal you confirmed was interrupted, and your saved data has changed since. Nothing more was removed. Review it again.")
        }
    }

    var hasPendingEvidenceRemoval: Bool { FileManager.default.fileExists(atPath: evidenceRemovalMarkerURL.path) }

    // MARK: - Steps

    private func removeConfirmed(_ confirmed: EvidenceRemovalReview) -> EvidenceRemovalOutcome {
        guard !privacyBlocksWork, storageIsAvailable else {
            return .notStarted(String(localized: "Saved data is unavailable right now. Nothing was removed."))
        }
        guard !busy, !sessionActive else {
            return .notStarted(String(localized: "Finish or stop this morning and wait for current work to end, then try again. Nothing was removed."))
        }
        // Unsaved edits to another observation reach disk first, as for deleting one.
        // Edits to an observation being removed go with it.
        if !(selectedObservationID.map(confirmed.acquisitionIDs.contains) ?? false) {
            guard saveObservationEdits() else {
                return .notStarted(String(localized: "Your other changes couldn't be saved first. Nothing was removed."))
            }
        }
        let now = Date()
        // Checked against the current data before the marker, so a changed plan writes nothing.
        do { _ = try confirmed.applied(to: evidenceRetentionWorkspace, now: now) }
        catch { return Self.outcome(for: error) }
        do {
            let marker = EvidenceRemovalMarker(review: confirmed, confirmedAt: now)
            let url = evidenceRemovalMarkerURL
            try LocalDataControl(directory: url.deletingLastPathComponent()).withReadyAccess { _ in
                try AtomicJSONFile<EvidenceRemovalMarker>(url: url).save(marker)
            }
        } catch {
            return .notStarted(String(localized: "Removal couldn't start. Nothing was removed. \(error.localizedDescription)"))
        }
        return commit(confirmed, now: now)
    }

    /// From the marker on. Works the plan out again one last time, saves, then cleans up.
    private func commit(_ review: EvidenceRemovalReview, now: Date) -> EvidenceRemovalOutcome {
        let next: EvidenceRetentionWorkspace
        do { next = try review.applied(to: evidenceRetentionWorkspace, now: now) }
        catch {
            // Nothing was changed: the marker goes so nothing resumes without a new confirmation.
            try? removeEvidenceRemovalMarker()
            return Self.outcome(for: error)
        }
        guard commitEvidenceRemoval(next, removing: Set(review.acquisitionIDs)) else {
            // The save failed and memory is unchanged. If the marker cannot be removed,
            // the next launch finds the same data and the same plan, which was confirmed.
            try? removeEvidenceRemovalMarker()
            return .notStarted(String(localized: "Your data couldn't be saved, so nothing was removed. Try again."))
        }
        do {
            try removeLeftoverSaveFiles()
            try removeEvidenceRemovalMarker()
        } catch {
            return .cleanupPending(Self.cleanupMessage(error))
        }
        return .removed(count: review.acquisitionIDs.count)
    }

    private var evidenceRemovalMarkerURL: URL {
        LocalDataControl.defaultDirectory.appendingPathComponent(EvidenceRemovalMarker.fileName)
    }

    private func removeEvidenceRemovalMarker() throws {
        let url = evidenceRemovalMarkerURL
        try LocalDataControl(directory: url.deletingLastPathComponent()).withReadyAccess { _ in
            try Self.removeOwnedFile(url)
        }
    }

    /// An interrupted save leaves a reserved `.morning-save-` sibling that can hold an
    /// older complete workspace, observation text included. Removed under the shared
    /// lock, so no cooperating writer is between staging and rename.
    private func removeLeftoverSaveFiles() throws {
        let directory = LocalDataControl.defaultDirectory
        try LocalDataControl(directory: directory).withReadyAccess { _ in
            for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                where url.lastPathComponent.hasPrefix(".morning-save-") {
                try Self.removeOwnedFile(url)
            }
        }
    }

    /// A regular file or a link itself, never a link's target; anything else is reported.
    private static func removeOwnedFile(_ url: URL) throws {
        let attributes: [FileAttributeKey: Any]
        do { attributes = try FileManager.default.attributesOfItem(atPath: url.path) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return }
        guard let type = attributes[.type] as? FileAttributeType,
              type == .typeRegular || type == .typeSymbolicLink else { throw CocoaError(.fileWriteNoPermission) }
        try FileManager.default.removeItem(at: url)
    }

    // MARK: - Messages

    private static func outcome(for error: any Error) -> EvidenceRemovalOutcome {
        switch error as? EvidenceRemovalError {
        case .planChanged(let fresh): return .changed(fresh.isEmpty ? nil : fresh)
        case .observationGone: return .changed(nil)
        case .unsupportedCopy(.session):
            return .notStarted(String(localized: "A saved morning still holds this draft. Approve or edit your routine first. Nothing was removed."))
        case .unsupportedCopy:
            return .notStarted(String(localized: "Part of this can't be removed safely here. Nothing was removed."))
        case .segmentedSession:
            return .notStarted(String(localized: "This observation belongs to a recorded session, which can't be removed here yet. Nothing was removed."))
        case .copyMoved:
            return .notStarted(String(localized: "Your routine changed. Review the list again. Nothing was removed."))
        case nil:
            return .notStarted(String(localized: "Removal couldn't start. Nothing was removed. \(error.localizedDescription)"))
        }
    }

    private static func cleanupMessage(_ error: any Error) -> String {
        String(localized: "Removed from MORE’s saved data. A leftover temporary copy couldn’t be removed yet; MORE tries again the next time it opens. \(error.localizedDescription)")
    }

    private static func status(for outcome: EvidenceRemovalOutcome) -> String? {
        switch outcome {
        case .removed(let count): String(localized: "Removed \(count) observations. Everything listed as kept is still there.")
        case .changed: String(localized: "Your saved data changed, so nothing was removed. Review the updated list.")
        case .notStarted(let message), .cleanupPending(let message): message
        }
    }
}
