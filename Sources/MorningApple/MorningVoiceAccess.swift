import Foundation
import Observation
import MorningCore
#if os(iOS)
import AVFAudio
import Speech
import UIKit
#endif

public struct MorningVoiceAccessSnapshot: Equatable, Sendable {
    public enum Speech: Sendable, Equatable { case notDetermined, authorized, denied, restricted, unavailable }
    public enum Microphone: Sendable, Equatable { case undetermined, granted, denied, unavailable }
    public enum LocalRecognition: Sendable, Equatable { case notChecked, available, temporarilyUnavailable, unsupported }
    public let speech: Speech
    public let microphone: Microphone
    public let localRecognition: LocalRecognition
    public init(speech: Speech, microphone: Microphone, localRecognition: LocalRecognition) {
        self.speech = speech; self.microphone = microphone; self.localRecognition = localRecognition
    }
    public var isReady: Bool { speech == .authorized && microphone == .granted && localRecognition == .available }
    public var canRequest: Bool {
        localRecognition != .unsupported && speech != .denied && speech != .restricted && speech != .unavailable &&
            microphone != .denied && microphone != .unavailable && (speech == .notDetermined || microphone == .undetermined)
    }
    public var canOpenSettings: Bool { speech == .denied || microphone == .denied }

    public func description(french: Bool = AppLanguage.isFrench) -> String {
        let recognition: String
        switch speech {
        case .notDetermined: recognition = french ? "Reconnaissance vocale : autorisation à préparer." : "Speech recognition: permission not prepared."
        case .authorized: recognition = french ? "Reconnaissance vocale : autorisée." : "Speech recognition: allowed."
        case .denied: recognition = french ? "Reconnaissance vocale : accès refusé. Vous pouvez le modifier dans les réglages iPhone." : "Speech recognition: denied. You can change this in iPhone settings."
        case .restricted: recognition = french ? "Reconnaissance vocale : limitée par les restrictions de cet iPhone." : "Speech recognition: restricted on this iPhone."
        case .unavailable: recognition = french ? "Reconnaissance vocale : indisponible ici." : "Speech recognition: unavailable here."
        }
        let input: String
        switch microphone {
        case .undetermined: input = french ? "Microphone : autorisation à préparer." : "Microphone: permission not prepared."
        case .granted: input = french ? "Microphone : autorisé." : "Microphone: allowed."
        case .denied: input = french ? "Microphone : accès refusé. Vous pouvez le modifier dans les réglages iPhone." : "Microphone: denied. You can change this in iPhone settings."
        case .unavailable: input = french ? "Microphone : indisponible ici." : "Microphone: unavailable here."
        }
        let local: String
        switch localRecognition {
        case .notChecked: local = french ? "La disponibilité de la reconnaissance locale sera vérifiée après votre autorisation. Aucune écoute n’a commencé." : "Local recognition availability will be checked after your permission. Listening has not started."
        case .available: local = french ? "Reconnaissance locale disponible pour cette langue. Aucun son n’est envoyé à un serveur." : "Local recognition is available for this language. No audio is sent to a server."
        case .temporarilyUnavailable: local = french ? "Reconnaissance locale temporairement indisponible. Actualisez son état ou utilisez les boutons." : "Local recognition is temporarily unavailable. Refresh its status or use the buttons."
        case .unsupported: local = french ? "La reconnaissance locale n’est pas prise en charge ici pour cette langue. Vous pouvez continuer avec les boutons ; aucun service distant ne prendra le relais." : "Local recognition is not supported here for this language. You can continue with the buttons; no remote service will take over."
        }
        return [recognition, input, local].joined(separator: "\n\n")
    }
}

/// Permission preparation only. This object has no audio engine, input tap or
/// AVAudioSession activation, and never invokes a recognition task or synthesis.
@MainActor @Observable public final class MorningVoiceAccess {
    public private(set) var snapshot: MorningVoiceAccessSnapshot
    public private(set) var isRequesting = false
    @ObservationIgnored private let probe: @MainActor (MorningVoiceCommandLanguage) -> MorningVoiceAccessSnapshot
    @ObservationIgnored private let speechRequest: @MainActor () async -> Void
    @ObservationIgnored private let microphoneRequest: @MainActor () async -> Void
    @ObservationIgnored private var revision = UUID()

    public convenience init() {
        self.init(probe: Self.systemSnapshot, speechRequest: {
            #if os(iOS)
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                SFSpeechRecognizer.requestAuthorization { _ in continuation.resume() }
            }
            #endif
        }, microphoneRequest: {
            #if os(iOS)
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                AVAudioApplication.requestRecordPermission { _ in continuation.resume() }
            }
            #endif
        })
    }

    init(probe: @escaping @MainActor (MorningVoiceCommandLanguage) -> MorningVoiceAccessSnapshot,
         speechRequest: @escaping @MainActor () async -> Void,
         microphoneRequest: @escaping @MainActor () async -> Void) {
        self.probe = probe; self.speechRequest = speechRequest; self.microphoneRequest = microphoneRequest
        snapshot = probe(.english)
    }

    @discardableResult public func refresh(language: MorningVoiceCommandLanguage) -> MorningVoiceAccessSnapshot {
        snapshot = probe(language)
        return snapshot
    }

    /// Called only by the permission button. Cancellation invalidates a late OS
    /// callback even though the system's permission dialog itself is not cancellable.
    @discardableResult public func requestAccess(language: MorningVoiceCommandLanguage) async throws -> MorningVoiceAccessSnapshot {
        guard !isRequesting else { throw CancellationError() }
        try Task.checkCancellation()
        let id = UUID(); revision = id; isRequesting = true
        defer { isRequesting = false }
        var current = refresh(language: language)
        guard current.canRequest else { return current }
        if current.speech == .notDetermined {
            await speechRequest()
            try check(id)
            current = refresh(language: language)
        }
        guard current.speech == .authorized else { return current }
        guard current.localRecognition != .unsupported else { return current }
        if current.microphone == .undetermined {
            await microphoneRequest()
            try check(id)
            current = refresh(language: language)
        }
        try check(id)
        return current
    }

    // Keep a system request owned until its actual callback arrives, so reopening
    // this screen cannot overlap a still-pending, noncancellable system dialog.
    public func cancel() { revision = UUID() }
    private func check(_ id: UUID) throws {
        try Task.checkCancellation()
        guard revision == id else { throw CancellationError() }
        #if os(iOS)
        guard UIApplication.shared.applicationState != .background else { throw CancellationError() }
        #endif
    }

    private static func systemSnapshot(_ language: MorningVoiceCommandLanguage) -> MorningVoiceAccessSnapshot {
        #if os(iOS)
        let speech: MorningVoiceAccessSnapshot.Speech = switch SFSpeechRecognizer.authorizationStatus() {
        case .notDetermined: .notDetermined
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .unavailable
        }
        let microphone: MorningVoiceAccessSnapshot.Microphone = switch AVAudioApplication.shared.recordPermission {
        case .undetermined: .undetermined
        case .granted: .granted
        case .denied: .denied
        @unknown default: .unavailable
        }
        let local: MorningVoiceAccessSnapshot.LocalRecognition
        if speech == .authorized {
            let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language.localeIdentifier))
            local = recognizer?.supportsOnDeviceRecognition != true
                ? .unsupported : (recognizer?.isAvailable == true ? .available : .temporarilyUnavailable)
        } else { local = .notChecked }
        return .init(speech: speech, microphone: microphone, localRecognition: local)
        #else
        return .init(speech: .unavailable, microphone: .unavailable, localRecognition: .unsupported)
        #endif
    }
}
