import Foundation
import Testing

/// The live-morning demo drives Messages, Mail and Instagram on the owner's phone. These
/// checks keep its interaction surface exactly as reviewed: one policy-checked tap site,
/// one typing site (a draft), two drag sites (back swipe and reel swipe), nothing else.
@Suite("Live morning demo interaction surface")
struct LiveDemoSourceGuardTests {
    private func source() throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("UITests/LiveMorningDemoTests.swift"), encoding: .utf8)
    }

    private func count(_ needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    @Test("Exactly one tap, guarded by the policy; no other gesture or key APIs")
    func interactionSurface() throws {
        let code = try source()
        #expect(count(".tap()", in: code) == 1)
        #expect(count("typeText(", in: code) == 1)
        #expect(count("press(forDuration:", in: code) == 2)
        for banned in ["doubleTap", "twoFingerTap", "tap(withNumberOfTaps", "swipeUp(", "swipeDown(", "swipeLeft(",
                       "swipeRight(", "typeKey(", "pinch(", "rotate(", "XCUIKeyboardKey", "\\n\")", "adjust(to",
                       "XCTAttachment", "screenshot()", "print(", "NSLog(", "os_log", "Logger("] {
            #expect(!code.contains(banned), "Unexpected \(banned) in the live demo")
        }
        let tapLine = try #require(code.components(separatedBy: "\n").firstIndex { $0.contains(".tap()") })
        let lines = code.components(separatedBy: "\n")
        let guardBlock = lines[max(0, tapLine - 8)..<tapLine].joined(separator: "\n")
        #expect(guardBlock.contains("LiveDemoTapPolicy.permits("))
        #expect(guardBlock.contains("noPrompt(in: app)"))
    }
}
