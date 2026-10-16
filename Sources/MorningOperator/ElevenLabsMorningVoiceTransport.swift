import Foundation
import Combine
import ElevenLabs
import LiveKit
import MorningApple

/// ElevenLabs owns microphone capture, streamed audio and interruption; Apple's listener stays stopped.
@MainActor
final class ElevenLabsMorningVoiceTransport: MorningCloudVoiceTransport {
    var onEvent: (@MainActor (MorningCloudVoiceEvent) -> Void)?
    private var conversation: Conversation?
    private var subscriptions = Set<AnyCancellable>()
    private var attempt = UUID()
    private var playbackMuted = false
    private var playbackRevision = UUID()
    private var interruptionTask: Task<Void, Never>?

    func connect(token: String, language: String, voiceGender: MorningVoiceGender) async throws {
        // Configure before either SDK initializes a conversation or its shared logger.
        LiveKitSDK.disableLogging()
        ElevenLabs.configure(.init(logLevel: .error, debugMode: false))
        let id = UUID(); attempt = id
        let config = ConversationConfig(
            agentOverrides: AgentOverrides(language: language.hasPrefix("fr") ? .french : .english),
            // Public premade voices, verified for French and English. Only this
            // TTS field and language are permitted by the private agent policy.
            ttsOverrides: TTSOverrides(voiceId: voiceGender == .male ? "CwhRBWXzGAHq8TQ4Fs17" : "EXAVITQu4vr4xnSDxMaL"),
            onError: { [weak self] _ in
                Task { @MainActor in if self?.attempt == id { self?.onEvent?(.failed) } }
            },
            onAgentResponse: { [weak self] text, eventID in
                Task { @MainActor in
                    guard let self, self.attempt == id else { return }
                    guard !self.playbackMuted else { return }
                    self.onEvent?(.agentText(text))
                }
            },
            onUserTranscript: { [weak self] text, eventID in
                Task { @MainActor in
                    guard let self, self.attempt == id else { return }
                    self.onEvent?(.userText(text, eventID: eventID))
                    await self.resumePlaybackForNewTurn()
                }
            },
            onInterruption: { [weak self] _ in
                Task { @MainActor in if self?.attempt == id { self?.onEvent?(.interruption) } }
            })
        let client = try await ElevenLabs.startConversation(conversationToken: token, config: config)
        guard attempt == id, !Task.isCancelled else {
            await client.endConversation()
            throw CancellationError()
        }
        conversation = client
        client.$agentState.sink { [weak self] state in
            guard self?.attempt == id else { return }
            switch state {
            case .speaking: self?.onEvent?(.speaking)
            case .listening: self?.onEvent?(.listening)
            case .thinking: break
            }
        }.store(in: &subscriptions)
        client.$state.sink { [weak self] state in
            guard self?.attempt == id else { return }
            switch state {
            case .ended: self?.onEvent?(.ended)
            case .error: self?.onEvent?(.failed)
            default: break
            }
        }.store(in: &subscriptions)
        client.$pendingToolCalls.sink { [weak self] calls in
            guard let self, attempt == id else { return }
            for call in calls {
                guard call.expectsResponse else { client.markToolCallCompleted(call.toolCallId); continue }
                let parameters = (try? call.getParameters()) ?? [:]
                let data = (try? JSONSerialization.data(withJSONObject: parameters)) ?? Data("{}".utf8)
                onEvent?(.tool(.init(id: call.toolCallId, name: call.toolName,
                                    parametersJSON: String(decoding: data, as: UTF8.self), eventID: call.eventId)))
            }
        }.store(in: &subscriptions)
    }

    func updateContext(_ context: String) async throws {
        guard let conversation else { throw MorningCloudVoiceError.unavailable }
        try await conversation.updateContext(context)
    }

    func reply(to callID: String, result: String, isError: Bool) async throws {
        guard let conversation else { throw MorningCloudVoiceError.unavailable }
        try await conversation.sendToolResult(for: callID, result: result, isError: isError)
    }

    func sendUserMessage(_ text: String) async throws {
        try Task.checkCancellation()
        await resumePlaybackForNewTurn()
        try Task.checkCancellation()
        guard let conversation else { throw MorningCloudVoiceError.unavailable }
        try await conversation.sendMessage(text)
    }

    func cancelPlayback() {
        guard let conversation else { return }
        let needsInterruption = !playbackMuted
        playbackMuted = true; playbackRevision = UUID()
        conversation.agentAudioTrack?.volume = 0
        guard needsInterruption else { return }
        interruptionTask = Task { _ = try? await conversation.interruptAgent() }
    }

    func suspendReply() {
        playbackMuted = true; playbackRevision = UUID()
        conversation?.agentAudioTrack?.volume = 0
    }

    /// A delayed response never resumes canceled audio by itself. Only a new
    /// live transcript or an explicitly approved app narration reopens output.
    private func resumePlaybackForNewTurn() async {
        guard playbackMuted else { return }
        let revision = playbackRevision, id = attempt
        await interruptionTask?.value
        guard attempt == id, playbackRevision == revision, !Task.isCancelled else { return }
        playbackMuted = false; interruptionTask = nil
        conversation?.agentAudioTrack?.volume = 1
    }

    func stop() async {
        attempt = UUID(); playbackRevision = UUID()
        interruptionTask?.cancel(); interruptionTask = nil
        subscriptions.removeAll(); conversation?.agentAudioTrack?.volume = 0
        let previous = conversation; conversation = nil
        await previous?.endConversation()
    }
}
