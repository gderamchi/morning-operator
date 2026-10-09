# Phase one: native app and device proof

Updated 9 October 2026. The earlier Mac application was built, launched and exercised, then its generated bundle was moved to Trash at the owner’s request. The iPhone is now the sole active product; the Mac remains a development/test machine and optional controller. Full Xcode 27 is now installed, and the signed iPhone application has built, installed and launched on a physical iPhone running iOS 27.0.1. Four synthetic device journeys, one bounded Clock navigation and real on-phone model generation passed. Newer integrations still need their own evidence.

## Current implementation

This describes the current working tree. The recording UX, observation persistence/recovery and app-transition logger below were added after the `b5914db` verification. An initial revised phone build-for-testing, nine focused transition checks and a later 64-check full package run passed. That later package run intentionally skipped the opt-in real-model check. It preceded the latest background recording-handoff fix. The final iPhone build-for-testing and two recovery storage retests then passed; end-to-end recording/Shortcuts checks remain pending.

- **Native interface:** Morning, Review and Notes tabs, a routine timeline, day navigation, and Learn/Settings sheets. The sample is labeled synthetic; manual and learned routines must be reviewed and approved before starting.
- **Versions and recovery:** edits produce an unapproved next version and retain the previous approved routine for restoration. Atomic workspace saves preserve the draft, current session, history and notes. A run pins its approved version; reopening a running session restores it paused at the same step. This is not a full version-history browser.
- **App-owned execution:** hands-free mode can read a step or query/read today's authorized calendar and advance only after its speech completion callback. Interactive or unsupported steps wait for the user. Cancellation and stable identities reject stale/duplicate callbacks. Synthesis completion does not prove the user heard the chosen speaker.
- **Observation import:** the native file picker reads a selected UTF-8 note, image or video. AVFoundation samples a bounded number of frames and Vision extracts visible text. The user reviews this text before requesting semantic analysis.
- **Explicit recording:** the revised iOS 27 flow uses explicit Apple picker consent, screen-only capture, a shared service and compact Stop/status. App-owned Record/Learn sheets dismiss when capture starts; Apple's system panel dismissal remains unverified. Choose 5/10/20/30 minutes, with a separate 256 MiB bound. The latest source stages finalized recordings directly from the service callback, including while the UI is in the background. Same-session recordings process after foreground/idle; a recovered recording after relaunch requires Retry. Extraction persists OCR text and can propose an unapproved routine automatically; the normal new flow needs no Use step. Recovery now has a local single-recording slot restored at launch; it retains raw media after extraction/cancellation/persistence failure for Retry/Discard, removing it after successful extraction persistence or discard. User-selected files remain untouched.
- **Local semantic learning:** Foundation Models produces a constrained, unapproved proposal and validates source quotations. Model availability is visible. Manual/sample routines work without the model; there is no cloud fallback. The revised source persists the latest extracted observation text/source. Clear this observation removes that text; evidence quotes saved in routine steps remain. This is one latest observation, not a multi-day observation library.
- **Capture and Apple apps:** thoughts/dreams save locally. Reviewed reminder/calendar requests can optionally be written through EventKit. Permission is requested only for the chosen integration; pending writes are persisted before dispatch, and known receipts prevent retrying a successful write. An uncertain outcome asks the user to check the Apple app before trying again. Live system writes remain unverified.
- **Voice and shortcuts:** foreground App Intents request an approved morning start or open capture text for review. They do not approve a changed routine or silently save an event. Installed built-in voice selection, search, preview and persisted preference are implemented. Personal Voice authorization is not requested. The iPhone exposes Apple's audio-route picker; Mac uses system sound controls.
- **History:** stopped/completed local sessions feed day and seven-day review. Synthetic runs are excluded from ordinary summaries. A new background App Intent and separate local journal record user-configured Instagram/TikTok/Snapchat entry/exit callbacks; Review has a Today entry/return card. Installed delivery remains unverified; this implementation does not silently install automations and does not establish pickups, app duration or read/reply metrics.
- **Separate development controller:** XCTest fixture, Settings and opt-in external-app tests are outside the normal application. The external-app test defaults to capture-only and can attempt bounded, read-only navigation with a fresh target and postcondition. A persistent model-driven phone controller is not implemented.

## Actual verification

Baseline tested application source: `b5914db`. The full package and four-journey phone runs used this source; later focused checks/build observations are separately identified below. These are recorded observations, not claims that every current integration passed.

| Check | Observed result |
|---|---|
| Toolchain/device setup | Xcode 27 (27A266a); physical iPhone 15 Pro Max on iOS 27.0.1 paired, Developer Mode enabled, signed build/install/launch succeeded |
| Mac application | Native bundle built and launched |
| Earlier real Mac walkthrough | Sample approval/start/next/pause/resume/stop, edited draft and restoration, and paused recovery after relaunch worked |
| Earlier native file panels | Synthetic UTF-8 observation imported into reviewable notes; sample JSON exported and parsed |
| Baseline full package run | **53 passed, 1 skipped**. The skipped integration test was real Foundation Models inference because the Mac reported **modelNotReady** |
| Physical iPhone fixture journey | **Passed:** approve/start/next/pause/resume/stop |
| Physical iPhone local dream | **Passed:** local save, kind filtering and persistence across tab navigation |
| Physical iPhone empty history day | **Passed:** day swipe shows an empty state without inventing history |
| Physical iPhone external Clock navigation | **Passed:** World Clock → Alarms, one read-only scroll, return to World Clock; no writes |
| Physical iPhone Foundation Models generation | **Passed on 9 October 2026:** synthetic calendar/chess observation → a two-step unapproved draft, using the actual on-device model with no fixture fallback; 1 test, 0 failures, no skip, 28.8 seconds |
| Phone draft/relaunch recovery | **Passed:** edit → relaunch with draft → restore approved version → run → relaunch paused at same step → resume/stop |
| Earlier iOS recording XCTest | **End-to-end test failed:** approximately 244 seconds; Apple panel visible in captured evidence, notes empty after Use |
| Later owner recording/import | **End-to-end user check failed/unresolved:** record → system Stop → Use showed Observation loaded, but the owner then checked Learn and found the text box empty. The banner does not prove a usable extraction or model result |
| Initial revised iPhone build-for-testing | **Succeeded**, before the latest recording-recovery fix; this is a build result, not runtime verification |
| Final revised iPhone build-for-testing | **Succeeded** after the latest background handoff; a build result does not prove recording ingestion |
| Latest five-fixture attempt | **Not executed / environment-blocked:** Xcode timed out enabling automation mode before test initialization. No assertion result; phone build passed |
| Recovery storage retest | **2 passed** after the final metadata change; not an end-to-end phone recording pass |
| Revised recording flow and saved observation recovery | End-to-end device verification **pending** |
| Later working-tree full package run | **64 passed, 1 intentionally skipped:** real-model check was not opted in; this run preceded the latest background handoff fix |
| Focused app-transition checks | **9 passed**; separate from the earlier full package result |
| App-transition intent delivery and Today card | Installed Shortcuts/background/runtime verification **pending** |
| Built-in voice chooser | **Compiled; audible selection, preview and route verification pending** |
| Calendar read and Calendar/Reminders writes | Live permissions and actual system data **not verified** |
| Siri invocation and dictation | End-to-end device invocation **not verified** |
| Settings controller checks | **Pending**; the Clock result does not establish every prepared controller test |
| HomePod output and transfer | **Not verified** |

The four phone fixture tests use synthetic isolated data with spoken guidance and automatic progression disabled. They do not prove recording, model inference, audio or EventKit writes. The separate learning test used real inference on synthetic input; its local result is `.build/iphone-learning-v2.xcresult`. This does not establish quality across varied observations or a real week of behavior. The Mac model-readiness skip remains a separate result. The Clock check proves only that specific tethered navigation; its bundle is retained under ignored `work/device-runs/`. Package tests include actual Vision OCR of synthetic content. The final fixture suite passed 4/4 with no skips in 124.6 seconds. Its result is `work/device-runs/20261009T193427Z-20165/Results.xcresult`. The final package run passed 53 checks with one Mac model-readiness skip, including real Vision OCR.

The earlier recording attempt is retained at `work/device-runs/20261009T193725Z-21155/Results.xcresult`. It used the flow before automatic foreground processing. Its failure remains separate from the later manual observation: the owner confirmed recording, system Stop and Use; a Home-screen image showed the red recording indicator; then the app displayed Observation loaded. The owner subsequently checked the ordinary-app Learn text box and found it empty. This is an unresolved failed end-to-end user check; the banner is insufficient evidence of successful extraction, persistence or presentation. The failure could be in any of those stages and has not yet been localized. No new recording/logger revision is covered by the earlier package or fixture passes.

The latest five-fixture attempt is `work/device-runs/20261009T201452Z-27480/Results.xcresult`. The runner timed out enabling automation mode before initialization; no tests executed. This is an environment-blocked run, not five failed assertions or a pass. The owner was asked to unlock both Mac and iPhone before another attempt.

## Next checks

1. Broaden the passed local-model example with more deliberately chosen observations and review the proposed steps and source quotations. Keep unavailable-model skips distinct from inference failures and passed generation.
2. Reproduce and localize the ordinary-app empty-observation failure before claiming recording success: check the finalized source, OCR result, saved workspace text and rendered Learn field. Build the revised flow, record a short deliberately chosen sequence with the real picker, stop it and return to the foreground. Verify app-sheet dismissal separately from Apple-panel dismissal, automatic OCR/draft preparation, saved text after relaunch, Clear observation, unavailable-model fallback and unapproved state. Exercise every limit, system stop and Retry/Discard recovery; retain evidence of failures. Do not infer full app usage from sparse frames.
3. Audition a built-in voice on the phone, verify saved selection after relaunch, and test speech cancellation/interruption. Verify a real output route to the single available HomePod mini and continuation of the same routine item. See [device setup](DEVICE-SETUP.md).
4. Test Calendar read and one intentionally created reminder/event with the owner's permission. Verify timezone, date, default destination, denial, receipt and uncertain-write recovery behavior against the actual Apple apps.
5. Invoke start/capture through Siri or Shortcuts, review the received text, and verify that unapproved routines and unsaved capture drafts stay under user control.
6. Configure one supported app-transition automation pair and verify discovery, background execution without opening Morning Operator, cold launch, timestamped persistence and Today counts/returns. Test missing/duplicate events separately; no pickup or full-usage claim follows.
7. Extend the bounded device-control proof with reviewed non-destructive targets before attempting a model-driven loop. Keep external-app/account scope explicit.

## Remaining boundaries

No exact count of reels, likes, emails read/replied/discarded, or total cross-app time is established. No ongoing automatic recording, first-pickup detection, historical touch log, continuous command listener, autonomous cross-app action loop, live message-send adapter or multi-day learned habit aggregation is claimed. [Issue #21](https://github.com/gibouu/morning-operator/issues/21) tracks evidence-based daily/weekly analytics; [issue #20](https://github.com/gibouu/morning-operator/issues/20) tracks voice choice and the separate consented-custom-voice investigation.

Raw HomePod microphone access, proactive room detection, automatic speaker transfer and two-speaker continuation remain unproved. HealthKit, Screen Time, Live Activities, billing and public distribution remain separate work.

Use the [test report template](TEST-REPORT-TEMPLATE.md) to record each device/software version, scoped source, observed result and evidence location. Keep raw personal recordings and device logs local; share only reviewed evidence. Regenerating the Xcode project does not itself compile, sign, install or test it.
