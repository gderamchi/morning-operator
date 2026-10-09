# Start working on Morning Operator

For the two founders. Updated 9 October 2026. Start with the working Mac app, reproduce the basic journey, then choose a bounded next experiment together.

## What you can try today

The Mac app lets you review or build a routine, approve it, run its steps, pause/resume/stop, edit a new draft, restore the previous approved version, and export it. Local text, screenshot and video imports feed a reviewable observation field. Apple model analysis, speech and Calendar adapters are present, with different levels of verification.

The last completed combined test run was **17 passed, 1 skipped, 0 failures** on macOS 27.0.1 with Apple Swift 6.4. The skipped test attempted real Apple model inference but the model reported **modelNotReady**. The native Mac journey, restart recovery, text import and JSON export were exercised. These are earlier results, not a fresh run performed while writing this guide. See [the full verification record](PHASE-ONE.md).

The iPhone application and UI-test harness are checked-in source and project configuration. They have not yet been compiled against the iOS SDK or run on an iPhone. Calendar access, audible speech, HomePod routing and real model generation remain first-proof work. The app does not yet accept live spoken commands, send email, or run an autonomous phone-control loop.

## On the existing development Mac

Use the existing `morning-operator` checkout; you do not need a second clone. Open a terminal in that repository folder, then run:

```sh
./scripts/build-mac-app.sh --open
```

This builds and opens `build/Morning Operator.app`. To reopen the existing build later, use Finder or `open "build/Morning Operator.app"` from the repository. Rebuild after changing source code. Quit the running app before replacing its bundle.

The last inspected setup had Command Line Tools, Swift 6.4 and XcodeGen 2.45.3; full Xcode was absent. Do not assume full Xcode has since been installed or selected. The Mac build and package tests worked with that Command Line Tools setup.

## On the partner's Mac

1. The repository owner manually invites the partner's confirmed GitHub account to the private [morning-operator repository](https://github.com/gibouu/morning-operator). The partner accepts the invitation and checks that the repository is visible when signed in. No invitation is implied by this document, and no partner account has been assumed. The owner can use repository **Settings → Collaborators → Add people**, then the partner accepts the invitation. See [GitHub’s invitation guide](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/repository-access-and-collaboration/inviting-collaborators-to-a-personal-repository).
2. Use **macOS 26 or later**. That is the application's minimum; the actual tested host was macOS 27.0.1 on a MacBook Air M4. Apple Intelligence analysis additionally needs compatible hardware and a ready local model. The minimum OS declaration does not prove every Mac/toolchain combination has been tested.
3. Install/open [Apple Xcode](https://developer.apple.com/xcode/) compatible with the Mac's OS and, for phone work, the phone's installed iOS. Finish first-launch setup and select it in Xcode Settings → Locations → Command Line Tools. Record the actual version. No particular newly installed Xcode version has been validated by this project yet. A compatible Command Line Tools installation may be enough for Mac-only work; the successful baseline was Swift 6.4, not every Swift 6 release.
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
| Continue, then **Stop** | State becomes stopped; the run no longer advances by itself. |
| Edit a step and save | Changes create an unapproved next draft. **Restore previous approved routine** restores the earlier approved content. |
| Export the approved routine | The native save panel writes JSON to the chosen local file. Review its content before sharing. |
| In Learn, import a local UTF-8 text file containing only an invented morning | The selected text appears in the notes field for review. Import alone does not generate or approve a routine. |
| Check Setup and Learn with an unavailable model | The unavailable reason is visible and analysis is disabled; sample/manual routines still work. Mark real inference skipped. |
| If the model is available, review the notes and choose **Find my routine** | A generated routine remains a draft for review. Its steps and supporting quotes should match the selected observation; reject invented claims. |

Use **I'll build it myself** in Learn to test a manual routine independently of model availability. Imported observation notes are temporary UI content and do not survive quitting. Saved routines, the current session and one previous approved routine do persist.

Optional checks come after this basic journey: test voice audibly on a known output; connect Calendar deliberately and verify the local day/events. Calendar reading requests Apple's full calendar permission, although the app does not modify events. Record permission denial, an empty calendar and a successful read as distinct outcomes. These checks have not yet been demonstrated in the project evidence.

## Move to iPhone and HomePod

Follow [DEVICE-SETUP.md](DEVICE-SETUP.md) for pairing, Developer Mode, signing, explicit device selection, fixture tests and bounded installed-app observation. Full Xcode and matching iOS platform support are required. A successful Mac build or generated project is not an iPhone build result.

The generated project is checked in, so begin with:

```sh
open MorningOperator.xcodeproj
```

**XcodeGen is optional for opening the checked-in project.** Install it only when you need to regenerate after adding/removing source files or changing `project.yml`; use its [upstream installation instructions](https://github.com/yonaskolb/XcodeGen#installing), which include alternatives to Homebrew. Then run `./scripts/generate-project.sh` and review the project diff. Where the device guide includes generation, you can omit that step when the checked-in project is already current. The device-test runner itself regenerates the project and therefore requires XcodeGen.

Select your own development team locally. Do not commit a personal team setting, certificate, provisioning profile, Apple account credential or device identifier. Run the fixture suite before the Settings suite or any deliberately selected external app. Keep XCTest control in the separate test target; it is not a permission granted to the ordinary iPhone application.

The currently known hardware is one iPhone 15 Pro Max, one MacBook Air M4 and **one HomePod mini**. The first audio proof is phone-or-Mac → that HomePod, with the actual microphone and audio origin identified. The saved **Set Playback Destination** Shortcut experiment is described in the device guide. It has not been implemented or proved here. One HomePod cannot demonstrate transfer between two HomePods; manual route selection must be labeled as manual. A room-detection prompt and automatic transfer still require separate real evidence.

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
