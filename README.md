# Morning Operator

A personal Apple-native prototype for learning a morning routine, reviewing it, and moving through it with less phone handling.

**Phase 1:** working native Mac app and shared SwiftUI iPhone source, local routine/session logic, Apple intelligence and media ingestion adapters, and a separate Xcode UI-test harness. Physical iPhone automation and HomePod handoff still need their first hardware proof.

## Working together

Start with the [onboarding and smoke-test guide](docs/ONBOARDING.md). Use the [prioritized roadmap](docs/ROADMAP.md), [GitHub issues](https://github.com/gibouu/morning-operator/issues), and [test report template](docs/TEST-REPORT-TEMPLATE.md) to split work and record what actually works. The original private PRD remains local.

## Try the Mac app

Requires macOS 26 or later and a compatible Swift toolchain. No third-party packages or cloud account are required.

```sh
./scripts/build-mac-app.sh --open
```

The app bundle is written to `build/Morning Operator.app`.

1. Choose **Explore a sample** for an explicitly synthetic routine, or **Figure out my morning routine** to supply your own observation.
2. Edit the steps and choose **This feels like me** to approve the routine. While reviewing a new draft, you can restore the previous approved version.
3. Turn on spoken steps if you want, then choose **OK, here we go**. Next, skip, pause, resume and stop operate on the saved session.
4. In **Learn**, import a local video/screenshot/text file or describe your morning. Review the extracted text before asking the local Apple model to propose steps.
5. In **Setup**, test system speech and optionally connect Calendar. The app only reads events, although Apple's permission is full calendar access.

Apple Intelligence must be enabled and its local model available for actual model analysis. Unavailable models produce a clear message; manual/sample routines still work. There is no silent cloud-model fallback.

## iPhone and developer controller

Full Xcode with its iOS platform is required. The app and UI-test bundle are separate targets; XCTest is not embedded in the normal application.

```sh
./scripts/check-environment.sh
./scripts/generate-project.sh
open MorningOperator.xcodeproj
```

Choose your personal development team and the paired iPhone in Xcode. Start with the synthetic fixture suite before trying a selected external app. See [device setup](docs/DEVICE-SETUP.md) for exact commands, required local configuration, and the HomePod experiment.

The driver can capture selected installed apps and exercise a bounded, read-only navigation target. It is not yet a persistent model-driven phone controller. Capturing screenshots in a UI test does not give the ordinary application continuous cross-app access.

## What's included

| Area | Implemented behavior |
|---|---|
| Native UI | Today, Learn and Setup; editable routines, explicit approval, guidance and export |
| Shared core | Codable models, pinned routine versions, session state machine and command deduplication |
| Local persistence | Atomic versioned JSON, recovery checkpoint, portable exports |
| Action journal | Exact/standing approval matching and durable pre-dispatch/unknown-outcome states; no live send adapter |
| Apple intelligence | Real Foundation Models schema-constrained analysis with source-quote validation; no action tools |
| Observation import | Selected local notes/images/video; AVFoundation sampling and Vision OCR; review before generation |
| Audio | AVSpeechSynthesizer output, pause/resume/stop, iOS interruption/route-loss handling |
| Calendar | User-initiated EventKit read and timestamped day snapshot |
| Device tests | Fixture journey, Settings navigation, missing-target refusal and opt-in external-app capture |

Not yet implemented: automatic recording schedules, multi-day habit aggregation, live voice-command input, email sending, autonomous cross-app model loop, HealthKit, Screen Time shields, Live Activities, proactive room detection or automatic HomePod transfer. No private inbox or social account is connected by default.

## Tests and evidence

Core and Apple library checks are Swift package tests; physical iPhone UI tests are a separate verification layer. See [phase-one status](docs/PHASE-ONE.md) for actual results and unrun checks.

```sh
./scripts/test.sh
```

The script uses the selected toolchain's default build engine, explicitly loads its bundled Swift Testing macro plugin when present, and disables the XCTest runner for Command Line Tools compatibility. Build/cache files stay under `.build/testing*`; the local dependency-free package runs with its package sandbox disabled. Add `--with-model` to attempt the optional real Apple model test; an unavailable model is reported as skipped. Device UI tests still use XCTest under full Xcode.

## Local data

The Mac app saves routines and session state in `~/Library/Application Support/MorningOperator/workspace.json`. `MORNING_OPERATOR_DATA_DIR` can override that location for local development. UI-test fixture launches use an isolated temporary directory.

Imported media is read locally and not copied into the repository or uploaded. Extracted text remains in the active UI until the app closes; approved routine details may retain short evidence quotes. Exports can include those quotes, so review them before sharing.

Build outputs, device screenshots/results, local recordings, signing credentials and the original private PRD are ignored by Git. Xcode can create additional test recordings and result bundles: inspect their retention separately from the application's data.

## Layout

```text
Sources/MorningCore         Models, state, persistence, action journal
Sources/MorningApple        Apple inference, OCR/media, speech, calendar
Sources/MorningOperator     Shared SwiftUI app and local store
Tests/                     Swift package invariant/integration tests
UITests/                   Separate personal-device development harness
Configuration/             App metadata and purpose strings
scripts/                   Mac build, project generation, device testing
docs/                      Setup, verification and project decisions
```

This is an early personal-development project. A successful tethered experiment is not a claim that the same control is available to a standalone public iPhone app.
