# Shared roadmap

Updated 10 October 2026. The roadmap separates observed capability, implementation and later product work. Issues #1–#19 were organized into three milestones; the newer voice and evidence-analytics issues are listed separately below. Collaborators can choose ownership together. No deadline or partner access has been assumed.

Start with [onboarding](ONBOARDING.md), then use [the test report template](TEST-REPORT-TEMPLATE.md). The existing app verification is recorded in [PHASE-ONE.md](PHASE-ONE.md).

## What is already done

- The V2 source has two native tabs, Morning and Review, with compact routine controls, review/edit/approval, local dreams/thoughts, recovery and history. The installed phone baseline still has the earlier interface; V2 has not replaced it. iPhone is the sole active product; the Mac is the development/test machine and optional controller.
- Selected observation import and real Vision OCR; local model adapter; supported app-owned speech/calendar progression and foreground Siri/Shortcuts entry points.
- Signed iPhone builds have installed and launched. Synthetic phone journeys, real on-device generation from synthetic notes and bounded read-only Clock navigation have passing evidence. The current source/install state and exact results are maintained in [the verification record](PHASE-ONE.md).
- One real recording passed the narrow capture → OCR → saved text → visible unapproved draft path; its text also survived ordinary-app relaunch. Its draft incorrectly interpreted app setup/Review copy as habits. The corrected evidence policy passes focused tests and rejects that same saved input in a deterministic replay, without changing the text or making a new model call. General habit accuracy, broader recording lifecycle and installed app-transition delivery remain open. Earlier empty-observation failures remain in the verification record; they are not the latest ingestion result.
- A phone greeting preview completed through the speech system, but there is no audible listener confirmation. Full routine narration, live EventKit writes and HomePod behavior require their own evidence. See [the observation plan](OBSERVATION-PLAN.md) for the next learning slices.

The V2 branch now retains separate dated observations, original extraction and corrections across imports, with exact-file deduplication and scoped deletion in Review. Unknown observed dates stay unassigned. These records are not yet comparable full mornings or an observed-habit profile. The same branch carries ordered samples from the finalized recording into saved observation evidence. A separate, explicitly requested Foundation Models classifier proposes quoted visible contexts and preserves unknowns. The first two-app controlled capture and its import/relaunch/blank-video checks passed; actual classification failed in the simulator’s unsupported native backend. No action-recognition accuracy or personal averages are established. See [the reproducible benchmark](OBSERVATION-BENCHMARK.md).

The current saved-observation slice advances #11: **Choose mornings** selects one to five dated, same-zone human observations or synthetic samples, then saves a pending update with exact quotations, source layers and omitted-frame reasons. Explicit approval replaces the routine; source/base changes invalidate stale suggestions. The existing routine and required rituals remain protected during review. Shared validation, the native build and six synthetic UI journeys have passing scoped results. Real multi-observation generation and quality remain unverified. The `d9a6120` archive results precede this slice. [Learning flow and limits](ROUTINE-LEARNING.md), [verification chronology](PHASE-ONE.md).

## Start with two parallel tracks

1. **Device and audio:** finish the expanded #1 checks, build on the bounded #3 proof, then verify #4 and the built-in portion of #20.
2. **App and learning:** obtain real model output for the implemented #11 pending-update journey from selected #9/#19 evidence, then connect comparable observations to #21 analytics. Work on #8 retention controls and durable preference reconciliation alongside that pipeline.

Agree jointly on interfaces before #7 and #12. Integrate at #14. These tracks are suggestions, not assignments to particular people. Keep one active coding ticket per person where possible.

Priorities describe importance, not permission to bypass dependencies. A feasibility spike may finish with a documented blocker; that is different from a working feature. Milestones have no due dates because the hackathon date is not yet recorded.

## [01 - First hardware proof](https://github.com/gibouu/morning-operator/milestone/1)

Establish the real iPhone, local model, external-app capture and HomePod capabilities. Close spikes with observed evidence; a negative feasibility result is not a working product feature.

| Issue | Priority | Stream | Depends on |
|---|---|---|---|
| [#1 — Build and run Morning Operator on the real iPhone](https://github.com/gibouu/morning-operator/issues/1) | P0 | device | Can start independently |
| [#2 — Make Apple Intelligence ready and prove real routine generation](https://github.com/gibouu/morning-operator/issues/2) | P0 | learning | Can start independently |
| [#3 — Prove screenshot capture and one real cross-app navigation on iPhone](https://github.com/gibouu/morning-operator/issues/3) | P0 | device | [#1](https://github.com/gibouu/morning-operator/issues/1) |
| [#4 — Verify spoken guidance and a real transfer to the HomePod mini](https://github.com/gibouu/morning-operator/issues/4) | P0 | integrations | Can start independently |
| [#5 — Test a real room-presence signal and prompted speaker handoff](https://github.com/gibouu/morning-operator/issues/5) | P0 | integrations | [#4](https://github.com/gibouu/morning-operator/issues/4) |

## [02 - Live hackathon demo](https://github.com/gibouu/morning-operator/milestone/2)

Combine voice, local learning, bounded phone control and one real action into a repeatable demonstration. Dependencies and acceptance criteria define completion.

| Issue | Priority | Stream | Depends on |
|---|---|---|---|
| [#6 — Connect native voice commands to the active morning session](https://github.com/gibouu/morning-operator/issues/6) | P0 | app | [#4](https://github.com/gibouu/morning-operator/issues/4) |
| [#7 — Build the tethered observe → plan → act → verify phone loop](https://github.com/gibouu/morning-operator/issues/7) | P1 | device | [#1](https://github.com/gibouu/morning-operator/issues/1), [#2](https://github.com/gibouu/morning-operator/issues/2), [#3](https://github.com/gibouu/morning-operator/issues/3) |
| [#8 — Add local privacy controls for evidence retention, export and forgetting](https://github.com/gibouu/morning-operator/issues/8) | P1 | app | Can start independently |
| [#9 — Carry time-linked observation evidence from import through routine review](https://github.com/gibouu/morning-operator/issues/9) | P1 | learning | [#2](https://github.com/gibouu/morning-operator/issues/2) |
| [#19 — Add explicitly started morning observation sessions and learning windows](https://github.com/gibouu/morning-operator/issues/19) | P1 | learning | [#1](https://github.com/gibouu/morning-operator/issues/1), [#3](https://github.com/gibouu/morning-operator/issues/3), [#9](https://github.com/gibouu/morning-operator/issues/9); coordinate with [#8](https://github.com/gibouu/morning-operator/issues/8) |
| [#10 — Preserve enjoyable rituals through routine review, time budgets and session recap](https://github.com/gibouu/morning-operator/issues/10) | P1 | app | Can start independently |
| [#11 — Propose editable multi-day routine versions from comparable mornings](https://github.com/gibouu/morning-operator/issues/11) | P1 | learning | [#9](https://github.com/gibouu/morning-operator/issues/9), [#10](https://github.com/gibouu/morning-operator/issues/10), [#8](https://github.com/gibouu/morning-operator/issues/8) |
| [#12 — Connect scoped approvals and the durable journal to one real action adapter](https://github.com/gibouu/morning-operator/issues/12) | P0 | integrations | Choose channel; controller route uses [#7](https://github.com/gibouu/morning-operator/issues/7) |
| [#13 — Deliver a live calendar and weather briefing with freshness checks](https://github.com/gibouu/morning-operator/issues/13) | P1 | integrations | [#4](https://github.com/gibouu/morning-operator/issues/4) |
| [#14 — Rehearse one honest end-to-end learned morning on the actual setup](https://github.com/gibouu/morning-operator/issues/14) | P0 | app | [#1](https://github.com/gibouu/morning-operator/issues/1), [#2](https://github.com/gibouu/morning-operator/issues/2), [#7](https://github.com/gibouu/morning-operator/issues/7), [#6](https://github.com/gibouu/morning-operator/issues/6), [#12](https://github.com/gibouu/morning-operator/issues/12), [#4](https://github.com/gibouu/morning-operator/issues/4), [#13](https://github.com/gibouu/morning-operator/issues/13) |

## [03 - Product follow-up](https://github.com/gibouu/morning-operator/milestone/3)

Optional native surfaces, health, limits and repeat-use/pricing work after the live loop is stable. No delivery dates have been assumed.

| Issue | Priority | Stream | Depends on |
|---|---|---|---|
| [#15 — Add an optional, accurately sourced HealthKit morning summary](https://github.com/gibouu/morning-operator/issues/15) | P2 | integrations | [#1](https://github.com/gibouu/morning-operator/issues/1), [#13](https://github.com/gibouu/morning-operator/issues/13) |
| [#16 — Add a supported morning start action and Live Activity progress](https://github.com/gibouu/morning-operator/issues/16) | P2 | app | [#1](https://github.com/gibouu/morning-operator/issues/1) |
| [#17 — Prototype optional Screen Time limits that preserve chosen rituals](https://github.com/gibouu/morning-operator/issues/17) | P2 | integrations | [#1](https://github.com/gibouu/morning-operator/issues/1) |
| [#18 — Run a small repeat-use trial and define the first pricing hypothesis](https://github.com/gibouu/morning-operator/issues/18) | P2 | app | [#14](https://github.com/gibouu/morning-operator/issues/14) |

## New follow-ups awaiting prioritization

These issues have no milestone or priority assigned yet.

| Issue | Current position | Next evidence |
|---|---|---|
| [#20 — Choose a morning companion voice and investigate consented custom voices](https://github.com/gibouu/morning-operator/issues/20) | Built-in voice chooser, search, preview and saved preference exist; a phone greeting preview completed through the speech system. Audible listener confirmation remains absent. The custom-voice investigation is separate. | Verify audible selection, fallback, persistence and output route on hardware. No Personal Voice prompt or custom-voice cloning is implemented. |
| [#21 — Turn recorded mornings into evidence-based daily and weekly analytics](https://github.com/gibouu/morning-operator/issues/21) | Local run history and a dated acquisition archive exist, with original/corrected evidence and same-file deduplication. Comparable day windows and observed-habit averages remain unconnected. Optional Shortcuts callback logging has focused test coverage; installed delivery and its Today entry/return card remain unverified; no complete external-app usage pipeline exists. | Validate selected-app delivery and counts; connect recordings to time-linked observations and coverage. DeviceActivity first-use/data access remain spikes. Coordinate with #8, #9 and #19; see OBSERVATION-PLAN. |

## Next product slices from the latest owner feedback

Preserve the now-demonstrated ingestion and relaunch path under #19/#9, then broaden reliability and semantic quality through #23. A success banner alone is still insufficient: compare deliberately shown content with the saved observation and distinguish supported activities from app-interface copy. The filter correction is a targeted guard, not proof of a learned routine or full action recognition. [PHASE-ONE](PHASE-ONE.md) is the canonical record of passes, failures and pending hardware checks.

| Scope | Backlog home | Concrete next result |
|---|---|---|
| Simpler daily experience and weekly averages | [#25 — V2 design work](https://github.com/gibouu/morning-operator/issues/25); coordinates #11/#21 | Keep recording and the current morning easy to reach, then present evidence-based averages from comparable mornings with clear coverage. This habit-average view remains planned. |
| Controlled ground-truth capture benchmark | [#23 — controlled ground-truth benchmark](https://github.com/gibouu/morning-operator/issues/23); coordinates #2/#9/#19/#21 | Repeat the implemented two-app recording on supported model hardware, then run the held-out sequence. Compare extracted evidence and model claims against independently logged postconditions; report precision/recall, omissions and unknowns before multi-day averages. |
| Screen narration and actions after learning | Extend #7 with #6/#12 | Explain the currently observed selected screen, perform one supported scoped action, reacquire evidence and verify its outcome on the personal development setup. |
| Verify reviewed updates from saved observations | [#11 — multi-day routine versions](https://github.com/gibouu/morning-operator/issues/11); coordinates #8/#9/#10 | Obtain a real supported-hardware model result and assess its quotations and required-ritual preservation; six synthetic UI journeys now have passing scoped results. Current source has explicit pending review; comprehensive optional-preference reconciliation remains open. |
| Learn after every eligible morning | Extend #11 with #21 | Build an initial profile from four or five adequately observed comparable days, then refresh it after each consented morning. Preserve corrections and separate human behavior from automation/test traces. |
| Optional reduction of a chosen habit | Extend #10; optional enforcement belongs to #17 | Let the person choose a habit, target and time period, including no reduction. Compare against an observed baseline and preserve required enjoyable rituals. |
| Separately opted-in mobile-agent research data | [#24 — opt-in research-data feasibility](https://github.com/gibouu/morning-operator/issues/24); coordinates #8/#18 | Evaluate whether deliberately retained, reviewed/redacted interaction recordings could support a useful licensed research dataset. Decide consent, exclusions, redaction quality, retention, withdrawal and demand before building collection or export. |

These are planned outcomes, not new test results. Four/five-day estimates expose their actual evidence-day denominator and remain separate from the seven-calendar-day history view. Continued learning means repeated bounded, consented sessions; it does not imply continuous background recording. Research participation is a separate optional purpose, disabled by default; this roadmap does not extend existing recovery retention or authorize any upload or sale.

## Later concepts without an implementation commitment

HomeKit scenes, Apple TV presentation, more speakers and a future moving/robot device remain exploratory extensions. First prove actual presence, routing and session continuity with the hardware already owned. An in-app voice chess board is another optional product experiment; controlling a separate chess app needs its own evidence. These concepts do not block the current live-demo milestone.

## How we work together

1. Choose an issue, assign yourself after both collaborators have access, and leave a short approach before changing shared interfaces.
2. Use a small branch named for the issue, such as `issue-1-iphone-proof`. Check for existing work before starting.
3. Open a pull request with the concrete change, test evidence and known gaps. Review one another’s work; add `Closes #N` only when that issue’s acceptance criteria are met.
4. Report tests as passed, failed, skipped or not run. Keep raw media local and share only deliberately reviewed evidence.
5. Update the issue and verification record when a hardware claim becomes proved. No CI or branch protection is implied by these conventions.

The original private PRD is still excluded from Git. Repository code and these operational guides are the shared onboarding material.
