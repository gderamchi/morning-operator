import MorningLiveDemo
import Network
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
        static let calendar = "com.apple.mobilecal"
        static let instagram = "com.burbn.instagram"
        static let tiktok = "com.zhiliaoapp.musically"
        static let springboard = "com.apple.springboard"
    }

    private struct VoiceFailed: Error {}

    private var environment: [String: String] { ProcessInfo.processInfo.environment }
    private var voice: VoiceClient?
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
        // 1. MORE is the voice and the ears. On iOS 27 this runner is already in the
        //    background when a test starts, so it can never start audio ('!pla'). MORE has
        //    the `audio` background mode: it starts its session while in front and keeps it
        //    while the runner drives other apps. The channel is loopback-only with a
        //    one-time token. Fixture mode keeps MORE's own data and speech out of the way.
        let runnerState = UIApplication.shared.applicationState
        let token = LiveDemoWire.makeToken()
        let port = LiveDemoWire.makePort()
        let more = XCUIApplication()
        more.launchArguments = ["--ui-testing", "--fixture-mode", LiveDemoWire.launchArgument]
        more.launchEnvironment = [LiveDemoWire.tokenEnvironmentKey: token, LiveDemoWire.portEnvironmentKey: String(port)]
        more.launch()
        guard more.wait(for: .runningForeground, timeout: 15) else {
            emit(LiveDemoReport.line(["audio", "runner=\(Self.name(runnerState))", "more=not-foreground"]))
            report.record(.soundCheck, .skipped(.voiceFailed))
            fail(.moreNotReady, [])
            throw VoiceFailed()
        }
        let client = VoiceClient(port: port, token: token)
        voice = client
        // MORE prepares audio, plays "Sound check." and asks for the microphone and speech
        // recognition (tap Allow on the phone) before it answers.
        let steps = LiveDemoSteps.from(environment: environment)
        for step in LiveDemoSteps.all.subtracting(steps) { report.record(step, .skipped(.disabled)) }
        let hello = XCTContext.runActivity(named: "MORE sound check") { _ in
            client.call(.hello, wantsCalendar: steps.contains(.calendar), timeout: 150)
        }
        emit(LiveDemoReport.line(["audio", "runner=\(Self.name(runnerState))", "more=\(hello == nil ? "no-answer" : "answered")"]
                                 + (hello?.detail ?? [])))
        guard let hello, hello.ok else {
            report.record(.soundCheck, .skipped(.voiceFailed))
            fail(hello?.code.flatMap(LiveDemoFailure.init(rawValue:)) ?? .voiceChannelFailed, hello?.code.map { [$0] } ?? [])
            throw VoiceFailed()
        }
        report.record(.soundCheck, .ran)
        let detail = hello.detail ?? []
        if detail.contains("voice=default") {
            try say("For a better voice, download a Premium voice in Settings.")
        }
        if let state = detail.first(where: { $0.hasPrefix("listening=") })?.dropFirst("listening=".count),
           state != "ready" {
            report.record(.listening, .skipped(LiveDemoSkip(rawValue: String(state)) ?? .audioInputFailed))
            try say("I can't listen today. I'll skip replies.")
        } else {
            listening = true
            report.record(.listening, .ran)
        }

        // 2. Look first, then say a short summary.
        var unreadConversations: Int?
        var unreadEmails: Int?
        if steps.isDisjoint(with: [.messages, .mail, .weather]) {
            report.record(.summary, .skipped(.disabled))
            try say("Good morning.")
        } else {
            try say("Good morning. One moment. I'm looking at your morning.")
            if steps.contains(.messages) {
                unreadConversations = try XCTContext.runActivity(named: "Survey Messages") { _ in try surveyMessages() }
            }
            if steps.contains(.mail) {
                unreadEmails = try XCTContext.runActivity(named: "Survey Mail") { _ in try surveyMail() }
            }
            let weather = steps.contains(.weather)
                ? try XCTContext.runActivity(named: "Weather") { _ in try readWeather() } : nil
            for sentence in LiveDemoSummary.sentences(unreadConversations: unreadConversations, unreadEmails: unreadEmails,
                                                      weather: weather).dropFirst() {
                try say(sentence)
            }
            report.record(.summary, .ran)
            hold(2)
        }
        if LiveDemoStopAfter.from(environment: environment) == .summary {
            // Owner-present check: nothing is opened or read after the summary. A survey that
            // succeeded counts as ran.
            if unreadConversations != nil { report.record(.messages, .ran) }
            if unreadEmails != nil { report.record(.mail, .ran) }
            for step in [LiveDemoStep.messages, .mail, .calendar, .reels] { report.record(step, .skipped(.stoppedEarly)) }
            try say("That's all for this check.")
            return
        }
        if steps.contains(.calendar) {
            let calendarReady = detail.contains("calendar=ready")
            try XCTContext.runActivity(named: "Calendar") { _ in try readCalendar(accessGranted: calendarReady) }
        }

        // 3. Ask, then read.
        if steps.contains(.messages), let count = unreadConversations {
            if count == 0 && !LiveDemoGate.allowsReadConversations(environment: environment) {
                report.record(.messages, .ran)
            } else if try askToStartWithMessages() {
                try XCTContext.runActivity(named: "Messages") { _ in try readMessages() }
            } else {
                report.record(.messages, .skipped(.ownerDeclined))
            }
        }
        if steps.contains(.mail), let count = unreadEmails {
            if count == 0 {
                report.record(.mail, .ran)
            } else {
                try XCTContext.runActivity(named: "Mail") { _ in try readMail() }
            }
        }
        if steps.contains(.reels) {
            try XCTContext.runActivity(named: "Reels") { _ in try scrollReels() }
        }

        try XCTContext.runActivity(named: "Return to MORE") { _ in
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
        _ = voice?.call(.stop, timeout: 5)
        voice?.close()
        voice = nil
    }

    private func askToStartWithMessages() throws -> Bool {
        try say("Shall we start with your messages?")
        guard listening else {
            hold(3)
            try say("I'll start with your messages.")
            return true
        }
        switch LiveDemoYesNo.parse(listen() ?? "") {
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
        guard listening else {
            hold(4)
            try say("No answer. I'll move on.")
            return
        }
        var intent = LiveDemoReplyIntent.parse(listen() ?? "")
        if intent == .affirm {
            try say("What should I say?")
            intent = LiveDemoReplyIntent.parseDictation(listen(seconds: 15) ?? "")
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

    // MARK: - Calendar

    /// Shows Calendar on today (the Today button is the only tap; no event is opened) and
    /// speaks today's plan from MORE's EventKit reader, not from the screen.
    private func readCalendar(accessGranted: Bool) throws {
        let calendarApp: XCUIApplication
        switch launch(App.calendar) {
        case .skipped(let reason):
            report.record(.calendar, .skipped(reason))
            return
        case .app(let app):
            calendarApp = app
        }
        hold(2)
        if let today = snapshotDescendants(of: calendarApp).first(where: { node in
            node.elementType == .button
                && LiveDemoTapPolicy.permits(kind: .calendarToday, label: node.label, identifier: node.identifier, isButtonLike: true)
        }) {
            _ = tapChecked(Target(today), kind: .calendarToday, in: calendarApp)
            hold(1.5)
        }
        guard accessGranted, let voice,
              let response = XCTContext.runActivity(named: "Today's events", block: { _ in voice.call(.calendar, timeout: 30) }),
              response.ok, let events = response.events else {
            report.record(.calendar, .skipped(.permissionDenied))
            try say("I can't read your calendar. Allow calendar access for MORE in Settings.")
            return
        }
        report.record(.calendar, .ran)
        try say("Now your calendar.")
        for sentence in LiveDemoDayPlan.sentences(events: events, now: Date(), calendar: .current) {
            try say(sentence)
        }
        emit(LiveDemoReport.line(["calendar", "events=\(events.count)"]))
        hold(3)
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
        let nodes = snapshotDescendants(of: feed)
        let tab = nodes.first { node in
            node.elementType == .button && tabLabels.contains(node.label)
                && LiveDemoTapPolicy.permits(kind: .feedTab, label: node.label, identifier: node.identifier, isButtonLike: true)
        }
        if tab == nil {
            // Diagnostics: only the bottom tab bar's buttons (identifier, label, frame).
            // No other element, no screenshot, no post text.
            let snapshotError: String
            do { _ = try feed.snapshot(); snapshotError = "none" } catch { snapshotError = "\((error as NSError).code)" }
            let known = ["clips-tab", "reels-tab", "clips_tab", "reels_tab"].map { id in
                "\(id)=\(feed.descendants(matching: .any).matching(identifier: id).count)"
            }
            emit(LiveDemoReport.line(["tab-probe", "nodes=\(nodes.count)", "snapshot-error=\(snapshotError)",
                                      "tabbars=\(feed.tabBars.count)"] + known))
            var bar = tabBarButtons(in: feed, nodes: nodes)
            if bar.isEmpty, let barSnapshot = try? feed.tabBars.firstMatch.snapshot() {
                bar = Self.descendants(of: barSnapshot).filter { Self.isButtonLike($0.elementType) }
                    .sorted { $0.frame.minX < $1.frame.minX }
            }
            for (index, button) in bar.enumerated() {
                let f = button.frame
                emit(LiveDemoReport.line(["tab", "i=\(index)", "id=\(button.identifier.isEmpty ? "none" : button.identifier)",
                                          "label=\(button.label.isEmpty ? "none" : button.label)",
                                          "frame=\(Int(f.minX)).\(Int(f.minY)).\(Int(f.width)).\(Int(f.height))"]))
            }
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

    /// Buttons of the bottom tab bar: inside a tab bar element if there is one, otherwise
    /// button-like controls whose centre is in the bottom 12% of the screen.
    private func tabBarButtons(in app: XCUIApplication, nodes: [any XCUIElementSnapshot]) -> [any XCUIElementSnapshot] {
        let screen = app.frame
        let bars = nodes.filter { $0.elementType == .tabBar && $0.frame.midY > screen.maxY * 0.8 }
        let inBars = bars.flatMap { Self.descendants(of: $0).filter { Self.isButtonLike($0.elementType) } }
        let buttons = inBars.isEmpty
            ? nodes.filter { Self.isButtonLike($0.elementType) && $0.frame.midY > screen.maxY * 0.88 && isOnScreen($0.frame, in: app) }
            : inBars
        return buttons.sorted { $0.frame.minX < $1.frame.minX }
    }

    // MARK: - Speaking, reporting and holding

    /// MORE speaks one sentence and answers only after the hardware played it. Any failure,
    /// or no answer in time, fails the run with a fixed code and stops the demo.
    private func say(_ text: String) throws {
        guard let voice else { throw VoiceFailed() }
        utteranceCount += 1
        let response = XCTContext.runActivity(named: "Speak") { _ in
            voice.call(.say, text: text, timeout: LiveDemoWire.sayTimeout(characters: text.count))
        }
        guard let response, response.ok else {
            report.record(.soundCheck, .skipped(.voiceFailed))
            let failure = response?.code.flatMap(LiveDemoFailure.init(rawValue:)) ?? .voiceChannelFailed
            fail(failure, ["n=\(utteranceCount)"] + (response?.detail ?? []))
            throw VoiceFailed()
        }
    }

    /// One on-device listening turn in MORE. Nil when MORE could not listen.
    private func listen(seconds: Double = 10) -> String? {
        guard let voice else { return nil }
        let response = XCTContext.runActivity(named: "Listen") { _ in
            voice.call(.listen, seconds: seconds, timeout: seconds + 15)
        }
        return response?.ok == true ? response?.transcript : nil
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

// MARK: - Channel to MORE

/// The runner's end of the loopback channel. Requests and answers are matched by id; each
/// call waits a bounded time, pumping the run loop. Text is never logged.
final class VoiceClient: @unchecked Sendable {
    private let lock = NSLock()
    private let token: String
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "more.live-demo.client")
    private var buffer = Data()
    private var responses: [Int: LiveDemoWire.Response] = [:]
    private var nextID = 1
    private var ready = false
    private var broken = false

    init(port: UInt16, token: String) {
        self.token = token
        connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port) ?? .any, using: .tcp)
    }

    /// Connects (retrying while MORE's listener starts), sends one request, waits for its
    /// answer. Nil on timeout or a broken channel.
    func call(_ command: LiveDemoWire.Command, text: String? = nil, seconds: Double? = nil,
              wantsCalendar: Bool? = nil, timeout: TimeInterval) -> LiveDemoWire.Response? {
        guard connect(within: 15) else { return nil }
        let id = lock.withLock { () -> Int in nextID += 1; return nextID }
        let request = LiveDemoWire.Request(token: token, id: id, command: command, text: text, seconds: seconds,
                                           wantsCalendar: wantsCalendar)
        connection.send(content: LiveDemoWire.encode(request), completion: .contentProcessed { [weak self] error in
            if error != nil { self?.lock.withLock { self?.broken = true } }
        })
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let response = lock.withLock({ responses.removeValue(forKey: id) }) { return response }
            if lock.withLock({ broken }) { return nil }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return nil
    }

    private func connect(within seconds: TimeInterval) -> Bool {
        if lock.withLock({ ready }) { return true }
        if connection.state == .setup {
            connection.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready: self.lock.withLock { self.ready = true }
                case .failed, .cancelled: self.lock.withLock { self.broken = true }
                case .waiting:
                    // The listener may not be up yet: retry shortly.
                    self.queue.asyncAfter(deadline: .now() + 0.3) { self.connection.restart() }
                default: break
                }
            }
            connection.start(queue: queue)
            receive()
        }
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline, !lock.withLock({ ready || broken }) {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return lock.withLock { ready && !broken }
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            self.lock.withLock {
                if let data { self.buffer.append(data) }
                if let lines = try? LiveDemoWire.takeLines(from: &self.buffer) {
                    for line in lines {
                        if let response = LiveDemoWire.decodeResponse(line) { self.responses[response.id] = response }
                    }
                } else {
                    self.broken = true
                }
                if isComplete || error != nil { self.broken = true }
            }
            if !self.lock.withLock({ self.broken }) { self.receive() }
        }
    }

    func close() {
        connection.cancel()
    }
}
