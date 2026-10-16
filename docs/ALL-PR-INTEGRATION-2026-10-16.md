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

The prior subscription, permission onboarding, quiet solar Home, weather, native connections, routine execution and Health changes remain present. Current main also contributes explicit Apple/OpenAI model selection and bounded personal memory; the ElevenLabs microphone transcript feeds that selected route without uploading the raw memory to Gemini. Sleep and recovery readings are excluded from the general OpenAI context. Historical branches do not replace newer implementations wholesale. The ancestry evidence records all eleven PR histories, including the latest #193 and #203 heads; semantic conflict resolutions and combined checks are separate evidence.

## Owner-requested additions

- Direct **Settings → Health** with compact sleep, SDNN, resting heart rate and respiratory rate, observed source and time. Old sleep-only access requires an explicit upgrade. Proprietary recovery scores are not invented.
- **Settings → Talk with MORE**, with explicit consent before sending microphone audio or chosen readings to ElevenLabs and Gemini. Local voice remains available; provider configuration and temporary token delivery are separate from phone audio acceptance. See [natural voice](NATURAL-VOICE.md).
- A visible cross on development onboarding and paywall screens. One press persists developer access across launches. Release builds neither display the cross nor honor the flag; no StoreKit transaction is fabricated. The real App Store offer remains [#191](https://github.com/gibouu/morning-operator/issues/191).

## Evidence boundaries

Package tests, native compilation, synthetic UI checks, real backend/provider calls, signature checks and ordinary phone installation are distinct results. A passing compile does not prove a completed morning or audible interruption. Owner feedback confirms weather and Screen Time on the prior installed build, while rejecting the old sleep-only presentation and system voice. No Health values, owner screenshots, device identifiers or credentials belong in this record.

The voice backend passed 44 Node and Workerd/D1 tests. The deployed Worker returned a real temporary WebRTC token for the explicitly activated QA installation, while rejecting missing authentication, invalid bodies and inactive installations. The existing 16 catalogs, journal, database and connection configuration were preserved. No actual phone installation is activated by those QA results. See the [deployment record](../Services/Composio/CLOUDFLARE.md).

Combined source `4577ff4` passes **1,961 package tests** (MorningLiveDemo 51, MorningHealth 8, MorningCore 735, MorningApple 1,167), with optional live model calls disabled. Ordinary app/widget/UI-test compilation and the separate Demo build both pass; the Demo build leaves all 78 ordinary test-product files unchanged. The added microphone-memory and stale-response checks pass within 65 focused tests. No new physical microphone or Health result is inferred from those checks.

Eight earlier simulator UI checks pass, including the persistent cross at largest text, direct compact Health, pre-microphone sharing disclosure and language changes. A final ten-test selection adds explicit model configuration in English and French at largest text. The last incoming #203 delta (`76fef1d`) rebuilds only its duplex engine on resume and extends its gated tests; it is preserved after the full package result above.

Final UI completion, remote-main containment, strict signature verification and ordinary in-place phone installation remain delivery gates at this checkpoint. Real App Store configuration (#191), actual Health access and audible/interruption acceptance remain separate owner/provider gates. The jury-specific physical gates are tracked in [#205](https://github.com/gibouu/morning-operator/issues/205).
