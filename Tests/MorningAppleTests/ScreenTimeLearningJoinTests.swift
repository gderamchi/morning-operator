import Foundation
import MorningCore
import Testing
@testable import MorningApple

@Suite("Screen Time joins selected saved observations")
struct ScreenTimeLearningJoinTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(identifier: "Europe/Paris")!; return value
    }
    private func at(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }
    private func report(id: String = "com.burbn.instagram", seconds: Double = 480, empty: Bool = false) throws -> ScreenTimeObservationEvidence {
        let hours: [ScreenTimeHour] = empty ? [
            .init(interval: .init(start: at(14, 8), duration: 3600), firstPickup: at(14, 8),
                apps: [.init(bundleIdentifier: "com.burbn.instagram", seconds: 1200)])] : [
            .init(interval: .init(start: at(13, 22), duration: 3600), firstPickup: at(13, 22),
                apps: [.init(bundleIdentifier: "com.apple.mobilemail", seconds: 300)]),
            .init(interval: .init(start: at(14, 7), duration: 3600), firstPickup: at(14, 7),
                longestActivity: .init(start: at(14, 7), duration: seconds), apps: [.init(bundleIdentifier: id, seconds: seconds)])]
        return try #require(ScreenTimeObservationEvidence.make(hours: hours, queryStart: at(13, 18), now: at(14, 14), calendar: calendar)
            .first { $0.day == at(14, 0) })
    }
    private func day() throws -> ObservationObservedDate {
        try .init(date: at(14, 7), timeZoneIdentifier: "Europe/Paris", provenance: .userAssigned)
    }
    private func lesson() throws -> ObservationAcquisition {
        var rhythm = BrowserRhythmAccumulator(site: .instagram)
        let totals = try #require(BrowserRhythmTotals(distance: 200, movingSeconds: 5, scrollBursts: 3, clicks: 2))
        let segments = try [(WebMorningBehavior.browseFeed, 0.0, 10.0), (.watchStories, 20.0, 100.0)].map {
            try #require(BrowserLearningSegment(behavior: $0.0, startSeconds: $0.1, endSeconds: $0.2, gestures: 2))
        }
        let updated = rhythm.update(totals, segments: segments)
        #expect(updated)
        return try .browserLesson(summary: rhythm.summary(durationSeconds: 110), observedDate: day(), importedAt: at(14, 14))
    }
    private func video() throws -> ObservationAcquisition {
        let frame = try ObservationFrameEvidence(requestedTimeSeconds: 0, actualTimeSeconds: 0, outcome: .observed,
            text: "Apple Calendar\nA colleague shared the complete project agenda.")
        let evidence = try ObservationVideoEvidence(durationSeconds: 2, frames: [frame])
        return try .init(importedAt: at(14, 14), observedDate: day(), origin: .human, sourceKind: .video,
            sourceLabel: "Selected video", originalText: evidence.renderedText, videoEvidence: evidence,
            frameReviews: [.init(sampleID: frame.id, label: "Apple Calendar", evidenceQuote: "Apple Calendar", reviewedAt: at(14, 14))])
    }
    private func assemble(_ entries: [ObservationAcquisition], preferences: RoutinePreferenceJournal? = nil) throws -> EvidenceRoutineProposal {
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: entries)
        let inputs = evidence.units.filter { $0.sourceLayer == .videoFrame || $0.sourceLayer == .correction }.map {
            EvidenceRoutineStepInput(title: $0.sourceLayer == .correction ? "My correction" : "Calendar first", detail: "A tentative moment",
                kind: .calendar, durationMinutes: 2,
                citations: [.init(unitID: $0.id, quote: $0.sourceLayer == .correction ? $0.text : "A colleague shared the complete project agenda.")])
        }
        return try LearningEvidencePreparation.assemble(evidence: evidence, steps: inputs, preserving: nil, preferences: preferences, at: at(14, 14))
    }

    @Test("Three source types share one proposal; app totals do not rewrite observed gestures or budgets")
    func threeSourceJoin() throws {
        let entries = try [ObservationAcquisition.screenTime(report()), lesson(), video()]
        let proposal = try assemble(entries)
        #expect(proposal.sourceSnapshots.count == 3)
        #expect(proposal.routine.steps.map(\.webBehavior) == [nil, .browseFeed, .watchStories])
        #expect(proposal.routine.steps.map(\.durationMinutes) == [2, 1, 2])
        #expect(proposal.routine.steps[0].automation == .todayCalendar)
        #expect(proposal.support[1].citations.map(\.sourceLayer) == [.original, .screenTimeAggregate])
        #expect(proposal.support[2].citations.count == 1)
        #expect(proposal.routine.steps[1].detail.contains("480"))
        #expect(!proposal.routine.isApproved)
        let archive = try ObservationArchive(entries: entries)
        #expect(proposal.isCurrent(archive: archive, baseRoutine: nil))
        let restored = try JSONDecoder().decode(EvidenceRoutineProposal.self, from: JSONEncoder().encode(proposal))
        #expect(restored.isCurrent(archive: try JSONDecoder().decode(ObservationArchive.self, from: JSONEncoder().encode(archive)), baseRoutine: nil))
    }

    @Test("App minutes alone propose only a manual baseline and are never sent to a language model")
    func nativeOnlyManual() throws {
        let source = try ObservationAcquisition.screenTime(report())
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [source])
        #expect(evidence.hasOnlyStructuredEvidence && !evidence.hasOnlyBrowserLessons && evidence.modelRequestCount == 0)
        let proposal = try assemble([source])
        #expect(proposal.routine.steps.count == 1 && proposal.routine.steps[0].durationMinutes == 8)
        #expect(proposal.routine.steps[0].target == nil && proposal.routine.steps[0].automation == nil && proposal.routine.steps[0].webBehavior == nil)
        #expect(proposal.isCurrent(archive: try ObservationArchive(entries: [source]), baseRoutine: nil))
        let unit = try #require(evidence.units.first)
        #expect(throws: RoutineEvidenceProposalError.invalidCitation) {
            try LearningEvidencePreparation.assemble(evidence: evidence,
                steps: [.init(title: "Invented stories", detail: "Unobserved gestures", kind: .entertainment, durationMinutes: 5,
                    citations: [.init(unitID: unit.id, quote: unit.text)])], preserving: nil)
        }
    }

    @Test("A selected unknown report stays visible without blocking a usable video or browser lesson")
    func unknownAlongsideOtherEvidence() throws {
        let unknown = try ObservationAcquisition.screenTime(report(empty: true))
        let browser = try lesson()
        let proposal = try assemble([unknown, browser])
        #expect(proposal.sourceSnapshots.count == 2 && proposal.routine.steps.count == 2)
        #expect(proposal.sourceSnapshots.first?.sourceLayer == .screenTimeAggregate)
        #expect(proposal.support.allSatisfy { $0.citations.allSatisfy { $0.acquisitionID == browser.id } })
        #expect(proposal.isCurrent(archive: try ObservationArchive(entries: [unknown, browser]), baseRoutine: nil))
        #expect(throws: RoutineEvidenceProposalError.insufficientEvidence) {
            try LearningEvidencePreparation.prepare(acquisitions: [unknown])
        }
        let withVideo = try assemble([unknown, video()])
        #expect(withVideo.routine.steps.first?.automation == .todayCalendar)
    }

    @Test("A lookalike app name cannot borrow the known app's identity or browser gestures")
    func exactIdentity() throws {
        let source = try ObservationAcquisition.screenTime(report(id: "com.example.Instagram"))
        let browser = try lesson()
        let proposal = try assemble([source, browser])
        #expect(proposal.routine.steps.count == 3)
        let app = try #require(proposal.routine.steps.last)
        #expect(app.title == "Instagram" && app.target == nil && app.webBehavior == nil)
        #expect(proposal.support.prefix(2).allSatisfy { $0.citations.count == 1 })
        #expect(proposal.isCurrent(archive: try ObservationArchive(entries: [source, browser]), baseRoutine: nil))
    }

    @Test("Refresh updates one dated identity, keeps corrections, and invalidates a proposal even if displayed text is unchanged")
    func refreshRevision() throws {
        let original = try report()
        var archive = ObservationArchive()
        let id = try archive.upsertScreenTime(original)
        let proposal = try assemble(archive.entries)
        let changed = try ScreenTimeObservationEvidence(day: original.day, timeZoneIdentifier: original.timeZoneIdentifier,
            requestedWindow: original.requestedWindow, retrievedAt: original.retrievedAt.addingTimeInterval(1),
            returnedIntervals: original.returnedIntervals, morningWindow: original.morningWindow, apps: original.apps)
        #expect(changed.renderedText() == original.renderedText())
        #expect(try archive.upsertScreenTime(changed) == id)
        #expect(archive.entries.count == 1 && !proposal.isCurrent(archive: archive, baseRoutine: nil))
        try archive.correct(id: id, text: "I prefer stretching before breakfast.")
        let corrected = try assemble(archive.entries)
        #expect(corrected.support.first?.citations.first?.sourceLayer == .correction)
        #expect(corrected.routine.steps.first?.target == nil)
        #expect(try archive.upsertScreenTime(original) == id)
        #expect(archive.entry(id: id)?.correctedText == "I prefer stretching before breakfast.")
        #expect(archive.entry(id: id)?.screenTimeEvidence == original)
        #expect(!corrected.isCurrent(archive: archive, baseRoutine: nil))
        let unchanged = archive
        let unanswered = try ScreenTimeObservationEvidence.make(hours: [], queryStart: at(13, 18), now: at(14, 14), calendar: calendar)
        for report in unanswered { try archive.upsertScreenTime(report) }
        #expect(archive == unchanged)
    }

    @Test("Personal timing and exclusions run after native fusion")
    func preferencesLast() throws {
        let entries = try [ObservationAcquisition.screenTime(report()), lesson()]
        let first = try assemble(entries)
        let preferences = try RoutinePreferenceJournal(entries: [
            RoutinePreference(target: first.routine.steps[0], durationMinutes: 7),
            RoutinePreference(target: first.routine.steps[1], presence: .exclude)], revision: UUID())
        let proposal = try assemble(entries, preferences: preferences)
        #expect(proposal.routine.steps.count == 1 && proposal.routine.steps[0].durationMinutes == 7)
        #expect(proposal.routine.steps[0].webBehavior == .browseFeed)
        #expect(proposal.support[0].reason == .inferredEvidenceWithUserPreference)
        #expect(proposal.isCurrent(archive: try ObservationArchive(entries: entries), baseRoutine: nil, preferences: preferences))
    }

    @Test("Restoration recomputes native duration and source allocation rather than trusting a saved proposal")
    func forgedProposal() throws {
        let source = try ObservationAcquisition.screenTime(report())
        let proposal = try assemble([source])
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(proposal)) as? [String: Any])
        var routine = try #require(object["routine"] as? [String: Any])
        var steps = try #require(routine["steps"] as? [[String: Any]])
        steps[0]["durationMinutes"] = 30; routine["steps"] = steps; object["routine"] = routine
        let restored = try JSONDecoder().decode(EvidenceRoutineProposal.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(!restored.isCurrent(archive: try ObservationArchive(entries: [source]), baseRoutine: nil))
    }

    @Test("Legacy notes remain decodable; deleting or forgetting removes the typed source locally")
    func legacyAndPrivacy() throws {
        let legacy = try ObservationAcquisition(observedDate: day(), origin: .human, sourceKind: .manual,
            sourceLabel: "My old note", originalText: "I stretch before breakfast.")
        let restored = try JSONDecoder().decode(ObservationAcquisition.self, from: JSONEncoder().encode(legacy))
        #expect(restored.screenTimeEvidence == nil && restored == legacy)
        var archive = try ObservationArchive(entries: [legacy, ObservationAcquisition.screenTime(report())])
        let sourceID = archive.entries[1].id
        try archive.delete(id: sourceID)
        #expect(archive.entries == [legacy])
        try archive.upsertScreenTime(report())
        archive.clear()
        #expect(try JSONDecoder().decode(ObservationArchive.self, from: JSONEncoder().encode(archive)).entries.isEmpty)
        #expect(!String(decoding: try JSONEncoder().encode(archive), as: UTF8.self).contains("com.burbn.instagram"))
        let synthetic = try ObservationAcquisition.screenTime(report(), origin: .synthetic)
        #expect(throws: RoutineEvidenceProposalError.incompatibleSources) {
            try LearningEvidencePreparation.prepare(acquisitions: [legacy, synthetic])
        }
    }

    @Test("Saved presentation names are not reinterpreted through the current language or used as app identity")
    func savedNameAndDuplicateReports() throws {
        let original = try report()
        let named = try ScreenTimeObservationEvidence(day: original.day, timeZoneIdentifier: original.timeZoneIdentifier,
            requestedWindow: original.requestedWindow, retrievedAt: original.retrievedAt,
            returnedIntervals: original.returnedIntervals, morningWindow: original.morningWindow,
            apps: [.init(bundleIdentifier: "com.burbn.instagram", displayName: "Nom conservé dans la source", seconds: 480, secondsMeasured: false, firstHourIndex: 0)])
        let source = try ObservationAcquisition.screenTime(named, french: true)
        let decoded = try JSONDecoder().decode(ObservationAcquisition.self, from: JSONEncoder().encode(source))
        #expect(decoded.originalText.contains("Nom conservé dans la source"))
        #expect(decoded.screenTimeEvidence?.apps[0].bundleIdentifier == "com.burbn.instagram")
        #expect(try assemble([decoded, lesson()]).routine.steps.count == 2)
        let duplicate = try ObservationAcquisition.screenTime(named, french: false)
        #expect(throws: ObservationArchiveError.duplicateAcquisition) { try ObservationArchive(entries: [source, duplicate]) }
        #expect(throws: RoutineEvidenceProposalError.invalidSelection) {
            try LearningEvidencePreparation.prepare(acquisitions: [source, duplicate])
        }
    }
}
