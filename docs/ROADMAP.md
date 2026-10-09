# Shared roadmap

Updated 9 October 2026. The repository started with no issues. The 19 issues across three milestones separate observed capability, implementation and later product work. Issues are unassigned so the two collaborators can choose ownership together. No deadline or partner access has been assumed.

Start with [onboarding](ONBOARDING.md), then use [the test report template](TEST-REPORT-TEMPLATE.md). The existing app verification is recorded in [PHASE-ONE.md](PHASE-ONE.md).

## What is already done

- Native Mac UI for review, edits, approval, a guided routine and recovery after closing the app.
- Local selected observation import and real Apple Vision OCR; JSON export.
- Shared state, persistence and durable action journal; Apple model, speech and Calendar adapter code.
- Last recorded verification: **17 tests passed, 1 real-model test skipped, 0 failures** at application commit `b065bf4`. The Mac interface was exercised. iPhone and HomePod behavior remains unrun.

## Start with two parallel tracks

1. **Device and audio:** take #1 first, then #3; begin #4 on Mac while phone setup progresses.
2. **App and learning:** take #2 first, then #9. If model downloads block progress, work on #10 or #8.

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

## Later concepts without an implementation commitment

HomeKit scenes, Apple TV presentation, more speakers and a future moving/robot device remain exploratory extensions. First prove actual presence, routing and session continuity with the hardware already owned. An in-app voice chess board is another optional product experiment; controlling a separate chess app needs its own evidence. These concepts do not block the current live-demo milestone.

## How we work together

1. Choose an issue, assign yourself after both collaborators have access, and leave a short approach before changing shared interfaces.
2. Use a small branch named for the issue, such as `issue-1-iphone-proof`. Check for existing work before starting.
3. Open a pull request with the concrete change, test evidence and known gaps. Review one another’s work; add `Closes #N` only when that issue’s acceptance criteria are met.
4. Report tests as passed, failed, skipped or not run. Keep raw media local and share only deliberately reviewed evidence.
5. Update the issue and verification record when a hardware claim becomes proved. No CI or branch protection is implied by these conventions.

The original private PRD is still excluded from Git. Repository code and these operational guides are the shared onboarding material.
