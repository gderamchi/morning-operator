import Foundation
import Testing
@testable import MorningCore

@Suite("Any app name and Shortcuts alignment")
struct ObservationAppSignalTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func anyAppNameIsAcceptedAndKnownNamesKeepOneSpelling() throws {
        let typed = try #require(ObservedApp(name: "  whatsapp "))
        #expect(typed.displayName == "WhatsApp")
        #expect(typed == ObservedApp(name: "WHATSAPP"))
        let custom = try #require(ObservedApp(name: "Le Monde"))
        #expect(custom.displayName == "Le Monde")
        #expect(custom.observationIdentity.key == "visual-context:le monde")
        #expect(ObservedApp(name: "   ") == nil)
        #expect(ObservedApp(name: String(repeating: "a", count: 61)) == nil)
    }

    @Test func legacyJournalNamesDecodeToTheSameApps() throws {
        let legacy = try JSONDecoder().decode([ObservedApp].self, from: Data(#"["instagram","tiktok","snapchat"]"#.utf8))
        #expect(legacy == [.instagram, .tiktok, .snapchat])
        #expect(legacy.map(\.displayName) == ["Instagram", "TikTok", "Snapchat"])
        let encoded = try JSONEncoder().encode(ObservedApp(name: "Le Monde"))
        #expect(String(decoding: encoded, as: UTF8.self) == #""Le Monde""#)
    }

    @Test func framesTakeTheAppOpenedBeforeThemUntilItCloses() throws {
        let frames = try [0.0, 10, 20, 30].map { try ObservationFrameEvidence(requestedTimeSeconds: $0, outcome: .observed, text: "Screen") }
        let events = try [
            AppTransitionEvent(app: .instagram, kind: .entered, observedAt: start.addingTimeInterval(5), timeZoneIdentifier: "UTC"),
            AppTransitionEvent(app: .instagram, kind: .exited, observedAt: start.addingTimeInterval(15), timeZoneIdentifier: "UTC"),
            AppTransitionEvent(app: try #require(ObservedApp(name: "WhatsApp")), kind: .entered,
                               observedAt: start.addingTimeInterval(25), timeZoneIdentifier: "UTC")
        ]
        let signals = ShortcutAppAlignment.signals(frames: frames, recordingStartedAt: start, events: events)
        #expect(signals.map(\.sampleID) == [frames[1].id, frames[3].id])
        #expect(signals.map(\.app.displayName) == ["Instagram", "WhatsApp"])
        #expect(signals.allSatisfy { $0.source == .shortcut })
    }

    @Test func staleOpenTiedEventsAndUndecodedFramesGiveNoSignal() throws {
        let frame = try ObservationFrameEvidence(requestedTimeSeconds: 0, outcome: .observed, text: "Screen")
        let undecoded = try ObservationFrameEvidence(requestedTimeSeconds: 1, outcome: .decodeFailed)
        let old = try AppTransitionEvent(app: .tiktok, kind: .entered, observedAt: start.addingTimeInterval(-3_600), timeZoneIdentifier: "UTC")
        #expect(ShortcutAppAlignment.signals(frames: [frame], recordingStartedAt: start, events: [old]).isEmpty)
        let tied = try [AppTransitionEvent(app: .tiktok, kind: .entered, observedAt: start, timeZoneIdentifier: "UTC"),
                        AppTransitionEvent(app: .snapchat, kind: .entered, observedAt: start, timeZoneIdentifier: "UTC")]
        #expect(ShortcutAppAlignment.signals(frames: [frame], recordingStartedAt: start, events: tied).isEmpty)
        let recent = try AppTransitionEvent(app: .tiktok, kind: .entered, observedAt: start, timeZoneIdentifier: "UTC")
        #expect(ShortcutAppAlignment.signals(frames: [undecoded], recordingStartedAt: start, events: [recent]).isEmpty)
        #expect(ShortcutAppAlignment.signals(frames: [frame], recordingStartedAt: start, events: []).isEmpty)
    }

    @Test func dailyCountsListOnlyAppsThatActuallyAppear() throws {
        let mail = try #require(ObservedApp(name: "Mail"))
        let history = try AppTransitionHistory(events: [
            AppTransitionEvent(app: mail, kind: .entered, observedAt: start, timeZoneIdentifier: "UTC"),
            AppTransitionEvent(app: mail, kind: .entered, observedAt: start.addingTimeInterval(60), timeZoneIdentifier: "UTC"),
            AppTransitionEvent(app: .instagram, kind: .entered, observedAt: start.addingTimeInterval(30), timeZoneIdentifier: "UTC")
        ])
        let summary = try history.summary(for: start, timeZoneIdentifier: "UTC")
        #expect(summary.entryCounts.map(\.app.displayName) == ["Mail", "Instagram"])
        #expect(summary.entryCounts.map(\.count) == [2, 1])
    }
}

@Suite("Shortcuts setup diagnostics")
struct AppTransitionDiagnosticsTests {
    @Test func closingThatAlwaysFollowsOpeningIsReportedAndNotAligned() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var events: [AppTransitionEvent] = []
        for offset in stride(from: 0.0, to: 300, by: 60) {
            events.append(try AppTransitionEvent(app: .snapchat, kind: .entered, observedAt: start.addingTimeInterval(offset), timeZoneIdentifier: "UTC"))
            events.append(try AppTransitionEvent(app: .snapchat, kind: .exited, observedAt: start.addingTimeInterval(offset + 0.04), timeZoneIdentifier: "UTC"))
        }
        events.append(try AppTransitionEvent(app: .instagram, kind: .entered, observedAt: start.addingTimeInterval(400), timeZoneIdentifier: "UTC"))
        events.append(try AppTransitionEvent(app: .instagram, kind: .exited, observedAt: start.addingTimeInterval(460), timeZoneIdentifier: "UTC"))
        let history = try AppTransitionHistory(events: events)
        #expect(history.appsClosingRightAfterOpening() == [.snapchat])
        let frame = try ObservationFrameEvidence(requestedTimeSeconds: 30, outcome: .observed, text: "Screen")
        #expect(ShortcutAppAlignment.signals(frames: [frame], recordingStartedAt: start, events: events).isEmpty,
                "A misconfigured pair must not label later screens.")
    }
}

@Suite("App phrases in screen text")
struct ObservationAppSignatureTests {
    private func name(_ text: String) -> String? { ObservationAppSignatures.app(in: text)?.displayName }

    @Test func thirdPartyAppsSeenInRealRecordingsAreNamed() {
        #expect(name("10:12\nDiscussions\nQ Demander à Meta AI ou rechercher\nToutes\nNon lues") == "WhatsApp")
        #expect(name("10:11\n121\n628\nSECTION 3, UNIT 4\nTalk about relationships") == "Duolingo")
        #expect(name("October Quest\n• 18 DAYS\nEarn 45 Quest Points\n17 / 45") == "Duolingo")
        #expect(name("Recherche\nToutes\nOffres d'emploi\nMes posts") == "LinkedIn")
        #expect(name("Pour vous v\nVotre story\nsynthetic.account") == "Instagram")
        #expect(name("Chat\n●\nNon lu 2\nMy AI\nPrès de moi\nAppels") == "Snapchat")
        #expect(name("Réception la...\nSélectionner\nPrincipale • MAJ à...") == "Mail")
        #expect(name("Boîte principale\nPromotions") == "Gmail")
    }

    @Test func appleAppsHaveTheirOwnWordsWhileNotificationsAndFoldersDoNot() {
        #expect(name("Modifier\nMessages\nSynthetic contact\nhier") == "Messages")
        #expect(name("Paris\n18°\nNuageux\n10 h") == "Weather")
        #expect(name("WhatsApp\nNouveau message de Synthetic") == nil, "A bare app name is not its own screen.")
        #expect(name("Réseaux sociaux\nBeReal.\nDiscord\nFacebook") == nil)
    }
}

@Suite("App phrases from the 13:14 recording")
struct ObservationAppSignatureRegressionTests {
    private func name(_ text: String) -> String? { ObservationAppSignatures.app(in: text)?.displayName }

    @Test func musicWeatherConversationsAndMessengerAreTellApart() {
        #expect(name("Bibliothèque\nEpinglez votre musique\npréférée") == "Music")
        #expect(name("MA POSITION\nParis\n18°\nNuageux") == "Weather")
        #expect(name("Synthetic Contact\nく\nen ligne aujourd'hui à 13:07\nAujourd'hui") == "WhatsApp")
        #expect(name("messenger\nQ Demandez à Meta Al ou faites une rech...\nQuoi de") == "Messenger")
        #expect(name("Discussions\nQ Demander à Meta Al ou rechercher\nToutes") == "WhatsApp")
        #expect(name("Modifier\nMessages\nSynthetic contact") == "Messages")
    }
}

@Suite("WhatsApp inside a conversation")
struct ObservationWhatsAppConversationTests {
    private func name(_ text: String) -> String? { ObservationAppSignatures.app(in: text)?.displayName }

    @Test func readTicksUnderMessagesNameWhatsApp() {
        #expect(name("12:08 A\nSynthetic Group\nSynthetic message one\n12:00 V\nSynthetic message two\n12:01 //\nAnother reply\n12:06") == "WhatsApp")
        #expect(name("12:09 A\nSynthetic Group\nhello\n12:06\nsee you\n12:06\nok\n12:08 /") == "WhatsApp")
    }

    @Test func theUnreadDividerNamesWhatsApp() {
        #expect(name("12:08 A\nSynthetic Group\n3 messages non lus\nSynthetic Contact") == "WhatsApp")
    }

    @Test func plainTimesWithoutTicksAreNotAConversation() {
        // A world clock or a calendar lists times too, but never read ticks.
        #expect(name("12:08\nParis\n12:08\nNew York\n6:08\nTokyo\n19:08") == nil)
        // One stray tick-like line is not enough without other message times.
        #expect(name("12:08\nSynthetic note\n9:30 v") == nil)
    }
}
