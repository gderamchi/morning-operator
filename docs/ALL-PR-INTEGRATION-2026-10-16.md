# Combined development delivery · 16 October 2026

The owner requested one development version containing every open pull request, the expanded Apple Health connection, natural online conversation and a persistent development paywall close button. A task branch alone is not delivery; the final source must reach `origin/main` and the ordinary signed app must be installed in place.

## Preserved changes

| Pull request | Combined behavior |
| --- | --- |
| #193 | French/English interface, language choice and speech. |
| #174 | Native connection callback isolation and separate physical acceptance checks. |
| #113 | Design exploration assets and Debug previews alongside the current ordinary app. |
| #106 | Recover readable workspace fields without discarding the whole snapshot; preserve newer saved fields. |
| #114 | Opt-in live demo with phone control restricted to the UI-test target and a guarded Debug voice host. |
| #102 | Current accessibility layout and saved-action haptics. |
| #100 | Explicit retention review and durable local deletion. |
| #108 | Recognition from sampled recording frames while retaining browser and Screen Time provenance. |
| #122 | Screen Time learning and proposal review, retaining the newer permission, privacy and approval guards. |
| #123 | Optional morning extras and closing questions; extras start off and each Health function needs its own explicit choice. |
| #203 | Separate jury app/backend, bounded real-action flow, audio recovery and explicit physical/acoustic acceptance gates. The ordinary app and existing demo variant coexist. |
| #207 | Each connection opens its own provider; independent rows, readable professional-account labels and complete English catalog coverage. |
| #209 | Fixed-format Demo audio graph, bounded PCM conversion, identifiable Island controls and explicitly opt-in numeric microphone diagnostics. |

The prior subscription, permission onboarding, quiet solar Home, weather, native connections, routine execution and Health changes remain present. Current main also contributes explicit Apple/OpenAI model selection and bounded personal memory; the ElevenLabs microphone transcript feeds that selected route without uploading the raw memory to Gemini. Sleep and recovery readings are excluded from the general OpenAI context. Historical branches do not replace newer implementations wholesale. The ancestry evidence records all thirteen listed PR histories, including the latest #193, #203, #207 and #209 heads; semantic conflict resolutions and combined checks are separate evidence.

## Owner-requested additions

- Direct **Settings → Health** with compact sleep, SDNN, resting heart rate and respiratory rate, observed source and time. Old sleep-only access requires an explicit upgrade. Proprietary recovery scores are not invented.
- **Settings → Talk with MORE**, with explicit consent before sending microphone audio or chosen readings to ElevenLabs and Gemini. Local voice remains available; provider configuration and temporary token delivery are separate from phone audio acceptance. See [natural voice](NATURAL-VOICE.md).
- A visible cross on development onboarding and paywall screens. One press persists developer access across launches. Release builds neither display the cross nor honor the flag; no StoreKit transaction is fabricated. The real App Store offer remains [#191](https://github.com/gibouu/morning-operator/issues/191).

## Evidence boundaries

Package tests, native compilation, synthetic UI checks, real backend/provider calls, signature checks and ordinary phone installation are distinct results. A passing compile does not prove a completed morning or audible interruption. Owner feedback confirms weather and Screen Time on the prior installed build, while rejecting the old sleep-only presentation and system voice. No Health values, owner screenshots, device identifiers or credentials belong in this record.

The voice backend passed 44 Node and Workerd/D1 tests. The deployed Worker returned a real temporary WebRTC token for the explicitly activated QA installation, while rejecting missing authentication, invalid bodies and inactive installations. The existing 16 catalogs, journal, database and connection configuration were preserved. No actual phone installation is activated by those QA results. See the [deployment record](../Services/Composio/CLOUDFLARE.md).

At combined source `4577ff4`, Swift Testing reports **1,961 tests with no failures** (MorningLiveDemo 51, MorningHealth 8, MorningCore 735, MorningApple 1,167). Seven optional replay/live-model declarations are skipped; they are not provider or physical evidence. Ordinary app/widget/UI-test compilation and the separate Demo build both pass; the Demo build leaves all 78 ordinary test-product files unchanged. The added microphone-memory and stale-response checks pass within 65 focused tests. No new physical microphone or Health result is inferred from those checks.

All **ten distinct simulator UI checks are validated** at `4577ff4`: eight pass in the combined selection (persistent cross, direct compact Health, sharing disclosure and language changes), and the two Intelligence checks pass in a separate correctly signed simulator run. EN takes 18.094 seconds and FR at largest accessibility text 95.643 seconds. Synthetic credentials exercise actual simulator Keychain activation, return to Apple and deletion; no provider call occurs. Initial unsigned/first-launch failures are retained as environment evidence, not hidden or counted as passes; no app or helper source changed to obtain the final result. The last incoming #203 delta (`76fef1d`) rebuilds only its duplex engine on resume and extends its gated tests; it is preserved after the full package result above.

## Final combined checks

PR #207 adds three distinct passing simulator checks: English provider destinations/return and French largest-text retry at `28ffc6d`, then French largest-text night professional titles at `e80ef70`. The initial title failures exposed full-screen test swipes oscillating past the visible viewport; only the scrolling helper changed, retaining all four strict frame assertions. These are separate from the ten checks above, for thirteen distinct validated checks across the recorded runs. The voice Worker again passes 44 Node/Workerd/D1 tests; its deployed runtime is unchanged by the test-only timeout adjustment.

Both catalogs pass independent strict JSON, locale and printf checks. All 133 restored English units (104 app, 29 MorningApple) match the compiled resources; no existing French unit or key was removed. All 34 Python script tests pass at final source `43d1d04`; [#208](https://github.com/gibouu/morning-operator/issues/208) is resolved.

At `43d1d04`, ordinary app/widget/UI-test compilation and the separate Demo build pass with valid ad hoc simulator signatures. All 112 snapshotted ordinary test-product files are unchanged after the Demo build. Nine numeric cases execute the exact extracted conversion body (unchanged in the final source): identity, mono/stereo and interleaved conversion, duration/tail retention, and invalid/oversized input rejection. This harness does not run an iPhone audio engine. The new iOS-conditional audio code is compiled natively; the unchanged macOS runtime remains covered by the earlier package result, without another full SwiftPM build.

## Signed ordinary candidate

Remote main contains source `43d1d04` and all thirteen listed PR histories, including final #207 `a94cdf3` and #209 `9483c8f`. GitHub reports both merged and no open PR at this integration checkpoint.

**MORE 0.1.0 (2026101610)** from clean `43d1d04` is compiled, signed, strictly verified and frozen. Installation is waiting for other active physical test hosts to finish. The guard stopped before backup, installation or launch; those steps have not yet been performed for this candidate. Earlier builds 1608 and 1609 frozen by this task are not installed by it.

Strict app/widget signatures and embedded profiles match the local development kit: exactly the four expected app capabilities, none in the widget, no forbidden Health extras/PCC, pinned ElevenLabs SDK 3.4, real app-only Worker URL and public Google configuration. The frozen 76-file artifact has no configured Demo endpoint, StoreKit test configuration, enabled fixture arguments or provider credential. Signing files, raw logs, screenshots and backups stay outside Git.

GitHub CI is queued for source `43d1d04`; the local checks above are separate results. Documentation-only follow-ups do not change the signed app source.

Real App Store configuration (#191), actual expanded Health access and audible/interruption acceptance remain separate owner/provider gates. The actual voice installation has not been activated by the QA allowlist: its first explicit **Use ElevenLabs** request is needed for an individually correlated activation. No installation is activated from timing alone or by activating every pending request. The jury-specific acoustic, reminder and Island interaction gates remain tracked in [#205](https://github.com/gibouu/morning-operator/issues/205).
