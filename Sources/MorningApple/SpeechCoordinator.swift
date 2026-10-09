import AVFAudio
import Foundation
import Observation

public enum SpeechPlaybackState: String, Sendable, Equatable {
    case idle, speaking, paused
}

/// Local system text-to-speech. The system/user chooses the output route.
@MainActor
@Observable
public final class SpeechCoordinator: NSObject {
    public private(set) var state: SpeechPlaybackState = .idle
    public private(set) var lastError: String?
    public var isSpeaking: Bool { state == .speaking }

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var currentUtterance: ObjectIdentifier?
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
        lastError = nil
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            lastError = "Audio output is unavailable: \(error.localizedDescription)"
            return
        }
        #endif
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        if let language = Locale.current.language.languageCode?.identifier {
            utterance.voice = AVSpeechSynthesisVoice(language: language)
        }
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
        synthesizer.stopSpeaking(at: .immediate)
        state = .idle
        deactivateAudioSession()
    }

    private func receive(_ state: SpeechPlaybackState, utteranceID: ObjectIdentifier, finished: Bool = false) {
        guard currentUtterance == utteranceID else { return }
        self.state = state
        if finished {
            currentUtterance = nil
            deactivateAudioSession()
        }
    }

    private func deactivateAudioSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
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
        Task { @MainActor [weak self] in self?.receive(.idle, utteranceID: id, finished: true) }
    }
}
