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

## Integration and delivery

The current main baseline is `92528f3`. The localization implementation is `6ded082` (Sources tree `1049dc012bbff6e5780348ad29469c6be7331bd2`). It retains the latest single-passage Home, directly shaped floating Glass controls, compact native Settings and solar access onboarding. The new access flow keeps its short benefits, optional details, learning handoff and Settings-only revisit. The language switch clears the displayed generated caption without rewriting the routine.

Work remains isolated in its dedicated worktree. This workstream never reset, stashed, modified or built the owner checkout, and did not control the physical phone, its routine, grants or authorized draft. Delivery uses [PR #193](https://github.com/gibouu/morning-operator/pull/193), followed by integration into `main` after the required checks. **Integration and verification of the delivered commit on remote `main`: pending.**

Provenance note: an earlier reviewed source-only snapshot preserved 21 Swift files from the unchanged owner checkout at 2026-10-16 00:08:26 UTC, base `753609c`, SHA-256 `80f4edd26df8f849251d7cb292113605779f53d372497e8f3f51361ee4c841e3`. It excluded private/config files, AGENTS and generated project files, and was subsequently reconciled with the actual parent commits. The final baseline above supersedes that temporary snapshot.

## Verification

Checks use `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Shared functional code, catalogs, package tests and script inputs are unchanged from the passing `519a230` package baseline through `6ded082`; Core's privacy manifest additionally declares the app-local defaults reason `CA92.1`. The compact access UI and its test harness require their own final validation.

| Local check | Observed result |
| --- | --- |
| Swift Testing via `./scripts/test.sh --jobs 4 -Xswiftc -j4 --no-parallel` | Passed: MorningHealth 4 tests/1 suite, MorningCore 692/80, MorningApple 937/103. Six optional Apple-model/video/replay tests explicitly skipped. Log: `/tmp/more-localization-post0cd-serial-package.log`. |
| `python3 -m unittest discover -s scripts/tests` | 34 tests passed on the final inputs. Log: `/tmp/more-localization-final925-python.log`. |
| Catalog audit | Zero missing French entries; all translatable entries have explicit French and English resources. Across six catalogs: 192 formatted keys, 2,135 paired variants, 52 named/plural substitutions and 11 shortcut phrase variants pass position/type/length and placeholder checks. |
| Final Xcode simulator `build-for-testing`, source `6ded082` | Passed. Log: `/tmp/more-localization-final925-simulator-build.log`. |
| Final generic iOS Debug build 1600, source `6ded082` | Passed. Log: `/tmp/more-localization-final925-signed-build.log`. No physical device is selected or controlled. |
| Final simulator journeys | **RUNNING — 21 selected journeys.** Result bundle: `work/localization-final925-journeys.xcresult`. |
| Final signed artifact, archive and manifest verification | Passed for `6ded082`: strict deep signature verification, both languages in app/shared/widget bundles, public configuration present, and all six privacy manifests including Core's `CA92.1`. |

A parallel package attempt during compilation exhausted a pre-existing CitySuggestion fixture startup wait and trapped while releasing its empty gate. The passing package command uses explicit `--no-parallel`; product deadlines are unchanged. The fixture follow-up remains [issue #190](https://github.com/gibouu/morning-operator/issues/190).

The running final synthetic journeys cover language persistence against a different system language, actual synthesizer speaking state in both languages, exact session/step identity and pause during switching, retained mixed-language routine text, learning/import and native empty states, browser controls, unsupported-language fallback, transient Home controls, native day/night Settings and compact access onboarding. The earlier four access tests on `519a230` do **not** establish acceptance of the final compact flow. The DEBUG-only playback identity is exposed only under `--ui-testing`.

The verified local artifact is `work/localization-1600-artifact/MorningOperator.app`, with `MorningOperator-1600.zip` and `verification.json` in the same directory. The metadata records `6ded082`, Sources tree `1049dc012bbff6e5780348ad29469c6be7331bd2`, the archive hash, verified signature and both languages in the app/shared/widget bundles. Public Google client/callback and API base are configured; this does not establish live authentication. All six privacy manifests are packaged, including Core's app-local language-defaults reason `CA92.1`. The personal profile expires on 2026-10-22 and the signed app lacks WeatherKit and Family Controls entitlements. Signing inputs and binary artifacts remain local.

CI results are separate from these local checks; skipped draft jobs are not reported as passes. Integration on remote `main` remains pending. The results above are local. Synthetic simulator fixtures do not prove physical speaker audibility, live speech recognition, Siri/widget behavior, provider authentication or external effects. These localization acceptance gaps remain in [issue #184](https://github.com/gibouu/morning-operator/issues/184). The reserved phone and its existing authorized Gmail draft were untouched. Raw screenshots, test workspaces, signing configuration and result bundles stay ignored and local.
