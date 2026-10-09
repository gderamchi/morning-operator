# MORE documentation

The active product is the iPhone app. The Mac hosts development, package tests and optional tethered experiments. The repository and Xcode target still use Morning Operator naming.

**Choose the right version:** `codex/more-quiet-morning` contains the in-progress two-tab V2. It has not been installed on the owner's phone; the installed physical baseline is `8a640ea`. Source `52cbe56` has 106 passing shared checks (two optional model skips), corrected simulator journeys, largest-text and speech-output checks; [the verification record](PHASE-ONE.md) preserves exact results and earlier failures. Physical V2 and microphone recognition remain pending. The [V2 design contract](V2-DESIGN.md) defines the new navigation; older device walkthroughs describe the installed baseline.

## Use the app

| Guide | What it answers |
|---|---|
| [Voice commands](VOICE.md) | Use an explicit listening turn; understand commands, audio handoff and outstanding device checks |
| [V2 design contract](V2-DESIGN.md) | How Morning and Review divide the experience, with completion capture and accessible layout fallbacks |
| [Short morning trial checklist](DEVICE-SETUP.md#tomorrow-morning-checklist) | How to try recording, stop, review saved text and recover a failed import on the installed baseline |
| [Onboarding](ONBOARDING.md) | How either collaborator builds and installs the selected source branch |
| [Device setup](DEVICE-SETUP.md) | Signing, paired-device tests, recording, Shortcuts and the separate HomePod experiment |

## Understand and build it

| Guide | What it contains |
|---|---|
| [Architecture](ARCHITECTURE.md) | System diagrams, runtime states, persistence, model inference and effect boundaries |
| [Data retention today](ARCHITECTURE.md#data-retention-today) | What exists on disk, why it remains and what current controls remove |
| [Apple capabilities](CAPABILITIES.md) | Framework-specific behavior, permission requirements and official documentation |
| [Observation plan](OBSERVATION-PLAN.md) | Learning windows, evidence quality, app-return cycles, coverage and research hypotheses |
| [Roadmap](ROADMAP.md) | Priorities, dependencies and GitHub issues |
| [V2 issue #25](https://github.com/gibouu/morning-operator/issues/25) | Design acceptance criteria and the owner walkthrough still required |

## Assess the evidence

| Guide | How to use it |
|---|---|
| [Physical verification record](PHASE-ONE.md) | Read source, device, scope and outcome before carrying a phone result over to new code |
| [Test report template](TEST-REPORT-TEMPLATE.md) | Record a pass, failure, skip or environment block without uploading personal artifacts |
| [Controlled benchmark #23](https://github.com/gibouu/morning-operator/issues/23) | Compare known phone actions and visible evidence against extraction and model claims |

**Implemented** means the source contains the behavior. **Verified** means a specified check actually passed. **Planned** means further design or implementation remains. A simulator navigation pass is not a physical recording test; a passing synthetic import is not native capture; successful capture is not proof that proposed habits are correct.

V2 Review opens periods and days, but its real averages still describe routine runs. Observed-habit averages and ongoing adaptive profiles remain planned. Configured-app callbacks have separate, partial coverage; missing observations stay unknown. Removing the Notes tab preserves saved thoughts under Review and a capture invitation at completion—it does not create continuous voice listening.

The private source PRD, personal recordings, OCR, workspace snapshots and device-test media stay outside these shared guides. [Research-data feasibility #24](https://github.com/gibouu/morning-operator/issues/24) does not authorize retention or upload of those artifacts.
