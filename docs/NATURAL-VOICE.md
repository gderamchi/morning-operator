# Natural conversation in MORE

16 October 2026 · [Voice #116](https://github.com/gibouu/morning-operator/issues/116), [voice choice #20](https://github.com/gibouu/morning-operator/issues/20).

## Choice and data flow

**Settings → Talk with MORE → Use ElevenLabs** starts one explicitly chosen online conversation. The screen explains that microphone audio and the text MORE reads from the selected routine go to ElevenLabs and its Google Gemini model. This can include selected Health, calendar and message content; Apple permissions alone do not enable that sharing. Raw recordings, complete Health history and unread account contents are not automatically submitted. The current routine's steps remain available in the disclosure.

Apple's on-device listener and system speech remain the default. Choosing online conversation releases both before ElevenLabs takes the microphone. There is no automatic provider fallback. The current agent uses Gemini 3.5 Flash with Eleven v4 Turbo; the authenticated agent configuration has Zero Retention Mode enabled, voice recording disabled and LLM cascading disabled. These are verified provider settings, not an independent forensic guarantee about every system log or subprocessor.

The long-lived provider key and private agent ID stay in the backend. The app authenticates with its existing installation token and receives only a temporary WebRTC conversation token. Starting this mode does not subscribe to a provider plan or purchase the MORE subscription. The private prototype restricts token issuance to explicitly activated installations; a new phone's first request can require administrative activation.

## Conversation and execution

The official Swift SDK 3.4.0 owns continuous audio, streamed responses and interruptions. One conversation retains context across turns. Routine metadata is updated when the current moment changes. Source text enters through an approved narration message, with a fresh narration ID; it is data, never an instruction to perform an action.

The model has three client tools, with no provider action tools:

- `more_control`: one bounded pause, resume, next, skip, stop or extension, bound to the current session and step and a real microphone event.
- `more_request`: the exact latest microphone transcript, passed to MORE's existing source-bound service dialogues. The app accepts or refuses it; an accepted/pending response does not confirm sending anything. Existing draft review, send instructions, account checks and uncertain-effect reconciliation remain authoritative.
- `more_narration_complete`: the current narration ID, requested after speech. The app also waits for the SDK's remote speaking state to end. Interruption, stop, replacement or a deadline throws instead of advancing a routine on incomplete speech.

Only one effect is accepted for a microphone event, even if the model emits multiple tool-call IDs. Service requests do not receive arbitrary backend tools or credentials. Pending requests suppress voice and captions until an app narration or a new actual microphone turn authorizes output again.

## Lifecycle

Consent is memory-only and bound to the current session and privacy generation. Leaving the foreground, ending the morning, changing language, withdrawing Health, losing subscription access or forgetting local data stops the online owner and invalidates pending work. Hooks remain closed during asynchronous SDK release, preventing an accidental return to Apple speech while the online microphone is still owned. A manual dictation turn waits for release before taking the microphone.

The SDK's interruption method has no public cancellation acknowledgement or rendered-audio drain signal. Its speaking state uses LiveKit audio activity. A narration marker plus that state is stronger than a model-text callback, but actual audio cutoff and completion still need iPhone acceptance. LiveKit logging is disabled; ElevenLabs uses error-only logging with debug mode off. Its SDK has no public logging-off option, so do not claim an absolute absence of sensitive OS logs.

## Evidence and remaining checks

- Shared lifecycle/output checks: 17 tests passed, including pending-output suppression, explicit reopening, duplicate-event protection and cancellation. Synthetic transports only; no microphone or provider call in those tests.
- Real provider French test: private connection and clean close; 37 PCM chunks, about 14.7 seconds of synthetic audio. First audio arrived in 1.10 seconds; an approved narration and all three client tools were observed with synthetic IDs and no app effects.
- Real provider English test: private connection and clean close; eight PCM chunks. First audio arrived in 0.96 seconds. No subscription change or blocking quota was encountered during these bounded checks.
- The provider test exposed an ambiguous spoken acknowledgement after an accepted/pending request. The client now closes audio and captions during that phase; this is a client regression check, separate from the supplier's model behavior.

These results establish real provider connectivity and generated audio, not microphone recognition, iOS LiveKit playback, route changes, audible interruption or real provider effects on a phone. Keep all tokens, session identifiers, audio evidence and raw logs private. Physical acceptance must exercise an ordinary signed build with harmless selected content before any real mail send is claimed.

Official references: [Swift SDK](https://elevenlabs.io/docs/eleven-agents/libraries/swift), [temporary WebRTC tokens](https://elevenlabs.io/docs/api-reference/conversations/get-webrtc-token), [agent privacy](https://elevenlabs.io/docs/eleven-agents/customization/privacy/zrm), [LLM retention restrictions](https://elevenlabs.io/docs/eleven-api/resources/zero-retention-mode).
