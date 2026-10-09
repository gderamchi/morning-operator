import AVFAudio
import Foundation
import Observation

public enum SpeechPlaybackState: String, Sendable, Equatable {
    case idle, speaking, paused
}

public struct SpeechVoiceDescriptor: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let language: String
}

public enum SpeechPlaybackError: LocalizedError, Sendable, Equatable {
    case emptyText
    case audioUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .emptyText: "There is no text to read."
        case .audioUnavailable(let reason): "Audio output is unavailable: \(reason)"
        }
    }
}

/// Local system text-to-speech. The system/user chooses the output route.
@MainActor
@Observable
public final class SpeechCoordinator: NSObject {
    public private(set) var state: SpeechPlaybackState = .idle
    public private(set) var lastError: String?
    /// Identifies the current utterance so a preview cannot stop later routine speech.
    public private(set) var playbackID: UUID?
    /// A persisted choice may become unavailable after a system voice is removed.
    /// Nil, unknown, and unavailable choices use the current system language.
    public var voiceIdentifier: String?
    public var isSpeaking: Bool { state == .speaking }

    public var availableVoices: [SpeechVoiceDescriptor] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { Self.isBuiltInVoice($0) }
            .map { SpeechVoiceDescriptor(id: $0.identifier, name: $0.name, language: $0.language) }
            .sorted {
                let nameOrder = $0.name.localizedStandardCompare($1.name)
                if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
                if $0.language != $1.language { return $0.language < $1.language }
                return $0.id < $1.id
            }
    }

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var currentUtterance: ObjectIdentifier?
    @ObservationIgnored private var speechRequestID: UUID?
    @ObservationIgnored private var completion: CheckedContinuation<Void, any Error>?
    @ObservationIgnored private var routeTask: Task<Void, Never>?
    @ObservationIgnored private var interruptionTask: Task<Void, Never>?

    public override init() {
        super.init()
        synthesizer.delegate = self
        #if os(iOS)
        routeTask = Task { [weak self] in
            let reasons = NotificationCenter.default.notifications(named: AVAudioSession.routeChangeNotification)
                .compactMap { $0.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt }
            for await rawReason in reasons {
                guard !Task.isCancelled else { return }
                let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason)
                if reason == .oldDeviceUnavailable {
                    self?.pause()
                    self?.lastError = "Audio output changed. Resume when you are ready to listen."
                }
            }
        }
        interruptionTask = Task { [weak self] in
            let types = NotificationCenter.default.notifications(named: AVAudioSession.interruptionNotification)
                .compactMap { $0.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt }
            for await rawType in types {
                guard !Task.isCancelled else { return }
                let type = AVAudioSession.InterruptionType(rawValue: rawType)
                if type == .began {
                    self?.pause()
                    self?.lastError = "Speech was interrupted. Resume when you are ready."
                }
            }
        }
        #endif
    }

    deinit {
        routeTask?.cancel()
        interruptionTask?.cancel()
    }

    public func speak(_ text: String) {
        stop()
        beginSpeech(text)
    }

    /// Returns only when AVSpeechSynthesizer reports didFinish for this exact utterance.
    /// Stop, replacement, cancellation or didCancel throws; pause alone keeps waiting.
    /// Completion proves synthesis finished, not that a listener heard the selected output.
    public func speakAndWait(_ text: String) async throws {
        try Task.checkCancellation()
        let requestID = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                stop()
                speechRequestID = requestID
                completion = continuation
                beginSpeech(text)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                // A delayed cancellation must not stop a newer request.
                guard self?.speechRequestID == requestID else { return }
                self?.stop()
            }
        }
    }

    private func beginSpeech(_ text: String) {
        lastError = nil
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            failBeforeSpeaking(SpeechPlaybackError.emptyText)
            return
        }
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            failBeforeSpeaking(SpeechPlaybackError.audioUnavailable(error.localizedDescription))
            return
        }
        #endif
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        if let voiceIdentifier,
           let selectedVoice = AVSpeechSynthesisVoice(identifier: voiceIdentifier),
           Self.isBuiltInVoice(selectedVoice) {
            utterance.voice = selectedVoice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
        }
        playbackID = UUID()
        currentUtterance = ObjectIdentifier(utterance)
        synthesizer.speak(utterance)
    }

    public func pause() {
        if synthesizer.pauseSpeaking(at: .immediate) { state = .paused }
    }

    public func resume() {
        lastError = nil
        if synthesizer.continueSpeaking() { state = .speaking }
    }

    public func stop() {
        // Invalidate first, so a late callback from the previous utterance cannot stop a new one.
        currentUtterance = nil
        playbackID = nil
        speechRequestID = nil
        let pending = completion
        completion = nil
        synthesizer.stopSpeaking(at: .immediate)
        state = .idle
        deactivateAudioSession()
        pending?.resume(throwing: CancellationError())
    }

    private func failBeforeSpeaking(_ error: SpeechPlaybackError) {
        lastError = error.localizedDescription
        playbackID = nil
        speechRequestID = nil
        let pending = completion
        completion = nil
        state = .idle
        deactivateAudioSession()
        pending?.resume(throwing: error)
    }

    private func receive(_ state: SpeechPlaybackState, utteranceID: ObjectIdentifier,
                         finished: Bool = false, cancelled: Bool = false) {
        guard currentUtterance == utteranceID else { return }
        self.state = state
        if finished {
            currentUtterance = nil
            playbackID = nil
            speechRequestID = nil
            let pending = completion
            completion = nil
            deactivateAudioSession()
            if cancelled { pending?.resume(throwing: CancellationError()) }
            else { pending?.resume() }
        }
    }

    private func deactivateAudioSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    private static func isBuiltInVoice(_ voice: AVSpeechSynthesisVoice) -> Bool {
        // speechVoices() also includes third-party providers. Apple exposes no provider
        // ownership property, so use a conservative namespace filter for this chooser.
        // Personal Voice stays excluded even if another app flow previously authorized it.
        voice.identifier.hasPrefix("com.apple.") && !voice.voiceTraits.contains(.isPersonalVoice)
    }
}

extension SpeechCoordinator: AVSpeechSynthesizerDelegate {
    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.receive(.speaking, utteranceID: id) }
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.receive(.paused, utteranceID: id) }
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.receive(.speaking, utteranceID: id) }
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.receive(.idle, utteranceID: id, finished: true) }
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.receive(.idle, utteranceID: id, finished: true, cancelled: true) }
    }
}
