import Foundation
import Testing
@testable import MorningLiveDemo

@Suite("Live morning demo gate")
struct LiveDemoGateTests {
    private let optedIn = ["MO_LIVE_DEMO": "1", "MO_LIVE_DEMO_SCHEME": "1"]

    @Test("Runs only with MO_LIVE_DEMO=1 under the demo scheme on a physical phone outside CI")
    func gate() {
        #expect(LiveDemoGate.evaluate(environment: optedIn, isSimulator: false) == .run)
        for environment in [[:], ["MO_LIVE_DEMO": "1"], ["MO_LIVE_DEMO_SCHEME": "1"],
                            ["MO_LIVE_DEMO": "0", "MO_LIVE_DEMO_SCHEME": "1"],
                            ["MO_LIVE_DEMO": "true", "MO_LIVE_DEMO_SCHEME": "1"],
                            ["MO_LIVE_DEMO": " 1", "MO_LIVE_DEMO_SCHEME": "1"]] {
            #expect(LiveDemoGate.evaluate(environment: environment, isSimulator: false) != .run)
        }
        #expect(LiveDemoGate.evaluate(environment: optedIn, isSimulator: true) != .run)
        for ci in [["CI": "true"], ["CI": "1"], ["GITHUB_ACTIONS": "true"], ["CONTINUOUS_INTEGRATION": "yes"]] {
            #expect(LiveDemoGate.evaluate(environment: ci.merging(optedIn) { $1 }, isSimulator: false) != .run)
        }
        #expect(LiveDemoGate.evaluate(environment: optedIn.merging(["CI": "false"]) { $1 }, isSimulator: false) == .run)
    }

    @Test("Read conversations need their own flag; reel count is bounded")
    func flags() {
        #expect(!LiveDemoGate.allowsReadConversations(environment: ["MO_LIVE_DEMO": "1"]))
        #expect(LiveDemoGate.allowsReadConversations(environment: ["MO_LIVE_DEMO_ANY": "1"]))
        #expect(LiveDemoGate.reelCount(environment: [:]) == 10)
        #expect(LiveDemoGate.reelCount(environment: ["MO_LIVE_DEMO_REELS": "3"]) == 3)
        #expect(LiveDemoGate.reelCount(environment: ["MO_LIVE_DEMO_REELS": "0"]) == 0)
        #expect(LiveDemoGate.reelCount(environment: ["MO_LIVE_DEMO_REELS": "-4"]) == 0)
        #expect(LiveDemoGate.reelCount(environment: ["MO_LIVE_DEMO_REELS": "9999"]) == 50)
        #expect(LiveDemoGate.reelCount(environment: ["MO_LIVE_DEMO_REELS": "ten"]) == 10)
    }
}

@Suite("Live morning demo tap policy")
struct LiveDemoTapPolicyTests {
    @Test("Send, reply, post, like, follow, share and delete controls are always refused")
    func forbiddenControls() {
        let forbidden = ["Send", "send", "Reply", "Reply All", "Forward", "Post", "Like", "Unlike", "Follow",
                         "Following", "Share", "Comment", "Delete", "Move to Trash", "Archive", "Report",
                         "FaceTime", "Call", "Repost", "Save"]
        for label in forbidden {
            for kind in [LiveDemoTapPolicy.Kind.back, .feedTab, .mailbox, .composeField] {
                #expect(!LiveDemoTapPolicy.permits(kind: kind, label: label, identifier: "", isButtonLike: true))
                #expect(!LiveDemoTapPolicy.permits(kind: kind, label: "Reels", identifier: label, isButtonLike: true))
            }
        }
        for identifier in ["sendButton", "SendButton", "likeButton", "follow-button", "reply_button"] {
            #expect(!LiveDemoTapPolicy.permits(kind: .feedTab, label: "Reels", identifier: identifier, isButtonLike: true))
            #expect(!LiveDemoTapPolicy.permits(kind: .listRow, label: "", identifier: identifier, isButtonLike: false))
        }
    }

    @Test("Only the expected navigation labels are allowed for each kind")
    func allowlists() {
        #expect(LiveDemoTapPolicy.permits(kind: .back, label: "Back", identifier: "BackButton", isButtonLike: true))
        #expect(LiveDemoTapPolicy.permits(kind: .back, label: "Messages", identifier: "", isButtonLike: true))
        #expect(LiveDemoTapPolicy.permits(kind: .back, label: "Sam", identifier: "BackButton", isButtonLike: true))
        #expect(!LiveDemoTapPolicy.permits(kind: .back, label: "Delete", identifier: "BackButton", isButtonLike: true))
        #expect(!LiveDemoTapPolicy.permits(kind: .back, label: "Details", identifier: "", isButtonLike: true))
        #expect(LiveDemoTapPolicy.permits(kind: .feedTab, label: "Reels", identifier: "", isButtonLike: true))
        #expect(LiveDemoTapPolicy.permits(kind: .feedTab, label: "For You", identifier: "", isButtonLike: true))
        #expect(!LiveDemoTapPolicy.permits(kind: .feedTab, label: "Profile", identifier: "", isButtonLike: true))
        #expect(LiveDemoTapPolicy.permits(kind: .mailbox, label: "Inbox", identifier: "", isButtonLike: false))
        #expect(!LiveDemoTapPolicy.permits(kind: .mailbox, label: "Sent", identifier: "", isButtonLike: false))
        #expect(LiveDemoTapPolicy.permits(kind: .composeField, label: "iMessage", identifier: "messageBodyField", isButtonLike: false))
        #expect(!LiveDemoTapPolicy.permits(kind: .composeField, label: "Search", identifier: "", isButtonLike: false))
        #expect(!LiveDemoTapPolicy.permits(kind: .composeField, label: "iMessage", identifier: "", isButtonLike: true))
    }

    @Test("A conversation row is opened by type, whatever its message text says")
    func listRows() {
        #expect(LiveDemoTapPolicy.permits(kind: .listRow, label: "Unread, Sam, can you send me the file", identifier: "", isButtonLike: false))
        #expect(!LiveDemoTapPolicy.permits(kind: .listRow, label: "Sam", identifier: "", isButtonLike: true))
    }
}

@Suite("Live morning demo draft and timing")
struct LiveDemoDraftTests {
    @Test("Drafts are one line, without control characters, and capped")
    func sanitize() {
        #expect(LiveDemoDraft.sanitize("On my way\nsee you") == "On my way see you")
        #expect(LiveDemoDraft.sanitize("a\r\n\tb") == "a b")
        #expect(LiveDemoDraft.sanitize(" \n ") == nil)
        #expect(LiveDemoDraft.sanitize(String(repeating: "x", count: 500))?.count == 280)
        #expect(LiveDemoDraft.sanitize("ok\u{0}") == "ok")
    }

    @Test("Speech timeouts grow with length and stay bounded")
    func timing() {
        #expect(LiveDemoSpeechTiming.timeout(forCharacters: 0) == 4)
        #expect(LiveDemoSpeechTiming.timeout(forCharacters: 120) == 14)
        #expect(LiveDemoSpeechTiming.timeout(forCharacters: 100_000) == 90)
        #expect(LiveDemoSpeechTiming.timeout(forCharacters: -5) == 4)
    }
}
