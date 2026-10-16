# French and English in MORE

MORE has exactly two app languages: **Français** and **English**, selected in Settings → Language. The selection is persisted independently of routine/workspace data. The first system language determines the initial choice when it is French or English; any other language starts in French. There is no third “automatic” option.

`MorningCore.AppLanguage` is the common source for SwiftUI, Foundation string catalogs, date/number formatting, local model instructions, speech recognition, command interpretation and speech synthesis. SwiftUI receives its locale and observes the shared choice. Foundation strings select the matching catalog bundle explicitly so existing process bundle preferences cannot keep them in the previous language.

## Data and external boundaries

Changing the language never rewrites saved routine titles/details, personal notes, original recordings/OCR, mail or message contents, account/calendar names, provider names, website content, protocol identifiers, API argument values or provider documentation. New built-in examples use the selected language. Historical source labels and the structural serialization markers inside original learning evidence remain part of that evidence; they are not reinterpreted or migrated.

Provider pages and Apple-owned interface text follow their own language rules. MORE's permission descriptions live in `InfoPlist.xcstrings`; shortcut metadata and phrases live in `Localizable.xcstrings` and `AppShortcuts.xcstrings`. MORE saves its language as the app's bundle language for the next process launch, but cannot force another app, Siri's configured language or an external OAuth page. Runtime intent results and app-owned alarm labels use the selected language explicitly. Live Activity payloads carry a backwards-compatible language field so the widget does not infer the app preference from the extension's separate defaults.

Known connection-service error codes are mapped to app-controlled explanations. Raw provider diagnostic text is not displayed as interface copy. Framework errors without a typed app explanation use a localized fallback that does not expose private paths or request diagnostics.

## Speech and changing language

Installed voice choices are filtered by the app language, including search results. A saved unavailable or incompatible voice identifier is repaired to the automatic compatible choice. Speech never falls back to a voice in the other language. Recognition remains local and uses the same choice; command grammar and local model response instructions follow it too.

Changing language pauses an active morning, stops speech/listening, invalidates cached generated prose, refreshes local presentation and leaves source data, pending drafts, recipients, action receipts and uncertain-operation journals intact. It does not restart the routine, authorize an action, repeat a provider effect or request permission automatically. A partial dictation is retained for editable local review. Resuming remains an explicit user action. Invitation, recording, native-connection and privacy notices refresh from retained semantic state; this presentation refresh does not schedule, record, repeat a native action or write privacy controls.

## Integration baseline

The localization branch was created in a separate managed worktree from `2a6e3c1` on `guillaume/routine-automation`. This includes the current Home redesign, Google Calendar/Calendly/Outlook integration and learning work committed at creation. This workstream never reset, stashed, modified or built the owner checkout. Committed integration updates through `753609c` were merged. To preserve the newer Home playback/caption layout and Screen Time selection work, a reviewed source-only snapshot of 21 Swift files was integrated from the unchanged owner checkout (2026-10-16 00:08:26 UTC, base `753609c`, SHA-256 `80f4edd26df8f849251d7cb292113605779f53d372497e8f3f51361ee4c841e3`). Private/config files, AGENTS and generated project files were excluded; the project was regenerated here. The snapshot was subsequently reconciled with the actual parent commits `9089ff0` (Screen Time) and `0334b89` (Home), including the latest caption anchors and exact-identity retention fix. Those commits are now ancestors of this branch. The final integration also includes `3dfed93`: Home keeps a single current passage, reveals its controls on a tap and hides them after inactivity, with the latest sky colors and speech chunking. The language switch clears only its displayed generated caption; settings remain reachable from the transient menu. The physical phone, its existing routine, grants and authorized test draft were not controlled by this workstream.

The PR targets the routine integration branch to keep the localization change reviewable without replacing the recent connector work with an older main-branch UI.

## Verification

The final implementation source is `a4b061f` (Sources tree `bdee92f9ad878fa31af11b9ecef8a21f9834a1a1`). All commands used the full Xcode toolchain with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; the default Command Line Tools selection is not the verified toolchain.

| Local check | Observed result |
| --- | --- |
| Swift Testing via `./scripts/test.sh --jobs 4 -Xswiftc -j4` | All three runners pass: MorningHealth 4 tests/1 suite, MorningCore 684/79, MorningApple 926/102. Six optional Apple-model/video/replay tests were explicitly skipped. |
| `python3 -m unittest discover -s scripts/tests` | 34 tests pass. |
| Catalog audit | Zero missing French entries; all translatable entries have explicit French and English resources. Recursive format/substitution checks pass. |
| Xcode simulator `build-for-testing` | Succeeded for the isolated MORE Localization QA simulator, iOS 26.5. |
| Simulator journeys | 8 tests pass with zero failures. The final result is stored locally in `work/localization-final-journeys.xcresult`; screenshots are exported under `work/localization-final-screenshots`. |
| Generic iOS Debug build 1600 | Succeeded with the existing private personal signing configuration, without selecting or controlling a physical device. |

The simulator journeys use unique synthetic workspaces. They cover immediate switching and a relaunch against a different system language, compatible installed voices and actual synthesizer speaking state in both languages, exact session/step identity and pause during a switch, retained mixed-language routine text, paired learning/import and native empty states, browser controls, unsupported-language fallback, largest text with reduced motion, and transient Home controls. The DEBUG-only playback identity is exposed only under `--ui-testing`; ordinary app UI does not expose it.

The local signed candidate is `work/localization-1600-artifact/MorningOperator.app` and its archive is `MorningOperator-1600.zip` in the same directory. `verification.json` records its source revision/tree, archive hash and observed configuration booleans. `codesign --verify --deep --strict` passes. Main/shared/Live Activity resources contain both languages, and the existing public Google client/callback and API base are configured. The embedded personal profile expires on 2026-10-22. The signed app contains only application/team identifiers and development debugging; it has no WeatherKit or Family Controls entitlement. No signing inputs or binary artifacts are uploaded to Git.

GitHub reports no CI checks on this fork PR; these are local results. Simulator synthetic fixtures do not prove physical speaker audibility, live speech recognition, Siri invocation, provider login, or external effects. The reserved phone and its existing authorized Gmail draft were untouched. Physical acceptance is tracked in [issue #184](https://github.com/gibouu/morning-operator/issues/184). Raw screenshots, test workspaces, signing configuration and result bundles stay ignored and local.
