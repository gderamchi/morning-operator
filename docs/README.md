# MORE documentation

The active product is the iPhone app. The Mac hosts development, package tests and optional tethered experiments. The repository and Xcode target still use Morning Operator naming.

**Choose the right version:** `codex/more-quiet-morning` contains the in-progress two-tab V2. It has not been installed on the owner's phone; the physical baseline remains `8a640ea`. Latest source `d9a6120` keeps a dated observation archive with original evidence, corrections and same-file deduplication, alongside ordered recording evidence and explicit screen-context recognition. Its checks are recorded by source and scope below. Earlier simulator journeys, largest-text and speech-output checks are preserved in [the verification record](PHASE-ONE.md). The [V2 design contract](V2-DESIGN.md) defines the new navigation; older phone walkthroughs describe the installed baseline.

The [morning-entry slice](MORNING-ENTRY.md) adds a one-time local invitation. The real simulator delivery → tap → approved start rerun passed after a callback crash was corrected; five other entry checks passed before that fix. Physical delivery, cold launch, locked-device behavior and spoken Siri invocation still need separate trials.

The controlled recording and import/relaunch checks passed. The preceding layout source passed real Vision movie extraction. The archive update has 214 distinct shared checks passing across full and focused runs, with six optional skips; the native-service failure and successful targeted retry are retained in the verification record. Actual screen recognition remains unproved: earlier Mac and simulator model attempts were unavailable or failed in an unsupported backend. The new layout checks did not invoke a model. Shared logic, build and UI results are deliberately reported separately in [verification](PHASE-ONE.md).

## Use the app

| Guide | What it answers |
|---|---|
| [Morning entry](MORNING-ENTRY.md) | Schedule one invitation, enter through Start, and understand permissions, expiry and manual fallback |
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
| [Observation metrics](OBSERVATION-METRICS.md) | Ordered samples and text positions, bounded model evidence, unknowns, trace mathematics and day denominators |
| [Roadmap](ROADMAP.md) | Priorities, dependencies and GitHub issues |
| [V2 issue #25](https://github.com/gibouu/morning-operator/issues/25) | Design acceptance criteria and the owner walkthrough still required |

## Assess the evidence

| Guide | How to use it |
|---|---|
| [Physical verification record](PHASE-ONE.md) | Read source, device, scope and outcome before carrying a phone result over to new code |
| [Test report template](TEST-REPORT-TEMPLATE.md) | Record a pass, failure, skip or environment block without uploading personal artifacts |
| [Recording benchmark](OBSERVATION-BENCHMARK.md) | Reproduce real capture of two native fixture apps; distinguish extraction success, known actions and failed model inference |
| [Controlled benchmark #23](https://github.com/gibouu/morning-operator/issues/23) | Compare known phone actions and visible evidence against extraction and model claims |

**Implemented** means the source contains the behavior. **Verified** means a specified check actually passed. **Planned** means further design or implementation remains. A simulator navigation pass is not a physical recording test; a passing synthetic import is not native capture; successful capture is not proof that proposed habits are correct.

V2 Review opens periods and days and now preserves observations across imports, but its real averages still describe routine runs. Unknown observed dates remain in Date needed until explicitly assigned. Observed-habit averages and ongoing adaptive profiles remain planned. Configured-app callbacks have separate, partial coverage; missing observations stay unknown. Removing the Notes tab preserves saved thoughts under Review and a capture invitation at completion—it does not create continuous voice listening.

The private source PRD, personal recordings, OCR, workspace snapshots and device-test media stay outside these shared guides. [Research-data feasibility #24](https://github.com/gibouu/morning-operator/issues/24) does not authorize retention or upload of those artifacts.
