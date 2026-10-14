import AVFoundation
import MorningLiveDemo
import Speech
import XCTest

/// Opt-in, owner-present demo of a morning run on a tethered iPhone. The XCUITest runner is
/// the only process allowed to drive other apps (a shipped app cannot), so this lives here.
///
/// It reads unread Messages and Mail aloud, asks whether to reply, listens on-device only,
/// types a spoken reply as a DRAFT, reads the weather, then swipes through reels.
///
/// SENDING IS IMPOSSIBLE IN THIS FILE. Every tap goes through `tapChecked`, which asks
/// `LiveDemoTapPolicy` first; a label or identifier with send, reply, post, like, follow,
/// share, delete (and similar) is always refused. Typing removes newlines, so a return key
/// can never be pressed. Whether MORE may send after a spoken confirmation is a separate
/// owner decision (GitHub issue), not something this test may grow into.
/// `Tests/MorningLiveDemoTests/LiveDemoSourceGuardTests.swift` fails the package tests if
/// this file gains another tap, typing or press site.
///
/// Privacy: no screenshots or attachments are kept. Message, mail and transcript text is
/// spoken only; it is never printed, attached or used in an activity name. Taps on rows
/// that hold personal text are made by coordinate so XCTest logs no label.
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

    private var environment: [String: String] { ProcessInfo.processInfo.environment }
    private var voice: DemoVoice!
    private var ears: DemoEars?
    private var toldListeningUnavailable = false

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
        // Enforced when the command passes -test-timeouts-enabled YES (docs/DEVICE-SETUP.md).
        executionTimeAllowance = 30 * 60

        voice = DemoVoice()
        // The runner is in the foreground only now, before any app opens: ask for the
        // microphone and on-device speech here, and start the input while it is allowed.
        say("Good morning. I'll run your morning on this phone. I'll read your messages and mail, "
            + "check the weather, then play some reels. I never send anything.")
        if DemoEars.permissionStillUndecided {
            say("If the phone asks for microphone or speech recognition access, tap Allow.")
        }
        ears = XCTContext.runActivity(named: "Prepare on-device listening") { _ in DemoEars.prepare() }
        if ears == nil {
            say("I can't listen from here, so I'll skip replies today.")
            toldListeningUnavailable = true
        }

        XCTContext.runActivity(named: "Messages") { _ in readMessages() }
        XCTContext.runActivity(named: "Mail") { _ in readMail() }
        XCTContext.runActivity(named: "Weather") { _ in readWeather() }
        // Reels play their own audio, which interrupts the microphone; listening ends here.
        ears?.shutDown()
        ears = nil
        XCTContext.runActivity(named: "Reels") { _ in scrollReels() }

        XCTContext.runActivity(named: "Return to MORE") { _ in
            let more = XCUIApplication()
            more.activate()
            _ = more.wait(for: .runningForeground, timeout: 10)
            hold(2)
            say("That's the morning demo done. Nothing was sent.")
        }
    }

    // MARK: - Messages

    private func readMessages() {
        guard let messages = launch(App.messages, name: "Messages") else { return }
        guard showConversationList(in: messages) else {
            say("I couldn't find the conversation list in Messages, so I'll skip it.")
            return
        }
        let allowRead = LiveDemoGate.allowsReadConversations(environment: environment)
        let rows = visibleRows(in: messages)
        let chosen = Array(rows.filter { allowRead || $0.row.isUnread }.prefix(3))
        guard !chosen.isEmpty else {
            say("You have no unread messages.")
            hold(3)
            return
        }
        say(chosen.count == 1 ? "You have one unread conversation." : "Here are \(chosen.count) unread conversations.")
        for (index, target) in chosen.enumerated() {
            XCTContext.runActivity(named: "Messages conversation \(index + 1)") { _ in
                openConversation(target.row, in: messages)
            }
            guard messages.state == .runningForeground else { return }
        }
    }

    private func openConversation(_ row: LiveDemoListRow, in messages: XCUIApplication) {
        guard noPrompt(in: messages), showConversationList(in: messages),
              let fresh = visibleRows(in: messages).first(where: {
                  $0.row.sender == row.sender && $0.row.detail == row.detail
              }),
              tapChecked(fresh.target, kind: .listRow, in: messages) else {
            say("I couldn't open that conversation, so I'll move on.")
            return
        }
        hold(2)
        say("Message from \(row.sender).")
        if !row.detail.isEmpty { say(row.detail) }
        hold(2)
        offerReply(in: messages)
        hold(2)
        goBack(in: messages)
        hold(1)
    }

    private func offerReply(in messages: XCUIApplication) {
        say("Do you want to reply?")
        guard let ears else {
            hold(4)
            say("No answer, so I'll move on.")
            return
        }
        var intent = LiveDemoReplyIntent.parse(ears.listen() ?? "")
        if intent == .affirm {
            say("What should I say?")
            intent = LiveDemoReplyIntent.parseDictation(ears.listen(maxSeconds: 15) ?? "")
        }
        switch intent {
        case .draft(let text):
            if typeDraft(text, in: messages) {
                say("I wrote a draft: \(text). I did not send it.")
                hold(4)
            } else {
                say("I couldn't find the message field, so I left it.")
            }
        case .decline:
            say("OK, no reply.")
        case .silence:
            say("I didn't hear anything, so I'll move on.")
        case .affirm, .unclear:
            say("I didn't catch a reply, so I'll leave it.")
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

    private func readMail() {
        guard let mail = launch(App.mail, name: "Mail") else { return }
        guard showInbox(in: mail) else {
            say("I couldn't find your inbox in Mail, so I'll skip it.")
            return
        }
        hold(2)
        let unread = Array(visibleRows(in: mail).filter(\.row.isUnread).prefix(3))
        guard !unread.isEmpty else {
            say("No unread mail in your inbox.")
            hold(3)
            return
        }
        say(unread.count == 1 ? "One unread email." : "\(unread.count) unread emails.")
        for (index, mailRow) in unread.enumerated() {
            XCTContext.runActivity(named: "Mail row \(index + 1)") { _ in
                say(mailRow.row.detail.isEmpty ? "From \(mailRow.row.sender)."
                    : "From \(mailRow.row.sender): \(mailRow.row.detail).")
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

    private func readWeather() {
        guard let weather = launch(App.weather, name: "Weather") else { return }
        hold(3)
        let texts = snapshotDescendants(of: weather)
            .filter { $0.elementType == .staticText && isOnScreen($0.frame, in: weather) }
            .sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }
            .map(\.label)
        if let summary = LiveDemoWeather.summary(texts: texts) {
            say(summary.condition.map { "It's \(summary.temperature) and \($0)." } ?? "It's \(summary.temperature).")
        } else {
            say("I couldn't read the weather on screen.")
        }
        hold(5)
    }

    // MARK: - Reels

    private func scrollReels() {
        let count = LiveDemoGate.reelCount(environment: environment)
        guard count > 0 else { return }
        var feed = launch(App.instagram, name: "Instagram", announceMissing: false)
        var tabLabels = ["Reels"]
        if feed == nil {
            feed = launch(App.tiktok, name: "TikTok", announceMissing: false)
            tabLabels = ["For You", "Home"]
        }
        guard let feed else {
            say("Neither Instagram nor TikTok is installed, so no reels today.")
            return
        }
        hold(3)
        let tab = snapshotDescendants(of: feed).first { node in
            node.elementType == .button && tabLabels.contains(node.label)
                && LiveDemoTapPolicy.permits(kind: .feedTab, label: node.label, identifier: node.identifier, isButtonLike: true)
        }
        // Swipes happen only after the feed tab itself was found and tapped.
        guard let tab, tapChecked(Target(tab), kind: .feedTab, in: feed) else {
            say("I couldn't find the video feed, so I'll skip reels.")
            return
        }
        hold(2)
        say("Now some reels. I'll swipe every eight seconds and won't like, comment or follow anything.")
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
                say("Something changed on screen, so I stopped the reels.")
                return
            }
        }
        hold(4)
    }

    // MARK: - Speaking and holding

    private func say(_ text: String) {
        XCTContext.runActivity(named: "Speak") { _ in voice?.speak(text) }
    }

    private func hold(_ seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline { RunLoop.current.run(until: min(deadline, Date().addingTimeInterval(0.1))) }
    }

    // MARK: - Apps, prompts and navigation

    /// Launches an app; a missing app is announced and skipped, not a test failure.
    private func launch(_ bundleID: String, name: String, announceMissing: Bool = true) -> XCUIApplication? {
        let app = XCUIApplication(bundleIdentifier: bundleID)
        XCTExpectFailure("\(name) may not be installed on this phone.", options: .nonStrict()) {
            app.activate()
        }
        guard app.wait(for: .runningForeground, timeout: 10) else {
            if announceMissing { say("\(name) isn't available, so I'll skip it.") }
            return nil
        }
        guard noPrompt(in: app) else {
            say("\(name) is showing a prompt I won't answer, so I'll skip it.")
            return nil
        }
        return app
    }

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

// MARK: - Voice

/// Speaks one English utterance at a time and waits for it to finish, with a timeout so a
/// silent or broken audio route can never hang the demo.
final class DemoVoice: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()
    private let lock = NSLock()
    private var finished = false
    private var failedOnce = false

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        lock.withLock { finished = false }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.postUtteranceDelay = 0.3
        synthesizer.speak(utterance)
        // If speech already failed once, keep the pacing but stop waiting the full timeout.
        let timeout = lock.withLock { failedOnce } ? 2 : LiveDemoSpeechTiming.timeout(forCharacters: text.count)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !lock.withLock({ finished }) {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        if !lock.withLock({ finished }) {
            synthesizer.stopSpeaking(at: .immediate)
            lock.withLock { failedOnce = true }
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        lock.withLock { finished = true }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        lock.withLock { finished = true }
    }
}

// MARK: - Ears

/// On-device speech recognition only (`requiresOnDeviceRecognition = true`): audio never
/// leaves the phone, and there is no server fallback. The microphone input starts while
/// the runner is still in the foreground and stays running until `shutDown`, because iOS
/// does not let a background process start recording. Buffers reach the recognizer only
/// during a listening turn. Transcripts are returned to the caller and never logged.
final class DemoEars: @unchecked Sendable {
    private let lock = NSLock()
    private let recognizer: SFSpeechRecognizer
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var latest = ""
    private var lastChange: Date?
    private var isFinal = false
    private var failed = false

    private init(recognizer: SFSpeechRecognizer) { self.recognizer = recognizer }

    /// Nil when on-device listening is not possible here (permission denied or not given
    /// within 45 s, no on-device English model, or the audio input cannot start).
    static var permissionStillUndecided: Bool {
        SFSpeechRecognizer.authorizationStatus() == .notDetermined
            || AVAudioApplication.shared.recordPermission == .undetermined
    }

    static func prepare() -> DemoEars? {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.supportsOnDeviceRecognition else { return nil }
        let speechGranted = Box<Bool?>(nil)
        let micGranted = Box<Bool?>(nil)
        SFSpeechRecognizer.requestAuthorization { speechGranted.set($0 == .authorized) }
        AVAudioApplication.requestRecordPermission { micGranted.set($0) }
        let deadline = Date().addingTimeInterval(45)
        while Date() < deadline, speechGranted.get() == nil || micGranted.get() == nil {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        guard speechGranted.get() == true, micGranted.get() == true, recognizer.isAvailable else { return nil }
        let ears = DemoEars(recognizer: recognizer)
        return ears.startInput() ? ears : nil
    }

    private func startInput() -> Bool {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.defaultToSpeaker, .mixWithOthers, .allowBluetoothHFP])
            try session.setActive(true)
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.channelCount > 0, format.sampleRate > 0 else { return false }
            input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
                self?.append(buffer)
            }
            engine.prepare()
            try engine.start()
            return true
        } catch {
            shutDown()
            return false
        }
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        lock.withLock { request?.append(buffer) }
    }

    /// One listening turn: ends 1.8 s after speech stops, after `maxSeconds`, or after 7 s
    /// of silence. Returns nil if the turn could not run.
    func listen(maxSeconds: TimeInterval = 10) -> String? {
        guard engine.isRunning else { return nil }
        // Let the last spoken word fade so the demo does not hear itself.
        let settle = Date().addingTimeInterval(0.5)
        while Date() < settle { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
        let turn = SFSpeechAudioBufferRecognitionRequest()
        turn.requiresOnDeviceRecognition = true
        turn.shouldReportPartialResults = true
        turn.addsPunctuation = true
        turn.taskHint = .dictation
        lock.withLock { latest = ""; lastChange = nil; isFinal = false; failed = false; request = turn }
        let task = recognizer.recognitionTask(with: turn) { [weak self] result, error in
            self?.receive(result.map { ($0.bestTranscription.formattedString, $0.isFinal) }, failed: error != nil)
        }
        let started = Date()
        let hardStop = started.addingTimeInterval(min(maxSeconds, 20))
        while Date() < hardStop {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            let state = lock.withLock { (lastChange, isFinal, failed) }
            if state.1 || state.2 { break }
            if let change = state.0, Date().timeIntervalSince(change) > 1.8 { break }
            if state.0 == nil, Date().timeIntervalSince(started) > 7 { break }
        }
        lock.withLock { request = nil }
        turn.endAudio()
        let finalDeadline = Date().addingTimeInterval(2.5)
        while Date() < finalDeadline, !lock.withLock({ isFinal || failed }) {
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
            if didFail { failed = true }
        }
    }

    func shutDown() {
        lock.withLock { request = nil }
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

private final class Box<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func get() -> Value { lock.withLock { value } }
    func set(_ newValue: Value) { lock.withLock { value = newValue } }
}
