import Foundation
import MorningCore
import Observation
#if os(iOS)
import AVFAudio
import Speech
import UIKit
#endif

public enum MorningVoiceListeningState: String, Sendable {
    case idle, requestingPermission, preparing, listening, finishing, unavailable, failed
}

public enum MorningVoiceListeningError: LocalizedError, Sendable, Equatable {
    case alreadyListening, microphoneDenied, speechDenied, onDeviceUnavailable, unavailable
    case unrecognized, timedOut, audio(String)

    public var errorDescription: String? {
        switch self {
        case .alreadyListening: "Finish or cancel the current listening turn first."
        case .microphoneDenied: "Microphone access is off. Use the routine buttons, or enable access in Settings."
        case .speechDenied: "Speech recognition is unavailable or not allowed. You can still use the routine buttons."
        case .onDeviceUnavailable: "On-device recognition is not available for this language. Use the routine buttons; audio will not be sent to a server."
        case .unavailable: "Voice commands are not available here right now. Use the routine buttons."
        case .unrecognized: "That was not one clear command. Try next, pause, resume, skip, repeat or stop."
        case .timedOut: "No final command was received. Nothing was changed. Try again or use the routine buttons."
        case .audio(let reason): "Listening could not finish safely: \(reason)"
        }
    }
}

/// One user-initiated, on-device microphone turn. The caller first pauses its routine,
/// cancels automation and awaits SpeechCoordinator.stopAndRelease(). Returned commands
/// have no effect until the caller verifies their pinned context and dispatches them.
@MainActor
@Observable
public final class MorningVoiceCommandListener {
    public private(set) var state: MorningVoiceListeningState = .idle
    public private(set) var transcript = ""
    public private(set) var message = "Tap to say one command."
    public private(set) var inputRouteName: String?
    /// Playback must remain blocked until microphone ownership has been released.
    public private(set) var needsAudioRelease = false
    public var isBusy: Bool {
        switch state {
        case .requestingPermission, .preparing, .listening, .finishing: true
        default: false
        }
    }

    #if os(iOS)
    @ObservationIgnored private var activeTurnID: UUID?
    @ObservationIgnored private var finishingTurnID: UUID?
    @ObservationIgnored private var cancelledTurnID: UUID?
    @ObservationIgnored private var turn: MorningVoiceCommandTurn?
    @ObservationIgnored private var recognizer: SFSpeechRecognizer?
    @ObservationIgnored private var recognitionTask: SFSpeechRecognitionTask?
    @ObservationIgnored private var sink: CommandAudioBufferSink?
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var hasTap = false
    @ObservationIgnored private var inputRouteIDs: [String] = []
    @ObservationIgnored private var pending: CheckedContinuation<MorningVoiceCommandEnvelope, any Error>?
    @ObservationIgnored private var captureDeadline: Task<Void, Never>?
    @ObservationIgnored private var finalDeadline: Task<Void, Never>?
    @ObservationIgnored private var shutdownTask: Task<Void, any Error>?
    @ObservationIgnored private var routeTask: Task<Void, Never>?
    @ObservationIgnored private var interruptionTask: Task<Void, Never>?
    @ObservationIgnored private var backgroundTask: Task<Void, Never>?
    @ObservationIgnored private lazy var audioSession = SpeechAudioSessionGate(
        activate: { try await Self.activateMicrophone() },
        deactivate: { try await Self.releaseMicrophone() }
    )
    #endif

    public init() {
        #if os(iOS)
        routeTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: AVAudioSession.routeChangeNotification) {
                guard !Task.isCancelled else { return }
                guard let self, self.state == .listening,
                      self.inputRouteIDs != AVAudioSession.sharedInstance().currentRoute.inputs.map(\.uid) else { continue }
                try? await self.cancel()
            }
        }
        interruptionTask = Task { [weak self] in
            let types = NotificationCenter.default.notifications(named: AVAudioSession.interruptionNotification)
                .compactMap { $0.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt }
            for await type in types {
                guard !Task.isCancelled else { return }
                if type == AVAudioSession.InterruptionType.began.rawValue { try? await self?.cancel() }
            }
        }
        backgroundTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UIApplication.didEnterBackgroundNotification) {
                guard !Task.isCancelled else { return }
                try? await self?.cancel()
            }
        }
        #endif
    }

    deinit {
        #if os(iOS)
        captureDeadline?.cancel(); finalDeadline?.cancel()
        routeTask?.cancel(); interruptionTask?.cancel(); backgroundTask?.cancel()
        #endif
    }

    /// Requests permissions only in response to this call. Captures for at most eight
    /// seconds, then allows three seconds for the recognizer's final whole-turn result.
    /// Never persists audio or a transcript and never falls back to server recognition.
    public func listen(context: MorningVoiceCommandContext,
                       language: MorningVoiceCommandLanguage = .english) async throws -> MorningVoiceCommandEnvelope {
        guard !isBusy else { throw MorningVoiceListeningError.alreadyListening }
        guard !needsAudioRelease else {
            throw MorningVoiceListeningError.audio("Microphone release is still unconfirmed. Retry stopping listening before starting another turn.")
        }
        #if os(iOS)
        try Task.checkCancellation()
        let newTurn = MorningVoiceCommandTurn(context: context)
        let id = newTurn.id
        activeTurnID = id; turn = newTurn
        cancelledTurnID = nil
        transcript = ""; inputRouteName = nil
        state = .requestingPermission; message = "Checking microphone and speech access…"
        return try await withTaskCancellationHandler {
            do {
                try await requestPermissionsAndRecognizer(language: language, id: id)
                try checkCurrent(id)
                state = .preparing; message = "Preparing the microphone…"
                needsAudioRelease = true
                let prepared = try await audioSession.prepare(for: id).value
                try checkCurrent(id)
                guard prepared else { throw CancellationError() }
                let command = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<MorningVoiceCommandEnvelope, any Error>) in
                    pending = continuation
                    do { try beginCapture(id: id, language: language) }
                    catch { _ = completeTurn(id: id, result: .failure(error)) }
                }
                try Task.checkCancellation()
                guard cancelledTurnID != id else { throw CancellationError() }
                return command
            } catch {
                // Also handles permission/setup failures before a continuation exists.
                if let cleanup = completeTurn(id: id, result: .failure(error)) {
                    try await cleanup.value
                }
                throw error
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, self.activeTurnID == id else { return }
                try? await self.cancel()
            }
        }
        #else
        state = .unavailable; message = MorningVoiceListeningError.unavailable.localizedDescription
        throw MorningVoiceListeningError.unavailable
        #endif
    }

    /// End input but allow its final recognition result. Cancel is a separate operation.
    public func finishListening() {
        #if os(iOS)
        guard state == .listening, let id = activeTurnID else { return }
        captureDeadline?.cancel(); captureDeadline = nil
        stopAudioInput()
        state = .finishing; message = "Understanding your command…"
        recognitionTask?.finish()
        finalDeadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            guard let self, self.activeTurnID == id else { return }
            _ = self.completeTurn(id: id, result: .failure(MorningVoiceListeningError.timedOut))
        }
        #endif
    }

    /// Invalidates late callbacks before releasing the microphone. Repeated cancellation
    /// awaits the same cleanup; a release failure is surfaced rather than claiming success.
    public func cancel() async throws {
        #if os(iOS)
        if let id = activeTurnID {
            cancelledTurnID = id
            if let cleanup = completeTurn(id: id, result: .failure(CancellationError())) { try await cleanup.value }
        } else if needsAudioRelease, state != .finishing {
            // A previous release failure remains a real ownership problem. Retrying
            // cleanup never activates the microphone or starts a recognition turn.
            state = .finishing; message = "Releasing the microphone…"
            let retry = Task { @MainActor [self] in
                do {
                    try await audioSession.cancelAndWait()
                    needsAudioRelease = false
                    state = .idle; message = "Microphone released."
                } catch {
                    state = .failed
                    message = MorningVoiceListeningError.audio(error.localizedDescription).localizedDescription
                    throw error
                }
            }
            shutdownTask = retry
            try await retry.value
        } else if let shutdownTask {
            if let finishingTurnID { cancelledTurnID = finishingTurnID }
            try await shutdownTask.value
        }
        #endif
    }

    #if os(iOS)
    private func requestPermissionsAndRecognizer(language: MorningVoiceCommandLanguage, id: UUID) async throws {
        try checkCurrent(id)
        var authorization = SFSpeechRecognizer.authorizationStatus()
        if authorization == .notDetermined {
            let raw = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0.rawValue) }
            }
            authorization = SFSpeechRecognizerAuthorizationStatus(rawValue: raw) ?? .denied
        }
        try checkCurrent(id)
        guard authorization == .authorized else { throw MorningVoiceListeningError.speechDenied }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language.localeIdentifier)),
              recognizer.isAvailable else { throw MorningVoiceListeningError.unavailable }
        let actualLanguage = recognizer.locale.identifier.replacingOccurrences(of: "_", with: "-")
            .components(separatedBy: "-").first
        let expectedLanguage = language.localeIdentifier.components(separatedBy: "-").first
        guard actualLanguage == expectedLanguage, recognizer.supportsOnDeviceRecognition else {
            throw MorningVoiceListeningError.onDeviceUnavailable
        }
        var granted = AVAudioApplication.shared.recordPermission == .granted
        if AVAudioApplication.shared.recordPermission == .undetermined {
            granted = await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
            }
        }
        try checkCurrent(id)
        guard granted else { throw MorningVoiceListeningError.microphoneDenied }
        self.recognizer = recognizer
    }

    private func checkCurrent(_ id: UUID) throws {
        try Task.checkCancellation()
        guard activeTurnID == id else { throw CancellationError() }
    }

    private func beginCapture(id: UUID, language: MorningVoiceCommandLanguage) throws {
        try checkCurrent(id)
        guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            throw MorningVoiceListeningError.onDeviceUnavailable
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = false
        request.taskHint = .confirmation
        request.contextualStrings = language.exampleCommands + language.exampleCommands.map { "MORE \($0)" }
        let sink = CommandAudioBufferSink(request: request)
        self.sink = sink
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            // Only send value types across the framework callback's executor boundary.
            let hypothesis = result.map { CommandHypothesis(text: $0.bestTranscription.formattedString,
                isFinal: $0.isFinal, alternatives: $0.transcriptions.map(\.formattedString)) }
            let failure = error?.localizedDescription
            Task { @MainActor [weak self] in self?.receive(hypothesis, error: failure, id: id) }
        }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            throw MorningVoiceListeningError.audio("No microphone input is available.")
        }
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in sink.append(buffer) }
        hasTap = true
        engine.prepare()
        try engine.start()
        let route = AVAudioSession.sharedInstance().currentRoute
        inputRouteIDs = route.inputs.map(\.uid)
        inputRouteName = route.inputs.map(\.portName).joined(separator: ", ")
        state = .listening; message = "Listening for one command…"
        captureDeadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            guard let self, self.activeTurnID == id else { return }
            self.finishListening()
        }
    }

    private func receive(_ hypothesis: CommandHypothesis?, error: String?, id: UUID) {
        guard activeTurnID == id else { return }
        if let error {
            _ = completeTurn(id: id, result: .failure(MorningVoiceListeningError.audio(error)))
            return
        }
        guard let hypothesis else { return }
        transcript = hypothesis.text
        guard hypothesis.isFinal else { return }
        if let envelope = turn?.accept(transcript: hypothesis.text, isFinal: true, alternatives: hypothesis.alternatives) {
            _ = completeTurn(id: id, result: .success(envelope))
        } else {
            _ = completeTurn(id: id, result: .failure(MorningVoiceListeningError.unrecognized))
        }
    }

    private func stopAudioInput() {
        engine.stop()
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        sink?.endAudio()
    }

    @discardableResult
    private func completeTurn(id: UUID, result: Result<MorningVoiceCommandEnvelope, any Error>) -> Task<Void, any Error>? {
        guard activeTurnID == id else { return nil }
        activeTurnID = nil; turn?.cancel()
        finishingTurnID = id
        state = .finishing
        captureDeadline?.cancel(); captureDeadline = nil
        finalDeadline?.cancel(); finalDeadline = nil
        stopAudioInput()
        recognitionTask?.cancel(); recognitionTask = nil
        sink = nil; recognizer = nil
        let continuation = pending; pending = nil
        let cleanup = Task { @MainActor [self] in
            var outcome = result
            var releaseFailure: (any Error)?
            do {
                try await audioSession.cancelAndWait()
                needsAudioRelease = false
            }
            catch {
                releaseFailure = error
                outcome = .failure(MorningVoiceListeningError.audio(error.localizedDescription))
            }
            if releaseFailure == nil, cancelledTurnID == id { outcome = .failure(CancellationError()) }
            finishingTurnID = nil
            switch outcome {
            case .success(let command):
                state = .idle; message = "Heard: \(command.transcript)"
            case .failure(let error):
                if error is CancellationError { state = .idle; message = "Listening stopped." }
                else {
                    switch error as? MorningVoiceListeningError {
                    case .microphoneDenied, .speechDenied, .onDeviceUnavailable, .unavailable: state = .unavailable
                    default: state = .failed
                    }
                    message = error.localizedDescription
                }
            }
            continuation?.resume(with: outcome)
            if let releaseFailure { throw releaseFailure }
        }
        shutdownTask = cleanup
        return cleanup
    }

    private static func activateMicrophone() async throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [])
        if #available(iOS 27.0, *) {
            guard try await session.activate(options: []) else { throw MorningVoiceListeningError.audio("The microphone session did not activate.") }
        } else { try session.setActive(true) }
    }

    private static func releaseMicrophone() async throws {
        let session = AVAudioSession.sharedInstance()
        if #available(iOS 27.0, *) {
            guard try await session.deactivate(options: .notifyOthersOnDeactivation) else {
                throw MorningVoiceListeningError.audio("Microphone audio release was not confirmed.")
            }
        } else { try session.setActive(false, options: .notifyOthersOnDeactivation) }
    }
    #endif
}

#if os(iOS)
private struct CommandHypothesis: Sendable {
    let text: String
    let isFinal: Bool
    let alternatives: [String]
}

/// AVAudioEngine invokes its tap outside the main actor. This small locked sink is the
/// only cross-executor owner of the request's append/endAudio boundary; no audio is saved.
private final class CommandAudioBufferSink: @unchecked Sendable {
    private let lock = NSLock()
    private let request: SFSpeechAudioBufferRecognitionRequest
    private var ended = false
    init(request: SFSpeechAudioBufferRecognitionRequest) { self.request = request }
    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        guard !ended else { return }
        request.append(buffer)
    }
    func endAudio() {
        lock.lock(); defer { lock.unlock() }
        guard !ended else { return }
        ended = true
        request.endAudio()
    }
}
#endif
