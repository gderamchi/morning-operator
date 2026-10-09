# Phase one: working Mac app and remaining device proof

Updated 9 October 2026. The native Mac application has been built, launched and exercised through its real interface. The iPhone application shares its SwiftUI source and libraries, but has not been compiled or run against the iOS SDK. The separate phone test harness is prepared; full Xcode is unavailable on this Mac.

## Current implementation

- **Today, Learn and Setup:** native SwiftUI screens for a clearly labeled sample or manually created routine, step editing, explicit approval, start/next/skip/pause/resume/stop, and JSON export.
- **Versions and draft recovery:** editing an approved routine creates an unapproved next version. One previous approved routine is retained so the user can restore it while reviewing the replacement. The routine, current session and previous approved routine are saved in the local workspace snapshot. This is not a full version-history browser. Imported observation notes are temporary UI content, not a saved draft document.
- **Session recovery:** a run pins its approved routine version. Local atomic JSON persistence preserves progress. A session saved while running reopens paused at its current step, requiring an explicit resume.
- **Observation import:** the native file picker reads a selected local UTF-8 note, screenshot or video. Image/video paths use Apple Vision OCR and bounded AVFoundation frame sampling. Extracted text is available for review before requesting semantic analysis; imports do not silently invoke the model or send data remotely.
- **Apple semantic adapter:** Foundation Models receives reviewed observation text, produces a constrained proposal and validates source quotations. Actual generation requires an available local Apple model. Unavailable-model status is visible, analysis is disabled, and sample/manual routines remain usable without a cloud fallback.
- **Speech and Calendar adapters:** AVSpeechSynthesizer output is wired to run controls. Calendar is connected only after the user's action, uses EventKit to read a timestamped local schedule, and does not modify events. Live permissions, audible speech and hardware routing remain unverified.
- **Shared control logic:** portable Codable models, session transitions, version pinning and command deduplication; an action journal supports scoped approval checks and conservative recovery after interrupted dispatch. No live message-send adapter is connected.
- **Separate iPhone development harness:** XcodeGen defines the iOS app and an independent UI Testing Bundle. Fixture tests cover the app journey. Installed-Settings tests cover bounded capture/navigation and missing-target refusal. An explicitly configured external-app test defaults to capture-only; a single optional read-only navigation step requires a fresh semantic target and a new-screen postcondition. These static tests are not a persistent model-driven controller.

The configuration contains microphone/speech/Calendar purpose strings, without a hardcoded team, account or credentials. Scripts build the Mac bundle, run local Swift Testing, inspect the environment, generate the iOS project and run an explicitly selected physical-device suite. Device evidence stays under ignored local work/device-runs.

## Actual verification

The counts below are results reported by the checks that ran. Skipped model work and unrun hardware checks are separate from passed tests.

| Check | Observed result |
|---|---|
| Environment | macOS 27.0.1; Apple Swift 6.4; XcodeGen 2.45.3; Command Line Tools selected |
| Mac application | Native app bundle built and launched successfully |
| Real Mac UI walkthrough | Sample review/approval, start, next, pause, resume, stop, edit into V2, and restore approved V1 worked through the application interface |
| Relaunch recovery | Quitting during a running session and reopening restored that session paused at the same step |
| Native JSON export | Exported the sample through the native save panel; parsed the result and verified approved V1 with four steps |
| Native import workflow | Selected a local synthetic UTF-8 observation through the native file picker; its content appeared in the reviewable notes field |
| Model availability in UI | Reported **modelNotReady**; analysis was appropriately disabled |
| Core Swift Testing suite | **8 passed** |
| Apple Swift Testing suite | **9 passed**, including actual Vision OCR of a synthetic screenshot and selected UTF-8 file reading |
| Optional real Foundation Models test | Explicitly enabled but **skipped** because the local model reported **modelNotReady**; no successful model generation is claimed |
| Combined scripts/test.sh --with-model run | **Completed successfully: 17 passed, 1 skipped, 0 failures**. The skipped test is real model inference; the full package, including the app, built successfully |
| Script/configuration checks | Shell syntax and iOS/macOS plist lint passed; scripts/test.sh --help worked |
| UI-test source | Swift parse-only check passed; this does not type-check XCUI code against an iOS SDK |
| XcodeGen project | Generated successfully; local package reference and product dependencies inspected |
| Device-run refusal/configuration | A Send target was rejected before device access; synthetic modern/legacy .xctestrun environment-injection checks passed |
| Calendar permission and real events | **Not exercised** |
| Audible speech and selected audio device | **Not verified**; exposed buttons/code do not prove audible output |
| Full Xcode / iOS compilation | **Not run**; full Xcode is absent |
| Physical iPhone fixture, Settings and external-app tests | **Not run** |
| HomePod audio/input/transfer | **Not run** |

The Mac UI walkthrough used the actual app; it was not an iPhone XCTest run. Synthetic test content proves the import/OCR path without establishing access to a personal inbox or learning from a real week of activity. The local-model readiness failure is a concrete remaining dependency, not an inference-quality result.

Regenerate MorningOperator.xcodeproj after source additions using scripts/generate-project.sh. Generation does not compile, sign or install the app.

## Next concrete checks

1. Resolve local Apple model readiness in system settings/downloads and refresh the app's capability status. When ready, run scripts/test.sh --with-model and then analyze a deliberately chosen observation in the app. Check that the generated routine is unapproved and grounded in the reviewed source.
2. Exercise the optional Calendar consent and real local-event query; verify the selected day, timezone, all-day events and empty/denied states. Test speech audibly on the actual selected Mac/phone output, including pause/stop and interruption behavior.
3. Install/select full Xcode, pair and unlock the owner's phone, verify Developer Mode and development signing, and record exact Xcode/iOS versions. Build/run the iPhone app, then run the fixture journey and inspect pass/fail/skip status in its .xcresult.
4. Run the Settings suite from its main page. Collect evidence for benign navigation and the missing-target stop. Select one real external app/account next, first capture-only and then one reviewed navigation step if its actual accessibility interface supports it.
5. Prove real phone-or-Mac → HomePod output with the available single HomePod mini. Investigate the saved routing Shortcut, callback handling and actual route verification; preserve the current routine item. Live spoken commands require an input implementation and hardware proof. See [DEVICE-SETUP.md](DEVICE-SETUP.md).

## Remaining boundaries

- No successful Foundation Models inference has been demonstrated on this machine while the model is unavailable. Schema/evidence-validation tests are not substitutes for that integration result.
- Live microphone command recognition, a persistent bidirectional Mac/phone transport and a long-lived autonomous phone controller are not implemented or proved. USB pairing alone does not create an application data channel.
- No external message has been composed, sent or deleted by the prepared device tests. A real messaging channel/account/conversation must be selected before a later messaging integration.
- No ongoing automatic recording, multi-day habit aggregation, first-pickup detection, historical cross-app touch log or always-running background agent is claimed.
- No raw HomePod microphone access, proactive person/room detection, automatic output transfer or two-speaker continuation is established.
- HealthKit, Screen Time shields, Live Activities, billing and public distribution remain separate work. They do not gate the current personal Mac prototype.

For each next hardware milestone, record the device/software, deliberate source/account scope, check performed, observed outcome, evidence location and remaining failure. Keep screenshots and logs local; share only intentionally reviewed evidence.
