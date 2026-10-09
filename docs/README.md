# Morning Operator documentation

Start with the experience you want to try, then use the architecture and evidence guides when you need detail. The active product is the iPhone app; the Mac hosts development, package tests and optional tethered experiments.

## Use the app

| Guide | What it answers |
|---|---|
| [Tomorrow morning checklist](DEVICE-SETUP.md#tomorrow-morning-checklist) | How to try a short recording, stop, review text and recover a failed import |
| [Onboarding](ONBOARDING.md) | How either collaborator builds, installs and uses the current app |
| [Device setup](DEVICE-SETUP.md) | Signing, paired-device tests, recording, Shortcuts and the separate HomePod experiment |

## Understand and build it

| Guide | What it contains |
|---|---|
| [Architecture](ARCHITECTURE.md) | System diagrams, runtime states, persistence, model inference and effect boundaries |
| [Data retention today](ARCHITECTURE.md#data-retention-today) | What exists on disk, why it remains and what current controls remove |
| [Apple capabilities](CAPABILITIES.md) | Framework-specific behavior, permission requirements and official documentation |
| [Observation plan](OBSERVATION-PLAN.md) | Learning windows, evidence quality, app-return cycles, coverage and research hypotheses |
| [Roadmap](ROADMAP.md) | Priorities, dependencies and GitHub issues |
| [V2 design work #25](https://github.com/gibouu/morning-operator/issues/25) | A simpler daily experience and planned week-average presentation |

## Assess the evidence

| Guide | How to use it |
|---|---|
| [Verification record](PHASE-ONE.md) | Read the exact source, scope and outcome before calling a feature working |
| [Test report template](TEST-REPORT-TEMPLATE.md) | Record a new pass, failure, skip or environment block without uploading personal artifacts |
| [Controlled benchmark #23](https://github.com/gibouu/morning-operator/issues/23) | Compare known phone actions and visible evidence against extraction and model claims |

**Implemented** means the source contains the behavior. **Verified** means a specified check actually passed. **Planned** means further design or implementation remains. A passing synthetic import is not a native-recording test; a successful capture is not proof that the proposed habits are correct.

The intended simple weekly average is still planned. Current Review summarizes routine runs and separately shows Today’s configured-app callbacks. Missing observations must remain unknown.

The private source PRD, personal recordings, OCR, workspace snapshots and device-test media stay outside these shared guides. [Research-data feasibility #24](https://github.com/gibouu/morning-operator/issues/24) does not authorize retention or upload of those artifacts.
