# MORE: implementation and verification

The installed iPhone app remains at **`8a640ea`**. The **`codex/more-quiet-morning`** branch has been built and checked on an iPhone 15 Pro Max simulator running iOS 27.0 with Xcode 27. The current saved-observation proposal source **`4a2fd30`** builds on **`d9a6120`**, which added dated observation history and preserved original evidence alongside corrections. The preceding source **`fb0e4a2`** added optional native OCR layout evidence; its historical checks remain separate below. The historical **`e7666cd`/`dd611fd`** refinement and **`4ddb524`** baseline retain their separate results. None of these follow-ups replaced the owner's phone build, and no physical phone was connected for them.

## V2 in this branch

Morning now contains the date, compact routine and start/run controls. Review owns history, routine edits, approval, observations, thoughts and connections. Installed Apple voice selection considers language, dialect and quality; an explicit voice-command turn pauses the routine and releases playback before using on-device speech recognition. [Design](V2-DESIGN.md) · [Voice behavior](VOICE.md) · [Architecture](ARCHITECTURE.md).

Learning preserves complete required rituals from the person's previous routine, keeps proposals unapproved and strips model-assigned automation. Sample rituals stay out of personal learning. This is not a complete edit/removal preference journal or a multi-day habit-quality result.

## Saved-observation routine proposals — 10 October 2026 (`4a2fd30`)

**Review → Saved observations → Choose mornings** now prepares one separately saved proposal from one to five dated observations. Selection requires the same time zone and human-or-synthetic origin. Exact source-unit citations, corrections, declared frame exclusions, full source/base-routine revisions, required-ritual preservation and a ten-moment final limit keep the result reviewable. Approval, rejection and source invalidation are separate transitions; the current routine stays in place during this flow. The older single-observation Learn path still installs an unapproved draft. [Detailed flow and retention](ROUTINE-LEARNING.md).

| Check | Result and scope |
|---|---|
| Shared logic and adapters | **232 distinct passing checks across full and focused runs, six optional skips.** Core: 89 passed. Apple: 143 distinct passed across runs, six skipped. Includes all 18 new source-selection, exact-quotation, staleness, restoration-bound and ritual-preservation checks. |
| Native OCR failure and retry | Full native-access run: the existing screenshot OCR test failed with an `e5rt` execution error (13.542s), while the native layout extraction check passed (26.681s). The focused rerun passed **17/17**: all 16 proposal checks plus the isolated actual Vision screenshot check (28.353s). This is not one uninterrupted all-green suite. |
| Final restoration regressions | **18/18 proposal checks passed**, no skips, after requiring embedded quotations to survive restoration and candidate versions to follow the current base safely. A saved derived proposal cannot approve missing quotation content or an invalid version. |
| Native build | **Succeeded** after the final restoration guards, Xcode 27 / iPhone 15 Pro Max simulator / iOS 27.0, including app and UI-test targets. |
| Initial proposal app journeys | **4 passed, 1 failed; no skips**, 495.490s. Correction invalidation, paused-run protection, date/deletion invalidation and quotation/relaunch/approval/restore passed. Keep current was below the visible list and could not be reached by the test. |
| Fixed actions and affected rerun | Moved Keep current and Approve update into one fixed bottom bar. **2/2 passed; no skips**, 227.579s: discard/current-routine start (74.945s) and quotation/relaunch/approval/restore (152.634s). |
| Final compact review | Reduced the introductory copy and put further explanation in a disclosure. **1/1 passed; no skips**, 30.200s: suggested moment and both review actions were reachable without scrolling at default portrait size. Inspected the exported synthetic screenshot. This is not a large-text or physical VoiceOver check. |
| Final app recovery after restore guards | **1/1 passed; no skips**, 151.270s on final source `4a2fd30`: exact quotations/source links, dismissal/relaunch with current routine intact, approval, approved-version relaunch and previous-version restoration/relaunch. Other UI journeys were not repeated after the two shared validation guards. |
| Supported-model readiness | A fresh native Mac probe outside the tool sandbox returned `.unavailable(.modelNotReady)` on macOS 27.0.1. The device listing contained only a simulator, with no physical iPhone reachable. Zero generation/prewarm calls were made. No retry of the unsupported simulator model backend. |

The six distinct app journeys above use explicitly labeled synthetic assembly and make no Foundation Models call. They are passing results across separate scoped runs, not one uninterrupted all-green suite.

No real multi-observation model result, measured personal habit average, physical V2 install, microphone recognition or HomePod transfer is established by this slice. Approved step content retains embedded quotations; pending typed citations are removed on approval, discard or invalidation. Listener-confirmed physical speech is still open.

## Dated observation history — 10 October 2026 (`d9a6120`)

Review now saves separate observations across imports, places explicitly dated observations under their local day, and provides Date needed for unknown dates. Originals and corrections are retained separately. Same-file SHA-256 deduplication preserves the acquisition identity, corrections and date; single/all deletion removes its advertised evidence scope and leaves routines intact. Native recording-start metadata survives the recovery slot, but its physical callback path still needs a phone trial.

| Check | Result and scope |
|---|---|
| Shared logic and native adapters | **214 distinct checks passed across the full and focused runs; six optional checks skipped.** Core: 89 passed. Apple: 125 passed across runs, six skipped. New archive, recording metadata, recovery and fingerprint checks are included. |
| Native service failures retained | The restricted package attempt could not create Vision pixel buffers for two existing image tests. Retrying with native-service access passed the layout test (49.987s), while the screenshot test encountered an `e5rt` execution error. A focused rerun passed that actual Vision screenshot check (26.796s) and all 12 final archive checks. This is not one uninterrupted all-green suite. |
| Final iOS build | **Succeeded**, Xcode 27 / iPhone 15 Pro Max simulator / iOS 27.0. Includes final archive validation and Store integration. |
| Initial archive UI attempt | Original/correction/relaunch/scoped-deletion passed (84.046s); real text reimport/deduplication passed (74.917s). The date journey could not find a standalone date string; its screenshot shows that value during the detail transition. The staged legacy test was skipped because that first invocation did not supply its opt-in workspace. Readiness waits were added, and the subsequent run exposed the grouped-accessibility selector issue below. |
| Archive/import UI run | **Four passed, two failed; no skips**, 318.700s. Original/correction/scoped deletion passed (90.550s), same-file real text reimport passed (74.623s), blank-video preservation passed (40.101s), and the actual fixture-app recording import/edit/clear passed (71.400s). Date and legacy journeys failed to locate standalone strings inside native grouped metadata rows. Local inspection confirmed migration had saved one entry, retained the routine, kept both dates unknown and removed the invalid derived result. |
| Final accessibility correction and affected journeys | Added explicit spoken labels/values for observed date, import date and origin, then rebuilt successfully. **2/2 passed, no skips**, 120.360s: a freshly staged old-format workspace migrated and survived relaunch (48.566s); assigning day/origin, opening the dated day, unassigning and relaunching passed (71.795s). The other four UI journeys were not repeated after this accessibility-only change. |
| Visual review | Inspected the saved original/correction detail and final undated-observation screenshots. The native lists and disclosure controls remain in Review; no new controls or counters were added to Morning. This is not a full spoken VoiceOver or physical-device audit. |

Synthetic origins remain separate from human activity. The local-day archive does not provide complete capture intervals, actual app dwell time, gestures, reading intent or comparable-day habit averages. No new model call, physical phone install, Siri/microphone or HomePod trial was performed in this slice. The device query found only a simulated device; listener-confirmed phone speech remains open.

## Native OCR layout evidence — 10 October 2026 (`fb0e4a2`)

The existing single Vision pass now also retains optional line/region evidence: exact text and Swift Character spans, extraction-local IDs, approximate normalized lower-left bounds for the oriented image, and OCR candidate confidence. Invalid or missing geometry leaves readable text intact with a warning. Character/UTF-8 limits preserve only complete region spans, and a separate 256-region cap limits metadata. Legacy observations remain readable without geometry.

Optional classifier hints refer only to exact source lines inside the bounded prefix. Rounded hints cannot displace text from the prompt budget or resolve competing catalog names by themselves. Exact citation checks now compare source UTF-8 bytes rather than accepting Unicode canonical equivalence. No new model call or supported-device inference result is claimed.

| Check | Observed result and scope |
|---|---|
| Full shared package | **190 passed, six optional checks skipped**: 86 Core passes plus 110 Apple cases including the skips. Both real synthetic-image Vision checks passed in approximately 28.3 seconds each. Includes geometry/range validation, legacy decoding, clipping, metadata caps and conservative classifier hints. |
| Native app build | Passed. This is a build result, not a new physical-phone installation. |
| Complete saved-movie layout extraction | **1/1 passed in 83.642s**. `baseline-01/layout-01.json`: 24/24 observed samples, 647 native OCR regions, zero frame warnings; 24 selected frames/140 selected hints/12 prepared batches. No model was called. |
| Recorded-movie import regression | `.build/more-ocr-layout-import.xcresult`: actual movie → notes/frame evidence → relaunch → edit invalidates association → clear stays cleared **passed in 71.113s**. The blank-video test **skipped in 0.05s** because its separate opt-in was missing; this was one pass plus one skip. |
| Blank-video fault regression with corrected opt-in | `.build/more-ocr-layout-blank.xcresult`: **1/1 passed in 39.404s, no skips**. Failed extraction preserved the previous observation across relaunch. This separate pass does not erase the earlier missing-opt-in skip or establish native capture. |

See [the benchmark guide](OBSERVATION-BENCHMARK.md#native-ocr-layout-evidence--10-october-2026) for geometry semantics and the explicit no-model extraction command. Layout is approximate visual evidence, not a foreground-app identity, action counter or habit measurement.

## Recording benchmark refinement — 10 October 2026 (`dd611fd`)

The dense-frame exclusion is corrected through explicit exact-source header excerpts. Each complete frame contributes up to 320 characters/six nonempty lines, with original evidence and timestamps retained and selection ranges saved. Citations must match both excerpt and source. Leading punctuation/symbol decorations may match a catalog header, but alphabetic OCR noise is not repaired and competing app-name breadcrumbs remain ambiguous. This changes input eligibility, not model accuracy.

| Check | Observed result and scope |
|---|---|
| Full shared package after excerpt refinement | **170 passed, four explicitly skipped**: 77 Core and 97 Apple cases including skips. This full run predates the three new sanitized-error mapping tests below. |
| Preparation-only baseline replay | `preparation-v2.json`: **24/24 frames eligible**, **2,217 selected characters**, zero excluded frames, eight deterministic lexical candidate frames. No OCR or model inference was performed by the replay; candidates are not recognized app appearances or an AI-accuracy score. |
| Corrected simulator app-process model attempt | `.build/more-recorded-model-fixed.xcresult` reached the actual recognition control after its accessibility correction. Availability reported available, but the saved result was **failed**: **six attempted, zero responded, six failed batches; all 24 decisions unknown**. No inference-response, abstention-quality or semantic-recognition pass. |
| Own-process backend investigation | `simulator-model-log.txt` records `operationNotAllowed` / “Simulator is not supported” when a required model backend tries to fetch metadata. This identifies an environment/backend rejection for this attempt, not a finding that the synthetic content breached a content rule. Availability preflight alone was insufficient. |
| Native error-category diagnostics | Additive optional fixed categories cover current and legacy Foundation Models errors; fallback stores only an allowlisted system domain/numeric code. SDK associated text, localized descriptions, prompts and responses are not persisted. Targeted checks: **22 passed, one optional preparation-replay check skipped** (23 listed); app build passed. At this checkpoint the full shared package had not rerun since these three new mapping tests. |
| Final diagnostic runtime check | `.build/more-recorded-model-diagnostics.xcresult`: **failed 1/1 in 31.936s**. Again available/six attempted/zero responded/six failed/24 unknown. `simulator-classification-diagnostics.json` saves only `{category: other}` for each native error; the unsupported-simulator finding comes from the separate own-process log. |

The initial Mac-unavailable result and initial UI-identifier failure remain below as historical evidence. Their results have not been rewritten as passes. The 2,217-character total describes only the preparation replay; separate OCR reruns vary slightly. Original extraction and both failed app-process classifications remain local. No further unchanged simulator model retries are planned. A supported physical-device inference attempt and independent semantic scoring are still pending; the stable installed phone build was untouched. See [benchmark details](OBSERVATION-BENCHMARK.md).

## Recording benchmark — 10 October 2026 (`4ddb524`)

Ordered frame evidence is now connected to video extraction, durable latest-observation storage and a compact Learn disclosure. A separate Foundation Models classifier proposes visible-context labels with exact citations; it cannot emit gesture counts, reading intent or OS-verified app identities. See [the benchmark protocol and results](OBSERVATION-BENCHMARK.md).

| Check | Observed result and scope |
|---|---|
| Shared package | **163 passed, four optional model skips**: 77 Core and 90 Apple cases including skips. Actual synthetic Vision OCR passed in 28.480s. Includes extraction budgets/failures, citation validation, model-input constraints and existing behavior. |
| Native benchmark build and driver | Build succeeded; **1/1 passed**, 91.870s. Two separately installed synthetic apps followed Cedar → Lumen → Cedar. Two issued swipes had independently verified row movement, and a synthetic message detail appeared. Controller truth remained separate from movie analysis. |
| Actual simulator movie | Finalized at **97.155s**. Vision returned text for all 24 requests, resolving to **14 distinct actual presentation times**. Readable text was available for all seven planned visible screen states. This is availability, not an OCR character-accuracy or model score. |
| Mac movie/model attempt | **Failed the explicit model-availability requirement after saving diagnostics**: `modelNotReady`, zero generation attempts, 24 unknown decisions. No inference, abstention-quality or semantic-accuracy pass is claimed. |
| App import and recovery | **2/2 passed**, 112.369s. Actual movie → visible notes and frame metadata → relaunch persistence → editing invalidates association → clear stays cleared (72.021s). Separate generated black-video fault case preserved previous text through failure and relaunch (40.348s). |
| Initial app-process model UI check | **Failed before inference**, 89.208s. The disclosure opened but the visible recognition action's accessibility identifier could not be found. Removing the parent identifier and moving the action above the sample list are follow-up corrections, not a model result. |
| First classifier limitations | Dense whole-frame text excluded 11 samples. Icon-prefixed headers and system return-to-app breadcrumbs prevented the remaining fixture samples satisfying the initial catalog predicate. Full A → B → A recognition and comparable-day averages remain unproven. |

The first baseline is kept intact. The UI checks validate file import in the simulator, not native iPhone ScreenCaptureKit. Neither the phone build nor personal observations were changed. Raw movie, OCR, truth, test data and screenshots remain ignored/local.

## Earlier invitation evidence — 10 October 2026 (`6f647b4`)

Source **`6f647b4`** adds [one-time morning invitations](MORNING-ENTRY.md), acknowledged foreground entry, and a [structured observation core](OBSERVATION-METRICS.md). At this earlier checkpoint the trace/report mathematics were implemented and tested; the recording adapter, classifier and controlled movie benchmark were not connected yet.

| Check | Observed result and scope |
|---|---|
| Full shared package run | **138 passed, two optional model skips**: 69 Core and 71 Apple cases including skips. Includes 11 trace/window checks, five entry-policy checks, 16 invitation model/service checks, earlier voice/learning checks, and real synthetic Vision OCR (26.978s). The first attempt failed to compile mutating calls inside test macros; evaluating those calls before assertions fixed the tests. |
| Scheduler race review | Passive foreground refresh could suppress a pending explicit permission request. The corrected service preserves that intent for the same occurrence, claims it once, and never restores permission intent from disk. A held-callback regression passed. |
| Initial entry UI checks | **4/4 passed**, 33.195s: approved start, draft review, first-use learning, invitation settings without a permission prompt. This preceded recovery/detail-sheet changes. |
| Revised entry suite | **Five passed, one failed**, 142.396s. Approved/draft/empty routing, settings and deferral behind an open detail sheet passed. The real local notification registered, appeared and was tapped, then the app crashed before a run appeared. The crash stack showed the SDK async delegate completion entering UIKit state restoration from a cooperative worker. |
| Corrected real local notification handoff | **1/1 passed**, 59.100s after changing notification delegate callbacks to explicit completions on the main actor. A native calendar-triggered local invitation appeared while the app was backgrounded; tapping it foregrounded MORE and started the approved synthetic routine. This used real UserNotifications delivery, not injected push delivery. The existing grant was used on this rerun; the earlier attempt had exercised the permission prompt. |
| Final app build | **Succeeded** with Xcode 27 / iPhone 15 Pro Max simulator / iOS 27.0, including the delegate correction. The earlier five entry UI checks were not rerun after that callback-only fix. |
| Remaining entry trials | Physical phone, terminated/cold app, locked phone, notification action button, actual Siri voice/discovery, Focus behavior and physical cancellation/replacement remain pending. |

The simulator's notification identifier and fixture workspace are separate from ordinary app data; notification permission itself remains app-wide. No physical phone build was replaced in this slice. All screenshots, logs, crash evidence, test workspaces and result bundles remain local and ignored.

## Earlier V2 evidence — 9 October 2026 (`52cbe56`)

| Check | Observed result and scope |
|---|---|
| Shared package suite after the new voice/ritual changes | **106 passed, two optional model skips**: 48 Core cases and 60 Apple cases including the skips. Actual Vision OCR of a synthetic image passed. Command grammar, final-result gating, stale-context refusal, session transitions and audio-release races are deterministic checks; they do not prove microphone accuracy. |
| iOS simulator build for testing | **Succeeded** with the native listener and two-tab app. No compiler errors; only the UI-test target's unrelated App Intents metadata warning. |
| Initial compact layout suite | **3/3 passed**, 31.347 seconds: first use, ten moments without scrolling, Review-owned approval and date entry. |
| Expanded simulator attempt | Test log records **8 passed, three failures** over 11 tests. Five layout/detail/dark checks, local dream retention, first-use learning and observation correction/relaunch/clear passed. Two failures read an empty accessibility value instead of the visible title; the third could not locate a day link. Xcode then stalled finalizing diagnostics; that collector was stopped after preserving the log. Its unfinished result bundle is not treated as a complete xcresult. |
| Corrected navigation and new voice-entry checks, before final menu/copy polish | **5/5 passed**, 166.111 seconds: approve/run/pause/resume/stop; edited-draft restoration and paused recovery after relaunch; empty-day/history/date routing; ten active moments without scrolling; explicit voice entry/close without microphone permission. |
| Largest accessibility text size | Initial check reached Start and full instructions but failed to find End morning at the bottom of the long native menu. Moving End morning to the top fixed it: **1/1 passed**, 16.932 seconds; start → read detail → stop. Normal simulator text size restored. |
| Final synthetic voice output and dark layout | **3/3 passed**, 56.568 seconds: dark ten-moment fit (5.555s), actual system-speech step completion → next manual step (34.634s), preview speaking → idle (16.379s). These are simulator callbacks, not microphone recognition or listener-confirmed quality. |
| Landscape, VoiceOver, Reduce Motion/Transparency and physical V2 | Pending separate checks. |

Opening the voice-command sheet does not itself listen. Real microphone permission, recognition quality, selected input route, audio interruptions and listener-confirmed output still require device trials. The owner did not hear or was not listening to the earlier phone greeting. The existing callback proofs do not establish audibility or HomePod output.

## Keep the boundaries clear

- The earlier real recording proved one capture → OCR → saved-text path. Its proposed habits were wrong; deterministic rejection now covers the known setup-only input, not general habit accuracy.
- Review averages describe actual app-owned routine runs. Samples, missing days and incomplete timings do not become measured personal app usage.
- Native recording of WhatsApp, selected-message reading, narrated cross-app actions, first-pickup/alarm behavior and HomePod transfer remain separate open checks.
- Recordings, observation text, workspace snapshots, screenshots and result bundles stay local and ignored by Git. Only reviewed aggregate results belong here.

<details>
<summary>Earlier physical-phone results and investigation history</summary>

The following record preserves the original test chronology. References to the “current working tree” or a pending rebuild describe the stage at which they were written; the installed baseline and new V2 status above take precedence.

Updated 9 October 2026. The earlier Mac application was built, launched and exercised, then its generated bundle was moved to Trash at the owner’s request. The iPhone is now the sole active product; the Mac remains a development/test machine and optional controller. Full Xcode 27 is now installed, and the signed iPhone application has built, installed and launched on a physical iPhone running iOS 27.0.1. The latest six-fixture phone suite and real on-device positive model example passed. Shared package checks passed 73 with two optional model skips. The negative phone evidence-guard check passed its targeted rerun after an XCTest query exception. The final focused evidence-policy suite passed 11/11, and a deterministic replay rejected the earlier problematic observation without changing it. The final iPhone rebuild/install after that correction is pending; broader integrations still need their own evidence.

## Current implementation

This describes the current working tree. Recording recovery, saved observations, an app-transition journal, a first-use learning action and a bounded observation editor extend the earlier `b5914db` baseline. A later real clip reached saved OCR and an unapproved draft but misread setup/marketing text as habits. The new evidence policy filters recognized setup/picker/launcher/marketing contexts, validates eligible quotations and preserves an insufficient-evidence outcome. It is a targeted heuristic, not reliable habit recognition. The final focused deterministic evidence suite passed 11/11, including two additional Review/setup cases after the earlier nine tests. A local replay also rejected the saved problematic observation; the optional direct real-model negative check was not opted in. Broader recording lifecycle checks and installed Shortcuts delivery remain pending.

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

Baseline tested application source: `b5914db`. The earlier full package and four-journey phone runs used that source. The real recording result used `51b1de9`; its targeted observation rerun additionally includes the test-only empty-accessibility-value assertion correction. The latest working-tree revision adds evidence guards and the first-use/editor refinements; final checks below identify their own scope. These are recorded observations, not claims that every current integration passed.

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
| Earlier owner recording/import | **Failed user check:** record → system Stop → Use showed Observation loaded, but Learn was empty. Preserve this failure; the banner alone was insufficient |
| Fresh owner recording-to-result on `51b1de9` | **Narrow path passed:** 40.3-second real clip, 21 sampled frames, 5,357 saved observation characters, visible unapproved two-step draft. Actual saved recording text was also readable after ordinary-app termination/relaunch, with Clear this observation visible. This was not the synthetic import fixture |
| Habit interpretation of that real clip | **Quality failure:** the model treated Morning Operator setup/marketing text as habits. No accurate routine, exact action count or personal habit-learning claim follows; controlled validation is tracked in #23 |
| Tethered WhatsApp launch/capture | **1/1 passed**, 9.612 seconds: ordinary Chats screenshot was readable; no conversation selected or message sent. This was XCTest capture, not native ScreenCaptureKit recording |
| Initial local replay of the real observation | **Further quality gap found:** app Review text survived the initial filter. This led to an additional public-copy-only regression and filter correction |
| Final focused evidence-policy tests | **11/11 passed** after the Review/setup correction; deterministic checks only |
| Final replay of the saved real observation | **Passed:** the 5,357-character input is rejected as insufficient activity evidence by the same source policy, with the original text unchanged. No new model call, fine-tuning or real-model abstention was involved |
| Apple sharing-panel dismissal | **Not established:** the system panel remained visible at 00:07 in the observed capture |
| Initial revised iPhone build-for-testing | **Succeeded**, before the latest recording-recovery fix; this is a build result, not runtime verification |
| Final revised iPhone build-for-testing | **Succeeded** after the latest background handoff; a build result does not prove recording ingestion |
| Initial revised five-fixture attempt | **Not executed / environment-blocked:** Xcode timed out enabling automation mode before test initialization. No assertion result; phone build passed |
| Revised five-fixture retry | **4 passed, 1 failed** in 176.732 seconds. The original four passed; the new import test failed only at its final empty-field assertion because accessibility returned nil instead of an empty string |
| Targeted synthetic observation regression | **1/1 passed**, 56.566 seconds, no skip, after the test assertion correction. Actual text-file import → visible Learn text → sheet reopen → relaunch → clear → relaunch stayed correct |
| Recovery storage retest | **2 passed** after the final metadata change; not an end-to-end phone recording pass |
| Broader recording lifecycle and recovery | One capture-to-result path passed; interruption, bounds, retry/discard and reliability still need their own device evidence |
| Later working-tree full package run | **64 passed, 1 intentionally skipped:** real-model check was not opted in; this run preceded the latest background handoff fix |
| Focused app-transition checks | **9 passed**; separate from the earlier full package result |
| Full package run before the final two evidence regressions | **73 passed, 2 intentional optional-model skips**: 30 Core and 45 Apple cases including the two skips. Actual synthetic Vision OCR passed in 28.126 seconds; nine new deterministic evidence-policy tests passed |
| iPhone build-for-testing before the final Review filter correction | **Succeeded** for the evidence-policy/first-use/editor revision |
| Final iPhone rebuild/install after the Review filter and observation-edit corrections | **Succeeded** at source `8a640ea`; ordinary app launched without fixture flags, saved observation verified unchanged |
| Latest six-fixture suite | **6/6 passed**, 186.709 seconds, including the above-fold first-use action and observation import/persistence/clear |
| Latest real on-device positive model example | **Passed**, 30.360 seconds; real generation from synthetic input, separate from the negative guard |
| Initial phone negative evidence-guard attempt | **Harness failure:** XCTest rejected an accessibility identifier query exceeding its 128-character limit with `NSInternalInconsistencyException`. This was not a product assertion failure; seven other tests passed in that combined run |
| Corrected targeted negative guard | **1/1 passed**, 28.972 seconds, after changing the test query to an exact-label predicate; no application-code change was needed for that rerun. This is deterministic rejection before inference, not real-model abstention |
| App-transition intent delivery and Today card | Installed Shortcuts/background/runtime verification **pending** |
| Built-in voice greeting preview | **1/1 passed**, 14.912 seconds, no skip in the corrected run: physical-iPhone speech delegate reached speaking then idle. The first attempt skipped because the test opt-in setting was missing. Owner was not listening; listener audibility, full routine narration and HomePod routing remain unverified |
| Calendar read and Calendar/Reminders writes | Live permissions and actual system data **not verified** |
| Siri invocation and dictation | End-to-end device invocation **not verified** |
| Settings controller checks | **Pending**; the Clock result does not establish every prepared controller test |
| HomePod output and transfer | **Not verified** |

The phone fixture journeys use synthetic isolated data with spoken guidance and automatic progression disabled. They do not prove recording, model inference, audio or EventKit writes. The separate learning test used real inference on synthetic input; its local result is `.build/iphone-learning-v2.xcresult`. This does not establish quality across varied observations or a real week of behavior. The Mac model-readiness skip remains a separate result. The Clock check proves only that specific tethered navigation; its bundle is retained under ignored `work/device-runs/`. Package tests include actual Vision OCR of synthetic content. The earlier baseline fixture suite passed 4/4 with no skips in 124.6 seconds. Its result is `work/device-runs/20261009T193427Z-20165/Results.xcresult`. That baseline package run passed 53 checks with one Mac model-readiness skip, including real Vision OCR. The later 64-pass/one-intentional-skip package run and two final recovery retests remain separate observations in the table.

The earlier recording attempt is retained at `work/device-runs/20261009T193725Z-21155/Results.xcresult`. It used the flow before automatic foreground processing. Its failure remains separate from the later manual observation: the owner confirmed recording, system Stop and Use; a Home-screen image showed the red recording indicator; then the app displayed Observation loaded. The owner subsequently checked the ordinary-app Learn text box and found it empty. That earlier check failed; the banner was insufficient evidence of successful extraction, persistence or presentation. Its precise failure stage has not been localized, and the later successful clip does not retroactively turn it into a pass. No new recording/logger revision is covered by the earlier package or fixture passes.

The initial revised fixture attempt, `work/device-runs/20261009T201452Z-27480/Results.xcresult`, timed out enabling automation mode before initialization; no tests executed. The retry, `work/device-runs/20261009T201934Z-28080/Results.xcresult`, executed five tests: four passed and the observation test failed only at the final empty-editor assertion. Its accessibility value was nil rather than an empty string; the test now normalizes that representation while still requiring an exact nonempty text match.

The corrected targeted rerun is `.build/iphone-observation-persistence-final.xcresult`, with log `/tmp/morning-observation-regression-test.log`: one test passed in 56.566 seconds with no skip. Thus five phone journeys passed **across separate runs**, not one five-of-five suite. The synthetic UTF-8 file goes through the real asynchronous importer and mounted Learn editor, survives sheet reopen and app relaunch, and remains cleared after a further relaunch. It does not test native screen capture, video OCR or a recorded-morning model proposal.

The updated ordinary app is installed. In a subsequent owner-confirmed 40.3-second recording on `51b1de9`, the ordinary explicitly shared recording source produced 21 sampled frames, 5,357 saved observation characters and a visible unapproved two-step draft. This establishes capture → OCR → persistence → draft display for that one clip, independently of the synthetic import test. The ordinary app was subsequently terminated/relaunched; reopening the latest observation showed readable OCR text and Clear this observation. Thus actual recording text survived relaunch; no real-recording clear operation is claimed. Raw text, workspace contents and screenshots stay private; only summary counts are reported here.

The draft incorrectly promoted Morning Operator setup/marketing content into morning habits. The real clip therefore passed ingestion/display and failed meaningful habit interpretation. No exact action recognition, actual routine quality or repeated-morning reliability is established. Apple’s sharing panel was still visible at 00:07. The subsequent targeted evidence guard has 11 passing focused deterministic checks and a successful rejection replay of the same saved input. That is not a real-model abstention result or proof of general habit accuracy; [#23](https://github.com/gibouu/morning-operator/issues/23) is the controlled ground-truth gate.

The full package run before the final two evidence regressions passed 73 cases with two intentional opt-in model skips (30 Core; 45 Apple including two skips). The final focused evidence-policy suite then passed 11/11; it is a separate result, not a newly completed full-package run. The direct real-model negative test did not execute. This supersedes neither the earlier 64/1 result nor its recovery chronology; they describe different source revisions.

The latest combined phone result is `.build/iphone-tomorrow-ready.xcresult`: six fixture journeys passed in 186.709 seconds and the positive real-model test passed in 30.360 seconds. The negative guard encountered XCTest's 128-character identifier-query limit before its intended assertion. The test now uses an exact-label predicate; `.build/iphone-evidence-guard-final.xcresult` passed 1/1 in 28.972 seconds. All eight intended phone checks therefore passed across the combined run and targeted rerun, not as one eight-of-eight suite. No application-code change was needed for this harness correction. Deterministic rejection of setup-only input before inference must not be described as the model learning to abstain.

A subsequent bounded tethered WhatsApp check passed 1/1 in 9.612 seconds at `.build/iphone-whatsapp-capture-check.xcresult`. The ordinary Chats screen was readable in its screenshot; no conversation was selected and no message was sent. This does not validate native ScreenCaptureKit capture, individual chat content or protected media. Separately, a local replay of the earlier real observation revealed that app Review text still passed the initial evidence filter. The additional public-copy-only regression and correction are complete: 11 focused policy tests passed. A deterministic replay of the actual saved 5,357-character observation now rejects it as insufficient activity evidence, leaving the original text unchanged. This did not invoke the model; no real-model abstention or general semantic-quality pass is claimed.

The phone greeting-preview check observed actual `AVSpeechSynthesizer` delegate progression from speaking to idle in 14.912 seconds, with no skip after correcting the test opt-in configuration. Its initial skipped attempt did not establish playback. This verifies a system greeting preview, not that a person heard it, a complete spoken morning, cross-app narration or HomePod output; the owner reported not hearing it or not listening, so audibility remains unconfirmed.

### Final phone handoff

Source `8a640ea` built for testing, installed and launched in the ordinary app without fixture arguments. Two final targeted checks passed together in 98.322 seconds, with no skips: observation import → correction → Done → relaunch → exact edited text → clear → relaunch (75.178 seconds), and a real system-spoken synthetic routine step advancing through the production executor to the next manual item (23.144 seconds). The latter is sample speech/progression, not a complete personalized recap, external message reading, or listener-confirmed sound. Screenshots were inspected locally. Results: `.build/iphone-final-trial-checks.xcresult`.

The ordinary workspace was checked after final installation: all 5,357 saved observation characters remained identical and the existing routine remained unapproved. Tests did not replace it with fixture content. That old incorrect draft was not retroactively changed by the evidence filter. Fresh native recording after these final changes, long-duration capture, save-failure injection, background-edit saving and general semantic accuracy remain separate checks. The tested correction path closed Learn with Done.

Observation edits now use a live store binding and save on editing/lifecycle boundaries; failed saves retain the in-memory correction and show Retry. An import or analysis first attempts to save pending edits. This fixes the discovered loss of manual corrections after closing Learn/relaunch, without writing the workspace on every keystroke.

## Next checks

1. Broaden the passed local-model example with more deliberately chosen observations and review the proposed steps and source quotations. Keep unavailable-model skips distinct from inference failures and passed generation.
2. Broaden validation of the targeted evidence guard: distinguish setup/marketing text from evidenced behavior, and use #23’s known-action recordings to measure supported claims, misses and unknowns. Recheck the earlier blank-Learn path and broader recording lifecycle: app-sheet versus system-panel dismissal, limits, interruption, relaunch, unavailable-model fallback and Retry/Discard. Preserve the narrow successful clip and earlier failures as separate results; sparse frames do not establish full app usage.
3. Confirm audible output of the tested greeting/sample step, verify saved voice selection after relaunch, and test speech cancellation/interruption. Include the known idle-route stale “Resume” status and the SDK warning about synchronous audio-session activation on the main actor. Verify a real output route to the single available HomePod mini and continuation of the same routine item. See [device setup](DEVICE-SETUP.md).
4. Test Calendar read and one intentionally created reminder/event with the owner's permission. Verify timezone, date, default destination, denial, receipt and uncertain-write recovery behavior against the actual Apple apps.
5. Invoke start/capture through Siri or Shortcuts, review the received text, and verify that unapproved routines and unsaved capture drafts stay under user control.
6. Configure one supported app-transition automation pair and verify discovery, background execution without opening Morning Operator, cold launch, timestamped persistence and Today counts/returns. Test missing/duplicate events separately; no pickup or full-usage claim follows.
7. Extend the bounded device-control proof with reviewed non-destructive targets before attempting a model-driven loop. Keep external-app/account scope explicit.

## Remaining boundaries

No exact count of reels, likes, emails read/replied/discarded, or total cross-app time is established. No ongoing automatic recording, first-pickup detection, historical touch log, continuous command listener, autonomous cross-app action loop, live message-send adapter or multi-day learned habit aggregation is claimed. [Issue #21](https://github.com/gibouu/morning-operator/issues/21) tracks evidence-based daily/weekly analytics; [issue #20](https://github.com/gibouu/morning-operator/issues/20) tracks voice choice and the separate consented-custom-voice investigation.

Raw HomePod microphone access, proactive room detection, automatic speaker transfer and two-speaker continuation remain unproved. HealthKit, Screen Time, Live Activities, billing and public distribution remain separate work.

Use the [test report template](TEST-REPORT-TEMPLATE.md) to record each device/software version, scoped source, observed result and evidence location. Keep raw personal recordings and device logs local; share only reviewed evidence. Regenerating the Xcode project does not itself compile, sign, install or test it.


</details>
