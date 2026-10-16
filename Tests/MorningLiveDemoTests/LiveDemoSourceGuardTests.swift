import Foundation
import Testing

/// The live-morning demo drives Messages, Mail and Instagram on the owner's phone. These
/// checks keep its interaction surface exactly as reviewed: one policy-checked tap site,
/// one typing site (a draft), one drag site (the reel swipe), nothing else.
@Suite("Live morning demo interaction surface")
struct LiveDemoSourceGuardTests {
    private func source(_ path: String = "UITests/LiveMorningDemoTests.swift") throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func count(_ needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    @Test("Exactly one tap, guarded by the policy; no other gesture or key APIs")
    func interactionSurface() throws {
        let code = try source()
        #expect(count(".tap()", in: code) == 1)
        #expect(count("typeText(", in: code) == 1)
        #expect(count("press(forDuration:", in: code) == 1)
        for banned in ["doubleTap", "twoFingerTap", "tap(withNumberOfTaps", "swipeUp(", "swipeDown(", "swipeLeft(",
                       "swipeRight(", "typeKey(", "pinch(", "rotate(", "XCUIKeyboardKey", "\\n\")", "adjust(to",
                       "XCTAttachment", "screenshot()", "NSLog(", "os_log", "Logger(", "debugPrint(", "dump(",
                       "FileHandle.standard", "XCTAssert"] {
            #expect(!code.contains(banned), "Unexpected \(banned) in the live demo")
        }
        let lines = code.components(separatedBy: "\n")
        let tapLine = try #require(lines.firstIndex { $0.contains(".tap()") })
        let functionStart = try #require(lines[..<tapLine].lastIndex { $0.contains("private func tapChecked(") })
        let guardBlock = lines[functionStart..<tapLine].joined(separator: "\n")
        #expect(guardBlock.contains("LiveDemoTapPolicy.permits("))
        #expect(guardBlock.contains("noPrompt(in: app)"))
        #expect(guardBlock.contains("pointIsSafe("))
    }

    @Test("One print site and one failure site, both fed only by LiveDemoReport")
    func reportingSurface() throws {
        let code = try source()
        #expect(count("print(", in: code) == 1)
        #expect(count("XCTFail(", in: code) == 1)
        let lines = code.components(separatedBy: "\n")
        let printLine = try #require(lines.first { $0.contains("print(") })
        #expect(printLine.contains("print(LiveDemoReport.line("))
        let failLine = try #require(lines.first { $0.contains("XCTFail(") })
        #expect(failLine.contains("XCTFail(LiveDemoReport.failureMessage("))
        // Every emitted line is built by LiveDemoReport.line or LiveDemoReport.lines.
        for line in lines where line.contains("emit(") && !line.contains("func emit(") {
            #expect(line.contains("emit(LiveDemoReport.line(") || line.contains("emit(line)"))
        }
    }

    @Test("MORE's voice host exists only in DEBUG builds and never logs")
    func voiceHostIsDebugOnly() throws {
        let host = try source("Sources/MorningOperator/LiveDemoVoiceHost.swift")
        let lines = host.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        #expect(lines.first == "#if DEBUG")
        #expect(lines.last == "#endif")
        // One condition around the whole file: no #else or second #endif could re-expose code.
        #expect(lines.filter { $0.hasPrefix("#endif") }.count == 1)
        #expect(!lines.contains { $0.hasPrefix("#else") || $0.hasPrefix("#elseif") })
        for banned in ["print(", "NSLog(", "os_log", "Logger(", "debugPrint(", "dump(", "FileManager", "UserDefaults",
                       "write(to", "XCTest"] {
            #expect(!host.contains(banned), "Unexpected \(banned) in the voice host")
        }
        #expect(host.contains("requiredLocalEndpoint = .hostPort(host: \"127.0.0.1\""))
        #expect(host.contains("LiveDemoWire.isLoopback(host:"))
        #expect(host.contains("LiveDemoWire.tokensMatch("))
        #expect(host.contains("requiresOnDeviceRecognition = true"))

        // The only reference from the rest of the app sits inside #if DEBUG.
        let app = try source("Sources/MorningOperator/MorningOperatorApp.swift").components(separatedBy: "\n")
        let call = try #require(app.firstIndex { $0.contains("LiveDemoVoiceHost.") })
        let before = app[..<call].last { $0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
        let after = app[(call + 1)...].first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
        #expect(before?.trimmingCharacters(in: .whitespaces) == "#if DEBUG")
        #expect(after?.trimmingCharacters(in: .whitespaces) == "#endif")
        #expect(app.filter { $0.contains("LiveDemoVoiceHost") }.count == 1)
    }

    @Test("The runner does no audio of its own: MORE is the voice")
    func runnerHasNoAudio() throws {
        let code = try source()
        for banned in ["import AVFoundation", "import AVFAudio", "import Speech", "AVAudioSession", "AVSpeechSynthesizer"] {
            #expect(!code.contains(banned), "Unexpected \(banned) in the runner")
        }
    }
}
