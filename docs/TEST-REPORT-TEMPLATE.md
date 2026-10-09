# Morning Operator test report

Copy this template to an ignored local location such as `work/test-reports/`. Replace placeholders and remove rows that do not apply. Keep raw screenshots, logs, recordings and result bundles local. Share only a reviewed, redacted summary.

## Build and environment

| Field | Value |
|---|---|
| Date, time and timezone | |
| Tester / session label | |
| Goal of this run | |
| Commit (`git rev-parse HEAD`) | |
| Branch and relevant uncommitted changes | |
| Mac model/chip and macOS version/build | |
| Selected developer directory (`xcode-select -p`) | |
| Swift version | |
| Full Xcode version/build, or CLT only | |
| iOS SDK / XcodeGen version, if used | |
| Phone model and iOS version/build, if used | |
| HomePod count and software version, if used | |
| Actual audio origin / output / microphone, if used | |
| App workspace: normal, isolated synthetic, or fixture | |
| Apple model availability as reported by app | |
| Calendar / microphone / speech permission state, if relevant | |
| Source data scope: synthetic or deliberately selected local data | |

Do not include serial numbers, device IDs, personal account names, team credentials or tokens in a shared report. Record whether signing/pairing succeeded without publishing those identifiers. Record the test workspace type; keep any personal absolute path local.

## Results

Use **PASS** only when the stated check ran and matched its expectation. Use **FAIL** for an observed mismatch or error. Use **SKIP** when a check could not run and state why. Use **NOT RUN** when it was not attempted. A skip is never a pass. A tooling prerequisite that blocks a test is distinct from an app failure.

| Check | Status | Expected result | Observed result / skip reason | Local evidence reference |
|---|---|---|---|---|
| Mac build and launch | NOT RUN | Native app opens | | |
| Sample review and approval | NOT RUN | Sample is labeled; explicit approval allows start | | |
| Start / Next | NOT RUN | Running state; current step advances | | |
| Pause / Continue | NOT RUN | Same step retained | | |
| Quit running and reopen same workspace | NOT RUN | Paused at the same step | | |
| Stop | NOT RUN | Stopped state | | |
| Edit draft / restore previous approved version | NOT RUN | Draft needs approval; prior approved content can be restored | | |
| Native JSON export | NOT RUN | Selected local file contains expected routine | | |
| Selected synthetic UTF-8 import | NOT RUN | Text appears for review; no automatic generation | | |
| Image/video import, if exercised | NOT RUN | Extracted text can be reviewed; source/limitations recorded | | |
| Unavailable-model handling | NOT RUN | Visible reason, analysis disabled, manual/sample usable | | |
| Real model inference, if attempted | NOT RUN | Grounded proposal remains unapproved | | |
| Core package tests | NOT RUN | All executed checks pass | | |
| Apple package tests | NOT RUN | All executed checks pass; skips counted separately | | |
| Audible speech / pause / stop | NOT RUN | Sound and controls verified on named output type | | |
| Calendar consent / denied / empty / events | NOT RUN | Record each state actually exercised | | |
| iOS SDK build and phone installation | NOT RUN | App compiles, signs and opens on selected phone | | |
| iPhone fixture suite | NOT RUN | Approve/start/next/pause/resume/stop verified | | |
| Settings navigation and missing-target refusal | NOT RUN | Benign navigation; no tap for missing target | | |
| Explicit external-app capture/navigation | NOT RUN | Only declared observation/navigation occurs | | |
| HomePod output and cancellation/route loss | NOT RUN | Actual audible route and behavior recorded | | |

For Calendar, audio or hardware checks with several outcomes, split the row instead of implying every case ran. For external-app work, identify the app and intended navigation without recording private account/content details. Distinguish a user-selected route from an automatic transfer; a Shortcut callback alone does not prove audio reached the HomePod.

## Commands and counts

- Exact command or Xcode scheme/action used:
- Tests discovered / passed / failed / skipped:
- Process exit status, if captured:
- Skipped test names and explicit reasons:
- Whether real model inference was enabled (`--with-model`):
- Did real inference actually complete successfully? Yes / No / Not attempted
- Local log or `.xcresult` location, retained only on test machine:

The previously recorded baseline was 17 passed, 1 model-not-ready skip, 0 failures on 9 October 2026. Do not copy those counts into this run unless this run actually reports them. Package tests do not establish iPhone UI behavior or HomePod operation.

## A reproducible issue

Duplicate this section for each issue.

- Short title:
- Impact: blocks setup / blocks core journey / affects optional feature / cosmetic
- Starting state and synthetic input:
- Steps: replace the following numbered placeholders with exact actions.

1. [First action]
2. [Second action]
3. [Third action]

- Expected:
- Observed, including exact non-sensitive error text:
- Repeatability: reproduced __ of __ attempts
- Last known working commit, if known:
- Small redacted screenshot or log excerpt, if necessary:
- Current workaround:
- Smallest next check or proposed fix:

## Evidence and next decision

- [ ] The tested commit and any local changes are identified.
- [ ] Pass, fail, skip and not-run results are separate.
- [ ] Any unavailable-model result is separate from successful generation.
- [ ] Device claims refer to devices actually used, not source code or simulated output.
- [ ] Evidence shared outside this machine was inspected and redacted.
- [ ] No tokens, credentials, personal recordings, inbox content or private source PRD were attached.
- [ ] Raw evidence stays in an ignored local location, with retention reviewed.

What is now proved:

What is still unknown or blocked:

Next small action and the evidence that will decide whether it worked:
