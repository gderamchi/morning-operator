import Foundation
import Testing
@testable import MorningLiveDemo

@Suite("Live morning demo voice commands")
struct LiveDemoVoiceIntentTests {
    @Test("More reels, English and French")
    func more() {
        #expect(LiveDemoVoiceIntent.parse("8 more") == .more(8))
        #expect(LiveDemoVoiceIntent.parse("Add eight more.") == .more(8))
        #expect(LiveDemoVoiceIntent.parse("eight more reels please") == .more(8))
        #expect(LiveDemoVoiceIntent.parse("huit de plus") == .more(8))
        #expect(LiveDemoVoiceIntent.parse("encore trois") == .more(3))
        #expect(LiveDemoVoiceIntent.parse("200 more") == .more(50))
        #expect(LiveDemoVoiceIntent.parse("0 more") == nil)
        #expect(LiveDemoVoiceIntent.parse("more") == nil)
    }

    @Test("Navigation words")
    func navigation() {
        #expect(LiveDemoVoiceIntent.parse("Next") == .next)
        #expect(LiveDemoVoiceIntent.parse("suivant") == .next)
        #expect(LiveDemoVoiceIntent.parse("skip this one") == .skip)
        #expect(LiveDemoVoiceIntent.parse("Stop.") == .stop)
        #expect(LiveDemoVoiceIntent.parse("arrête") == .stop)
        #expect(LiveDemoVoiceIntent.parse("Let me finish this one") == .hold)
        #expect(LiveDemoVoiceIntent.parse("laisse-moi finir") == .hold)
        #expect(LiveDemoVoiceIntent.parse("read it again") == .repeatLast)
        #expect(LiveDemoVoiceIntent.parse("MORE, go to my messages") == .goTo(.messages))
        #expect(LiveDemoVoiceIntent.parse("More open my mail") == .goTo(.mail))
        #expect(LiveDemoVoiceIntent.parse("MORE va dans mon calendrier") == .goTo(.calendar))
        // Without the wake word, "go to" is ignored: media could say it.
        #expect(LiveDemoVoiceIntent.parse("Go to my messages") == nil)
        #expect(LiveDemoVoiceIntent.parse("open my mail") == nil)
        #expect(LiveDemoVoiceIntent.parse("hey, next please") == .next)
    }

    @Test("Replies are drafts with the original wording")
    func replies() {
        #expect(LiveDemoVoiceIntent.parse("Reply I'm on my way") == .reply("I'm on my way"))
        #expect(LiveDemoVoiceIntent.parse("réponds-lui j'arrive") == .reply("j'arrive"))
        #expect(LiveDemoVoiceIntent.parse("reply") == nil)
    }

    @Test("Ordinary speech, reel audio and actions that are not intents do nothing")
    func noIntent() {
        for text in ["", "what a great video", "next time we should go", "like this", "follow me for more",
                     "send it", "comment below", "share this with your friends", "I'm going to stop by later",
                     "don't stop", "go home"] {
            #expect(LiveDemoVoiceIntent.parse(text) == nil, "\(text)")
        }
    }

    @Test("Wake word mode needs MORE first")
    func wakeWord() {
        #expect(LiveDemoVoiceIntent.parse("next", requireWakeWord: true) == nil)
        #expect(LiveDemoVoiceIntent.parse("MORE, next", requireWakeWord: true) == .next)
        #expect(LiveDemoVoiceIntent.parse("more eight more", requireWakeWord: true) == .more(8))
    }

    @Test("The model's answer counts only if it is exactly one allowed token")
    func model() {
        #expect(LiveDemoVoiceIntent.fromModelAnswer(" next\n") == .next)
        #expect(LiveDemoVoiceIntent.fromModelAnswer("Messages.") == nil)
        #expect(LiveDemoVoiceIntent.fromModelAnswer("calendar") == nil)
        for answer in ["send", "like", "next and stop", "reply hello", "none", ""] {
            #expect(LiveDemoVoiceIntent.fromModelAnswer(answer) == nil)
        }
        #expect(LiveDemoVoiceIntent.worthAskingModel("could you move on"))
        #expect(!LiveDemoVoiceIntent.worthAskingModel(String(repeating: "word ", count: 20)))
    }

    @Test("Reel loop decisions")
    func reelActions() {
        #expect(LiveDemoReelAction.decide(.next) == .advanceNow)
        #expect(LiveDemoReelAction.decide(.more(8)) == .extend(by: 8))
        #expect(LiveDemoReelAction.decide(.hold) == .holdUntilNext)
        #expect(LiveDemoReelAction.decide(.stop) == .endReels)
        #expect(LiveDemoReelAction.decide(.goTo(.messages)) == .leave(.messages))
        #expect(LiveDemoReelAction.decide(.reply("x")) == .ignore)
        #expect(LiveDemoReelAction.extendedTarget(current: 6, by: 8) == 14)
        #expect(LiveDemoReelAction.extendedTarget(current: 45, by: 20) == 50)
    }
}

@Suite("Live morning demo reel change")
struct LiveDemoReelChangeTests {
    @Test("Most elements new: advanced; one counter changed or nothing read: not advanced")
    func change() {
        let before: Set<Int> = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
        #expect(LiveDemoReelChange.advanced(before: before, after: [1, 2, 11, 12, 13, 14, 15, 16, 17, 18]))
        #expect(!LiveDemoReelChange.advanced(before: before, after: [1, 2, 3, 4, 5, 6, 7, 8, 9, 99]))
        #expect(!LiveDemoReelChange.advanced(before: before, after: before))
        #expect(!LiveDemoReelChange.advanced(before: [], after: [1]))
        #expect(!LiveDemoReelChange.advanced(before: before, after: []))
    }
}
