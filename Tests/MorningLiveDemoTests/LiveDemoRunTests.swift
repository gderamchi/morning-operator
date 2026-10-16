import Foundation
import Testing
@testable import MorningLiveDemo

@Suite("Live morning demo run report")
struct LiveDemoReportTests {
    private let strictLine = #"^MO-DEMO( [a-z0-9=._-]+)+$"#

    @Test("Every step is reported, unreached steps as skipped, in a fixed order")
    func lines() {
        var report = LiveDemoReport()
        report.record(.soundCheck, .ran)
        report.record(.messages, .skipped(.ownerDeclined))
        report.record(.mail, .ran)
        let lines = report.lines()
        #expect(lines.count == LiveDemoStep.allCases.count)
        #expect(lines[0] == "MO-DEMO step sound-check ran")
        #expect(lines.contains("MO-DEMO step messages skipped owner-declined"))
        #expect(lines.contains("MO-DEMO step reels skipped not-reached"))
        for line in lines { #expect(line.range(of: strictLine, options: .regularExpression) != nil) }
    }

    @Test("The first outcome wins, so a skip cannot be overwritten by ran")
    func firstWins() {
        var report = LiveDemoReport()
        report.record(.mail, .skipped(.notFound))
        report.record(.mail, .ran)
        #expect(report.outcomes[.mail] == .skipped(.notFound))
    }

    @Test("All app steps skipped fails the run; one app step that ran does not")
    func allSkipped() {
        var report = LiveDemoReport()
        report.record(.soundCheck, .ran)
        report.record(.summary, .ran)
        #expect(report.allAppStepsSkipped)
        report.record(.weather, .ran)
        #expect(!report.allAppStepsSkipped)
    }

    @Test("Lines and failure messages reduce any text to safe tokens")
    func tokens() {
        let line = LiveDemoReport.line(["audio", "route=Speaker", "Hi Sam, see you at 9!"])
        #expect(line.range(of: strictLine, options: .regularExpression) != nil)
        #expect(!line.contains(" "+"Sam"))
        #expect(LiveDemoReport.token("") == "-")
        #expect(LiveDemoReport.token(String(repeating: "a", count: 100)).count == 40)
        let failure = LiveDemoReport.failureMessage(.voiceNoPlayback, detail: ["n=3", "route=Receiver"])
        #expect(failure == "MO-DEMO-FAIL voice-no-playback n=3 route=receiver")
    }
}

@Suite("Live morning demo voice and summary")
struct LiveDemoVoiceAndSummaryTests {
    private func voice(_ id: String, _ language: String, _ quality: LiveDemoVoiceCandidate.Quality,
                       personal: Bool = false, novelty: Bool = false) -> LiveDemoVoiceCandidate {
        .init(identifier: id, language: language, quality: quality, isPersonalVoice: personal, isNoveltyVoice: novelty)
    }

    @Test("Premium beats enhanced beats default; Personal Voice and novelty voices are never used")
    func bestVoice() {
        let voices = [voice("a", "en-US", .standard), voice("b", "en-GB", .enhanced), voice("c", "en-US", .premium, personal: true),
                      voice("d", "en-US", .premium, novelty: true), voice("e", "fr-FR", .premium), voice("f", "en-AU", .premium)]
        #expect(LiveDemoVoicePick.best(from: voices)?.identifier == "f")
        #expect(LiveDemoVoicePick.best(from: voices + [voice("g", "en-US", .premium)])?.identifier == "g")
        #expect(LiveDemoVoicePick.best(from: [voice("a", "en-US", .standard), voice("b", "en-GB", .enhanced)])?.identifier == "b")
        #expect(LiveDemoVoicePick.best(from: [voice("e", "fr-FR", .premium)]) == nil)
    }

    @Test("The download hint is said only when the best voice is a default one")
    func hint() {
        #expect(LiveDemoVoicePick.needsPremiumHint(nil))
        #expect(LiveDemoVoicePick.needsPremiumHint(voice("a", "en-US", .standard)))
        #expect(!LiveDemoVoicePick.needsPremiumHint(voice("b", "en-US", .enhanced)))
    }

    @Test("The summary is short plain sentences from on-screen counts")
    func summary() {
        let sentences = LiveDemoSummary.sentences(unreadConversations: 7, unreadEmails: 3, weather: ("11°", "Cloudy"))
        #expect(sentences == ["Good morning.", "You have 7 unread conversations.", "You have 3 unread emails.",
                              "It's 11 degrees and cloudy."])
        #expect(LiveDemoSummary.sentences(unreadConversations: 1, unreadEmails: 0, weather: nil)
                == ["Good morning.", "You have one unread conversation.", "You have no unread emails."])
        #expect(LiveDemoSummary.sentences(unreadConversations: nil, unreadEmails: nil, weather: ("-3°C", nil))
                == ["Good morning.", "It's minus 3 degrees."])
        #expect(LiveDemoSummary.spokenTemperature("1°") == "1 degree")
    }

    @Test("Yes or no to starting")
    func yesNo() {
        #expect(LiveDemoYesNo.parse("Yes") == .yes)
        #expect(LiveDemoYesNo.parse("Let's go!") == .yes)
        #expect(LiveDemoYesNo.parse("no thanks") == .no)
        #expect(LiveDemoYesNo.parse("") == .unclear)
        #expect(LiveDemoYesNo.parse("what is this") == .unclear)
    }
}

@Suite("Live morning demo wire")
struct LiveDemoWireTests {
    @Test("Requests and responses round-trip as one line each, even with newlines in text")
    func framing() throws {
        let request = LiveDemoWire.Request(token: LiveDemoWire.makeToken(), id: 7, command: .say, text: "Line one\nline two")
        let response = LiveDemoWire.Response(id: 7, ok: false, code: "voice-no-playback", detail: ["route=speaker"])
        var buffer = LiveDemoWire.encode(request) + LiveDemoWire.encode(response)
        #expect(buffer.filter { $0 == 0x0A }.count == 2)
        let lines = try LiveDemoWire.takeLines(from: &buffer)
        #expect(lines.count == 2)
        #expect(buffer.isEmpty)
        #expect(LiveDemoWire.decodeRequest(lines[0]) == request)
        #expect(LiveDemoWire.decodeResponse(lines[1]) == response)
    }

    @Test("A partial line waits; an oversized line is refused")
    func partialAndOversized() throws {
        var buffer = Data("{\"id\":1".utf8)
        #expect(try LiveDemoWire.takeLines(from: &buffer).isEmpty)
        #expect(buffer.count == 7)
        var big = Data(repeating: 0x41, count: LiveDemoWire.maxLineBytes + 1)
        #expect(throws: LiveDemoWire.FramingError.lineTooLong) { try LiveDemoWire.takeLines(from: &big) }
        var bigLine = Data(repeating: 0x41, count: LiveDemoWire.maxLineBytes + 1) + Data([0x0A])
        #expect(throws: LiveDemoWire.FramingError.lineTooLong) { try LiveDemoWire.takeLines(from: &bigLine) }
        #expect(LiveDemoWire.decodeRequest(Data("not json".utf8)) == nil)
    }

    @Test("Tokens: random, well formed, compared exactly")
    func tokens() {
        let a = LiveDemoWire.makeToken(), b = LiveDemoWire.makeToken()
        #expect(a != b)
        #expect(LiveDemoWire.isWellFormedToken(a))
        #expect(LiveDemoWire.tokensMatch(a, a))
        #expect(!LiveDemoWire.tokensMatch(a, b))
        #expect(!LiveDemoWire.tokensMatch(a, String(a.dropLast())))
        #expect(!LiveDemoWire.tokensMatch("", ""))
        #expect(!LiveDemoWire.isWellFormedToken("ABCDEF" + String(repeating: "0", count: 26)))
        #expect(!LiveDemoWire.isWellFormedToken("short"))
    }

    @Test("Ports stay in the dynamic range; only loopback hosts are accepted")
    func portsAndHosts() {
        #expect(LiveDemoWire.portRange.contains(LiveDemoWire.makePort()))
        #expect(LiveDemoWire.port(from: "50000") == 50_000)
        #expect(LiveDemoWire.port(from: "80") == nil)
        #expect(LiveDemoWire.port(from: "x") == nil)
        #expect(LiveDemoWire.port(from: nil) == nil)
        for host in ["127.0.0.1", "::1", "::ffff:127.0.0.1", "::1%lo0"] { #expect(LiveDemoWire.isLoopback(host: host)) }
        for host in ["192.168.1.2", "10.0.0.1", "localhost.evil", "127.0.0.2", ""] { #expect(!LiveDemoWire.isLoopback(host: host)) }
    }

    @Test("Stop-after and reply timeouts")
    func options() {
        #expect(LiveDemoStopAfter.from(environment: ["MO_LIVE_DEMO_STOP_AFTER": "summary"]) == .summary)
        #expect(LiveDemoStopAfter.from(environment: ["MO_LIVE_DEMO_STOP_AFTER": ""]) == nil)
        #expect(LiveDemoStopAfter.from(environment: [:]) == nil)
        #expect(LiveDemoWire.sayTimeout(characters: 0) == 15)
        #expect(LiveDemoWire.sayTimeout(characters: 100_000) == 120)
    }
}
