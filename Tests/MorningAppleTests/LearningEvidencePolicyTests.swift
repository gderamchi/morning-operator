import Foundation
import Testing
@testable import MorningApple

/// Invented UI content plus public app copy. No captured personal OCR is stored in fixtures.
enum LearningEvidenceFixtures {
    static let setupOnly = """
    [User-selected video: 00:40.3; 3 frames sampled. This is partial visual evidence, not a complete interaction log.]

    [Observed frame at 00:00.0]
    Screen Sharing
    Morning Operator
    Share Screen
    Cancel

    [Observed frame at 00:10.0]
    Less handling. More morning.
    The briefing. The messages. That game of chess. Let's make space for the things you care about.
    Learn my morning

    [Observed frame at 00:20.0]
    App Library
    Suggestions
    Recently Added
    Social
    Entertainment
    """

    // Public interface copy only, not copied from a person's recorded observation.
    static let ownReviewScreen = """
    Learning your morning
    THE LAST SEVEN MORNINGS
    Find your rhythm.
    Average routine
    Routine timing excludes pauses. It doesn’t measure time in other apps or time saved.
    Morning
    Review
    Notes
    """

    static let calendarContent = "Calendar\nToday\n09:00 Team planning meeting\n10:30 Review project milestones"
    static let messageContent = "Messages\nAlex\nPlease bring the printed meeting notes tomorrow."
}

@Suite("Conservative observation evidence")
struct LearningEvidencePolicyTests {
    @Test("MORE's compact setup and routine surfaces remain interface content")
    func compactMoreScreensAreNotObservedHabits() {
        let screens = [
            "A little more morning.\nShow MORE a little of your morning.\nWe’ll find the rhythm together.",
            "Good morning.\n19 min planned\n09:00 Team planning meeting\nStart my morning\nUpdate my morning",
            "Good morning.\nYour first draft is ready to review.\nPeople and messages\nReview my morning",
            "A little perspective.\nAverage routine time\nSettings & connections\nRecord, describe or refine",
            "More room for your day.\nAnything you’d like to remember?\nA thought, a dream, a reminder"
        ]
        for screen in screens {
            #expect(throws: AppleIntelligenceError.insufficientActivityEvidence) {
                try LearningEvidencePolicy.prepare("[User-selected screenshot; one moment, not a confirmed habit]\n" + screen)
            }
        }
    }

    @Test("Setup, picker, app marketing and launcher frames abstain without inference")
    func setupOnlyHasNoActivityEvidence() {
        #expect(throws: AppleIntelligenceError.insufficientActivityEvidence) {
            try LearningEvidencePolicy.prepare(LearningEvidenceFixtures.setupOnly)
        }
    }

    @Test("Our Review screen's public copy is not evidence of a personal activity")
    func ownReviewScreenHasNoActivityEvidence() {
        let screenshot = "[User-selected screenshot; one moment, not a confirmed habit]\n" + LearningEvidenceFixtures.ownReviewScreen
        let video = "[Observed frame at 00:15.0]\n" + LearningEvidenceFixtures.ownReviewScreen
        for source in [screenshot, video] {
            #expect(throws: AppleIntelligenceError.insufficientActivityEvidence) { try LearningEvidencePolicy.prepare(source) }
        }
        #expect(ProposalValidation.step(title: "Review routine", detail: "", kind: "custom", durationMinutes: 3,
            evidenceQuote: "Routine timing excludes pauses.", source: LearningEvidenceFixtures.ownReviewScreen,
            sourceKind: .visibleTaskContent, claimedEvidenceKind: "visibleTaskContent") == nil)
    }

    @Test("A generic routine label or one Review heading does not exclude real content")
    func ownReviewRequiresMultipleDistinctiveMarkers() throws {
        for heading in ["Average routine", "Learning your morning", "THE LAST SEVEN MORNINGS", "Find your rhythm."] {
            let source = "[User-selected screenshot; one moment, not a confirmed habit]\nCalendar\n\(heading)\n09:00 Team planning meeting"
            let units = try LearningEvidencePolicy.prepare(source)
            #expect(units.count == 1)
            #expect(units[0].text.contains("09:00 Team planning meeting"))
        }
    }

    @Test("Bare app icons or names do not establish that the apps were used")
    func appInventoryCannotBecomeActions() {
        let source = "[User-selected screenshot; one moment, not a confirmed habit]\nCalendar\nMessages\nChess\nMail\nPhotos\nSettings"
        #expect(throws: AppleIntelligenceError.insufficientActivityEvidence) { try LearningEvidencePolicy.prepare(source) }
    }

    @Test("Useful calendar and message content survive rejected surrounding frames unchanged")
    func mixedRecordingRetainsOnlyEligibleOriginalEvidence() throws {
        let source = LearningEvidenceFixtures.setupOnly
            + "\n[Observed frame at 00:22.0]\n" + LearningEvidenceFixtures.ownReviewScreen
            + "\n[Observed frame at 00:25.0]\n" + LearningEvidenceFixtures.calendarContent
            + "\n[Observed frame at 00:30.0]\n" + LearningEvidenceFixtures.messageContent
        let original = source
        let units = try LearningEvidencePolicy.prepare(source)
        #expect(units.count == 2)
        #expect(units[0].text.trimmingCharacters(in: .whitespacesAndNewlines) == LearningEvidenceFixtures.calendarContent)
        #expect(units[1].text.trimmingCharacters(in: .whitespacesAndNewlines) == LearningEvidenceFixtures.messageContent)
        #expect(units.allSatisfy { $0.kind == .visibleTaskContent })
        #expect(source == original)
    }

    @Test("Personal calendar, Messages and chess descriptions are preserved")
    func writtenActivityRemainsPositive() throws {
        let source = "At 07:30 I review today's calendar. I read Messages, then play chess for ten minutes. Later I join a screen sharing workshop."
        let units = try LearningEvidencePolicy.prepare(source)
        #expect(units.count == 1)
        #expect(units.first?.kind == .userReportedActivity)
        #expect(units.first?.text == source)
        #expect(ProposalValidation.step(title: "Review calendar", detail: "A reported activity.", kind: "calendar", durationMinutes: 3,
            evidenceQuote: "review today's calendar", source: source) != nil)
    }

    @Test("An exact quote from marketing is rejected even when the model claims activity")
    func exactQuoteAloneDoesNotGroundAnAction() {
        let source = "The briefing. The messages. That game of chess. Let's make space for the things you care about."
        #expect(ProposalValidation.step(title: "Read messages", detail: "Read messages each morning.", kind: "messages", durationMinutes: 5,
            evidenceQuote: "The messages. That game of chess.", source: source, sourceContext: source,
            sourceKind: .visibleTaskContent, claimedEvidenceKind: "visibleTaskContent") == nil)
        #expect(ProposalValidation.step(title: "Read messages", detail: "", kind: "messages", durationMinutes: 5,
            evidenceQuote: "The messages. That game of chess.", source: source) == nil)
    }

    @Test("Frame context survives chunk boundaries and evidence kinds cannot be relabelled")
    func validatorChecksWholeFrameAndProvenance() {
        let quote = "09:00 Team planning meeting"
        let source = LearningEvidenceFixtures.calendarContent
        let picker = "Screen Sharing\nCancel\n" + source
        #expect(ProposalValidation.step(title: "Calendar", detail: "", kind: "calendar", durationMinutes: 3,
            evidenceQuote: quote, source: source, sourceContext: picker,
            sourceKind: .visibleTaskContent, claimedEvidenceKind: "visibleTaskContent") == nil)
        #expect(ProposalValidation.step(title: "Calendar", detail: "", kind: "calendar", durationMinutes: 3,
            evidenceQuote: quote, source: source, sourceContext: source,
            sourceKind: .visibleTaskContent, claimedEvidenceKind: "userReportedActivity") == nil)
    }

    @Test("Visible task content stays tentative, optional and without automation")
    func visualCalendarAndMessageQuotesRemainEligible() throws {
        let calendar = ProposalValidation.step(title: "Review calendar", detail: "A calendar entry was visible.", kind: "calendar", durationMinutes: 3,
            evidenceQuote: "09:00 Team planning meeting", source: LearningEvidenceFixtures.calendarContent,
            sourceKind: .visibleTaskContent, claimedEvidenceKind: "visibleTaskContent")
        let step = try #require(calendar)
        #expect(step.detail.contains("does not prove an action or repeated habit"))
        #expect(step.automation == nil)
        #expect(!step.isRequired)
        #expect(ProposalValidation.step(title: "Review messages", detail: "A message was visible.", kind: "messages", durationMinutes: 3,
            evidenceQuote: "Please bring the printed meeting notes tomorrow.", source: LearningEvidenceFixtures.messageContent,
            sourceKind: .visibleTaskContent, claimedEvidenceKind: "visibleTaskContent") != nil)
    }

    @Test("Generic labels, metadata and invented quotes are insufficient")
    func labelsAndMetadataAreNotActivityEvidence() {
        let source = LearningEvidenceFixtures.calendarContent
        #expect(ProposalValidation.step(title: "Calendar", detail: "", kind: "calendar", durationMinutes: 3,
            evidenceQuote: "Calendar", source: source, sourceKind: .visibleTaskContent,
            claimedEvidenceKind: "visibleTaskContent") == nil)
        #expect(ProposalValidation.step(title: "Calendar", detail: "", kind: "calendar", durationMinutes: 3,
            evidenceQuote: "09:00 Invented appointment", source: source, sourceKind: .visibleTaskContent,
            claimedEvidenceKind: "visibleTaskContent") == nil)
    }

    @Test("Equivalent frames deduplicate and many frames share bounded inference batches")
    func repeatedFramesDoNotCreateOneModelSessionEach() throws {
        let repeated = (0..<24).map { "[Observed frame at 00:\($0)]\n\(LearningEvidenceFixtures.calendarContent)" }.joined(separator: "\n")
        let unique = try LearningEvidencePolicy.prepare(repeated)
        #expect(unique.count == 1)
        #expect(LearningEvidencePolicy.inferenceChunks(unique, maximumCharacters: 1_500).count == 1)
        let different = (0..<24).map { "[Observed frame at 00:\($0)]\nCalendar\n09:00 Team planning meeting number \($0)" }.joined(separator: "\n")
        let units = try LearningEvidencePolicy.prepare(different)
        let chunks = LearningEvidencePolicy.inferenceChunks(units, maximumCharacters: 1_500)
        #expect(units.count == 24)
        #expect(chunks.count <= ObservationText.chunks(different, maximumCharacters: 1_500).count)
        #expect(chunks.allSatisfy { $0.count <= 1_500 })
    }
}
