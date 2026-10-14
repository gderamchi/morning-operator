#if DEBUG
// DEBUG builds only. The whole file is inside this condition, so a Release build of MORE
// contains no listener (checked by LiveDemoSourceGuardTests and the PR's Release build).
//
// In the owner-present live demo (UITests/LiveMorningDemoTests.swift) the UI-test runner
// drives other apps but cannot play audio: on iOS 27 it is already in the background when
// a test starts, and a background process cannot start an audio session ('!pla'). MORE has
// the `audio` background mode, so MORE is the voice and the ears and the runner the hands.
//
// The runner launches MORE with `--live-demo-voice` plus a one-time token and a port.
// MORE listens on 127.0.0.1 only, accepts one loopback connection that presents the token,
// and answers hello / say / listen / stop. Text lives only in memory; nothing here logs,
// prints or stores it. The listener closes on stop, on disconnect, or after 45 minutes.
import AVFoundation
import EventKit
import Foundation
import MorningApple
import MorningLiveDemo
import Network
import Speech

enum LiveDemoVoiceHost {
    nonisolated(unsafe) private static var host: VoiceHost?

    /// Called once at launch. Does nothing unless the runner asked for demo voice mode.
    static func startIfRequested(arguments: [String] = ProcessInfo.processInfo.arguments,
                                 environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard host == nil, arguments.contains(LiveDemoWire.launchArgument),
              let token = environment[LiveDemoWire.tokenEnvironmentKey], LiveDemoWire.isWellFormedToken(token),
              let port = LiveDemoWire.port(from: environment[LiveDemoWire.portEnvironmentKey]) else { return }
        let created = VoiceHost(token: token, port: port)
        host = created
        created.start()
    }
}

private final class VoiceHost: @unchecked Sendable {
    private let token: String
    private let port: UInt16
    private let queue = DispatchQueue(label: "more.live-demo.voice")
    private var listener: NWListener?
    private var connection: NWConnection?
    private var buffer = Data()
    private var audio: DemoVoice?
    private var closed = false

    init(token: String, port: UInt16) {
        self.token = token
        self.port = port
    }

    func start() {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port) ?? .any)
        parameters.acceptLocalOnly = true
        guard let listener = try? NWListener(using: parameters) else { return }
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.close() }
        }
        listener.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 45 * 60) { [weak self] in self?.close() }
    }

    /// One connection, from loopback only.
    private func accept(_ incoming: NWConnection) {
        guard connection == nil, !closed, case .hostPort(let host, _) = incoming.endpoint,
              LiveDemoWire.isLoopback(host: "\(host)") else {
            incoming.cancel()
            return
        }
        connection = incoming
        incoming.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.close()
            default: break
            }
        }
        incoming.start(queue: queue)
        receive()
    }

    private func receive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data { self.buffer.append(data) }
            do {
                for line in try LiveDemoWire.takeLines(from: &self.buffer) { self.handle(line) }
            } catch {
                self.close()
                return
            }
            if isComplete || error != nil { self.close() } else if !self.closed { self.receive() }
        }
    }

    /// Runs on `queue`, one command at a time. A wrong token closes everything.
    private func handle(_ line: Data) {
        guard !closed else { return }
        guard let request = LiveDemoWire.decodeRequest(line), LiveDemoWire.tokensMatch(request.token, token) else {
            close()
            return
        }
        let response: LiveDemoWire.Response
        switch request.command {
        case .hello:
            response = hello(id: request.id, wantsCalendar: request.wantsCalendar == true)
        case .calendar:
            response = todaysEvents(id: request.id)
        case .say:
            guard let audio, let text = request.text, !text.isEmpty else {
                response = .init(id: request.id, ok: false, code: LiveDemoFailure.moreNotReady.rawValue)
                break
            }
            switch audio.speak(text) {
            case .spoken: response = .init(id: request.id, ok: true)
            case .failed(let failure, let detail):
                response = .init(id: request.id, ok: false, code: failure.rawValue, detail: detail + audio.diagnostics())
            }
        case .listen:
            let transcript = audio?.listen(maxSeconds: min(max(request.seconds ?? 10, 1), 20))
            response = .init(id: request.id, ok: transcript != nil, transcript: transcript)
        case .stop:
            send(.init(id: request.id, ok: true))
            close()
            return
        }
        send(response)
    }

    /// Prepares audio while MORE is in front and plays the sound check.
    private func hello(id: Int, wantsCalendar: Bool) -> LiveDemoWire.Response {
        if audio == nil {
            switch DemoVoice.start() {
            case .failed(let failure, let detail):
                return .init(id: id, ok: false, code: failure.rawValue, detail: detail)
            case .ready(let ready):
                audio = ready
            }
        }
        guard let audio else { return .init(id: id, ok: false, code: LiveDemoFailure.moreNotReady.rawValue) }
        if case .failed(let failure, let detail) = audio.speak("Sound check.") {
            return .init(id: id, ok: false, code: failure.rawValue, detail: detail + audio.diagnostics())
        }
        var detail = audio.diagnostics() + [
            "voice=\(audio.voiceQuality.name)",
            "listening=\(audio.listeningSkip?.rawValue ?? "ready")"
        ]
        if wantsCalendar {
            let granted = Self.requestCalendarAccess()
            detail.append("calendar=\(granted ? "ready" : "permission-denied")")
            // 0 not asked, 1 restricted, 2 denied, 3 full access, 4 add-only.
            detail.append("calendar-status=\(EKEventStore.authorizationStatus(for: .event).rawValue)")
        }
        return .init(id: id, ok: true, detail: detail)
    }

    /// Asks for full calendar access while MORE is in front (the prompt appears now).
    private static func requestCalendarAccess() -> Bool {
        let granted = Box<Bool?>(nil)
        Task { @MainActor in
            let service = CalendarObservationService()
            do { try await service.requestAccess(); granted.set(service.isAuthorized) } catch { granted.set(false) }
        }
        _ = DemoVoice.wait(60) { granted.get() != nil }
        return granted.get() == true
    }

    /// Today's events from every calendar on the phone, read with MORE's read-only
    /// EventKit service. The demo reads all calendars on purpose (owner present); titles
    /// stay in memory and go back to the runner only.
    private func todaysEvents(id: Int) -> LiveDemoWire.Response {
        let result = Box<[LiveDemoDayPlan.Event]?>(nil)
        let done = Box<Bool>(false)
        Task { @MainActor in
            let service = CalendarObservationService()
            if service.isAuthorized, let choices = try? service.calendarChoices(), !choices.isEmpty,
               let snapshot = try? service.snapshot(for: Date(), calendarIDs: Set(choices.map(\.id))) {
                result.set(snapshot.events.map {
                    LiveDemoDayPlan.Event(title: $0.title, start: $0.start, end: $0.end, isAllDay: $0.isAllDay)
                })
            }
            done.set(true)
        }
        _ = DemoVoice.wait(20) { done.get() }
        guard let events = result.get() else {
            return .init(id: id, ok: false, code: LiveDemoSkip.permissionDenied.rawValue)
        }
        return .init(id: id, ok: true, events: events)
    }

    private func send(_ response: LiveDemoWire.Response) {
        connection?.send(content: LiveDemoWire.encode(response), completion: .contentProcessed { _ in })
    }

    private func close() {
        guard !closed else { return }
        closed = true
        audio?.shutDown()
        audio = nil
        connection?.cancel()
        connection = nil
        listener?.cancel()
        listener = nil
        buffer.removeAll()
    }
}

// MARK: - Voice and ears

/// One audio path for the whole demo:
/// - Session `.playAndRecord` with `.defaultToSpeaker` (loudspeaker, not the earpiece),
///   `.allowBluetoothA2DP`, `.allowAirPlay` and `.mixWithOthers` (a reels app playing sound
///   does not interrupt it). This category ignores the Ring/Silent switch. It is activated
///   while MORE is in front and stays active; the `audio` background mode keeps it alive.
/// - Speech is rendered with `AVSpeechSynthesizer.write` and played by our engine's
///   player. A sentence counts only when the player reports `.dataPlayedBack` and nothing
///   interrupted, stopped or muted it, and most of its length elapsed.
/// - Listening is on-device only (`requiresOnDeviceRecognition = true`). Microphone buffers
///   reach the recognizer only during a turn. Transcripts go back to the runner only.
///
/// All waits are bounded and run on the host's serial queue, never the main thread.
private final class DemoVoice: @unchecked Sendable {
    enum StartResult {
        case ready(DemoVoice)
        case failed(LiveDemoFailure, [String])
    }

    enum SpeakResult {
        case spoken
        case failed(LiveDemoFailure, [String])
    }

    private let lock = NSLock()
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let synthesizer = AVSpeechSynthesizer()
    private let voice: AVSpeechSynthesisVoice?
    private let chosenVoice: LiveDemoVoiceCandidate?
    var voiceQuality: LiveDemoVoiceCandidate.Quality { chosenVoice?.quality ?? .standard }
    private var speechFormat: AVAudioFormat?
    private var observers: [any NSObjectProtocol] = []
    private var generation = 0

    private var recognizer: SFSpeechRecognizer?
    private var hasInputTap = false
    private(set) var listeningSkip: LiveDemoSkip?
    private var goodGeneration = 0
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
        let center = NotificationCenter.default
        for name in [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification,
                     AVAudioSession.mediaServicesWereResetNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in self?.bump() })
        }
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
            self?.bump()
        })
    }

    private func bump() { lock.withLock { generation += 1 } }
    private var currentGeneration: Int { lock.withLock { generation } }

    static func start() -> StartResult {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.defaultToSpeaker, .allowBluetoothA2DP, .allowAirPlay, .mixWithOthers])
            try session.setActive(true)
        } catch {
            return .failed(.audioSessionFailed, ["os=\((error as NSError).code)"])
        }
        let audio = DemoVoice(chosenVoice: LiveDemoVoicePick.best(from: installedVoices()))
        // Render a probe to learn the voice's format; wire the player as standard float.
        guard let probe = audio.render("Sound check."), let first = probe.first else { return .failed(.voiceNoRender, []) }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: first.format.sampleRate,
                                         channels: first.format.channelCount) else { return .failed(.voiceFormat, []) }
        audio.speechFormat = format
        // Set up listening first (permission prompts appear while MORE is in front), so the
        // engine is wired once, microphone and player together, and started once. Adding
        // the microphone to a running engine changed its configuration and lost playback
        // on the phone (voice-no-playback right after a heard sound check).
        audio.listeningSkip = audio.prepareListening()
        audio.engine.attach(audio.player)
        audio.engine.connect(audio.player, to: audio.engine.mainMixerNode, format: format)
        audio.engine.prepare()
        do {
            try audio.engine.start()
        } catch {
            guard audio.hasInputTap else { return .failed(.audioEngineFailed, ["os=\((error as NSError).code)"]) }
            // Keep the voice even if the microphone cannot run.
            audio.engine.inputNode.removeTap(onBus: 0)
            audio.hasInputTap = false
            audio.recognizer = nil
            audio.listeningSkip = .audioInputFailed
            audio.engine.prepare()
            do { try audio.engine.start() } catch {
                return .failed(.audioEngineFailed, ["os=\((error as NSError).code)"])
            }
        }
        audio.player.play()
        // Let the start-up notifications arrive, then treat this configuration as good.
        Thread.sleep(forTimeInterval: 0.5)
        audio.goodGeneration = audio.currentGeneration
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

    func diagnostics() -> [String] {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs.map(\.portType.rawValue).joined(separator: "+")
        return ["route=\(outputs.isEmpty ? "none" : outputs)",
                "volume=\(String(format: "%.2f", session.outputVolume))",
                "engine=\(engine.isRunning ? "running" : "stopped")",
                "player=\(player.isPlaying ? "playing" : "stopped")",
                "cfg=\(currentGeneration)"]
    }

    static func wait(_ seconds: TimeInterval, until done: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if done() { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return done()
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
        if currentGeneration != goodGeneration || !engine.isRunning || !player.isPlaying {
            // Something changed the audio path since the last sentence (a route or engine
            // configuration change stops the engine). Rewire the player and start again.
            if let failure = rewire(format: format) { return .failed(.audioEngineFailed, [failure, "rewired"]) }
        }
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
        let duration = frames / format.sampleRate
        var muted = false
        let finished = Self.wait(duration + 5) {
            if session.outputVolume <= 0 { muted = true }
            return done.isSet
        }
        guard finished else {
            player.stop()
            player.play()
            return .failed(.voiceNoPlayback, [])
        }
        // The completion also fires when the player is stopped: check nothing cut it short.
        if currentGeneration != startGeneration || !engine.isRunning || !player.isPlaying {
            return .failed(.audioInterrupted, [])
        }
        if muted || session.outputVolume <= 0 { return .failed(.volumeZero, []) }
        if Date().timeIntervalSince(started) < 0.8 * duration { return .failed(.voiceNoPlayback, ["cut-short"]) }
        if session.currentRoute.outputs.contains(where: { $0.portType == .builtInReceiver }) {
            return .failed(.routeEarpiece, [])
        }
        Thread.sleep(forTimeInterval: 0.25)
        return .spoken
    }

    /// Stops the engine, reconnects the player, starts again. Nil on success.
    private func rewire(format: AVAudioFormat) -> String? {
        player.stop()
        engine.stop()
        engine.disconnectNodeOutput(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.prepare()
        do { try engine.start() } catch { return "os=\((error as NSError).code)" }
        player.play()
        Thread.sleep(forTimeInterval: 0.3)
        goodGeneration = currentGeneration
        return nil
    }

    private func render(_ text: String) -> [AVAudioPCMBuffer]? {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        let collected = BufferCollector()
        synthesizer.write(utterance) { buffer in
            guard let pcm = buffer as? AVAudioPCMBuffer else { return }
            if pcm.frameLength == 0 { collected.finish() } else { collected.append(pcm) }
        }
        guard Self.wait(LiveDemoSpeechTiming.timeout(forCharacters: text.count), until: { collected.isFinished }) else {
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

    /// Asks for the microphone and speech recognition (MORE is in front) and installs the
    /// microphone tap before the engine starts. Nil when listening is ready.
    private func prepareListening() -> LiveDemoSkip? {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.supportsOnDeviceRecognition else { return .onDeviceUnavailable }
        let speechGranted = Box<Bool?>(nil)
        let micGranted = Box<Bool?>(nil)
        SFSpeechRecognizer.requestAuthorization { speechGranted.set($0 == .authorized) }
        AVAudioApplication.requestRecordPermission { micGranted.set($0) }
        _ = Self.wait(45) { speechGranted.get() != nil && micGranted.get() != nil }
        guard speechGranted.get() == true, micGranted.get() == true else { return .permissionDenied }
        guard recognizer.isAvailable else { return .onDeviceUnavailable }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else { return .audioInputFailed }
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
            self?.append(buffer)
        }
        hasInputTap = true
        self.recognizer = recognizer
        return nil
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        lock.withLock { request?.append(buffer) }
    }

    /// One turn: ends 1.8 s after speech stops, after `maxSeconds`, or after 7 s of
    /// silence. Nil if listening is not available.
    func listen(maxSeconds: TimeInterval) -> String? {
        guard let recognizer, hasInputTap, engine.isRunning else { return nil }
        Thread.sleep(forTimeInterval: 0.5)
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
        _ = Self.wait(min(maxSeconds, 20)) {
            let state = lock.withLock { (lastChange, isFinal, recognitionFailed) }
            if state.1 || state.2 { return true }
            if let change = state.0, Date().timeIntervalSince(change) > 1.8 { return true }
            return state.0 == nil && Date().timeIntervalSince(started) > 7
        }
        lock.withLock { request = nil }
        turn.endAudio()
        _ = Self.wait(2.5) { lock.withLock { isFinal || recognitionFailed } }
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
#endif
