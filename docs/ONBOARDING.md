# Start working on Morning Operator

For the two founders. Updated 9 October 2026. Start with the installed iPhone app or build from source, reproduce the basic journey, then choose the next issue together.

## What you can try today

The current native interface has **Morning**, **Review** and **Notes** tabs. Morning contains the day strip and routine timeline; Learn and Settings open from their controls. You can build/review/approve a routine, run its steps, pause/resume/stop, edit a draft, restore the previous approved version, and export it. Notes captures local thoughts and dreams; reminder/calendar requests are reviewed separately before a system write. Review summarizes recorded mornings, with missing history kept distinct from measured activity.

Selected text, screenshots and videos feed a reviewable observation field. Apple model analysis, speech, Calendar/Reminders and automatic step execution have different verification needs. Automatic progression waits for a supported operation to finish; speaking an instruction does not prove a real-world task was done. Interactive steps remain user-controlled.

**Xcode 27 is installed, and the native app is signed, installed and running on the owner's iPhone 15 Pro Max with iOS 27.0.1.** Three core phone journeys passed, along with a real local-model proposal and a read-only Clock navigation/scroll test. The expanded verification record is in [PHASE-ONE.md](PHASE-ONE.md). Siri, real Calendar/Reminders writes, HomePod routing and recording ingestion need their own individual checks.

## First five minutes on your iPhone

1. Open **Morning Operator** and choose **Learn my morning**.
2. On iOS 27, choose **Record a little of my morning**, confirm Apple's sharing picker and show a short, harmless part of your routine. Return, stop, and use the recording. On earlier supported iOS versions, choose an existing recording or screenshot.
3. Review the extracted text, choose **Suggest a routine**, then edit the suggested moments. Apple Intelligence must be available; **Build it myself** and **Explore a sample** work independently.
4. Choose **This feels like me**, then **OK, here we go**. Supported spoken actions can advance when finished; personal activities and unconnected apps wait for you. The playback controls include Pause, Next and End morning.
5. Swipe between days in **Morning**, open **Review**, and save a dream or thought in **Notes**. Missing days stay empty. History currently measures app-run sessions; exact TikTok, Instagram and email behavior is a separate analytics milestone.
6. In **Settings → Companion voice**, choose an installed Apple voice and preview it. The audio-output control is where you choose AirPods or an available AirPlay speaker.

The recorder is a new device integration: use the current verification record to distinguish compiled code from an observed end-to-end recording result. No background week-long capture starts automatically.

## On the existing development Mac

Use the existing `morning-operator` checkout; you do not need a second clone. Open a terminal in that repository folder, then run:

```sh
./scripts/build-mac-app.sh --open
```

This builds and opens `build/Morning Operator.app`. To reopen the existing build later, use Finder or `open "build/Morning Operator.app"` from the repository. Rebuild after changing source code. Quit the running app before replacing its bundle.

The initial Mac build and package tests worked with Command Line Tools, Swift 6.4 and XcodeGen 2.45.3. Full Xcode 27 has since been installed and used for a successful signed iPhone build/install. Record the toolchain selected for each new run rather than treating the earlier Command Line Tools result as proof for every configuration.

## On the partner's Mac

1. Sign in with your own GitHub account and accept the invitation to the private [morning-operator repository](https://github.com/gibouu/morning-operator). If access is missing, ask the owner to check repository **Settings → Collaborators**. See [GitHub’s invitation guide](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/repository-access-and-collaboration/inviting-collaborators-to-a-personal-repository).
2. Use **macOS 26 or later**. That is the application's minimum; the actual tested host was macOS 27.0.1 on a MacBook Air M4. Apple Intelligence analysis additionally needs compatible hardware and a ready local model. The minimum OS declaration does not prove every Mac/toolchain combination has been tested.
3. Install/open [Apple Xcode](https://developer.apple.com/xcode/) compatible with the Mac's OS and, for phone work, the phone's installed iOS. Finish first-launch setup and select it in Xcode Settings → Locations → Command Line Tools. Record the actual version. The owner's successful signed phone installation used Xcode 27 with iOS 27.0.1; repeat setup with the partner's own machine and device. A compatible Command Line Tools installation may be enough for Mac-only work; the initial successful baseline was Swift 6.4, not every Swift 6 release.
4. Clone into a folder you choose using your own authenticated GitHub account. GitHub Desktop is an alternative to the terminal commands below. Never put access tokens in a clone URL, project file or test report.

```sh
mkdir -p "$HOME/Developer"
cd "$HOME/Developer"
git clone https://github.com/gibouu/morning-operator.git
cd morning-operator
./scripts/build-mac-app.sh --open
```

There are no third-party Swift package dependencies, cloud-model keys or shared signing secrets to install for this Mac prototype. Homebrew is not required. The local build script creates an ad hoc signed app bundle; this is a source build on your own Mac, not a notarized installer or TestFlight release.

If cloning says the repository is unavailable, check invitation acceptance and which GitHub account is authenticated before changing the URL or visibility. The original private product brief is deliberately excluded from Git; this guide and the checked-in setup/status documents are sufficient for the first build.

## Record the environment and run the package checks

Run these from your own checkout and record their output in a local test report:

```sh
git rev-parse HEAD
git status --short
./scripts/check-environment.sh
./scripts/test.sh --with-model
```

The environment script exits with code 2 when full Xcode is unavailable. That identifies the iPhone tooling gap; it does not mean the Mac tests failed. Run the test command separately even if that environment check reports the expected gap. The test script handles the Swift Testing macro plugin needed by the observed Command Line Tools 6.4 setup. It runs the local, dependency-free package with its package sandbox disabled; it does not install or control an iPhone.

For model readiness, check that Apple Intelligence is enabled in the device’s Apple Intelligence & Siri settings, use a supported language/region, and allow the local models to finish downloading. Apple recommends keeping the device on Wi-Fi and power while the models download. See [Apple’s setup guide](https://support.apple.com/en-lamr/121115). The app’s reported local-model availability remains the deciding check; enabling a separate Siri feature does not prove the app’s model is ready.

Use `./scripts/test.sh` without `--with-model` when you do not want to attempt the optional real model test. Read the reported counts and reasons. **Skipped means the check did not execute successfully, not that the feature passed.** Record an unavailable model separately from a failed core invariant. A clean run without real inference does not establish model quality.

Copy [TEST-REPORT-TEMPLATE.md](TEST-REPORT-TEMPLATE.md) into an ignored local folder for each run, for example:

```sh
mkdir -p work/test-reports
cp docs/TEST-REPORT-TEMPLATE.md work/test-reports/first-mac-run.md
```

## First Mac smoke test

Start with synthetic data. The normal app saves its workspace at `~/Library/Application Support/MorningOperator/workspace.json`. Approving a replacement draft releases the one previous approved version; this is not unlimited undo or a version-history browser.

For the manual sequence below, turn off automatic progression and spoken guidance in Settings first. Test automatic execution separately after the manual controls work. The `--ui-testing` fixture does this automatically so its step assertions do not race speech completion.

To keep the following test separate from an existing personal routine, quit Morning Operator and launch the built executable with a dedicated local workspace:

```sh
mkdir -p work/onboarding
MORNING_OPERATOR_DATA_DIR="$PWD/work/onboarding/app-data" \
  "./build/Morning Operator.app/Contents/MacOS/MorningOperator"
```

Keep that terminal open while using the app. Reuse this exact command for the restart check so the same test workspace is loaded. A normal Finder launch uses the normal Application Support workspace instead. For a fresh test later, choose another local directory; you do not need to delete personal data.

| Step | Expected result |
|---|---|
| Choose **Explore a sample** | A routine is clearly labeled as demo/sample data and awaits review. It is not presented as learned from your behavior. |
| Choose **This feels like me** | The routine is approved and can start. |
| Choose **OK, here we go**, then **Next** | State is running; Next advances to another step. Note its title. |
| Choose **Pause**, then **Continue** | State becomes paused, then running, with the same current step. |
| Quit while running; relaunch using the same workspace command | The session returns paused at the same step; it requires an explicit Continue. |
| Continue, then open **Morning controls → End morning** | State becomes stopped; the run no longer advances by itself. |
| Edit a step and save | Changes create an unapproved next draft. **Restore previous approved routine** restores the earlier approved content. |
| Export the approved routine | The native save panel writes JSON to the chosen local file. Review its content before sharing. |
| In Learn, import a local UTF-8 text file containing only an invented morning | The selected text appears in the notes field for review. Import alone does not generate or approve a routine. |
| Check Settings and Learn with an unavailable model | The unavailable reason is visible and analysis is disabled; sample/manual routines still work. Mark real inference skipped. |
| If the model is available, review the notes and choose **Suggest a routine** | A generated routine remains a draft for review. Its steps and supporting quotes should match the selected observation; reject invented claims. |

Also try the newer screens with synthetic data: in Notes, open capture, select **Dream**, enter an invented dream and choose **Save my dream**. Confirm the Dream filter shows it after leaving and returning to Notes. Swipe Morning to an empty previous day and back; an empty day should not display today's routine as historical activity. These are explicit test steps, not assertions that every new device check has passed.

Use **Build it myself** in Learn to test a manual routine independently of model availability. Imported observation notes are temporary UI content and do not survive quitting. Saved routines, the current session and one previous approved routine do persist.

Optional checks come after this basic journey: test voice audibly on a known output; connect Calendar deliberately and verify the local day/events. Calendar reading requests Apple's full calendar permission. The briefing reads events; saving a reviewed Calendar capture is a separate explicit write. Likewise, a local dream does not create an Apple Reminder. Record permission denial, an empty calendar and a successful read/write as distinct outcomes, and verify each against the detailed test record before claiming it works.

The source now exposes foreground Siri/Shortcuts actions: **Start morning** requests an approved routine, and **Quick capture** accepts a thought, dream, reminder request or calendar idea and opens it for review. The intent does not itself save to Calendar/Reminders or approve a changed routine. Siri phrase recognition and discovery still need a real installed-app test. System keyboard dictation and a Siri action are separate from continuous in-app voice commands.

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
| Product journey | Observe someone using sample/manual routines; fix one confusing interaction and reproduce the smoke test | Working Mac build |
| Semantic learning | Resolve model readiness, analyze synthetic observations, record grounded/unsupported steps and cancellation behavior | Available local Apple model |
| Phone proof | Compile/install the app, run fixture then Settings checks, document actual signing/SDK issues | Full Xcode and selected phone |
| Voice and audio | Verify local speech first, then one HomePod route; separately design live command input | Actual audio devices; phone work for iOS routing |
| Calendar | Test consent, denied/empty/event states and the correct day/timezone | A deliberately chosen local calendar |

Agree on files/interfaces before starting overlapping changes, use short branches, and review a concrete diff with test evidence. Keep one report per device/build. Merge only the completed scope and state any skips. The next useful milestone is a repeatable native Mac-to-iPhone demonstration, followed by a separately proven audio route; do not bundle all remaining integrations into one change.

## Keep evidence useful and private

Use invented names and events for first tests. `work/`, build outputs, screenshots and `.xcresult` bundles are ignored, but ignoring a file is not redaction. Logs, screenshots, accessibility trees, routine exports and short retained evidence quotes can still reveal personal content. Review and redact any excerpt before sharing it in a private issue or pull request. Do not attach complete personal recordings, calendar data, inboxes, workspace snapshots, account identifiers or credentials.

Share the commit, exact steps, observed/expected result and the smallest redacted evidence needed. Leave the raw evidence on the test machine. Do not copy the private source PRD into onboarding documents or test reports.
