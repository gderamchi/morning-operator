import Foundation
import MorningCore
import Observation
#if os(iOS)
import AVFAudio
import OSLog
import Speech
import UIKit
#endif

public enum JuryDemoVoiceState: String, Sendable {
    case idle, preparing, listening, thinking, speaking, paused, completed, failed
}

/// An explicit, continuously listening session. Background execution is supported
/// by genuine microphone/audio work, never by silent playback or a keepalive.
@MainActor @Observable
public final class JuryDemoVoiceSession {
    public private(set) var state: JuryDemoVoiceState = .idle {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    public private(set) var message = ""
    public private(set) var transcript = ""
    public private(set) var stage = "morning"
    public private(set) var sessionID: String?
    public var isActive: Bool { [.preparing, .listening, .thinking, .speaking].contains(state) }
    public var isPlaying: Bool { state == .speaking }
    public var onResponse: (@MainActor (JuryDemoResponse) -> Void)?
    public var onText: (@MainActor (String) -> Void)?
    public var onCompleted: (@MainActor () -> Void)?
    public var onStateChange: (@MainActor (JuryDemoVoiceState) -> Void)?
    public var onUserRequest: (@MainActor (String) -> Bool)?

    @ObservationIgnored private let client: JuryDemoClient?
    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private let sessionStorageKey: String?
    @ObservationIgnored private var runID: UUID?
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var speechOperation: Task<Void, Never>?
    @ObservationIgnored private var latestResponse: JuryDemoResponse?
    @ObservationIgnored private var queuedText: String?
    @ObservationIgnored private var pendingAcknowledgement: (requestID: String, status: String, receiptID: String?)?
    @ObservationIgnored private var language: MorningVoiceCommandLanguage = .french
    #if os(iOS)
    @ObservationIgnored private var engine = AVAudioEngine()
    @ObservationIgnored private let sink = JuryDemoAudioSink()
    @ObservationIgnored private var output: JuryDemoAudioOutput?
    @ObservationIgnored private var recognizer: SFSpeechRecognizer?
    @ObservationIgnored private var recognition: SFSpeechRecognitionTask?
    @ObservationIgnored private var recognitionID: UUID?
    @ObservationIgnored private var silence: Task<Void, Never>?
    @ObservationIgnored private var recognitionDeadline: Task<Void, Never>?
    @ObservationIgnored private var finalDeadline: Task<Void, Never>?
    @ObservationIgnored private var observers: [Task<Void, Never>] = []
    @ObservationIgnored private var finishingInput = false
    @ObservationIgnored private var hasTap = false
    @ObservationIgnored private var audioPreparationID: UUID?
    @ObservationIgnored private var audioReleaseID: UUID?
    @ObservationIgnored private var recognitionFailures = 0
    @ObservationIgnored private var outputText: String?
    @ObservationIgnored private var outputFinishedAt = Date.distantPast
    @ObservationIgnored private var captionTask: Task<Void, Never>?
    #if DEBUG
    @ObservationIgnored private var configurationObservation: JuryDemoAudioConfigurationObservation?
    #endif
    @ObservationIgnored private lazy var audioSession = SpeechAudioSessionGate(
        activate: { try await Self.activateAudio() }, deactivate: { try await Self.deactivateAudio() }
    )
    #endif

    public convenience init(configuration: JuryDemoConfiguration? = try? .fromBundle()) {
        self.init(configuration: configuration, preferences: .standard)
    }

    init(configuration: JuryDemoConfiguration?, preferences: UserDefaults, client: JuryDemoClient? = nil) {
        self.client = client ?? configuration.map { JuryDemoClient(configuration: $0) }
        self.preferences = preferences
        sessionStorageKey = configuration.map {
            "MorningJuryDemoSession:\(Bundle.main.bundleIdentifier ?? "MORE"):\($0.baseURL.absoluteString)"
        }
        sessionID = sessionStorageKey.flatMap { preferences.string(forKey: $0) }
    }

    deinit {
        operation?.cancel(); speechOperation?.cancel()
        #if os(iOS)
        silence?.cancel(); recognitionDeadline?.cancel(); finalDeadline?.cancel()
        captionTask?.cancel()
        for observer in observers { observer.cancel() }
        #endif
    }

    public func start(language: MorningVoiceCommandLanguage = .french) {
        guard !isActive, state != .paused else { return }
        if let operation {
            let retainedID = sessionID
            Task { [weak self] in
                await operation.value
                guard let self, sessionID == retainedID, state == .failed else { return }
                start(language: language)
            }
            return
        }
        guard let client else { fail(JuryDemoError.configuration); return }
        #if os(iOS)
        guard UIApplication.shared.applicationState == .active else { return }
        self.language = language
        let id = UUID(); runID = id
        let retainedID = sessionID
        state = .preparing; message = "Connexion à MORE…"; transcript = ""
        latestResponse = nil; queuedText = nil; pendingAcknowledgement = nil; recognitionFailures = 0
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                try await prepareAudio(id: id)
                let response: JuryDemoResponse
                if let retainedID { response = try await client.resume(sessionID: retainedID) }
                else { response = try await client.start() }
                try requireCurrent(id)
                rememberSession(response.sessionID)
                operation = nil
                beginRecognition(run: id)
                apply(response, run: id)
            } catch is CancellationError { if runID == id { operation = nil } }
            catch { if runID == id { fail(error) } }
        }
        #else
        fail(JuryDemoError.localVoiceUnavailable)
        #endif
    }

    public func send(text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count <= 4_000, !text.isEmpty, isActive else { return }
        if case .session(.pause) = MorningHandsFreeVoicePolicy.control(in: text, language: language) { pause(); return }
        if case .session(.stop) = MorningHandsFreeVoicePolicy.control(in: text, language: language) { stop(); return }
        if state == .preparing { queuedText = text; return }
        guard let id = runID, let sessionID, let client else { return }
        interruptSpeech()
        if operation == nil, onUserRequest?(text) == true { return }
        guard runID == id, isActive else { return }
        // An in-flight effect must finish before a later instruction can change
        // its context. Never cancel/retry an ambiguous mail send.
        guard operation == nil else { queuedText = text; return }
        state = .thinking; message = "MORE vous répond…"
        let requestID = UUID()
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await client.turn(sessionID: sessionID, requestID: requestID, text: text)
                try requireCurrent(id)
                operation = nil
                apply(response, run: id)
            } catch is CancellationError { }
            catch { if runID == id { fail(error) } }
        }
    }

    /// Verified browser/native actions use the same voice and landscape captions.
    public func announce(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isActive, let runID, let sessionID, !text.isEmpty, text.count <= 8_000 else { return }
        speak(JuryDemoResponse(sessionID: sessionID, stage: stage, text: text, completed: false,
                               receipt: nil, action: nil), run: runID)
    }

    /// The native executor acknowledges only an effect it has actually read back.
    /// An ambiguous result is reported once and reconciled without re-execution.
    public func acknowledgeAction(requestID: String, status: String, receiptID: String? = nil) {
        guard let sessionID, let client, isActive || state == .paused || state == .failed else { return }
        let voiceRun = runID
        guard operation == nil else {
            pendingAcknowledgement = (requestID, status, receiptID); return
        }
        interruptSpeech()
        if isActive { state = .thinking; message = "MORE vérifie le résultat…" }
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await client.actionResult(sessionID: sessionID, requestID: requestID, status: status, receiptID: receiptID)
                try Task.checkCancellation()
                guard self.sessionID == sessionID else { throw CancellationError() }
                operation = nil
                if let voiceRun, runID == voiceRun, state != .failed { apply(response, run: voiceRun) }
                else {
                    latestResponse = response; stage = response.stage
                    onResponse?(response)
                }
            } catch is CancellationError { }
            catch { if self.sessionID == sessionID { fail(error) } }
        }
    }

    /// Pausing really releases the microphone; resuming retains the backend session.
    public func pause() {
        guard isActive else { return }
        // Before bootstrap returns an ID, no user turn or effect can exist.
        // Invalidate it now so a quick resume cannot inherit a canceled startup.
        if sessionID == nil { runID = UUID(); operation?.cancel(); operation = nil }
        state = .paused; message = "Votre matin est en pause."; transcript = ""
        interruptSpeech()
        #if os(iOS)
        releaseAudio()
        #endif
    }

    public func pauseAndRelease() async throws {
        pause()
        #if os(iOS)
        try await audioSession.cancelAndWait()
        #endif
        try Task.checkCancellation()
    }

    public func resume(language: MorningVoiceCommandLanguage? = nil) {
        guard state == .paused, let id = runID else { return }
        if let language { self.language = language }
        #if os(iOS)
        guard UIApplication.shared.applicationState == .active else {
            message = "Ouvrez MORE pour reprendre le microphone."; return
        }
        if sessionID == nil, operation == nil {
            runID = nil; state = .idle; start(language: self.language); return
        }
        state = .preparing
        Task { [weak self] in
            guard let self else { return }
            do {
                try await prepareAudio(id: id)
                try requireCurrent(id)
                guard isActive else { return }
                beginRecognition(run: id)
                if operation != nil { state = .thinking; message = "MORE termine votre demande…" }
                else if let pendingAcknowledgement {
                    self.pendingAcknowledgement = nil
                    acknowledgeAction(requestID: pendingAcknowledgement.requestID, status: pendingAcknowledgement.status, receiptID: pendingAcknowledgement.receiptID)
                }
                else if let queuedText { self.queuedText = nil; send(text: queuedText) }
                else if let latestResponse { speak(latestResponse, run: id) }
            } catch is CancellationError { }
            catch { if runID == id { fail(error) } }
        }
        #endif
    }

    /// Invalidates callbacks synchronously. A late response cannot restart voice.
    public func stop() {
        let stoppedSession = sessionID
        runID = nil; forgetSession(); queuedText = nil; latestResponse = nil; pendingAcknowledgement = nil
        operation?.cancel(); operation = nil
        interruptSpeech(); transcript = ""; state = .idle; message = "Votre matin est arrêté."
        #if os(iOS)
        releaseAudio()
        #endif
        if let stoppedSession, let client {
            Task { try? await client.stop(sessionID: stoppedSession) }
        }
    }

    /// Existing microphone ownership continues in the background. Force-quitting
    /// the app ends the process; a Live Activity cannot restart a microphone.
    public func sceneDidEnterBackground() { }

    private func requireCurrent(_ id: UUID) throws {
        try Task.checkCancellation()
        guard runID == id else { throw CancellationError() }
    }

    private func apply(_ response: JuryDemoResponse, run id: UUID) {
        guard runID == id else { return }
        latestResponse = response; stage = response.stage
        onResponse?(response)
        if response.stage == "stopped" { receiveStoppedSession(response); return }
        if let pendingAcknowledgement {
            self.pendingAcknowledgement = nil
            acknowledgeAction(requestID: pendingAcknowledgement.requestID, status: pendingAcknowledgement.status, receiptID: pendingAcknowledgement.receiptID)
            return
        }
        guard state != .paused else { return }
        if let queuedText {
            self.queuedText = nil
            send(text: queuedText)
        } else { speak(response, run: id) }
    }

    private func speak(_ response: JuryDemoResponse, run id: UUID) {
        guard runID == id, isActive, let client else { return }
        // A response can arrive while resume is still activating audio.
        if state == .preparing { latestResponse = response; return }
        interruptSpeech()
        state = .thinking
        #if os(iOS)
        let speechID = UUID()
        output?.id = speechID
        speechOperation = Task { [weak self] in
            guard let self else { return }
            var phase = "request"
            var byteCount = 0
            do {
                JuryDemoAudioDiagnostic.log.info("speech_request engineRunning=\(self.engine.isRunning, privacy: .public)")
                let data = try await client.speech(text: response.text)
                byteCount = data.count
                phase = "decode_play"
                JuryDemoAudioDiagnostic.log.info("speech_received bytes=\(byteCount, privacy: .public) engineRunning=\(self.engine.isRunning, privacy: .public)")
                try requireCurrent(id)
                guard state != .paused, output?.id == speechID else { return }
                let duration = try output?.play(data: data, id: speechID) { [weak self] in
                    guard let self, runID == id, state != .paused else { return }
                    captionTask?.cancel(); captionTask = nil
                    outputFinishedAt = Date(); state = .listening; message = "Je vous écoute."
                    if response.stage == "complete", response.completed { finish() }
                }
                guard output != nil else { throw JuryDemoError.speechUnavailable }
                outputText = response.text
                state = .speaking; message = "Vous pouvez interrompre MORE."
                beginCaptions(response.text, duration: duration ?? 0, run: id, speech: speechID)
                speechOperation = nil
            } catch is CancellationError { }
            catch {
                let failure = error as NSError
                JuryDemoAudioDiagnostic.log.error("speech_failed phase=\(phase, privacy: .public) domain=\(failure.domain, privacy: .public) code=\(failure.code, privacy: .public) bytes=\(byteCount, privacy: .public) engineRunning=\(self.engine.isRunning, privacy: .public) voiceProcessing=\(self.engine.inputNode.isVoiceProcessingEnabled, privacy: .public)")
                if !Task.isCancelled, runID == id, state != .paused, output?.id == speechID {
                    fail(JuryDemoError.speechUnavailable)
                }
            }
        }
        #else
        onText?(response.text)
        #endif
    }

    private func interruptSpeech() {
        speechOperation?.cancel(); speechOperation = nil
        #if os(iOS)
        captionTask?.cancel(); captionTask = nil
        output?.stop(); outputFinishedAt = Date()
        #endif
        if state == .speaking { state = .listening }
    }

    private func finish() {
        interruptSpeech(); runID = nil; forgetSession()
        state = .completed; message = "Votre matin est terminé."; transcript = ""
        #if os(iOS)
        releaseAudio()
        #endif
        onCompleted?()
    }

    func fail(_ error: any Error) {
        runID = nil; operation?.cancel(); operation = nil; queuedText = nil; pendingAcknowledgement = nil
        interruptSpeech(); transcript = ""; state = .failed
        message = (error as? JuryDemoError)?.localizedDescription ?? JuryDemoError.serviceUnavailable.localizedDescription
        onText?(message)
        #if os(iOS)
        releaseAudio()
        #endif
        // A transport/voice failure is not a user request to stop the backend.
        // Retain its ID so reopening can reconcile a possibly completed effect.
    }

    func receiveStoppedSession(_ response: JuryDemoResponse) {
        guard response.stage == "stopped", response.completed else { return }
        runID = nil; operation?.cancel(); operation = nil; queuedText = nil; pendingAcknowledgement = nil
        interruptSpeech(); transcript = ""; state = .idle; stage = "stopped"
        message = response.text
        onText?(JuryDemoCaptionTiming.passages(response.text).first ?? "Votre matin est arrêté.")
        #if os(iOS)
        releaseAudio()
        #endif
    }

    private func rememberSession(_ id: String) {
        sessionID = id
        if let sessionStorageKey { preferences.set(id, forKey: sessionStorageKey) }
    }

    private func forgetSession() {
        sessionID = nil
        if let sessionStorageKey { preferences.removeObject(forKey: sessionStorageKey) }
    }

    #if os(iOS)
    private func beginCaptions(_ text: String, duration: TimeInterval, run: UUID, speech: UUID) {
        captionTask?.cancel()
        let passages = JuryDemoCaptionTiming.passages(text)
        guard let first = passages.first else { return }
        onText?(first)
        let total = Double(max(1, passages.reduce(0) { $0 + $1.count }))
        captionTask = Task { [weak self] in
            for index in passages.indices.dropFirst() {
                let delay = max(0.1, duration * Double(passages[index - 1].count) / total)
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                guard let self, runID == run, output?.id == speech, state == .speaking else { return }
                onText?(passages[index])
            }
        }
    }

    private func prepareAudio(id: UUID) async throws {
        JuryDemoAudioDiagnostic.log.info("prepare_begin engineRunning=\(self.engine.isRunning, privacy: .public)")
        let audioID = UUID(); audioPreparationID = audioID; audioReleaseID = nil
        guard SFSpeechRecognizer.authorizationStatus() == .authorized,
              AVAudioApplication.shared.recordPermission == .granted,
              let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language.localeIdentifier)),
              recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            throw JuryDemoError.localVoiceUnavailable
        }
        self.recognizer = recognizer
        guard try await audioSession.prepare(for: audioID).value else { throw CancellationError() }
        try requireCurrent(id)
        guard audioPreparationID == audioID, state != .paused else { throw CancellationError() }
        engine = AVAudioEngine()
        let input = engine.inputNode
        try input.setVoiceProcessingEnabled(true)
        guard input.isVoiceProcessingEnabled, !input.isVoiceProcessingBypassed else { throw JuryDemoError.localVoiceUnavailable }
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else { throw JuryDemoError.localVoiceUnavailable }
        let sink = sink
        let tap: @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void = { [sink] buffer, _ in sink.append(buffer) }
        input.installTap(onBus: 0, bufferSize: 1_024, format: format, block: tap)
        hasTap = true
        #if DEBUG
        let observedEngine = engine
        configurationObservation = JuryDemoAudioConfigurationObservation(engine: observedEngine) { [weak self, weak observedEngine] in
            guard let self, let observedEngine, self.engine === observedEngine,
                  runID == id, audioPreparationID == audioID else { return }
            let inputFormat = observedEngine.inputNode.outputFormat(forBus: 0)
            let outputFormat = observedEngine.outputNode.inputFormat(forBus: 0)
            JuryDemoAudioDiagnostic.log.info("configuration_change engineRunning=\(observedEngine.isRunning, privacy: .public) inputRate=\(inputFormat.sampleRate, privacy: .public) inputChannels=\(inputFormat.channelCount, privacy: .public) outputRate=\(outputFormat.sampleRate, privacy: .public) outputChannels=\(outputFormat.channelCount, privacy: .public)")
        }
        #endif
        output = try JuryDemoAudioOutput(engine: engine, format: format)
        engine.prepare(); try engine.start()
        guard engine.isRunning else { throw JuryDemoError.localVoiceUnavailable }
        JuryDemoAudioDiagnostic.log.info("prepare_ready engineRunning=\(self.engine.isRunning, privacy: .public) voiceProcessing=\(input.isVoiceProcessingEnabled, privacy: .public)")
        #if DEBUG
        let route = AVAudioSession.sharedInstance().currentRoute
        let inputPorts = route.inputs.map { $0.portType.rawValue }.joined(separator: ",")
        let outputPorts = route.outputs.map { $0.portType.rawValue }.joined(separator: ",")
        JuryDemoAudioDiagnostic.log.info("prepare_route inputType=\(inputPorts, privacy: .public) outputType=\(outputPorts, privacy: .public) inputMuted=\(input.isVoiceProcessingInputMuted, privacy: .public) appInputMuted=\(AVAudioApplication.shared.isInputMuted, privacy: .public)")
        #endif
        observeInterruptions(run: id)
    }

    private func releaseAudio() {
        JuryDemoAudioDiagnostic.log.info("release_begin engineRunning=\(self.engine.isRunning, privacy: .public)")
        audioPreparationID = nil
        #if DEBUG
        configurationObservation = nil
        #endif
        let releaseID = UUID(); audioReleaseID = releaseID
        for observer in observers { observer.cancel() }; observers.removeAll()
        endRecognition()
        engine.stop()
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        output?.detach(); output = nil; recognizer = nil
        let release = audioSession.cancel()
        Task { [weak self] in
            do { try await release.task.value }
            catch {
                guard let self, audioReleaseID == releaseID else { return }
                message = "Le microphone n’a pas pu être libéré. Arrêtez la voix avant de continuer."
                state = .failed
                onText?(message)
            }
        }
    }

    private func beginRecognition(run id: UUID) {
        guard runID == id, state != .paused, let recognizer, recognizer.isAvailable else { return }
        endRecognition()
        let turnID = UUID(); recognitionID = turnID; finishingInput = false
        transcript = ""
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true; request.shouldReportPartialResults = true
        request.addsPunctuation = true; request.taskHint = .dictation
        request.contextualStrings = ["MORE"] + language.exampleCommands
        sink.replace(request)
        let receive: @Sendable (SFSpeechRecognitionResult?, (any Error)?) -> Void = { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal == true
            #if DEBUG
            let failure = error as NSError?
            JuryDemoAudioDiagnostic.log.info("asr_callback chars=\(text?.count ?? 0, privacy: .public) final=\(final, privacy: .public) failed=\(error != nil, privacy: .public) domain=\(failure?.domain ?? "none", privacy: .public) code=\(failure?.code ?? 0, privacy: .public)")
            #endif
            let failed = error != nil
            Task { @MainActor [weak self] in
                self?.receive(text: text, final: final, failed: failed, run: id, turn: turnID)
            }
        }
        recognition = recognizer.recognitionTask(with: request, resultHandler: receive)
        if operation == nil, speechOperation == nil, state != .speaking { state = .listening; message = "Je vous écoute." }
        recognitionDeadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(40)) } catch { return }
            guard let self, runID == id, recognitionID == turnID else { return }
            if transcript.isEmpty { beginRecognition(run: id) }
            else { finishInput(run: id, turn: turnID) }
        }
    }

    private func receive(text: String?, final: Bool, failed: Bool, run id: UUID, turn turnID: UUID) {
        guard runID == id, recognitionID == turnID, state != .paused else { return }
        if failed {
            if !finishingInput { recognitionFailures += 1 }
            if recognitionFailures >= 3 { fail(JuryDemoError.localVoiceUnavailable); return }
            beginRecognition(run: id)
            return
        }
        guard let text, !text.isEmpty else { return }
        guard text.count <= 4_000 else {
            beginRecognition(run: id)
            message = "Votre demande est trop longue. Dites-la en quelques mots."
            onText?(message)
            return
        }
        let recentOutput = isPlaying || Date().timeIntervalSince(outputFinishedAt) < 1.2 ? outputText : nil
        let duplex = engine.isRunning && engine.inputNode.isVoiceProcessingEnabled &&
            !engine.inputNode.isVoiceProcessingBypassed && output != nil
        guard duplex else { fail(JuryDemoError.localVoiceUnavailable); return }
        if transcript.isEmpty, MorningHandsFreeVoicePolicy.isOutputEcho(text, output: recentOutput, acousticDuplexIsActive: duplex) {
            if final { beginRecognition(run: id) }
            return
        }
        if transcript.isEmpty { interruptSpeech(); recognitionFailures = 0 }
        transcript = text
        if final {
            let utterance = transcript
            beginRecognition(run: id)
            send(text: utterance)
        } else if !finishingInput {
            silence?.cancel()
            silence = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(800)) } catch { return }
                guard let self, runID == id, recognitionID == turnID else { return }
                finishInput(run: id, turn: turnID)
            }
        }
    }

    private func finishInput(run id: UUID, turn turnID: UUID) {
        guard !finishingInput else { return }
        finishingInput = true; sink.end(); recognition?.finish()
        finalDeadline?.cancel()
        finalDeadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            guard let self, runID == id, recognitionID == turnID else { return }
            // A partial transcript cannot authorize an external effect.
            beginRecognition(run: id)
        }
    }

    private func endRecognition() {
        recognitionID = nil; sink.end(); recognition?.cancel(); recognition = nil
        silence?.cancel(); recognitionDeadline?.cancel(); finalDeadline?.cancel()
        silence = nil; recognitionDeadline = nil; finalDeadline = nil
    }

    private func observeInterruptions(run id: UUID) {
        for name in [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification,
                     AVAudioSession.mediaServicesWereResetNotification] {
            observers.append(Task { [weak self] in
                let reasons = NotificationCenter.default.notifications(named: name)
                    .map { $0.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0 }
                for await reason in reasons {
                    guard !Task.isCancelled, let self, runID == id else { return }
                    if name == AVAudioSession.routeChangeNotification,
                       reason == AVAudioSession.RouteChangeReason.categoryChange.rawValue { continue }
                    pause()
                    message = "La voix est en pause après une interruption. Reprenez votre matin dans MORE."
                    return
                }
            })
        }
    }

    private static func activateAudio() async throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
        if #available(iOS 27.0, *) {
            guard try await session.activate(options: []) else { throw JuryDemoError.localVoiceUnavailable }
        } else { try session.setActive(true) }
    }

    private static func deactivateAudio() async throws {
        let session = AVAudioSession.sharedInstance()
        if #available(iOS 27.0, *) {
            guard try await session.deactivate(options: .notifyOthersOnDeactivation) else { throw JuryDemoError.localVoiceUnavailable }
        } else { try session.setActive(false, options: .notifyOthersOnDeactivation) }
    }
    #endif
}

#if os(iOS)
private enum JuryDemoAudioDiagnostic {
    static let log = Logger(subsystem: "com.gibouu.morningoperator.demo", category: "JURY_AUDIO")
}

#if DEBUG
private final class JuryDemoAudioConfigurationObservation: @unchecked Sendable {
    private let token: any NSObjectProtocol

    init(engine: AVAudioEngine, onChange: @escaping @MainActor @Sendable () -> Void) {
        token = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
                                                       object: engine, queue: nil) { _ in
            Task { @MainActor in onChange() }
        }
    }

    deinit { NotificationCenter.default.removeObserver(token) }
}
#endif

private final class JuryDemoAudioSink: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    #if DEBUG
    private var diagnosticBuffers: UInt64 = 0
    private var diagnosticFrames: UInt64 = 0
    private var diagnosticPeak: Double = 0
    private var diagnosticNonZero: UInt64 = 0
    private var diagnosticFormat: AVAudioFormat?
    private var diagnosticLoggedAt: TimeInterval = 0
    #endif
    func replace(_ request: SFSpeechAudioBufferRecognitionRequest) {
        lock.lock(); defer { lock.unlock() }
        self.request?.endAudio(); self.request = request
    }
    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        #if DEBUG
        diagnosticBuffers += 1
        diagnosticFrames += UInt64(buffer.frameLength)
        let stride = buffer.stride
        if diagnosticFormat?.isEqual(buffer.format) != true {
            diagnosticFormat = buffer.format
            JuryDemoAudioDiagnostic.log.info("tap_format commonFormat=\(buffer.format.commonFormat.rawValue, privacy: .public) sampleRate=\(buffer.format.sampleRate, privacy: .public) channels=\(buffer.format.channelCount, privacy: .public) stride=\(stride, privacy: .public) interleaved=\(buffer.format.isInterleaved, privacy: .public) floatPresent=\(buffer.floatChannelData != nil, privacy: .public) int16Present=\(buffer.int16ChannelData != nil, privacy: .public) int32Present=\(buffer.int32ChannelData != nil, privacy: .public)")
        }
        for channel in 0..<Int(buffer.format.channelCount) {
            for frame in 0..<Int(buffer.frameLength) {
                let offset = frame * stride
                let sample: Double
                if let channels = buffer.floatChannelData { sample = Double(channels[channel][offset]) }
                else if let channels = buffer.int16ChannelData { sample = Double(channels[channel][offset]) / 32_768 }
                else if let channels = buffer.int32ChannelData { sample = Double(channels[channel][offset]) / 2_147_483_648 }
                else { continue }
                if sample != 0 { diagnosticNonZero += 1 }
                diagnosticPeak = max(diagnosticPeak, abs(sample))
            }
        }
        let now = Date.timeIntervalSinceReferenceDate
        if now - diagnosticLoggedAt >= 1 {
            JuryDemoAudioDiagnostic.log.info("tap_buffers total=\(self.diagnosticBuffers, privacy: .public) frames=\(self.diagnosticFrames, privacy: .public) peakMicro=\(self.diagnosticPeak * 1_000_000, privacy: .public) nonZeroSamples=\(self.diagnosticNonZero, privacy: .public) requestActive=\(self.request != nil, privacy: .public)")
            diagnosticLoggedAt = now; diagnosticPeak = 0
        }
        #endif
        request?.append(buffer)
    }
    func end() { lock.lock(); defer { lock.unlock() }; request?.endAudio(); request = nil }
}

/// ElevenLabs output shares the microphone's voice-processing engine, so the
/// recognizer cannot mistake speaker output for the user's authorization.
@MainActor
private final class JuryDemoAudioOutput {
    var id: UUID?
    private let engine: AVAudioEngine
    private let player = AVAudioPlayerNode()
    private let playbackFormat: AVAudioFormat

    init(engine: AVAudioEngine, format: AVAudioFormat) throws {
        guard format.sampleRate > 0, format.channelCount > 0 else { throw JuryDemoError.speechUnavailable }
        self.engine = engine; playbackFormat = format
        engine.attach(player)
        // Voice processing uses the same format for both I/O nodes. Build this
        // path before engine.start; decoded speech never reconnects the graph.
        if #available(iOS 27.0, *) { try engine.connectNode(player, to: engine.outputNode, format: format) }
        else { engine.connect(player, to: engine.outputNode, format: format) }
    }

    func play(data: Data, id: UUID, completion: @escaping @MainActor () -> Void) throws -> TimeInterval {
        var phase = "write"
        do {
        // Only synthesized output is decoded via a protected temporary MP3.
        // It is removed when scheduling finishes; microphone audio never touches disk.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("more-voice-\(UUID().uuidString).mp3")
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        phase = "decode"
        let file = try AVAudioFile(forReading: url)
        guard file.length > 0, file.length <= 12_000_000,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw JuryDemoError.speechUnavailable
        }
        try file.read(into: buffer)
        phase = "convert"
        let playbackBuffer = try convertForPlayback(buffer)
        phase = "play"
        JuryDemoAudioDiagnostic.log.info("output_decoded frames=\(buffer.frameLength, privacy: .public) sampleRate=\(buffer.format.sampleRate, privacy: .public) engineRunning=\(self.engine.isRunning, privacy: .public)")
        #if DEBUG
        JuryDemoAudioDiagnostic.log.info("output_converted frames=\(playbackBuffer.frameLength, privacy: .public) sampleRate=\(playbackBuffer.format.sampleRate, privacy: .public) channels=\(playbackBuffer.format.channelCount, privacy: .public)")
        #endif
        guard engine.isRunning else { throw JuryDemoError.speechUnavailable }
        self.id = id
        player.stop()
        let played: @Sendable (AVAudioPlayerNodeCompletionCallbackType) -> Void = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.id == id else { return }
                self.id = nil; completion()
            }
        }
        player.scheduleBuffer(playbackBuffer, completionCallbackType: .dataPlayedBack, completionHandler: played)
        player.play()
        JuryDemoAudioDiagnostic.log.info("output_playing engineRunning=\(self.engine.isRunning, privacy: .public) playerPlaying=\(self.player.isPlaying, privacy: .public)")
        return Double(playbackBuffer.frameLength) / playbackBuffer.format.sampleRate
        } catch {
            let failure = error as NSError
            JuryDemoAudioDiagnostic.log.error("output_failed phase=\(phase, privacy: .public) domain=\(failure.domain, privacy: .public) code=\(failure.code, privacy: .public) engineRunning=\(self.engine.isRunning, privacy: .public)")
            throw error
        }
    }

    private func convertForPlayback(_ input: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        if input.format.isEqual(playbackFormat) { return input }
        guard input.format.sampleRate > 0,
              let converter = AVAudioConverter(from: input.format, to: playbackFormat) else {
            throw JuryDemoError.speechUnavailable
        }
        let ratio = playbackFormat.sampleRate / input.format.sampleRate
        let primingFrames = Double(converter.primeInfo.leadingFrames) + Double(converter.primeInfo.trailingFrames)
        let capacity = ceil((Double(input.frameLength) + primingFrames) * ratio) + 32
        guard capacity.isFinite, capacity > 0, capacity <= 12_000_000,
              let converted = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: AVAudioFrameCount(capacity)) else {
            throw JuryDemoError.speechUnavailable
        }
        var supplied = false
        var failure: NSError?
        let status = converter.convert(to: converted, error: &failure) { _, outStatus in
            guard !supplied else { outStatus.pointee = .endOfStream; return nil }
            supplied = true; outStatus.pointee = .haveData
            return input
        }
        if let failure { throw failure }
        guard status != .error, converted.frameLength > 0 else { throw JuryDemoError.speechUnavailable }
        return converted
    }

    func stop() { id = nil; player.stop() }
    func detach() { stop(); engine.disconnectNodeOutput(player); engine.detach(player) }
}
#endif

/// Captions track short passages by their share of decoded playback duration.
/// Their timing is approximate; it is never presented as word-level alignment.
enum JuryDemoCaptionTiming {
    static func passages(_ text: String) -> [String] {
        var passages: [String] = []
        var current = ""
        for word in text.split(whereSeparator: \.isWhitespace) {
            for part in word.chunks(maximum: 150) {
                if !current.isEmpty, current.count + part.count + 1 > 150 {
                    passages.append(current); current = ""
                }
                if !current.isEmpty { current += " " }
                current += part
                if current.count >= 75, let last = current.last, ".!?;".contains(last) {
                    passages.append(current); current = ""
                }
            }
        }
        if !current.isEmpty { passages.append(current) }
        return passages
    }
}

private extension Substring {
    func chunks(maximum: Int) -> [String] {
        var remaining = self
        var parts: [String] = []
        while !remaining.isEmpty {
            let end = remaining.index(remaining.startIndex, offsetBy: maximum, limitedBy: remaining.endIndex) ?? remaining.endIndex
            parts.append(String(remaining[..<end])); remaining = remaining[end...]
        }
        return parts
    }
}
