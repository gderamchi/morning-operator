import AVFoundation
import MorningLiveDemo
import Speech
import XCTest

/// Opt-in, owner-present demo of a morning run on a tethered iPhone. The XCUITest runner is
/// the only process allowed to drive other apps (a shipped app cannot), so this lives here.
///
/// It checks the sound, looks at Messages, Mail and Weather, says a short summary, asks
/// whether to start, reads unread messages and asks about replies (listening on-device
/// only), types a spoken reply as a DRAFT, reads unread mail subjects, then swipes reels.
///
/// SENDING IS IMPOSSIBLE IN THIS FILE. Every tap goes through `tapChecked`, which asks
/// `LiveDemoTapPolicy` first; a label or identifier with send, reply, post, like, follow,
/// share, delete (and similar) is always refused. Typing removes newlines, so a return key
/// can never be pressed. Whether MORE may send after a spoken confirmation is a separate
/// owner decision (GitHub issue #111), not something this test may grow into.
/// `Tests/MorningLiveDemoTests/LiveDemoSourceGuardTests.swift` fails the package tests if
/// this file gains another tap, typing, press, print or failure site.
///
/// Honesty: every utterance must render and be played back by the audio hardware, or the
/// run FAILS (a silent run must never pass). Each step is reported as ran or skipped with a
/// fixed reason code, and the run fails if every app step was skipped.
///
/// Privacy: no screenshots or attachments are kept. Message, mail and transcript text is
/// spoken only; printed lines and failure messages carry fixed codes and technical tokens.
@MainActor
final class LiveMorningDemoTests: XCTestCase {
    private enum App {
        static let messages = "com.apple.MobileSMS"
        static let mail = "com.apple.mobilemail"
        static let weather = "com.apple.weather"
        static let instagram = "com.burbn.instagram"
        static let tiktok = "com.zhiliaoapp.musically"
        static let springboard = "com.apple.springboard"
    }

    private struct VoiceFailed: Error {}

    private var environment: [String: String] { ProcessInfo.processInfo.environment }
    private var audio: DemoAudio?
    private var listening = false
    private var report = LiveDemoReport()
    private var utteranceCount = 0

    func testLiveMorningDemo() throws {
        #if targetEnvironment(simulator)
        let isSimulator = true
        #else
        let isSimulator = false
        #endif
        if case .skip(let reason) = LiveDemoGate.evaluate(environment: environment, isSimulator: isSimulator) {
            throw XCTSkip(reason)
        }
        // A missing app or an unexpected screen skips that step; it must not end the demo.
        continueAfterFailure = true
        // Enforced when the command passes -test-timeouts-enabled YES (scripts/live-demo.sh).
        executionTimeAllowance = 30 * 60
        do {
            try runDemo()
        } catch {
            // A voice failure was already recorded as a test failure; stop and report.
        }
        finish()
    }

    private func runDemo() throws {
        // 1. Sound, set up while the runner is still in front: iOS does not let a
        //    background process start audio, so the session and engine start now and stay
        //    running until the end.
        let runnerState = UIApplication.shared.applicationState
        switch XCTContext.runActivity(named: "Start audio", block: { _ in DemoAudio.start() }) {
        case .failed(let failure, let detail):
            emit(LiveDemoReport.line(["audio", "runner=\(Self.name(runnerState))"] + detail))
            report.record(.soundCheck, .skipped(.voiceFailed))
            fail(failure, detail)
            throw VoiceFailed()
        case .ready(let ready):
            audio = ready
            emit(LiveDemoReport.line(["audio", "runner=\(Self.name(runnerState))"] + ready.diagnostics()))
            emit(LiveDemoReport.line(["voice", "quality=\(ready.voiceQuality.name)"]))
        }
        try say("Sound check.")
        report.record(.soundCheck, .ran)
        if let audio, LiveDemoVoicePick.needsPremiumHint(audio.chosenVoice) {
            try say("For a better voice, download a Premium voice in Settings.")
        }

        // 2. Listening (on-device only).
        if DemoAudio.permissionStillUndecided {
            try say("If the phone asks for the microphone or speech recognition, tap Allow.")
        }
        let listeningSkip: LiveDemoSkip? = XCTContext.runActivity(named: "Enable on-device listening") { _ in
            guard let audio else { return .audioInputFailed }
            return audio.enableListening()
        }
        if let skip = listeningSkip {
            report.record(.listening, .skipped(skip))
            try say("I can't listen today. I'll skip replies.")
        } else {
            listening = true
            report.record(.listening, .ran)
        }

        // 3. Look first, then say a short summary.
        try say("Good morning. One moment. I'm looking at your morning.")
        let unreadConversations = try XCTContext.runActivity(named: "Survey Messages") { _ in try surveyMessages() }
        let unreadEmails = try XCTContext.runActivity(named: "Survey Mail") { _ in try surveyMail() }
        let weather = try XCTContext.runActivity(named: "Weather") { _ in try readWeather() }
        for sentence in LiveDemoSummary.sentences(unreadConversations: unreadConversations, unreadEmails: unreadEmails,
                                                  weather: weather).dropFirst() {
            try say(sentence)
        }
        report.record(.summary, .ran)
        hold(2)

        // 4. Ask, then read.
        if let count = unreadConversations {
            if count == 0 && !LiveDemoGate.allowsReadConversations(environment: environment) {
                report.record(.messages, .ran)
            } else if try askToStartWithMessages() {
                try XCTContext.runActivity(named: "Messages") { _ in try readMessages() }
            } else {
                report.record(.messages, .skipped(.ownerDeclined))
            }
        }
        if let count = unreadEmails {
            if count == 0 {
                report.record(.mail, .ran)
            } else {
                try XCTContext.runActivity(named: "Mail") { _ in try readMail() }
            }
        }
        try XCTContext.runActivity(named: "Reels") { _ in try scrollReels() }

        try XCTContext.runActivity(named: "Return to MORE") { _ in
            let more = XCUIApplication()
            more.activate()
            _ = more.wait(for: .runningForeground, timeout: 10)
            hold(2)
            try say("That's the morning demo done. Nothing was sent.")
        }
    }

    /// Prints the step report and fails the run if no app step ran. Always runs last.
    private func finish() {
        for line in report.lines() { emit(line) }
        if report.allAppStepsSkipped { fail(.allAppStepsSkipped, []) }
        audio?.shutDown()
        audio = nil
    }

    private func askToStartWithMessages() throws -> Bool {
        try say("Shall we start with your messages?")
        guard listening, let audio else {
            hold(3)
            try say("I'll start with your messages.")
            return true
        }
        switch LiveDemoYesNo.parse(audio.listen() ?? "") {
        case .yes:
            try say("OK.")
            return true
        case .no:
            try say("OK. I'll skip your messages.")
            return false
        case .unclear:
            try say("I'll take that as a yes.")
            return true
        }
    }

    // MARK: - Messages

    /// Opens the conversation list and counts visible unread conversations. Nil, with the
    /// step recorded as skipped, when Messages or its list is not available.
    private func surveyMessages() throws -> Int? {
        let messages: XCUIApplication
        switch launch(App.messages) {
        case .skipped(let reason):
            report.record(.messages, .skipped(reason))
            return nil
        case .app(let app):
            messages = app
        }
        guard showConversationList(in: messages) else {
            report.record(.messages, .skipped(.notFound))
            return nil
        }
        hold(2)
        return visibleRows(in: messages).filter(\.row.isUnread).count
    }

    private func readMessages() throws {
        guard case .app(let messages) = launch(App.messages), showConversationList(in: messages) else {
            report.record(.messages, .skipped(.notFound))
            try say("I couldn't open your messages. I'll move on.")
            return
        }
        let allowRead = LiveDemoGate.allowsReadConversations(environment: environment)
        let chosen = Array(visibleRows(in: messages).filter { allowRead || $0.row.isUnread }.prefix(3))
        report.record(.messages, .ran)
        guard !chosen.isEmpty else {
            try say("There are no unread messages now.")
            return
        }
        for (index, target) in chosen.enumerated() {
            try XCTContext.runActivity(named: "Messages conversation \(index + 1)") { _ in
                try openConversation(target.row, in: messages)
            }
            guard messages.state == .runningForeground else { return }
        }
    }

    private func openConversation(_ row: LiveDemoListRow, in messages: XCUIApplication) throws {
        guard noPrompt(in: messages), showConversationList(in: messages),
              let fresh = visibleRows(in: messages).first(where: {
                  $0.row.sender == row.sender && $0.row.detail == row.detail
              }),
              tapChecked(fresh.target, kind: .listRow, in: messages) else {
            try say("I couldn't open that conversation. I'll move on.")
            return
        }
        hold(2)
        try say("Message from \(row.sender).")
        if !row.detail.isEmpty { try say(row.detail) }
        hold(1)
        try offerReply(in: messages)
        hold(2)
        goBack(in: messages)
        hold(1)
    }

    private func offerReply(in messages: XCUIApplication) throws {
        try say("Do you want to reply?")
        guard listening, let audio else {
            hold(4)
            try say("No answer. I'll move on.")
            return
        }
        var intent = LiveDemoReplyIntent.parse(audio.listen() ?? "")
        if intent == .affirm {
            try say("What should I say?")
            intent = LiveDemoReplyIntent.parseDictation(audio.listen(maxSeconds: 15) ?? "")
        }
        switch intent {
        case .draft(let text):
            if typeDraft(text, in: messages) {
                try say("I wrote a draft. It says: \(text). I did not send it.")
                hold(4)
            } else {
                try say("I couldn't find the message field. I left it.")
            }
        case .decline:
            try say("OK. No reply.")
        case .silence:
            try say("I didn't hear anything. I'll move on.")
        case .affirm, .unclear:
            try say("I didn't catch a reply. I'll leave it.")
        }
    }

    /// Focuses the compose field and types one sanitized line. Never taps Send: there is no
    /// code here that could, and the keyboard's return key is never pressed.
    private func typeDraft(_ text: String, in messages: XCUIApplication) -> Bool {
        guard let line = LiveDemoDraft.sanitize(text), noPrompt(in: messages) else { return false }
        let fields = snapshotDescendants(of: messages).filter { node in
            (node.elementType == .textView || node.elementType == .textField)
                && LiveDemoTapPolicy.permits(kind: .composeField, label: node.label.isEmpty ? (node.placeholderValue ?? "") : node.label,
                                             identifier: node.identifier, isButtonLike: false)
        }
        guard fields.count == 1, let field = fields.first,
              tapChecked(Target(field, label: field.label.isEmpty ? (field.placeholderValue ?? "") : field.label),
                         kind: .composeField, in: messages) else { return false }
        guard messages.keyboards.firstMatch.waitForExistence(timeout: 4) else { return false }
        messages.typeText(line)
        return true
    }

    /// The Messages list is showing when no back button is offered. Goes back at most twice.
    private func showConversationList(in messages: XCUIApplication) -> Bool {
        for _ in 0..<3 {
            if !messages.wait(for: .runningForeground, timeout: 5) { return false }
            if messages.navigationBars["Messages"].exists || messages.staticTexts["Messages"].exists,
               backButton(in: messages) == nil {
                return true
            }
            guard noPrompt(in: messages), goBack(in: messages) else { return false }
            hold(1.5)
        }
        return false
    }

    // MARK: - Mail

    private func surveyMail() throws -> Int? {
        let mail: XCUIApplication
        switch launch(App.mail) {
        case .skipped(let reason):
            report.record(.mail, .skipped(reason))
            return nil
        case .app(let app):
            mail = app
        }
        guard showInbox(in: mail) else {
            report.record(.mail, .skipped(.notFound))
            return nil
        }
        hold(2)
        return visibleRows(in: mail).filter(\.row.isUnread).count
    }

    private func readMail() throws {
        guard case .app(let mail) = launch(App.mail), showInbox(in: mail) else {
            report.record(.mail, .skipped(.notFound))
            try say("I couldn't open your inbox. I'll move on.")
            return
        }
        hold(1)
        let unread = Array(visibleRows(in: mail).filter(\.row.isUnread).prefix(3))
        report.record(.mail, .ran)
        guard !unread.isEmpty else {
            try say("There is no unread mail now.")
            return
        }
        try say("Now your email.")
        for (index, mailRow) in unread.enumerated() {
            try XCTContext.runActivity(named: "Mail row \(index + 1)") { _ in
                try say("From \(mailRow.row.sender).")
                if !mailRow.row.detail.isEmpty { try say(mailRow.row.detail) }
                hold(1)
            }
        }
        hold(3)
    }

    private func showInbox(in mail: XCUIApplication) -> Bool {
        func onInbox() -> Bool {
            mail.navigationBars.matching(NSPredicate(format: "identifier IN %@", ["Inbox", "All Inboxes"])).count > 0
        }
        for _ in 0..<3 {
            if !mail.wait(for: .runningForeground, timeout: 5) || !noPrompt(in: mail) { return false }
            if onInbox() { return true }
            // Open Inbox only from the Mailboxes screen, so a message row whose label starts
            // with "Inbox" can never be opened; anywhere else, go back one level.
            let onMailboxes = mail.navigationBars.matching(NSPredicate(format: "identifier == %@", "Mailboxes")).count > 0
            let mailbox = !onMailboxes ? nil : snapshotDescendants(of: mail).first { node in
                node.elementType == .cell
                    && LiveDemoTapPolicy.permits(kind: .mailbox,
                                                 label: node.label.components(separatedBy: ", ").first ?? "",
                                                 identifier: "", isButtonLike: false)
            }
            if let mailbox {
                guard tapChecked(Target(mailbox, label: mailbox.label.components(separatedBy: ", ").first ?? ""),
                                 kind: .mailbox, in: mail) else { return false }
            } else {
                guard goBack(in: mail) else { return false }
            }
            hold(1.5)
        }
        return onInbox()
    }

    // MARK: - Weather

    /// Opens Weather and returns what is on screen. The summary is spoken by the caller
    /// while Weather is still showing.
    private func readWeather() throws -> (temperature: String, condition: String?)? {
        let weather: XCUIApplication
        switch launch(App.weather) {
        case .skipped(let reason):
            report.record(.weather, .skipped(reason))
            return nil
        case .app(let app):
            weather = app
        }
        hold(3)
        let texts = snapshotDescendants(of: weather)
            .filter { $0.elementType == .staticText && isOnScreen($0.frame, in: weather) }
            .sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }
            .map(\.label)
        guard let summary = LiveDemoWeather.summary(texts: texts) else {
            report.record(.weather, .skipped(.notFound))
            return nil
        }
        report.record(.weather, .ran)
        return summary
    }

    // MARK: - Reels

    private func scrollReels() throws {
        let count = LiveDemoGate.reelCount(environment: environment)
        guard count > 0 else {
            report.record(.reels, .skipped(.disabled))
            return
        }
        var tabLabels = ["Reels"]
        var launched = launch(App.instagram)
        if case .skipped(.notInstalled) = launched {
            launched = launch(App.tiktok)
            tabLabels = ["For You", "Home"]
        }
        let feed: XCUIApplication
        switch launched {
        case .skipped(let reason):
            report.record(.reels, .skipped(reason))
            try say(reason == .notInstalled ? "Instagram and TikTok are not installed. No reels today."
                    : "The reels app is showing a prompt. I'll skip reels.")
            return
        case .app(let app):
            feed = app
        }
        hold(3)
        let tab = snapshotDescendants(of: feed).first { node in
            node.elementType == .button && tabLabels.contains(node.label)
                && LiveDemoTapPolicy.permits(kind: .feedTab, label: node.label, identifier: node.identifier, isButtonLike: true)
        }
        // Swipes happen only after the feed tab itself was found and tapped.
        guard let tab, tapChecked(Target(tab), kind: .feedTab, in: feed) else {
            report.record(.reels, .skipped(.notFound))
            try say("I couldn't find the video feed. Are you logged in? I'll skip reels.")
            return
        }
        hold(2)
        report.record(.reels, .ran)
        try say("Now some reels. I'll swipe every eight seconds. I won't like or follow anything.")
        for index in 0..<count {
            hold(8)
            let fine = XCTContext.runActivity(named: "Reel \(index + 1)") { _ in
                guard feed.state == .runningForeground, noPrompt(in: feed),
                      !feed.keyboards.firstMatch.exists else { return false }
                // One upward drag from the middle of the screen: a drag, never a tap or double tap.
                let start = feed.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
                let end = feed.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.22))
                start.press(forDuration: 0.05, thenDragTo: end)
                return true
            }
            if !fine {
                try say("Something changed on screen. I stopped the reels.")
                return
            }
        }
        hold(4)
    }

    // MARK: - Speaking, reporting and holding

    /// Speaks one sentence and waits until the hardware has played it. Any failure fails the
    /// run with a fixed code and stops the demo: it must never continue silently.
    private func say(_ text: String) throws {
        guard let audio else { throw VoiceFailed() }
        utteranceCount += 1
        let result = XCTContext.runActivity(named: "Speak") { _ in audio.speak(text) }
        if case .failed(let failure, let detail) = result {
            report.record(.soundCheck, .skipped(.voiceFailed))
            fail(failure, detail + ["n=\(utteranceCount)"] + audio.diagnostics())
            throw VoiceFailed()
        }
    }

    /// The only failure site. Messages are fixed codes and technical tokens.
    private func fail(_ failure: LiveDemoFailure, _ detail: [String]) {
        XCTFail(LiveDemoReport.failureMessage(failure, detail: detail))
    }

    /// The only print site. Lines come from LiveDemoReport, which reduces every token to
    /// `[a-z0-9=._-]`, so no sentence can be printed.
    private func emit(_ line: String) {
        print(LiveDemoReport.line(line.split(separator: " ").dropFirst().map(String.init)))
    }

    private static func name(_ state: UIApplication.State) -> String {
        switch state {
        case .active: "active"
        case .inactive: "inactive"
        case .background: "background"
        @unknown default: "unknown"
        }
    }

    private func hold(_ seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline { RunLoop.current.run(until: min(deadline, Date().addingTimeInterval(0.1))) }
    }

    private enum Launched {
        case app(XCUIApplication)
        case skipped(LiveDemoSkip)
    }

    /// Brings an app to the front. A missing app, or one showing a prompt, is a skip with a
    /// reason, never a test failure and never an answered prompt.
    private func launch(_ bundleID: String) -> Launched {
        let app = XCUIApplication(bundleIdentifier: bundleID)
        XCTExpectFailure("The app may not be installed on this phone.", options: .nonStrict()) {
            app.activate()
        }
        guard app.wait(for: .runningForeground, timeout: 10) else { return .skipped(.notInstalled) }
        guard noPrompt(in: app) else { return .skipped(.promptVisible) }
        return .app(app)
    }

    // MARK: - Prompts and navigation

    /// Never accepts or dismisses a prompt: a visible alert or sheet skips the step.
    private func noPrompt(in app: XCUIApplication) -> Bool {
        let springboard = XCUIApplication(bundleIdentifier: App.springboard)
        return app.alerts.count == 0 && app.sheets.count == 0 && springboard.alerts.count == 0
    }

    private func backButton(in app: XCUIApplication) -> Target? {
        guard let bar = snapshotDescendants(of: app).first(where: { $0.elementType == .navigationBar }) else { return nil }
        let buttons = Self.descendants(of: bar).filter { $0.elementType == .button && isOnScreen($0.frame, in: app) }
        let back = buttons.first { node in
            LiveDemoTapPolicy.permits(kind: .back, label: node.label, identifier: node.identifier, isButtonLike: true)
        }
        return back.map { Target($0) }
    }

    /// Only a permitted back button. There is no swipe fallback: a horizontal swipe on a
    /// list row is a row action in Messages and Mail (mark unread, delete), not navigation.
    @discardableResult
    private func goBack(in app: XCUIApplication) -> Bool {
        guard let back = backButton(in: app) else { return false }
        return tapChecked(back, kind: .back, in: app)
    }

    // MARK: - Snapshots and the one checked tap

    /// Value copy of an element, so taps use a frame and never a label-bearing query.
    @MainActor
    private struct Target {
        let elementType: XCUIElement.ElementType
        /// The label the policy judges (for a mailbox row, its first component).
        let label: String
        /// The element's own label, used only in memory to re-identify it before tapping.
        let rawLabel: String
        let identifier: String
        let frame: CGRect
        let blockingButtons: [CGRect]

        init(_ node: any XCUIElementSnapshot, label: String? = nil) {
            elementType = node.elementType
            self.label = label ?? node.label
            rawLabel = node.label
            identifier = node.identifier
            frame = node.frame
            // Buttons nested inside the element that would be refused on their own.
            blockingButtons = LiveMorningDemoTests.descendants(of: node).dropFirst()
                .filter { LiveMorningDemoTests.isButtonLike($0.elementType)
                    && (LiveDemoTapPolicy.containsForbiddenWord($0.label) || LiveDemoTapPolicy.containsForbiddenWord($0.identifier)) }
                .map { $0.frame }
        }
    }

    /// The single place this test taps. The policy decides; a refused tap returns false.
    private func tapChecked(_ target: Target, kind: LiveDemoTapPolicy.Kind, in app: XCUIApplication) -> Bool {
        let point = CGPoint(x: target.frame.midX, y: target.frame.midY)
        guard LiveDemoTapPolicy.permits(kind: kind, label: target.label, identifier: target.identifier,
                                        isButtonLike: Self.isButtonLike(target.elementType)),
              isOnScreen(target.frame, in: app),
              !target.blockingButtons.contains(where: { $0.contains(point) }),
              noPrompt(in: app), pointIsSafe(point, for: target, kind: kind, in: app) else { return false }
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x, dy: point.y)).tap()
        return true
    }

    /// Fresh hit-test just before tapping: the target must still be there with the same
    /// frame, and no other button-like control, nor any control with a forbidden word,
    /// may cover the point. Catches layout changes after the snapshot and overlays.
    private func pointIsSafe(_ point: CGPoint, for target: Target, kind: LiveDemoTapPolicy.Kind,
                             in app: XCUIApplication) -> Bool {
        let nodes = snapshotDescendants(of: app)
        // Exactly one fresh element must still be the same control: type, frame, label and
        // identifier. A same-sized replacement (say Back turning into Delete) does not match.
        let matches = nodes.indices.filter { index in
            let node = nodes[index]
            return node.elementType == target.elementType && node.frame == target.frame
                && node.label == target.rawLabel && node.identifier == target.identifier
        }
        guard matches.count == 1, let matched = matches.first else { return false }
        let fresh = nodes[matched]
        let judgedLabel = kind == .mailbox ? (fresh.label.components(separatedBy: ", ").first ?? "") : fresh.label
        guard LiveDemoTapPolicy.permits(kind: kind, label: judgedLabel.isEmpty && kind == .composeField
                                            ? (fresh.placeholderValue ?? "") : judgedLabel,
                                        identifier: fresh.identifier,
                                        isButtonLike: Self.isButtonLike(fresh.elementType)) else { return false }
        for index in nodes.indices where index != matched && nodes[index].frame.contains(point) {
            let node = nodes[index]
            // Any other control under the finger, or anything whose identifier names an action.
            if Self.isButtonLike(node.elementType) || LiveDemoTapPolicy.containsForbiddenWord(node.identifier) {
                return false
            }
        }
        return true
    }

    private struct RowTarget {
        let row: LiveDemoListRow
        let target: Target
    }

    /// Visible list cells in screen order, parsed without keeping or printing their text.
    private func visibleRows(in app: XCUIApplication) -> [RowTarget] {
        snapshotDescendants(of: app)
            .filter { $0.elementType == .cell && isOnScreen($0.frame, in: app) && $0.frame.height >= 40 }
            .sorted { $0.frame.minY < $1.frame.minY }
            .compactMap { cell in
                let texts = Self.descendants(of: cell).filter { $0.elementType == .staticText }.map(\.label)
                guard let row = LiveDemoListRow.parse(label: cell.label, value: (cell.value as? String) ?? "", texts: texts)
                else { return nil }
                return RowTarget(row: row, target: Target(cell))
            }
    }

    private func snapshotDescendants(of app: XCUIApplication) -> [any XCUIElementSnapshot] {
        guard let root = try? app.snapshot() else { return [] }
        return Self.descendants(of: root)
    }

    /// Depth-first, bounded so a pathological tree cannot stall the demo.
    private static func descendants(of root: any XCUIElementSnapshot) -> [any XCUIElementSnapshot] {
        var result: [any XCUIElementSnapshot] = []
        var stack: [any XCUIElementSnapshot] = [root]
        while let node = stack.popLast(), result.count < 5_000 {
            result.append(node)
            stack.append(contentsOf: node.children.reversed())
        }
        return result
    }

    private static func isButtonLike(_ type: XCUIElement.ElementType) -> Bool {
        [.button, .link, .toggle, .switch, .menuItem, .menuButton, .segmentedControl, .key, .slider, .stepper,
         .picker, .pickerWheel, .popUpButton, .radioButton, .checkBox, .incrementArrow, .decrementArrow].contains(type)
    }

    private func isOnScreen(_ frame: CGRect, in app: XCUIApplication) -> Bool {
        let screen = app.windows.firstMatch.exists ? app.windows.firstMatch.frame : app.frame
        return !frame.isEmpty && screen.contains(CGPoint(x: frame.midX, y: frame.midY))
    }
}

// MARK: - Audio

/// One audio path for the whole run, owned by the runner:
///
/// - Session `.playAndRecord` with `.defaultToSpeaker` (the loudspeaker, not the earpiece)
///   and `.allowBluetoothA2DP`, plus `.mixWithOthers` so a reels app playing sound does not
///   interrupt it. This category ignores the Ring/Silent switch. It is activated while the
///   runner is still in front and never deactivated until `shutDown`.
/// - Speech is rendered with `AVSpeechSynthesizer.write` and played through our own
///   `AVAudioEngine` player. The engine keeps running between sentences, so the session
///   stays in use while other apps are in front. Each sentence counts as spoken only when
///   the player reports `.dataPlayedBack` (the hardware played it), not on a timer.
/// - Listening: on-device recognition only (`requiresOnDeviceRecognition = true`); no
///   audio leaves the phone. Microphone buffers reach the recognizer only during a turn.
///   Transcripts are returned to the caller and never logged.
final class DemoAudio: @unchecked Sendable {
    enum StartResult: Sendable {
        case ready(DemoAudio)
        case failed(LiveDemoFailure, [String])
    }

    enum SpeakResult: Sendable {
        case spoken
        case failed(LiveDemoFailure, [String])
    }

    private let lock = NSLock()
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let synthesizer = AVSpeechSynthesizer()
    let voice: AVSpeechSynthesisVoice?
    let chosenVoice: LiveDemoVoiceCandidate?
    var voiceQuality: LiveDemoVoiceCandidate.Quality { chosenVoice?.quality ?? .standard }
    private var speechFormat: AVAudioFormat?

    private var recognizer: SFSpeechRecognizer?
    private var hasInputTap = false
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var latest = ""
    private var lastChange: Date?
    private var isFinal = false
    private var recognitionFailed = false

    private init(chosenVoice: LiveDemoVoiceCandidate?) {
        self.chosenVoice = chosenVoice
        voice = chosenVoice.flatMap { AVSpeechSynthesisVoice(identifier: $0.identifier) }
            ?? AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.usesApplicationAudioSession = true
        // Any interruption, engine configuration change or route change bumps the
        // generation; a sentence whose playback overlaps a bump does not count as heard.
        let center = NotificationCenter.default
        for name in [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification,
                     AVAudioSession.mediaServicesWereResetNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in self?.bump() })
        }
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
            self?.bump()
        })
    }

    private var observers: [any NSObjectProtocol] = []
    private var generation = 0

    private func bump() { lock.withLock { generation += 1 } }
    private var currentGeneration: Int { lock.withLock { generation } }

    static func start() -> StartResult {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.defaultToSpeaker, .allowBluetoothA2DP, .mixWithOthers])
            try session.setActive(true)
        } catch {
            return .failed(.audioSessionFailed, ["os=\((error as NSError).code)"])
        }
        let audio = DemoAudio(chosenVoice: LiveDemoVoicePick.best(from: installedVoices()))
        // Render one probe sentence to learn the voice's sample format, then wire the
        // player at that format (as standard float, which the engine requires).
        guard let probe = audio.render("Sound check."), let first = probe.first else {
            return .failed(.voiceNoRender, [])
        }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: first.format.sampleRate,
                                         channels: first.format.channelCount) else {
            return .failed(.voiceFormat, [])
        }
        audio.speechFormat = format
        audio.engine.attach(audio.player)
        audio.engine.connect(audio.player, to: audio.engine.mainMixerNode, format: format)
        audio.engine.prepare()
        do {
            try audio.engine.start()
        } catch {
            return .failed(.audioEngineFailed, ["os=\((error as NSError).code)"])
        }
        audio.player.play()
        return .ready(audio)
    }

    static func installedVoices() -> [LiveDemoVoiceCandidate] {
        AVSpeechSynthesisVoice.speechVoices().map { voice in
            let quality: LiveDemoVoiceCandidate.Quality = switch voice.quality {
            case .premium: .premium
            case .enhanced: .enhanced
            default: .standard
            }
            return LiveDemoVoiceCandidate(identifier: voice.identifier, language: voice.language, quality: quality,
                                          isPersonalVoice: voice.voiceTraits.contains(.isPersonalVoice),
                                          isNoveltyVoice: voice.voiceTraits.contains(.isNoveltyVoice))
        }
    }

    /// Route, volume and engine state as short tokens for the status lines.
    func diagnostics() -> [String] {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs.map(\.portType.rawValue).joined(separator: "+")
        return ["route=\(outputs.isEmpty ? "none" : outputs)",
                "volume=\(String(format: "%.2f", session.outputVolume))",
                "engine=\(engine.isRunning ? "running" : "stopped")"]
    }

    // MARK: Speaking

    func speak(_ text: String) -> SpeakResult {
        guard let format = speechFormat else { return .failed(.voiceFormat, []) }
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs.map(\.portType)
        if outputs.isEmpty { return .failed(.routeMissing, []) }
        if outputs.contains(.builtInReceiver) { return .failed(.routeEarpiece, []) }
        if session.outputVolume <= 0 { return .failed(.volumeZero, []) }
        guard let rendered = render(text), !rendered.isEmpty else { return .failed(.voiceNoRender, []) }
        var buffers: [AVAudioPCMBuffer] = []
        for buffer in rendered {
            guard let converted = convert(buffer, to: format) else { return .failed(.voiceFormat, []) }
            buffers.append(converted)
        }
        if !engine.isRunning {
            do { try engine.start() } catch { return .failed(.audioEngineFailed, ["os=\((error as NSError).code)"]) }
        }
        if !player.isPlaying { player.play() }
        let startGeneration = currentGeneration
        let started = Date()
        let done = Flag()
        for (index, buffer) in buffers.enumerated() {
            if index == buffers.count - 1 {
                player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in done.set() }
            } else {
                player.scheduleBuffer(buffer)
            }
        }
        let frames = buffers.reduce(0.0) { $0 + Double($1.frameLength) }
        let deadline = Date().addingTimeInterval(frames / format.sampleRate + 5)
        var mutedDuringPlayback = false
        while Date() < deadline, !done.isSet {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            if session.outputVolume <= 0 { mutedDuringPlayback = true }
        }
        guard done.isSet else {
            player.stop()
            player.play()
            return .failed(.voiceNoPlayback, [])
        }
        // The completion also fires when the player is stopped, so check that playback was
        // not cut short: nothing changed the audio path, the engine and player are still
        // running, the volume stayed up, and at least most of the sentence's time passed.
        if currentGeneration != startGeneration || !engine.isRunning || !player.isPlaying {
            return .failed(.audioInterrupted, ["engine=\(engine.isRunning ? "running" : "stopped")"])
        }
        if mutedDuringPlayback || session.outputVolume <= 0 { return .failed(.volumeZero, []) }
        if Date().timeIntervalSince(started) < 0.8 * frames / format.sampleRate {
            return .failed(.voiceNoPlayback, ["cut-short"])
        }
        if session.currentRoute.outputs.contains(where: { $0.portType == .builtInReceiver }) {
            return .failed(.routeEarpiece, [])
        }
        // A short gap between sentences.
        let gap = Date().addingTimeInterval(0.25)
        while Date() < gap { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        return .spoken
    }

    /// Renders a sentence to PCM buffers. Nil if nothing arrives in time.
    private func render(_ text: String) -> [AVAudioPCMBuffer]? {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        let collected = BufferCollector()
        synthesizer.write(utterance) { buffer in
            guard let pcm = buffer as? AVAudioPCMBuffer else { return }
            if pcm.frameLength == 0 { collected.finish() } else { collected.append(pcm) }
        }
        let deadline = Date().addingTimeInterval(LiveDemoSpeechTiming.timeout(forCharacters: text.count))
        while Date() < deadline, !collected.isFinished {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        guard collected.isFinished else {
            synthesizer.stopSpeaking(at: .immediate)
            return nil
        }
        return collected.buffers
    }

    private func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        if buffer.format == format { return buffer }
        guard buffer.format.sampleRate == format.sampleRate,
              buffer.format.channelCount == format.channelCount,
              let converter = AVAudioConverter(from: buffer.format, to: format),
              let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: buffer.frameLength) else { return nil }
        do { try converter.convert(to: output, from: buffer) } catch { return nil }
        return output
    }

    // MARK: Listening

    static var permissionStillUndecided: Bool {
        SFSpeechRecognizer.authorizationStatus() == .notDetermined
            || AVAudioApplication.shared.recordPermission == .undetermined
    }

    /// Nil when listening is ready; otherwise why not. Called while the runner is in front.
    func enableListening() -> LiveDemoSkip? {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.supportsOnDeviceRecognition else { return .onDeviceUnavailable }
        let speechGranted = Box<Bool?>(nil)
        let micGranted = Box<Bool?>(nil)
        SFSpeechRecognizer.requestAuthorization { speechGranted.set($0 == .authorized) }
        AVAudioApplication.requestRecordPermission { micGranted.set($0) }
        let deadline = Date().addingTimeInterval(45)
        while Date() < deadline, speechGranted.get() == nil || micGranted.get() == nil {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        guard speechGranted.get() == true, micGranted.get() == true else { return .permissionDenied }
        guard recognizer.isAvailable else { return .onDeviceUnavailable }
        // Add the microphone to the running engine: stop, tap, start again.
        engine.stop()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        var started = false
        if format.channelCount > 0, format.sampleRate > 0 {
            input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
                self?.append(buffer)
            }
            hasInputTap = true
            engine.prepare()
            started = (try? engine.start()) != nil
        }
        if !started {
            // Keep speaking even if the microphone cannot run.
            if hasInputTap { input.removeTap(onBus: 0); hasInputTap = false }
            engine.prepare()
            try? engine.start()
            player.play()
            return .audioInputFailed
        }
        player.play()
        self.recognizer = recognizer
        // Let the route and configuration notifications from adding the microphone arrive
        // now, before the next sentence starts, so they are not mistaken for an interruption.
        let settle = Date().addingTimeInterval(1)
        while Date() < settle { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
        return nil
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        lock.withLock { request?.append(buffer) }
    }

    /// One listening turn: ends 1.8 s after speech stops, after `maxSeconds`, or after 7 s
    /// of silence. Returns nil if the turn could not run.
    func listen(maxSeconds: TimeInterval = 10) -> String? {
        guard let recognizer, hasInputTap, engine.isRunning else { return nil }
        // Let the last spoken word fade so the demo does not hear itself.
        let settle = Date().addingTimeInterval(0.5)
        while Date() < settle { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
        let turn = SFSpeechAudioBufferRecognitionRequest()
        turn.requiresOnDeviceRecognition = true
        turn.shouldReportPartialResults = true
        turn.addsPunctuation = true
        turn.taskHint = .dictation
        lock.withLock { latest = ""; lastChange = nil; isFinal = false; recognitionFailed = false; request = turn }
        let task = recognizer.recognitionTask(with: turn) { [weak self] result, error in
            self?.receive(result.map { ($0.bestTranscription.formattedString, $0.isFinal) }, failed: error != nil)
        }
        let started = Date()
        let hardStop = started.addingTimeInterval(min(maxSeconds, 20))
        while Date() < hardStop {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            let state = lock.withLock { (lastChange, isFinal, recognitionFailed) }
            if state.1 || state.2 { break }
            if let change = state.0, Date().timeIntervalSince(change) > 1.8 { break }
            if state.0 == nil, Date().timeIntervalSince(started) > 7 { break }
        }
        lock.withLock { request = nil }
        turn.endAudio()
        let finalDeadline = Date().addingTimeInterval(2.5)
        while Date() < finalDeadline, !lock.withLock({ isFinal || recognitionFailed }) {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        task.cancel()
        return lock.withLock { latest }
    }

    private func receive(_ hypothesis: (String, Bool)?, failed didFail: Bool) {
        lock.withLock {
            if let (text, final) = hypothesis {
                if text != latest { latest = text; lastChange = Date() }
                if final { isFinal = true }
            }
            if didFail { recognitionFailed = true }
        }
    }

    func shutDown() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        lock.withLock { request = nil }
        player.stop()
        if engine.isRunning { engine.stop() }
        if hasInputTap { engine.inputNode.removeTap(onBus: 0); hasInputTap = false }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

private final class BufferCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var collected: [AVAudioPCMBuffer] = []
    private var finished = false
    var isFinished: Bool { lock.withLock { finished } }
    var buffers: [AVAudioPCMBuffer] { lock.withLock { collected } }
    func append(_ buffer: AVAudioPCMBuffer) { lock.withLock { collected.append(buffer) } }
    func finish() { lock.withLock { finished = true } }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}

private final class Box<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func get() -> Value { lock.withLock { value } }
    func set(_ newValue: Value) { lock.withLock { value = newValue } }
}
