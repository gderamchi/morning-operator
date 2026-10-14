import Foundation
import Testing
@testable import MorningLiveDemo

@Suite("Live morning demo spoken reply intent")
struct LiveDemoReplyIntentTests {
    @Test("Declines, bare yes and silence")
    func simpleAnswers() {
        for text in ["No", "no thanks.", "Not now", "skip", "Don't reply", "do not reply", "No, don't send anything",
                     "nope", "Leave it"] {
            #expect(LiveDemoReplyIntent.parse(text) == .decline)
        }
        for text in ["Yes", "yeah", "Yes please.", "OK", "reply"] {
            #expect(LiveDemoReplyIntent.parse(text) == .affirm)
        }
        #expect(LiveDemoReplyIntent.parse("") == .silence)
        #expect(LiveDemoReplyIntent.parse("  ...  ") == .silence)
    }

    @Test("A reply phrase becomes a draft with the original wording")
    func drafts() {
        #expect(LiveDemoReplyIntent.parse("Reply I'm on my way") == .draft("I'm on my way"))
        #expect(LiveDemoReplyIntent.parse("Yes, reply: see you at nine.") == .draft("see you at nine."))
        #expect(LiveDemoReplyIntent.parse("Tell them I'll call later") == .draft("I'll call later"))
        #expect(LiveDemoReplyIntent.parse("say Thanks!") == .draft("Thanks!"))
        #expect(LiveDemoReplyIntent.parse("Yes I'm running late") == .draft("I'm running late"))
        // "send" is heard as wording only; the demo still never sends.
        #expect(LiveDemoReplyIntent.parse("send ok") == .draft("ok"))
    }

    @Test("Anything else is unclear and skipped")
    func unclear() {
        #expect(LiveDemoReplyIntent.parse("what time is it") == .unclear)
        #expect(LiveDemoReplyIntent.parse("hmm maybe") == .unclear)
    }

    @Test("The answer to 'What should I say?' is the draft unless it declines")
    func dictation() {
        #expect(LiveDemoReplyIntent.parseDictation("Sounds good, see you soon") == .draft("Sounds good, see you soon"))
        #expect(LiveDemoReplyIntent.parseDictation("never mind") == .decline)
        #expect(LiveDemoReplyIntent.parseDictation("No") == .decline)
        #expect(LiveDemoReplyIntent.parseDictation("") == .silence)
    }
}

@Suite("Live morning demo list rows and weather")
struct LiveDemoListRowTests {
    @Test("Unread is the value or the first word of the label, never a word in the preview")
    func unread() {
        #expect(LiveDemoListRow.isUnread(label: "Unread, Sam, hello", value: ""))
        #expect(LiveDemoListRow.isUnread(label: "Sam, hello", value: "Unread"))
        #expect(!LiveDemoListRow.isUnread(label: "Sam, I left it unread", value: ""))
        #expect(!LiveDemoListRow.isUnread(label: "Sam, hello", value: ""))
    }

    @Test("Static texts give sender and detail, skipping times and status words")
    func staticTexts() {
        let row = LiveDemoListRow.parse(label: "Unread, Sam", value: "", texts: ["Sam", "9:41 AM", "See you, then"])
        #expect(row == LiveDemoListRow(isUnread: true, sender: "Sam", detail: "See you, then"))
        let mail = LiveDemoListRow.parse(label: "", value: "unread", texts: ["Bank", "Yesterday", "Your statement", "Preview"])
        #expect(mail == LiveDemoListRow(isUnread: true, sender: "Bank", detail: "Your statement"))
    }

    @Test("The comma label is the fallback")
    func labelFallback() {
        let row = LiveDemoListRow.parse(label: "Unread, Alex, Lunch today?, 10:02", value: "", texts: [])
        #expect(row == LiveDemoListRow(isUnread: true, sender: "Alex", detail: "Lunch today?"))
        #expect(LiveDemoListRow.parse(label: "", value: "", texts: []) == nil)
        #expect(LiveDemoListRow.parse(label: "Unread, 9:41", value: "", texts: []) == nil)
    }

    @Test("Weather reads the first temperature and a short condition")
    func weather() {
        let summary = LiveDemoWeather.summary(texts: ["My Location", "Paris", "14°", "Mostly Cloudy", "H:17° L:9°"])
        #expect(summary?.temperature == "14°")
        #expect(summary?.condition == "Mostly Cloudy")
        let bare = LiveDemoWeather.summary(texts: ["-3°", "H:1° L:-5°"])
        #expect(bare?.temperature == "-3°")
        #expect(bare?.condition == nil)
        #expect(LiveDemoWeather.summary(texts: ["Paris", "Loading"]) == nil)
    }
}

@Suite("Live morning demo Instagram")
struct LiveDemoInstagramTests {
    @Test("Unread count from the Direct tab label")
    func unreadCount() {
        #expect(LiveDemoInstagram.unreadCount(fromTabLabel: "Direct messages - 0 unread message") == 0)
        #expect(LiveDemoInstagram.unreadCount(fromTabLabel: "Direct messages - 3 unread messages") == 3)
        #expect(LiveDemoInstagram.unreadCount(fromTabLabel: "Direct messages") == nil)
        #expect(LiveDemoInstagram.unreadCount(fromTabLabel: "unread") == nil)
    }

    @Test("All-caught-up marker in English and French")
    func caughtUp() {
        for text in ["You're All Caught Up", "You\u{2019}ve seen all new posts from the past 3 days.",
                     "You've seen the latest posts", "Vous êtes à jour", "Vous avez vu toutes les nouvelles publications"] {
            #expect(LiveDemoInstagram.isCaughtUpMarker(text: text))
        }
        #expect(LiveDemoInstagram.isCaughtUpMarker(text: "", identifier: "feed-caught-up-view"))
        for text in ["Suggested for you", "Caught a fish today", "Liked by friends", ""] {
            #expect(!LiveDemoInstagram.isCaughtUpMarker(text: text))
        }
    }
}
