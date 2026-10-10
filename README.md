# MORE

**Less phone handling. More of the morning you enjoy.**

MORE — MOrning REcap — is an iPhone prototype that turns an explicitly shared glimpse of your morning into a routine you can review, adjust and run. Useful rituals—including messages, browsing and a game of chess—belong in the plan.

[V2 design](docs/V2-DESIGN.md) · [Get started](docs/ONBOARDING.md) · [Documentation](docs/README.md) · [Roadmap](docs/ROADMAP.md)

```mermaid
flowchart LR
    A["Record or import"] --> B["Local evidence"]
    B --> C["Apple model proposes or abstains"]
    C --> D["You review and approve"]
    D --> E["Run supported steps"]
    E --> F["Review your morning"]
```

## Two tabs, a quieter morning

This branch, `codex/more-quiet-morning`, introduces the V2 interface. It is **in progress and not yet installed on the owner's phone**.

| Experience | V2 source behavior |
|---|---|
| Morning | A date, a compact routine and a clear start. Up to ten moments fit at default portrait size in the tested simulator; larger text and short layouts have a scrolling fallback. Pause and Stop remain reachable. |
| Review | Open a seven-day period and its days; revisit dated observations and their originals, edit and approve your routine, find saved thoughts, and open settings or connections. There is no separate Notes tab. |
| Review what was observed | Open sampled moments and their original text, follow exact quotations, and see which visual labels appeared on distinct days. Missing days, unresolved samples and different origins/time zones stay separate. [Observed mornings](docs/OBSERVED-MORNINGS.md). |
| Learn across mornings | Choose up to five dated observations in Review, inspect exact supporting quotations, and approve a separately saved update. Your current routine remains ready during this review. Explicit keep/exclude/timing choices survive later suggestions and can be cleared in Review. [Learning flow](docs/ROUTINE-LEARNING.md). |
| Show your morning | Explicit iOS 27 screen recording, or selected text/image/video import. Local extraction saves separate observations with original text and corrections; identical file imports keep the existing entry. Unknown recording dates stay explicit. Screen recognition and routine suggestions are separate explicit actions; suggestions stay pending until approval. Manual setup also works. |
| Prepare your day | Select calendars and an optional city in Review → Settings → Your day. One sourced recap supplies the visible text and speech; adding it to the routine creates a draft to approve. [Your day](docs/YOUR-DAY.md). |
| Hear a saved moment | Choose a dated excerpt in Review, hear its exact preview and add it to an unapproved draft. Source changes or deletion block replay. [Saved moments](docs/SAVED-MOMENTS.md). |
| Move through it | Supported spoken/calendar/briefing operations advance after completion. Other activities wait for you. A saved completed morning offers Speak, Write or Not now. |
| Begin with an invitation | Set one future notification in Review → Settings. Its tap or a foreground Start intent routes into an approved morning, waiting for a ready app. Physical delivery and Siri invocation remain unverified. [Morning entry](docs/MORNING-ENTRY.md). |
| Keep your place | Optional Lock Screen and Dynamic Island progress shows generic categories and passed moments. MORE pauses when you leave; tapping the activity reveals the same morning. Personal text stays in the app. [Lock Screen guide](docs/LIVE-ACTIVITY.md). |
| Speak a command | An explicit on-device English/French turn supports next, pause, resume, skip, repeat and stop. Entry/cancel behavior is tested; real microphone recognition remains a device check. [Voice guide](docs/VOICE.md). |
| Control what stays | Review → Settings → Privacy explains saved copies, disables activity logging and removes local data. Removal resumes after interruption; originals and Apple-app items remain separate. [Privacy guide](docs/PRIVACY.md). |
| Keep what matters | Speak one English/French reflection or write it, edit the words, then explicitly save. The completion invitation never starts the microphone. Review reminder/calendar requests before an optional save to the corresponding Apple app. This is bounded dictation, not an open conversation. |

Review measures **routine runs** and shows source-linked appearances in sampled observations. It does not yet measure complete phone usage or learned app habits. Optional configured Shortcuts log selected app entries/returns with incomplete coverage. [The design contract](docs/V2-DESIGN.md) explains the layout, native controls and metric boundaries.

## Where it stands

**Current V2 source: `e150bfc`.** Saved observations can now supply an explicitly selected, dated spoken moment. Source edits or deletion block replay; samples remain separate from personal history even when kept in later routines. The Morning page stays compact.

| Verified development behavior | Evidence |
|---|---|
| Saved-moment narration | **79 focused shared checks and 2/2 final native simulator journeys passed.** Exact preview, approval/persistence, synthesis-driven progression and deleted-source refusal. This proves native callbacks and app behavior, not listener audibility. |
| Recording reliability | Earlier **69 focused checks and 2/2 recovery journeys passed** for actual fixture-video OCR and retained metadata. The new callback-ordering policy also has deterministic coverage. Real iPhone callback order remains unverified. |
| Compact experience | Earlier no-scroll Morning, reviewed learning, Calendar/Weather, Live Activity, portable-file and local-forgetting checks keep their separate results in [verification](docs/PHASE-ONE.md). |
| iPhone build | Simulator and unsigned generic iPhone builds pass. Signing still needs the Xcode developer account and a profile with WeatherKit. V2 has not been installed on the phone. |

**Recognition accuracy remains unproven.** The latest Mac model preflight returned `modelNotReady`; the earlier simulator backend rejected inference. Physical-device recognition remains unverified for V2. Synthetic suggestions test the app's review flow, not model quality, capture or audio. [Verification](docs/PHASE-ONE.md) preserves actual runs, earlier failures and corrected reruns.

**Installed phone baseline: `8a640ea`.** The earlier signed app passed synthetic phone journeys and a separate real on-device model example. One short real recording reached saved OCR and a visible draft, but that draft mistook setup text for habits. Targeted deterministic guards reject the known input; broad habit accuracy is still open. V2 has not replaced this phone build.

Observed-habit averages, ongoing adaptation, first-use/alarm opportunities and narrated cross-app actions remain [planned work](docs/ROADMAP.md). Physical V2, actual microphone/Siri, HomePod and listener-confirmed speech quality need their own checks. The owner has not confirmed hearing the earlier phone greeting.

## Build on your iPhone

The app targets iOS 26 or later; native recording needs iOS 27. Use full Xcode on the development Mac, your own signing team and a paired phone. The observed physical setup is Xcode 27 with iOS 27.0.1.

```sh
./scripts/check-environment.sh
open MorningOperator.xcodeproj
```

Select the **MorningOperator** target and your phone, then build/run the intended branch. Shared package checks run on the Mac with `./scripts/test.sh`; add `--with-model` only when deliberately testing the available local model. See [onboarding](docs/ONBOARDING.md) for setup and [device checks](docs/DEVICE-SETUP.md) for reproducible verification. The [short morning trial checklist](docs/DEVICE-SETUP.md#tomorrow-morning-checklist) describes the installed baseline; use the V2 contract for this branch's navigation.

The iPhone is the sole active product. The Mac is the development/test machine and optional tethered controller; no separate Mac app is required. The repository, Xcode target and bundle identity retain Morning Operator naming.

## Your data and the model

Extraction and Foundation Models inference run locally. Optional city searches and current weather use Apple Maps and Apple Weather network services; only selected city/calendar settings persist, while recap facts stay in memory. There is no cloud-model fallback, model fine-tuning, billing or research-data upload pipeline. Saved routines, explicit routine choices, the observation archive with original/corrected text and ordered video samples, thoughts and local activity logs have different lifecycles; a finalized app-owned clip can remain for recovery until its extracted text is saved or the person discards it. Review [what is retained and what each clear control removes](docs/PRIVACY.md). Full forgetting removes the app-owned copies and leaves future activity logging off until explicitly enabled; automatic age-based expiry remains future work.

A later, separately opted-in mobile-agent research dataset is a [feasibility question](https://github.com/gibouu/morning-operator/issues/24), not current collection behavior.

## Explore the project

| Read | For |
|---|---|
| [Documentation hub](docs/README.md) | Find the right guide quickly |
| [V2 design contract](docs/V2-DESIGN.md) | Morning/Review, completion capture, native glass and honest metrics |
| [Your day](docs/YOUR-DAY.md) | Calendar/city selection, prepared speech, freshness and source privacy |
| [Saved moments](docs/SAVED-MOMENTS.md) | Exact historical excerpts, native speech, approval and changed-source refusal |
| [Morning entry](docs/MORNING-ENTRY.md) | One-time invitations, foreground Start, permissions and delayed-entry fallback |
| [Architecture](docs/ARCHITECTURE.md) | Components, states, data flows, model boundaries and Apple integrations |
| [Recording benchmark](docs/OBSERVATION-BENCHMARK.md) | Reproduce the controlled cross-app capture and inspect its measured limits |
| [Routine learning](docs/ROUTINE-LEARNING.md) | Saved mornings, exact quotations, pending proposals and approval |
| [Privacy & local data](docs/PRIVACY.md) | Inventory, full forget, recovery, external copies and unfinished expiry work |
| [Routine files](docs/ROUTINE-FILES.md) | Review a portable plan before saving or importing it; notes stay out by default |
| [Observation plan](docs/OBSERVATION-PLAN.md) | Consent, evidence, cycles, unknowns and multi-day learning |
| [Verified phone results](docs/PHASE-ONE.md) | Actual physical device/build/test evidence and open checks |
| [Roadmap and issues](docs/ROADMAP.md) | The next product slices and collaboration plan |
