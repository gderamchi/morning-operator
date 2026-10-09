# Morning Operator

A personal Apple-native prototype for learning a morning routine, reviewing it, and moving through it with less phone handling.

The native Mac app has been exercised, and the signed iPhone app has built, installed and launched on iOS 27.0.1. Three synthetic phone UI checks, one bounded external-app navigation and actual on-phone model generation have passed. The latest recorded package run passed **53 tests**, with **1 real-model test skipped** because the Mac model was not ready. Expanded recovery checks are pending; see [verification and remaining checks](docs/PHASE-ONE.md).

## Working together

Start with [onboarding](docs/ONBOARDING.md), then use the [roadmap](docs/ROADMAP.md), [GitHub issues](https://github.com/gibouu/morning-operator/issues), and [test report template](docs/TEST-REPORT-TEMPLATE.md). The original private PRD stays local.

## Try the app

Requires macOS 26 or later, or iOS 26 or later, with a compatible Apple toolchain. In-app screen recording requires iOS 27. The project currently builds with Xcode 27. No third-party runtime packages or cloud account are required.

For the Mac:

```sh
./scripts/build-mac-app.sh --open
```

The bundle is written to `build/Morning Operator.app`.

For the iPhone:

```sh
./scripts/check-environment.sh
open MorningOperator.xcodeproj
```

Choose your own development team and paired, unlocked iPhone in Xcode. The checked-in project can be opened directly; after source additions, regenerate it with `./scripts/generate-project.sh` if XcodeGen is installed. See [device setup](docs/DEVICE-SETUP.md) for signing, explicit device selection and test commands.

1. Open a clearly labeled sample, build a routine yourself, or use **Learn & refine** to describe your morning or import an observation.
2. Review and edit the steps, then approve. Editing an approved routine creates a new draft; the previous approved version can be restored.
3. Start your morning. Hands-free mode advances supported spoken steps after synthesis finishes. Interactive rituals wait for **Next**; pause, resume, skip and stop remain available.
4. Use **Notes** for a thought or dream. Reminder/calendar requests can stay local or be saved to the chosen Apple app after reviewing the text and time.
5. Use **Settings** to connect Calendar, choose a built-in voice and preview speech. On iPhone, the system audio picker lets you choose an available output.

## Implemented features

| Area | Current behavior |
|---|---|
| Native interface | Morning, Review and Notes tabs; timeline, day navigation, Learn and Settings sheets |
| Routines and recovery | Editable versions, explicit approval, pinned run state, atomic local saves, interrupted runs reopen paused |
| Learning | Reviewed notes/images/video → bounded frame sampling and Vision OCR → Foundation Models proposal with source-quote validation |
| Recording | iOS 27 ScreenCaptureKit picker and explicitly started screen-only recording → temporary local video → reviewed OCR text; compiled, hardware verification pending |
| Supported automatic steps | Read a step aloud or query/read today's authorized Calendar; completion callbacks advance the run, with cancellation and duplicate-callback protection |
| Notes and Apple apps | Local thoughts/dreams; reviewed EventKit reminder/event creation with durable pending-write tracking and receipts |
| Siri and Shortcuts | Foreground start and quick-capture intents; drafts still need approval, and capture text opens for review before saving |
| Audio | Built-in voice selection and preview, speech pause/resume/stop, iOS route-loss/interruption handling and system output picker |
| Review | Local routine-run history and seven-day summaries; unknown measurements and missing days stay unknown |
| Development harness | Separate XCTest target for synthetic journeys, Settings navigation and opt-in external-app capture |

Apple Intelligence must be enabled and its local model ready for model analysis. Unavailable models produce a clear status; sample/manual routines and local notes remain usable. There is no silent cloud-model fallback.

The app does not yet measure exact cross-app usage, reels viewed, likes or emails read/replied/discarded. The evidence data model supports provenance and incomplete coverage, but the real recording-to-analytics pipeline remains [issue #21](https://github.com/gibouu/morning-operator/issues/21). A recording's visible text does not establish every tap, intention or read.

Continuous voice-command listening, autonomous cross-app control, email sending, multi-day habit learning, automatic recording schedules, HealthKit, Screen Time shields, Live Activities and proactive HomePod handoff remain future work. The separate development test runner does not grant the ordinary app continuous control of other apps.

## Tests

```sh
./scripts/test.sh
```

Add `--with-model` to attempt the optional real Foundation Models integration check. An unavailable model is a skip, not a successful inference. The script supports the selected Apple toolchain and keeps local build/cache files under `.build/testing*`; device UI tests use XCTest through full Xcode. Current pass/fail/skip evidence and unrun hardware checks are in [PHASE-ONE.md](docs/PHASE-ONE.md).

## Local data

The Mac app saves the workspace in `~/Library/Application Support/MorningOperator/workspace.json`; iPhone uses its app container. This includes routines, run state/history, saved notes, write receipts and voice preferences. `MORNING_OPERATOR_DATA_DIR` overrides the location for development. UI tests use isolated temporary workspaces.

Selected media and OCR/model analysis remain local. Extracted observation text is temporary UI content; routine details may retain evidence quotes. App-created recording files are removed after extraction; user-selected source files are preserved. Review exports before sharing. Apple Calendar/Reminders saves follow those accounts' existing sync settings.

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
