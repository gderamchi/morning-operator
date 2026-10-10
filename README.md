# MORE

**Less phone handling. More of the morning you enjoy.**

MORE — MOrning REcap — is an iPhone prototype that turns an explicitly shared glimpse of your morning into a routine you can review, adjust and run. Useful rituals—including messages, browsing and a game of chess—belong in the plan.

[V2 design](https://github.com/gibouu/morning-operator/blob/codex/more-quiet-morning/docs/V2-DESIGN.md) · [Get started](https://github.com/gibouu/morning-operator/blob/codex/more-quiet-morning/docs/ONBOARDING.md) · [Documentation](https://github.com/gibouu/morning-operator/blob/codex/more-quiet-morning/docs/README.md) · [Roadmap](https://github.com/gibouu/morning-operator/blob/codex/more-quiet-morning/docs/ROADMAP.md)

```mermaid
flowchart LR
    A["Record or import"] --> B["Local evidence"]
    B --> C["Apple model proposes or abstains"]
    C --> D["You review and approve"]
    D --> E["Run supported steps"]
    E --> F["Review your morning"]
```

## Two tabs, a quieter morning

The development branch `codex/more-quiet-morning` introduces the V2 interface. It is **in progress and not yet installed on the owner's phone**. Review [PR #26](https://github.com/gibouu/morning-operator/pull/26), stacked on [PR #22](https://github.com/gibouu/morning-operator/pull/22). The source code on `main` remains the earlier scaffold; select the development branch when building the current iPhone app.

| Experience | V2 source behavior |
|---|---|
| Morning | A date, a compact routine and a clear start. Up to ten moments fit at default portrait size in the tested simulator; larger text and short layouts have a scrolling fallback. Pause and Stop remain reachable. |
| Review | Open a seven-day period and its days; revisit dated observations and their originals, edit and approve your routine, find saved thoughts, and open settings or connections. There is no separate Notes tab. |
| Review what was observed | Open sampled moments and their original text, follow exact quotations, and see which visual labels appeared on distinct days. Missing days, unresolved samples and different origins/time zones stay separate. [Observed mornings](https://github.com/gibouu/morning-operator/blob/codex/more-quiet-morning/docs/OBSERVED-MORNINGS.md). |
| Learn across mornings | Choose up to five dated observations in Review, inspect exact supporting quotations, and approve a separately saved update. Your current routine remains ready during this review. Explicit keep/exclude/timing choices survive later suggestions and can be cleared in Review. [Learning flow](https://github.com/gibouu/morning-operator/blob/codex/more-quiet-morning/docs/ROUTINE-LEARNING.md). |
| Show your morning | Explicit iOS 27 screen recording, or selected text/image/video import. Local extraction saves separate observations with original text and corrections; identical file imports keep the existing entry. Unknown recording dates stay explicit. Screen recognition and routine suggestions are separate explicit actions; suggestions stay pending until approval. Manual setup also works. |
| Prepare your day | Select calendars and an optional city in Review → Settings → Your day. One sourced recap supplies the visible text and speech; adding it to the routine creates a draft to approve. [Your day](https://github.com/gibouu/morning-operator/blob/codex/more-quiet-morning/docs/YOUR-DAY.md). |
| Move through it | Supported spoken/calendar/briefing operations advance after completion. Other activities wait for you. A saved completed morning offers Speak, Write or Not now. |
| Begin with an invitation | Set one future notification in Review → Settings. Its tap or a foreground Start intent routes into an approved morning, waiting for a ready app. Physical delivery and Siri invocation remain unverified. [Morning entry](https://github.com/gibouu/morning-operator/blob/codex/more-quiet-morning/docs/MORNING-ENTRY.md). |
| Keep your place | Optional Lock Screen and Dynamic Island progress shows generic categories and passed moments. MORE pauses when you leave; tapping the activity reveals the same morning. Personal text stays in the app. [Lock Screen guide](https://github.com/gibouu/morning-operator/blob/codex/more-quiet-morning/docs/LIVE-ACTIVITY.md). |
| Speak a command | An explicit on-device English/French turn supports next, pause, resume, skip, repeat and stop. Entry/cancel behavior is tested; real microphone recognition remains a device check. [Voice guide](https://github.com/gibouu/morning-operator/blob/codex/more-quiet-morning/docs/VOICE.md). |
| Control what stays | Review → Settings → Privacy explains saved copies, disables activity logging and removes local data. Removal resumes after interruption; originals and Apple-app items remain separate. [Privacy guide](https://github.com/gibouu/morning-operator/blob/codex/more-quiet-morning/docs/PRIVACY.md). |
| Keep what matters | Speak one English/French reflection or write it, edit the words, then explicitly save. The completion invitation never starts the microphone. Review reminder/calendar requests before an optional save to the corresponding Apple app. This is bounded dictation, not an open conversation. |

Review measures **routine runs** and shows source-linked appearances in sampled observations. It does not yet measure complete phone usage or learned app habits. Optional configured Shortcuts log selected app entries/returns with incomplete coverage. [The design contract](https://github.com/gibouu/morning-operator/blob/codex/more-quiet-morning/docs/V2-DESIGN.md) explains the layout, native controls and metric boundaries.

## Where it stands

**Current V2 source: `0d7171a`.** Recordings now keep their original start independently of the day you assign, preserve native frame timing, and stay recoverable when their saved information cannot be read. Optional details live in Review; the Morning page stays compact. The checks below describe their actual scope.

| Verified development behavior | Evidence |
|---|---|
| Recording reliability | **69 focused tests and 2/2 final simulator journeys passed.** Actual fixture-video OCR, preserved start after removing its review date, and damaged metadata retained for recovery. All 24 saved frame timestamps match that movie’s encoded index. These are not physical capture or habit-accuracy results. |
| Earlier observed-morning review | **13 focused shared checks passed.** Both new simulator journeys passed across scoped runs: weekly quotation → source (26.551s), and correction → relaunch → preserved originals (63.775s). Two no-scroll Morning regressions also passed. Earlier failed assertions and the interrupted diagnostics phase remain documented. |
| New Live Activity logic | **20 focused tests passed (21 parameterized cases).** They cover payload privacy, late results, explicit retry, dismissal, stale revalidation and cleanup. The earlier full-suite result remains separate below. |
| Native Live Activity | **4/4 lifecycle journeys passed**, plus actual expanded Island → tap → same paused morning. The final stale-display check passed after Apple marked the content out of date. No physical-phone claim. |
| Shared logic, storage and Apple adapters | **360 checks passed across a full run and one targeted retry; six optional checks skipped.** All 49 new briefing checks passed. The full run retained one native OCR failure after disk cleanup; its isolated retry passed. Earlier failures remain documented. |
| App builds | Final simulator and unsigned generic iPhone compilation passed. Signing is blocked: Xcode reports no developer account, and the cached wildcard profile lacks WeatherKit. No signed candidate or new phone installation is claimed. |
| New recap and compact layout | **2/2 recap journeys passed** in 152.807s: selected sources → prepared text → unapproved draft → relaunch, and preview refresh preserving an active moment. Alongside the earlier three checks, all five intended journeys passed across the two runs. |
| Local forgetting | The cancel/preserve/forget/relaunch journey passed again with a synthetic briefing-settings payload; host inspection confirmed its removal and unchanged external-copy sentinels. Earlier 3/3 privacy journeys retain their separate results. Physical recording shutdown remains unverified. |
| Routine files | Actual **On My iPhone Save → select the same file → plan-only preview → manual unapproved draft → relaunch** passed again in 137.872 seconds after stale-picker protection was added. Earlier format, preview and malformed-file checks retain their separate results. |
| Spoken completion | All three synthetic completion journeys and the existing command-entry check passed in the final scoped run. They cover cancel/background rejection, editable review, explicit Save and relaunch. They do not use the microphone; an editor keyboard-layout warning remains under investigation. |
| Earlier learning and choices | Five preference/recovery journeys and five unified-learning journeys have passing results across their own scoped runs. Initial failures and corrected reruns remain in the verification record. |
| Earlier controlled recording | Two separate native fixture apps, two verified scrolls and a synthetic message detail; the actual 97-second video reached saved text and survived relaunch. These checks do not establish detected scroll counts or reading intent. [Benchmark](https://github.com/gibouu/morning-operator/blob/codex/more-quiet-morning/docs/OBSERVATION-BENCHMARK.md). |

**Recognition accuracy remains unproven.** The latest Mac model preflight returned `modelNotReady`; the earlier simulator backend rejected inference. Physical-device recognition remains unverified for V2. Synthetic suggestions test the app's review flow, not model quality, capture or audio. [Verification](https://github.com/gibouu/morning-operator/blob/codex/more-quiet-morning/docs/PHASE-ONE.md) preserves actual runs, earlier failures and corrected reruns.

**Installed phone baseline: `8a640ea`.** The earlier signed app passed synthetic phone journeys and a separate real on-device model example. One short real recording reached saved OCR and a visible draft, but that draft mistook setup text for habits. Targeted deterministic guards reject the known input; broad habit accuracy is still open. V2 has not replaced this phone build.

Observed-habit averages, ongoing adaptation, first-use/alarm opportunities and narrated cross-app actions remain [planned work](https://github.com/gibouu/morning-operator/blob/codex/more-quiet-morning/docs/ROADMAP.md). Physical V2, actual microphone/Siri, HomePod and listener-confirmed speech quality need their own checks. The owner has not confirmed hearing the earlier phone greeting.

## Build on your iPhone

The app targets iOS 26 or later; native recording needs iOS 27. Use full Xcode on the development Mac, your own signing team and a paired phone. The observed physical setup is Xcode 27 with iOS 27.0.1.

```sh
./scripts/check-environment.sh
open MorningOperator.xcodeproj
```

Select the **MorningOperator** target and your phone, then build/run the intended branch. Shared package checks run on the Mac with `./scripts/test.sh`; add `--with-model` only when deliberately testing the available local model. See [onboarding](https://github.com/gibouu/morning-operator/blob/codex/more-quiet-morning/docs/ONBOARDING.md) for setup and [device checks](https://github.com/gibouu/morning-operator/blob/codex/more-quiet-morning/docs/DEVICE-SETUP.md) for reproducible verification. The [short morning trial checklist](https://github.com/gibouu/morning-operator/blob/codex/more-quiet-morning/docs/DEVICE-SETUP.md#tomorrow-morning-checklist) describes the installed baseline; use the V2 contract for this branch's navigation.

The iPhone is the sole active product. The Mac is the development/test machine and optional tethered controller; no separate Mac app is required. The repository, Xcode target and bundle identity retain Morning Operator naming.

## Your data and the model

Extraction and Foundation Models inference run locally. Optional city searches and current weather use Apple Maps and Apple Weather network services; only selected city/calendar settings persist, while recap facts stay in memory. There is no cloud-model fallback, model fine-tuning, billing or research-data upload pipeline. Saved routines, explicit routine choices, the observation archive with original/corrected text and ordered video samples, thoughts and local activity logs have different lifecycles; a finalized app-owned clip can remain for recovery until its extracted text is saved or the person discards it. Review [what is retained and what each clear control removes](https://github.com/gibouu/morning-operator/blob/codex/more-quiet-morning/docs/PRIVACY.md). Full forgetting removes the app-owned copies and leaves future activity logging off until explicitly enabled; automatic age-based expiry remains future work.

A later, separately opted-in mobile-agent research dataset is a [feasibility question](https://github.com/gibouu/morning-operator/issues/24), not current collection behavior.

## Explore the project

| Read | For |
|---|---|
| [Documentation hub](https://github.com/gibouu/morning-operator/blob/codex/more-quiet-morning/docs/README.md) | Find the right guide quickly |
| [V2 design contract](https://github.com/gibouu/morning-operator/blob/codex/more-quiet-morning/docs/V2-DESIGN.md) | Morning/Review, completion capture, native glass and honest metrics |
| [Your day](https://github.com/gibouu/morning-operator/blob/codex/more-quiet-morning/docs/YOUR-DAY.md) | Calendar/city selection, prepared speech, freshness and source privacy |
| [Morning entry](https://github.com/gibouu/morning-operator/blob/codex/more-quiet-morning/docs/MORNING-ENTRY.md) | One-time invitations, foreground Start, permissions and delayed-entry fallback |
| [Architecture](https://github.com/gibouu/morning-operator/blob/codex/more-quiet-morning/docs/ARCHITECTURE.md) | Components, states, data flows, model boundaries and Apple integrations |
| [Recording benchmark](https://github.com/gibouu/morning-operator/blob/codex/more-quiet-morning/docs/OBSERVATION-BENCHMARK.md) | Reproduce the controlled cross-app capture and inspect its measured limits |
| [Routine learning](https://github.com/gibouu/morning-operator/blob/codex/more-quiet-morning/docs/ROUTINE-LEARNING.md) | Saved mornings, exact quotations, pending proposals and approval |
| [Privacy & local data](https://github.com/gibouu/morning-operator/blob/codex/more-quiet-morning/docs/PRIVACY.md) | Inventory, full forget, recovery, external copies and unfinished expiry work |
| [Routine files](https://github.com/gibouu/morning-operator/blob/codex/more-quiet-morning/docs/ROUTINE-FILES.md) | Review a portable plan before saving or importing it; notes stay out by default |
| [Observation plan](https://github.com/gibouu/morning-operator/blob/codex/more-quiet-morning/docs/OBSERVATION-PLAN.md) | Consent, evidence, cycles, unknowns and multi-day learning |
| [Verified phone results](https://github.com/gibouu/morning-operator/blob/codex/more-quiet-morning/docs/PHASE-ONE.md) | Actual physical device/build/test evidence and open checks |
| [Roadmap and issues](https://github.com/gibouu/morning-operator/blob/codex/more-quiet-morning/docs/ROADMAP.md) | The next product slices and collaboration plan |
