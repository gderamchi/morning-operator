# Start working on Morning Operator

For the two founders. Updated 9 October 2026. The iPhone is the sole active product. Start with the installed phone app or build it through Xcode, reproduce the basic journey, then choose the next issue together. The Mac is the development/test host and optional controller; no separate Mac app is required.

## What you can try today

The current native interface has **Morning**, **Review** and **Notes** tabs. Morning contains the day strip and routine timeline; Learn and Settings open from their controls. You can build/review/approve a routine, run its steps, pause/resume/stop, edit a draft, restore the previous approved version, and export it. Notes captures local thoughts and dreams; reminder/calendar requests are reviewed separately before a system write. Review summarizes recorded mornings, with missing history kept distinct from measured activity.

Selected text, screenshots and videos feed a reviewable observation field. The latest extracted text/source is saved locally; Clear this observation removes that text, while evidence quotes already saved in routines remain. The revised native recorder can prepare a draft automatically after foreground processing; selected file imports still use Suggest a routine. Apple model analysis, speech, Calendar/Reminders and automatic step execution have different verification needs. Automatic progression waits for a supported operation to finish; speaking an instruction does not prove a real-world task was done. Interactive steps remain user-controlled.

**Xcode 27 is installed, and the native app is signed, installed and running on the owner's iPhone 15 Pro Max with iOS 27.0.1.** Four core phone journeys passed, along with a real local-model proposal and a read-only Clock navigation/scroll test. The expanded verification record is in [PHASE-ONE.md](PHASE-ONE.md). Siri, real Calendar/Reminders writes, HomePod routing and recording ingestion need their own individual checks.

## First five minutes on your iPhone

1. Open **Morning Operator** and choose **Learn my morning**.
2. On iOS 27, choose **Record a little of my morning**, select a 5/10/20/30-minute limit and confirm Apple's sharing picker. Show a short, harmless part of your routine. The revised app-owned Record/Learn sheets close after capture starts; Apple's system panel dismissal remains unverified. Use the in-app or system Stop control, or let the chosen bound request a stop. On earlier supported iOS versions, choose an existing recording or screenshot.
3. In the revised flow, returning to the foreground with a finalized recording starts local OCR when no analysis or routine session is active. A ready Apple model can then propose an unapproved draft without a separate Use step. Review and edit it before approval. If the model is unavailable, review the saved text and choose **Suggest a routine** later; selected file imports also use that button. **Build it myself** and **Explore a sample** work independently.
4. Choose **This feels like me**, then **OK, here we go**. Supported spoken actions can advance when finished; personal activities and unconnected apps wait for you. The playback controls include Pause, Next and End morning.
5. Swipe between days in **Morning**, open **Review**, and save a dream or thought in **Notes**. Missing days stay empty. History currently measures app-run sessions; exact TikTok, Instagram and email behavior is a separate analytics milestone.
6. In **Settings → Companion voice**, choose an installed Apple voice and preview it. The audio-output control is where you choose AirPods or an available AirPlay speaker.

These recording and app-activity revisions are separate from the tested `b5914db` build. An initial revised phone build-for-testing and nine focused transition checks passed. A later full package run passed 64 with one intentional model opt-in skip, before the latest background handoff. The final iPhone build-for-testing and two recovery retests have since passed; new end-to-end device checks remain pending. The earlier recording test failed with empty notes after Use. A later owner Stop/Use sequence produced an Observation loaded banner, but the owner then found the ordinary-app Learn text box empty. The end-to-end user check remains failed/unresolved; that banner is not proof of usable extraction or a model result. See [verification](PHASE-ONE.md). First-use detection, Screen Time data access and scheduled recording are not implemented. No background week-long capture starts automatically.

## On the existing development Mac

Use the existing `morning-operator` checkout. The owner’s separate generated Mac app was moved to Trash; keep product work focused on the iPhone. From the repository, run the shared package checks and open the iPhone project:

```sh
./scripts/test.sh
open MorningOperator.xcodeproj
```

Choose the iPhone app target, your local development team and the explicitly selected paired phone. Build/run through Xcode, then follow [device setup](DEVICE-SETUP.md). Full Xcode is needed for phone installation and UI tests. The Mac may also host the bounded development controller; that is separate from shipping a native Mac app.

## On the partner's Mac

1. Sign in with your own GitHub account and accept the invitation to the private [morning-operator repository](https://github.com/gibouu/morning-operator). If access is missing, ask the owner to check repository **Settings → Collaborators**. See [GitHub’s invitation guide](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/repository-access-and-collaboration/inviting-collaborators-to-a-personal-repository).
2. Use a development Mac compatible with the required Xcode; the shared package targets macOS 26 or later for local checks. The observed host is macOS 27.0.1 on a MacBook Air M4. The iPhone app requires iOS 26 or later, with iOS 27 for native recording and compatible Apple Intelligence hardware/model readiness. This does not establish every older device/toolchain combination.
3. Install/open [Apple Xcode](https://developer.apple.com/xcode/) compatible with the Mac's OS and, for phone work, the phone's installed iOS. Finish first-launch setup and select it in Xcode Settings → Locations → Command Line Tools. Record the actual version. The owner's successful signed phone installation used Xcode 27 with iOS 27.0.1; repeat setup with the partner's own machine and device. A compatible Command Line Tools installation may be enough for shared package checks; the initial successful baseline was Swift 6.4, not every Swift 6 release.
4. Clone into a folder you choose using your own authenticated GitHub account. GitHub Desktop is an alternative to the terminal commands below. Never put access tokens in a clone URL, project file or test report.

```sh
mkdir -p "$HOME/Developer"
cd "$HOME/Developer"
git clone https://github.com/gibouu/morning-operator.git
cd morning-operator
./scripts/test.sh
open MorningOperator.xcodeproj
```

There are no third-party Swift package dependencies, cloud-model keys or shared signing secrets. Homebrew is not required. Build/run the iPhone target with your own account/team and selected phone; do not recreate the separate Mac app as part of onboarding.

If cloning says the repository is unavailable, check invitation acceptance and which GitHub account is authenticated before changing the URL or visibility. The original private product brief is deliberately excluded from Git; this guide and the checked-in setup/status documents are sufficient for the first build.

## Record the environment and run the package checks

Run these from your own checkout and record their output in a local test report:

```sh
git rev-parse HEAD
git status --short
./scripts/check-environment.sh
./scripts/test.sh --with-model
```

The environment script exits with code 2 when full Xcode is unavailable. That identifies the iPhone tooling gap; it does not mean the shared package tests failed. Run the test command separately even if that environment check reports the expected gap. The test script handles the Swift Testing macro plugin needed by the observed Command Line Tools 6.4 setup. It runs the local, dependency-free package with its package sandbox disabled; it does not install or control an iPhone.

For model readiness, check that Apple Intelligence is enabled in the device’s Apple Intelligence & Siri settings, use a supported language/region, and allow the local models to finish downloading. Apple recommends keeping the device on Wi-Fi and power while the models download. See [Apple’s setup guide](https://support.apple.com/en-lamr/121115). The app’s reported local-model availability remains the deciding check; enabling a separate Siri feature does not prove the app’s model is ready.

Use `./scripts/test.sh` without `--with-model` when you do not want to attempt the optional real model test. Read the reported counts and reasons. **Skipped means the check did not execute successfully, not that the feature passed.** Record an unavailable model separately from a failed core invariant. A clean run without real inference does not establish model quality.

Copy [TEST-REPORT-TEMPLATE.md](TEST-REPORT-TEMPLATE.md) into an ignored local folder for each run, for example:

```sh
mkdir -p work/test-reports
cp docs/TEST-REPORT-TEMPLATE.md work/test-reports/first-mac-run.md
```

## First iPhone smoke test

Use the isolated device fixture suite in [DEVICE-SETUP.md](DEVICE-SETUP.md) for the automated baseline. For a manual synthetic walkthrough, keep automatic progression and spoken guidance off while checking the controls, then verify those integrations separately. The basic phone journey is:

| Step | Expected result |
|---|---|
| Explore a sample, then This feels like me | Clearly synthetic draft becomes approved after review. |
| OK, here we go → Next → Pause → Continue | Current step advances only as requested and survives pause/resume. |
| Close/reopen the same installed app while a routine is running | Saved session reopens paused at the same step. |
| Morning controls → End morning | Run stops and records its actual terminal state. |
| Edit a step, then restore the previous approved routine | Edit creates an unapproved draft; restoration recovers the previous approved content. |
| Save an invented Dream in Notes | It stays local, appears under the Dream filter and survives tab navigation. |
| Swipe to an empty previous day | Empty history stays empty; today's routine is not invented as past activity. |
| Import a synthetic text observation, then Suggest a routine when the model is ready | Text is visible and saved; proposal remains unapproved. A model-unavailable result is a skip, not successful inference. |

The native recording path is a separate unresolved check: Learn was empty in the owner's ordinary-app test despite an Observation loaded banner. Validate the source recording, extracted text, saved workspace and visible field before accepting a result. Check Clear this observation and failed-recording Retry/Discard separately; saved routine quotes and raw recovery media have different lifecycles.

Test voice audibly on a known output, Calendar permission/read, and an intentionally reviewed Calendar/Reminders write as separate device checks. A saved local dream is not a system Reminder. Foreground Start morning requests an approved plan; Quick capture opens text for review. Neither intent approves changed routines or silently saves system items. Siri discovery/dictation and background app-transition logging need independent installed-device verification.

## Optional app activity

The new **Review → Connect app activity** setup explains how to create separate Is Opened/Is Closed automations for Instagram, TikTok or Snapchat. Each automation calls **Log an app transition** with the matching app and transition; leave Event ID empty for ordinary use. This background action is designed to log without opening Morning Operator. Its installation, background delivery and cold-launch behavior have not yet been verified. See [device setup](DEVICE-SETUP.md#optional-app-transition-logging).

The Today card counts recorded entries and returns after another tracked app. It is not a complete app log, pickup counter, duration measurement or seven-day external-app report. Missing events and unconfigured apps can change the apparent sequence. The journal is local and separate from the workspace. The setup sheet now has Clear recorded app activity; disable the corresponding Shortcuts automations to stop new entries. Journal export and automatic retention limits remain future work, and the clear flow still needs device verification.

## Move to iPhone and HomePod

Follow [DEVICE-SETUP.md](DEVICE-SETUP.md) for pairing, Developer Mode, signing, explicit device selection, fixture tests and bounded installed-app observation. Full Xcode and matching iOS platform support are required. The owner's signed installation, launch and core UI checks have succeeded; reproduce those checks on each partner device. A partner must independently build, sign and install using their own local account/team/device configuration.

The generated project is checked in, so begin with:

```sh
open MorningOperator.xcodeproj
```

**XcodeGen is optional for opening the checked-in project.** Install it only when you need to regenerate after adding/removing source files or changing `project.yml`; use its [upstream installation instructions](https://github.com/yonaskolb/XcodeGen#installing), which include alternatives to Homebrew. Then run `./scripts/generate-project.sh` and review the project diff. Where the device guide includes generation, you can omit that step when the checked-in project is already current. The device-test runner itself regenerates the project and therefore requires XcodeGen.

Select your own development team locally. Do not commit a personal team setting, certificate, provisioning profile, Apple account credential or device identifier. Run the fixture suite before the Settings suite or any deliberately selected external app. Keep XCTest control in the separate test target; it is not a permission granted to the ordinary iPhone application.

The currently known hardware is one iPhone 15 Pro Max, one MacBook Air M4 and **one HomePod mini**. On iPhone, Settings includes a real system audio-output picker; on Mac, it points to Control Center. Test actual sound on the chosen headphones or speaker. A visible picker does not prove successful routing or expose the HomePod microphone.

The first HomePod proof is phone-or-Mac → that speaker, with the actual microphone and audio origin identified. The saved **Set Playback Destination** Shortcut experiment is described in the device guide and remains separate from the output picker. It has not been implemented or proved here. One HomePod cannot demonstrate transfer between two HomePods; manual route selection must be labeled as manual. A room-detection prompt and automatic transfer still require separate real evidence.

## Work in parallel

Use the [shared roadmap and issue links](ROADMAP.md) to claim work. Choose independent tracks together; these are work areas, not assignments to either founder:

| Track | Small, reviewable outcome | Dependency |
|---|---|---|
| Product journey | Observe someone using sample/manual routines; fix one confusing interaction and reproduce the smoke test | Working iPhone build |
| Semantic learning | Resolve model readiness, analyze synthetic observations, record grounded/unsupported steps and cancellation behavior | Available local Apple model |
| Phone proof | Compile/install the app, run fixture then Settings checks, document actual signing/SDK issues | Full Xcode and selected phone |
| Voice and audio | Verify local speech first, then one HomePod route; separately design live command input | Actual audio devices; phone work for iOS routing |
| Calendar | Test consent, denied/empty/event states and the correct day/timezone | A deliberately chosen local calendar |

Agree on files/interfaces before starting overlapping changes, use short branches, and review a concrete diff with test evidence. Keep one report per device/build. Merge only the completed scope and state any skips. The next useful milestone is a repeatable iPhone demonstration, followed by a separately proven audio route; do not bundle all remaining integrations into one change.

## Keep evidence useful and private

Use invented names and events for first tests. `work/`, build outputs, screenshots and `.xcresult` bundles are ignored, but ignoring a file is not redaction. Logs, screenshots, accessibility trees, routine exports and short retained evidence quotes can still reveal personal content. Review and redact any excerpt before sharing it in a private issue or pull request. Do not attach complete personal recordings, calendar data, inboxes, workspace snapshots, account identifiers or credentials.

Share the commit, exact steps, observed/expected result and the smallest redacted evidence needed. Leave the raw evidence on the test machine. Do not copy the private source PRD into onboarding documents or test reports.
