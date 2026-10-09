# Get started with Morning Operator

The iPhone is the active product. Use the Mac for Xcode, shared package tests and optional tethered experiments. There is no separate Mac app to install for this workflow.

Already have the phone build? Start with [tomorrow's short recording checklist](DEVICE-SETUP.md#tomorrow-morning-checklist). For implementation detail, use the [documentation hub](README.md).

## Your first morning

1. Open **Morning Operator → Learn my morning**. Show a small, harmless part of your actual morning using the explicit recording flow, or import selected media. Recording comes first; the text field is optional context.
2. Stop the recording and return to the app. Foreground processing extracts and saves visible text; a ready local Apple model may propose an unapproved routine. Open the observation and read the actual text. A success banner alone is insufficient.
3. Review the proposal. Keep enjoyable rituals, correct unsupported steps and change suggested durations. A proposed duration is an estimate, not measured screen time. If evidence is insufficient, keep the text and try a clearer observation; **Build it myself** is also available.
4. Choose **This feels like me**, then **OK, here we go**. Supported spoken operations can advance after completion. Personal activities and unconnected apps wait for Next. Pause, continue or use **Morning controls → End morning** whenever needed.
5. Save a dream or thought in **Notes**. Reminder/calendar ideas can stay local or be reviewed before a separate save to Apple Reminders/Calendar.
6. Browse days in **Morning** and review recorded runs in **Review**. Missing days stay empty. The planned weekly average of observed app habits is separate from today's routine-run history.

The signed build has run on the owner's iPhone 15 Pro Max with iOS 27.0.1. One real short recording reached OCR, saved text, a visible draft and readable text after relaunch. Its habit interpretation was wrong: setup text became activities. A targeted evidence guard addresses that failure class, but accurate habit learning still requires the [controlled benchmark](https://github.com/gibouu/morning-operator/issues/23). See the [verification record](PHASE-ONE.md) for current results and earlier failures.

## Set up the development Mac

Use your own GitHub account and accept access to the private [repository](https://github.com/gibouu/morning-operator). Clone it into a folder you choose, or open the existing checkout. GitHub Desktop works too; never put access tokens in repository URLs or files.

```sh
git clone https://github.com/gibouu/morning-operator.git
cd morning-operator
./scripts/check-environment.sh
./scripts/test.sh
open MorningOperator.xcodeproj
```

Use full [Xcode](https://developer.apple.com/xcode/) compatible with the Mac and the phone's installed iOS. Finish its first-launch setup and select it in Xcode Settings → Locations → Command Line Tools. The observed working setup is **Xcode 27 on macOS 27.0.1**, with **iOS 27.0.1** on the phone. The package targets macOS/iOS 26; native recording needs iOS 27. Deployment targets alone do not prove every older hardware/toolchain combination works.

The environment check reports exit code 2 if full Xcode is unavailable. Run the package tests separately: a missing phone toolchain does not mean Core tests failed. There are no third-party Swift package dependencies, cloud-model keys or shared signing secrets.

The generated Xcode project is checked in. **XcodeGen is optional for opening it**, but required by `scripts/generate-project.sh` and the device-test runner. Regenerate after changing project structure or `project.yml`, and review the diff. Use [XcodeGen's installation instructions](https://github.com/yonaskolb/XcodeGen#installing); Homebrew is not required for ordinary onboarding.

## Build and run on your iPhone

1. Connect and unlock your phone. Complete Trust and Developer Mode prompts, then identify it in Xcode's device manager.
2. Open `MorningOperator.xcodeproj`, select **MorningOperator** and your phone, and choose your own development team. Resolve signing in Xcode first.
3. Build/run. Verify that the installed app opens before attempting model, recording or audio checks.
4. Follow the [device guide](DEVICE-SETUP.md) for the fixture suite and each integration's separate checks.

Each collaborator signs and installs with their own account/team/device configuration. Do not commit team settings, device identifiers, certificates, provisioning profiles or credentials. No App Store submission is needed for this personal development build.

The project’s XCTest controller is a separate Mac-hosted test target. It does not give the ordinary iPhone app permission to tap through arbitrary apps. Clock navigation has a bounded recorded proof; broader model-driven control is [future work](https://github.com/gibouu/morning-operator/issues/7).

## Check the model and keep test evidence

Apple Intelligence must be supported, enabled and ready on the device. Check the app's availability message and allow the local model to finish downloading. See [Apple's setup guide](https://support.apple.com/en-lamr/121115). Manual routines do not depend on model readiness.

```sh
./scripts/test.sh
./scripts/test.sh --with-model
```

The first command runs the shared package checks. The second deliberately opts into real-model integration checks. A skip means the check did not establish a pass. Deterministic evidence filtering, actual model generation and device UI behavior are separate results.

Copy [TEST-REPORT-TEMPLATE.md](TEST-REPORT-TEMPLATE.md) into an ignored local report for each device/build. Include the commit, actual environment, steps, observed result and skip reason. Keep personal recordings, OCR, screenshots, accessibility trees and result bundles local; share the smallest reviewed/redacted excerpt only when needed. Ignored files are not automatically private or redacted.

## Optional connections

| Connection | Try deliberately | Boundary |
|---|---|---|
| Voice and audio | In Settings, choose an installed voice, preview it and choose an output route | Hear the actual output. A visible AirPlay picker does not prove sound or HomePod microphone access. |
| Calendar / Reminders | Read an authorized day; review an invented item before intentionally saving it | Verify permissions, date/timezone and the Apple app's result. A local note is not a system reminder. |
| Siri / Shortcuts | Discover Start morning and Quick capture, then verify the received request | They open app-owned review/start flows; invocation and locked-device behavior need their own checks. |
| App transitions | Configure Opened/Closed automations for selected Instagram, TikTok or Snapchat activity | Delivery is a separate hardware check. These callbacks are not complete usage, pickup or scrolling metrics. |
| HomePod | Route phone audio to the one available HomePod mini | Output is independent work. Room detection, microphone access and room-to-room handoff are not established. |

App-transition setup and clearing are in [Device setup](DEVICE-SETUP.md#optional-app-transition-logging). Disable its Shortcuts automations to stop new callbacks; **Clear recorded app activity** removes the saved journal. That control does not delete routine history or observation text. See the [retention matrix](ARCHITECTURE.md#data-retention-today) for each store and control.

## Choose the next useful change

Use the [roadmap](ROADMAP.md) and [V2 design work](https://github.com/gibouu/morning-operator/issues/25) to agree on one small outcome. The immediate priorities are reliable observation and a clear morning experience, followed by evidence-based weekly averages and continuous adaptation. Preserve the activities the person enjoys; productivity targets are optional.

Agree on file ownership before parallel work. Use short branches, review the concrete diff and record what actually passed. Keep first-use triggers, HomePod, narration/actions and research-data feasibility in their respective issues instead of treating a working recorder as proof of those integrations.
