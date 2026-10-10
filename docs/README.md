# MORE documentation

MORE is a native iPhone app. The Mac is its development and test environment. The repository and Xcode project retain the Morning Operator name.

**Current app source and installed phone build: `0f94f6d`, on `codex/more-quiet-morning`.** The compact home uses small system text, relative plan offsets, tappable/reorderable glass tiles, a native corner popover, and a direct one-time invitation editor. Observed-first Review, exact-source corrections/narration and batched long-text learning remain implemented. Calendar/Weather preparation and optional Lock Screen progress retain their own verification.

**Testing on your phone:** signed `0f94f6d` was installed and launched as the ordinary app on the owner's iPhone on 10 October 2026, preserving the user store. The owner walkthrough, new physical capture, connected-service, model and listener checks remain separate.

**Verification:** the compact revision has **14/14** native journey passes; the final accessibility-state refinement has **4/4** regression passes plus **1/1** at largest text. All finalized cleanly with no skips. Focused evidence policy **22/22** and voice grammar **10/10** pass. The changing-content benchmark has one actual capture/OCR run; its semantic digest stage remains blocked. Earlier learning and integration results remain separately recorded in [verification](PHASE-ONE.md).

**Start here:** [Teammate handoff](HANDOFF.md) · [Repeatable digest protocol](DIGEST-TEST-PROTOCOL.md). **Direction:** [Low-effort morning experience](PRODUCT-DIRECTION.md) · [Business hypotheses](BUSINESS.md) · [Long-recording test plan](LONG-RECORDING-TEST-PLAN.md).

## Use the app

| Guide | What it answers |
|---|---|
| [Observed mornings](OBSERVED-MORNINGS.md) | Inspect sampled screens, exact source quotations and distinct-day labels without inventing usage totals |
| [Learn from saved mornings](ROUTINE-LEARNING.md) | Select comparable sources, inspect quotations, manage keep/exclude/timing choices, and approve or discard a pending update |
| [Privacy & local data](PRIVACY.md) | Review stored categories, disable activity logging and remove local data with recoverable cleanup |
| [Portable routine files](ROUTINE-FILES.md) | Preview a plan-only export, choose whether to include notes, and review an imported draft |
| [Morning entry](MORNING-ENTRY.md) | Schedule one invitation, enter through Start, and understand permissions, expiry and manual fallback |
| [Lock Screen progress](LIVE-ACTIVITY.md) | Opt into a generic Live Activity, understand its paused/stale state, and return to Morning without starting a run |
| [Your day](YOUR-DAY.md) | Select calendars and a city, preview a sourced recap, and add it to an approved morning |
| [Saved moments](SAVED-MOMENTS.md) | Select an exact historical excerpt, preview it and hear it in an approved routine |
| [Voice commands](VOICE.md) | Use an explicit listening turn; understand commands, audio handoff and outstanding device checks |
| [V2 design contract](V2-DESIGN.md) | Morning and Review, explicit spoken/typed completion capture, and accessible layout fallbacks |
| [Short morning trial checklist](DEVICE-SETUP.md#tomorrow-morning-checklist) | The recording checks and recovery boundaries retained from the earlier physical trial |
| [Onboarding](ONBOARDING.md) | Current sunrise/date/home navigation, plus how either collaborator builds and installs the selected source branch |
| [Device setup](DEVICE-SETUP.md) | Signing, paired-device tests, recording, Shortcuts and the separate HomePod experiment |

## Understand and build it

| Guide | What it contains |
|---|---|
| [Architecture](ARCHITECTURE.md) | System diagrams, runtime states, persistence, model inference and effect boundaries |
| [Business hypotheses](BUSINESS.md) | Customer jobs, proposed subscriptions, experiment measures and independent research feasibility |
| [Data retention today](ARCHITECTURE.md#data-retention-today) | What exists on disk, why it remains and what current controls remove |
| [Apple capabilities](CAPABILITIES.md) | Framework-specific behavior, permission requirements and official documentation |
| [Observation plan](OBSERVATION-PLAN.md) | Learning windows, evidence quality, app-return cycles, coverage and research hypotheses |
| [Observation metrics](OBSERVATION-METRICS.md) | Ordered samples and text positions, bounded model evidence, unknowns, trace mathematics and day denominators |
| [Roadmap](ROADMAP.md) | Priorities, dependencies and GitHub issues |
| [V2 issue #25](https://github.com/gibouu/morning-operator/issues/25) | Design acceptance criteria and the owner walkthrough still required |

## Assess the evidence

| Guide | How to use it |
|---|---|
| [Physical verification record](PHASE-ONE.md) | Read source, device, scope and outcome before carrying a phone result over to new code |
| [Digest test protocol](DIGEST-TEST-PROTOCOL.md) | Three fresh seeds, actual inference, exact source facts, speech and independent multi-day evidence |
| [Digest scorer contract](../Benchmarks/morning-digest-contract.md) | Versioned facts, withheld truth, runtime evidence and separate transcript checks; the digest model adapter remains unfinished |
| [Teammate handoff](HANDOFF.md) | Bounded next tasks, failure history and current issue coverage |
| [Test report template](TEST-REPORT-TEMPLATE.md) | Record a pass, failure, skip or environment block without uploading personal artifacts |
| [Recording benchmark](OBSERVATION-BENCHMARK.md) | Reproduce real capture of two native fixture apps; distinguish extraction success, known actions and failed model inference |
| [Controlled benchmark #23](https://github.com/gibouu/morning-operator/issues/23) | Compare known phone actions and visible evidence against extraction and model claims |

**Implemented** means the source contains the behavior. **Verified** means a specified check actually passed. **Planned** means further design or implementation remains. A simulator navigation pass is not a physical recording test; a passing synthetic import is not native capture; successful capture is not proof that proposed habits are correct.

V2 Review opens periods and days and preserves observations across imports. Its new explicit source-selection flow can prepare a reviewed update without replacing the current routine, but its real averages still describe routine runs. Unknown observed dates remain in Date needed until explicitly assigned. Observed-habit averages and ongoing adaptive profiles remain planned. Configured-app callbacks have separate, partial coverage; missing observations stay unknown. Saved thoughts live under Review. Completion offers Speak, Write or Not now; spoken words stay in memory until explicitly saved from review, with no retained audio file or open conversation.

The private source PRD, personal recordings, OCR, workspace snapshots and device-test media stay outside these shared guides. [Research-data feasibility #24](https://github.com/gibouu/morning-operator/issues/24) does not authorize retention or upload of those artifacts.
