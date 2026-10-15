# MORE §10 — normal iPhone voice acceptance

Status: planned physical tests; no microphone, audibility, model-quality or real-send result is claimed by this script. Do not run an external send until the owner has authorized the exact self-recipient and the reviewed body. A single authorization permits one effect, including reconciliation of that same effect; it never permits a resend after uncertainty.

## Record once

Installed commit/build; iPhone and iOS; interface/recognizer language; selected speech voice; actual microphone/output route; local model availability; whether Speech/microphone permissions are granted. Use the normal app, with no `--ui-testing` or fixture flags. Keep any recording and account details private and out of Git. Record actual outcomes and latency, never credentials or personal inbox text.

Prepare and explicitly approve a short routine with current Calendar/Weather or a harmless sourced note, a connected Gmail moment, a supported browser behavior with likes disabled, and a timed moment. Review account/destination/behavior/budget before approval. The Gmail account and any self-address must belong to the owner. Prefer a synthetic self-thread that the owner has already supplied; do not message a third party to create a fixture. Read real service content only within the owner's existing authorization.

## Trial A — commands and duplex acoustic output, no sends

1. Start once with hands-free execution and speech enabled, then put the phone down. Count all subsequent touches. During an audible sentence, say « pause ». The voice must stop, the same moment must pause, and no next step may run. Say « reprends » without touching; that same moment resumes. Repeat this three times, including one interruption at the beginning of a sentence and one near its end. Record speech-onset-to-audio-stop and utterance-end-to-result latency.
2. During current sourced speech, ask a checkable question, e.g. « Quelle est l’heure du premier rendez-vous ? ». The answer must use the currently available source, or clearly admit missing information. Ask « répète » during the answer, then « suivant ». Exactly one step advances. A late answer from the previous moment must never be spoken over the new one.
3. In the browser or timed moment, say « encore deux minutes ». The same timer gains exactly two minutes and no effect repeats. Say « pause », wait at least 130 seconds without touching the iPhone, then « reprends »: the foreground display must have stayed awake and recognition must still be available without opening a voice sheet. With a short system Auto-Lock setting, also verify the display returns to its ordinary idle behavior after Stop, leaving MORE, switching hands-free off or entering privacy cleanup. This is foreground screen-awake behavior, not background listening or a wake word. Also test « arrête » during output: the session ends and listening stops.
4. Repeat command checks in English in a separate approved run: “pause”, “resume”, “next”, “repeat”, “two more minutes”, “stop”. Record unavailable language/model cases as unavailable, not passing. Repeat the speaker test on the normal phone speaker, then an actually connected headset if available; simulated route labels do not count.

## Trial B — source-bound mail dialogue, no sends

5. Let MORE read the allowed current Inbox selection. Ask « pourquoi ces messages ? » and a factual question about the selected synthetic self-thread. Answers must stay grounded and must not change recipient, selected message or draft. Say « réponds-lui », dictate an intention, listen to the whole draft, and say « change la dernière phrase … ». Read back the revised draft; the same self-recipient and thread remain selected. Say « non » and verify no message was sent.
6. Acoustic echo challenge: prepare a second harmless draft whose quoted text includes the literal words « oui », « suivant » and « envoie » as content. Stay silent while MORE reads that content and its prompt. It must neither advance, approve nor send itself. Then genuinely interrupt with a short « oui »/« non »/« répète » as appropriate to the current dialogue. Those real short replies must remain usable. Any self-trigger or inability to interrupt is a failed acoustic test, even if unit tests pass.

## Trial C — exactly one self-mail, only after the owner's explicit authorization

7. Show or read the exact current account, self-recipient, thread and final synthetic body to the owner. After explicit authorization of that one effect, the owner says « envoie » once while the reviewed draft is active. Verify one matching provider Sent item and its Message-ID/thread, and verify the self-delivery if the provider exposes it. Success narration alone is insufficient. If connectivity is interrupted or confirmation is uncertain, say « vérifier »; reconcile the same journal operation. Never repeat « envoie » or create a new operation to resolve uncertainty. If the exact draft/account/thread changes, obtain a new exact authorization before any further effect.

## Trial D — interruption, cleanup and truthful ending

8. In separate no-send runs, background the app during speaking and during a pending local answer; change the real audio route; cause an actual system audio interruption if practical. Input and obsolete content must stop. Return and resume once: no stale answer, old command, duplicate provider effect or duplicate step completion may occur. Include a rapid background/foreground cycle to catch asynchronous release/restart races. If voice is unavailable, the reason and touch fallback must be understandable.
9. Finish a short approved run automatically without pressing Next for every step. A human must hear the final invitation once. The continuous microphone must be off after completion, including while the invitation speaks; it may reopen only after the owner chooses the separate capture action. Stop/new-start/background during invitation release must not cause late speech in a replacement session. Relaunch: the recap must distinguish completed, skipped, unavailable and uncertain work faithfully, and the approved routine must remain available.

## Evidence and remaining acceptance

For each trial record pass/fail/unavailable, touches after Start, real completed steps, actual external receipts, recognition/control latency, mistaken words, spontaneous triggers, recovery steps and human-confirmed audibility. Repeat the complete normal-app morning at least twice. MORE §10 supplies no numeric latency threshold; report measured latency rather than inventing a passing target.

Package tests establish deterministic command/context/cancellation/receipt behavior with synthetic inputs. They do not establish acoustic echo cancellation, speaker identity, recognition while moving around, local-model conversational accuracy, provider delivery or physical microphone release. Current runtime is foreground-only; leaving MORE releases listening. HomePod/background wake-word support is not implemented.
