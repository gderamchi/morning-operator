# Morning Operator

A personal Apple-native prototype for learning a morning routine, reviewing it, and moving through it with less phone handling.

The iPhone is the sole active product. Its signed app has built, installed and launched on iOS 27.0.1; the separate native Mac app has been removed. The Mac remains the development/test machine and optional tethered controller. Four synthetic phone UI checks, one bounded external-app navigation and actual on-phone model generation have passed. The baseline `b5914db` full package run passed **53 tests** with **1 unavailable-model skip**, and its four phone fixture journeys passed. A later working-tree package run passed **64 tests** with **1 intentional model opt-in skip**, before the latest background recording handoff fix. New recording UX, retained observation text and app-transition logging need their own device verification; see [verification and remaining checks](docs/PHASE-ONE.md), including the earlier unsuccessful recording test and the owner’s subsequent empty Learn field despite an Observation loaded banner. Recording-to-visible-observation success remains unresolved.

## Working together

Start with [onboarding](docs/ONBOARDING.md), then use the [roadmap](docs/ROADMAP.md), [GitHub issues](https://github.com/gibouu/morning-operator/issues), and [test report template](docs/TEST-REPORT-TEMPLATE.md). The original private PRD stays local.

## Try the app

The iPhone app requires iOS 26 or later; in-app screen recording requires iOS 27. Use a compatible Mac with full Xcode to build/run on the phone and run shared package tests. The observed toolchain is Xcode 27. No separate Mac app, third-party runtime packages or cloud account is required.

For the iPhone:

```sh
./scripts/check-environment.sh
open MorningOperator.xcodeproj
```

Choose your own development team and paired, unlocked iPhone in Xcode. The checked-in project can be opened directly; after source additions, regenerate it with `./scripts/generate-project.sh` if XcodeGen is installed. See [device setup](docs/DEVICE-SETUP.md) for signing, explicit device selection and test commands.

1. Use **Learn & refine → Show us your morning** to explicitly record a short segment on iOS 27 or choose an existing observation. The revised native flow processes a finalized recording when the app is foreground and idle, then proposes a draft if the local model is available. A sample and manual setup remain available.
2. Review and edit the steps, then approve. Editing an approved routine creates a new draft; the previous approved version can be restored.
3. Start your morning. Hands-free mode advances supported spoken steps after synthesis finishes. Interactive rituals wait for **Next**; pause, resume, skip and stop remain available.
4. Use **Notes** for a thought or dream. Reminder/calendar requests can stay local or be saved to the chosen Apple app after reviewing the text and time.
5. Use **Settings** to connect Calendar, choose a built-in voice and preview speech. On iPhone, the system audio picker lets you choose an available output.

## Implemented features

| Area | Current behavior |
|---|---|
| Native interface | Morning, Review and Notes tabs; timeline, day navigation, Learn and Settings sheets |
| Routines and recovery | Editable versions, explicit approval, pinned run state, atomic local saves, interrupted runs reopen paused |
| Learning | Notes/images/video → bounded Vision OCR → editable Foundation Models proposal with source-quote validation; selected imports use Suggest a routine, while finalized native recordings can propose automatically |
| Recording | Revised iOS 27 screen-only flow: explicit picker, 5/10/20/30-minute choice, compact Stop/status, foreground processing and unapproved draft; new flow not yet verified |
| Supported automatic steps | Read a step aloud or query/read today's authorized Calendar; completion callbacks advance the run, with cancellation and duplicate-callback protection |
| Notes and Apple apps | Local thoughts/dreams; reviewed EventKit reminder/event creation with durable pending-write tracking and receipts |
| Siri and Shortcuts | Foreground start/capture intents; new background Log an app transition action for manually configured Instagram/TikTok/Snapchat automations; discovery and delivery still need device verification |
| Audio | Built-in voice selection and preview, speech pause/resume/stop, iOS route-loss/interruption handling and system output picker |
| Review | Local run history and seven-day summaries; new Today card for recorded app entries/returns, limited to configured automations and awaiting verification |
| Development harness | Separate XCTest target for synthetic journeys, Settings navigation and opt-in external-app capture |

“Current behavior” describes source implementation. An initial revised iPhone build-for-testing succeeded and nine focused transition checks passed. The final iPhone build-for-testing succeeded and two recording-recovery checks passed again after the latest metadata change. End-to-end recording/Shortcuts device journeys remain pending. Closing the app-owned recording sheets is implemented; automatic dismissal of Apple’s system sharing panel remains unverified.

Apple Intelligence must be enabled and its local model ready for model analysis. Unavailable models produce a clear status; sample/manual routines and local notes remain usable. There is no silent cloud-model fallback.

Optional app-transition logging records callbacks from the automations the person configures. These entries and returns are separate from phone pickups, precise usage duration, reels, likes or emails read/replied/discarded. The recording-to-analytics pipeline remains [issue #21](https://github.com/gibouu/morning-operator/issues/21); see the [observation plan](docs/OBSERVATION-PLAN.md) for sources, coverage and unknown values.

Continuous voice-command listening, autonomous cross-app control, email sending, multi-day habit learning, automatic recording schedules, first-use triggers, HealthKit, Screen Time data access/shields, Live Activities and proactive HomePod handoff remain future work. The separate development test runner does not grant the ordinary app continuous control of other apps.

## Tests

```sh
./scripts/test.sh
```

Add `--with-model` to attempt the optional real Foundation Models integration check. An unavailable model is a skip, not a successful inference. The script supports the selected Apple toolchain and keeps local build/cache files under `.build/testing*`; device UI tests use XCTest through full Xcode. Current pass/fail/skip evidence and unrun hardware checks are in [PHASE-ONE.md](docs/PHASE-ONE.md).

## Local data

The iPhone saves its workspace as `workspace.json` inside its app container; development package tests run on the Mac. This includes routines, run state/history, saved notes, write receipts, voice preferences and the latest extracted observation text/source. App-transition callbacks use a separate local `app-transitions.json` journal. `MORNING_OPERATOR_DATA_DIR` overrides the location for development. UI tests use isolated temporary workspaces.

Selected media and OCR/model analysis remain local. **Clear this observation** removes the saved observation text; evidence quotes already attached to saved routines remain. The revised recording recovery contract retains an app-owned raw recording when OCR, cancellation or observation persistence fails, offers Retry/Discard, and removes it after successful extraction persistence or explicit discard. A later model failure does not require retaining the raw video. User-selected originals remain untouched. A single pending recording is retained in the local RecordingRecovery folder and offered again after relaunch; this recovery behavior still needs device verification. Clear observation text and Discard recording are separate controls. The app-activity setup sheet has Clear recorded app activity; disable unwanted automations in Shortcuts to stop future callbacks. Journal export/automatic expiry and device verification of the clear flow remain pending. Review exports before sharing. Apple Calendar/Reminders saves follow those accounts' existing sync settings.

Build outputs, recordings, screenshots/results, signing credentials and the private PRD are excluded from Git. Inspect local test-result media separately from the app's own data.

```text
Sources/MorningCore         Models, state, persistence, history and action journal
Sources/MorningApple        Apple model, media/recording, speech and EventKit adapters
Sources/MorningOperator     SwiftUI app, intents and local store
Tests/                     Swift package tests
UITests/                   Separate personal-device development harness
Configuration/             App metadata and purpose strings
scripts/                   Build, environment, generation and test helpers
docs/                      Setup, verification and roadmap
```
