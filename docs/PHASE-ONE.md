# Phase one: native app and device proof

Updated 9 October 2026. The Mac application has been built, launched and exercised through its interface. Full Xcode 27 is now installed, and the signed iPhone application has built, installed and launched on a physical iPhone running iOS 27.0.1. Three synthetic device checks, one bounded Clock navigation and real on-phone model generation passed. Expanded recovery checks and newer integrations still need their own evidence.

## Current implementation

- **Native interface:** Morning, Review and Notes tabs, a routine timeline, day navigation, and Learn/Settings sheets. The sample is labeled synthetic; manual and learned routines must be reviewed and approved before starting.
- **Versions and recovery:** edits produce an unapproved next version and retain the previous approved routine for restoration. Atomic workspace saves preserve the draft, current session, history and notes. A run pins its approved version; reopening a running session restores it paused at the same step. This is not a full version-history browser.
- **App-owned execution:** hands-free mode can read a step or query/read today's authorized calendar and advance only after its speech completion callback. Interactive or unsupported steps wait for the user. Cancellation and stable identities reject stale/duplicate callbacks. Synthesis completion does not prove the user heard the chosen speaker.
- **Observation import:** the native file picker reads a selected UTF-8 note, image or video. AVFoundation samples a bounded number of frames and Vision extracts visible text. The user reviews this text before requesting semantic analysis.
- **Explicit recording:** iOS 27 ScreenCaptureKit code presents Apple's picker, records screen content without microphone/camera audio, and offers use/discard. A used temporary recording passes to OCR and is removed afterward; user-selected files are preserved. The native recorder compiles, but actual capture, system-stop behavior and OCR handoff still require a hardware run.
- **Local semantic learning:** Foundation Models produces a constrained, unapproved proposal and validates source quotations. Model availability is visible. Manual/sample routines work without the model; there is no cloud fallback. Imported observation text remains temporary UI content rather than a saved observation library.
- **Capture and Apple apps:** thoughts/dreams save locally. Reviewed reminder/calendar requests can optionally be written through EventKit. Permission is requested only for the chosen integration; pending writes are persisted before dispatch, and known receipts prevent retrying a successful write. An uncertain outcome asks the user to check the Apple app before trying again. Live system writes remain unverified.
- **Voice and shortcuts:** foreground App Intents request an approved morning start or open capture text for review. They do not approve a changed routine or silently save an event. Installed built-in voice selection, search, preview and persisted preference are implemented. Personal Voice authorization is not requested. The iPhone exposes Apple's audio-route picker; Mac uses system sound controls.
- **History:** stopped/completed local sessions feed day and seven-day review. Synthetic runs are excluded from ordinary summaries. The evidence model records provenance, coverage and optional counts/durations; no live producer yet establishes exact external-app usage or read/reply metrics.
- **Separate development controller:** XCTest fixture, Settings and opt-in external-app tests are outside the normal application. The external-app test defaults to capture-only and can attempt bounded, read-only navigation with a fresh target and postcondition. A persistent model-driven phone controller is not implemented.

## Actual verification

These are recorded observations, not claims that every current feature passed. The expanded test run is pending and should replace this snapshot when its result is reviewed.

| Check | Observed result |
|---|---|
| Toolchain/device setup | Xcode 27 (27A266a); physical iPhone 15 Pro Max on iOS 27.0.1 paired, Developer Mode enabled, signed build/install/launch succeeded |
| Mac application | Native bundle built and launched |
| Earlier real Mac walkthrough | Sample approval/start/next/pause/resume/stop, edited draft and restoration, and paused recovery after relaunch worked |
| Earlier native file panels | Synthetic UTF-8 observation imported into reviewable notes; sample JSON exported and parsed |
| Latest completed package run | **53 passed, 1 skipped**. The skipped integration test was real Foundation Models inference because the Mac reported **modelNotReady** |
| Physical iPhone fixture journey | **Passed:** approve/start/next/pause/resume/stop |
| Physical iPhone local dream | **Passed:** local save, kind filtering and persistence across tab navigation |
| Physical iPhone empty history day | **Passed:** day swipe shows an empty state without inventing history |
| Physical iPhone external Clock navigation | **Passed:** World Clock → Alarms, one read-only scroll, return to World Clock; no writes |
| Physical iPhone Foundation Models generation | **Passed on 9 October 2026:** synthetic calendar/chess observation → a two-step unapproved draft, using the actual on-device model with no fixture fallback; 1 test, 0 failures, no skip, 28.8 seconds |
| Expanded phone draft/relaunch recovery check | **Pending** |
| iOS native recording | **Compiled; hardware verification pending** |
| Built-in voice chooser | **Compiled; audible selection, preview and route verification pending** |
| Calendar read and Calendar/Reminders writes | Live permissions and actual system data **not verified** |
| Siri invocation and dictation | End-to-end device invocation **not verified** |
| Settings controller checks | **Pending**; the Clock result does not establish every prepared controller test |
| HomePod output and transfer | **Not verified** |

The three phone fixture tests use synthetic isolated data with spoken guidance and automatic progression disabled. They do not prove recording, model inference, audio or EventKit writes. The separate learning test used real inference on synthetic input; its local result is `.build/iphone-learning-v2.xcresult`. This does not establish quality across varied observations or a real week of behavior. The Mac model-readiness skip remains a separate result. The Clock check proves only that specific tethered navigation; its bundle is retained under ignored `work/device-runs/`. Package tests include actual Vision OCR of synthetic content. Test counts refer to the last completed run, not every source change made afterward.

## Next checks

1. Finish the expanded phone recovery check: edited-draft restoration and recovery after relaunch. Broaden the passed local-model example with more deliberately chosen observations and review the proposed steps and source quotations. Keep unavailable-model skips distinct from inference failures and passed generation.
2. Record a short deliberately chosen screen sequence with the real iOS picker, stop it, use it and review the OCR result. Test cancellation, system stop, limits and temporary-file cleanup. Record what was visible and missed; do not infer full app usage from sparse frames.
3. Audition a built-in voice on the phone, verify saved selection after relaunch, and test speech cancellation/interruption. Verify a real output route to the single available HomePod mini and continuation of the same routine item. See [device setup](DEVICE-SETUP.md).
4. Test Calendar read and one intentionally created reminder/event with the owner's permission. Verify timezone, date, default destination, denial, receipt and uncertain-write recovery behavior against the actual Apple apps.
5. Invoke start/capture through Siri or Shortcuts, review the received text, and verify that unapproved routines and unsaved capture drafts stay under user control.
6. Extend the bounded device-control proof with reviewed non-destructive targets before attempting a model-driven loop. Keep external-app/account scope explicit.

## Remaining boundaries

No exact count of reels, likes, emails read/replied/discarded, or total cross-app time is established. No ongoing automatic recording, first-pickup detection, historical touch log, continuous command listener, autonomous cross-app action loop, live message-send adapter or multi-day learned habit aggregation is claimed. [Issue #21](https://github.com/gibouu/morning-operator/issues/21) tracks evidence-based daily/weekly analytics; [issue #20](https://github.com/gibouu/morning-operator/issues/20) tracks voice choice and the separate consented-custom-voice investigation.

Raw HomePod microphone access, proactive room detection, automatic speaker transfer and two-speaker continuation remain unproved. HealthKit, Screen Time, Live Activities, billing and public distribution remain separate work.

Use the [test report template](TEST-REPORT-TEMPLATE.md) to record each device/software version, scoped source, observed result and evidence location. Keep raw personal recordings and device logs local; share only reviewed evidence. Regenerating the Xcode project does not itself compile, sign, install or test it.
