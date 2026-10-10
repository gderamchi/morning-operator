# Get started with MORE

The iPhone is the active product. Use the Mac for Xcode, shared package tests and optional tethered experiments. There is no separate Mac app to install for this workflow.

This guide's first-morning steps follow V2 on `codex/more-quiet-morning`: **Morning** and **Review**. The installed phone baseline, `8a640ea`, still has the earlier labels and Notes tab; use its [short recording checklist](DEVICE-SETUP.md#tomorrow-morning-checklist). The [V2 design contract](V2-DESIGN.md) and [documentation hub](README.md) distinguish new source from verified device behavior.

## Your first morning

1. On first use, open **Morning → Learn my morning**. Show a short, harmless part of your actual morning using the explicit recording flow, or import selected media. Recording comes first; the text field is optional context. On later visits, open **Review → Learn from a morning** or **Review your observation**.
2. Stop recording and return to the app. Foreground processing extracts and saves visible text, then opens Learn when the app is ready. It does not generate a routine automatically. Read the actual observation and correct it if needed; a success banner alone is insufficient. **Confirm this observation** asks for a missing observed day, time zone and activity origin. Keep Unsure when you do not know; a file's import date is not its recording day. **Day and source** lets you revisit those details.
3. After saving the details, choose **Suggest a routine** or **Suggest an update** when the local model is available. Review the pending suggestion's moments and exact quotations while the current routine stays unchanged. **Done** keeps it for later; **Review suggested update** reopens it. Correct unsupported evidence in Learn and request a fresh suggestion, or choose **Build it myself** if needed. Planned minutes are estimates, not measured screen time.
4. Choose **Approve update**, then **Start my morning** in Morning. Approval itself does not start playback. To edit an installed/manual routine, use **Review → Your routine**, then **Approve this routine** after your changes. Supported spoken operations can advance after completion; personal activities and unconnected apps wait for **Next moment**. Pause, Continue or use **Morning controls → End morning** whenever needed.
5. At completion, **A thought, a dream, a reminder** opens capture. Save a local thought/dream or review an optional save to Apple Reminders/Calendar. Find saved items under **Review → Saved thoughts**. There is no Notes tab in V2, and this invitation is not yet a live spoken conversation.
6. In **Review**, tap the date range to reveal its days, then open a day. Use the period arrows or swipe the date range to move between seven-day periods. Dated observations and routine runs appear separately. Current averages measure recorded routine runs, not observed app usage. Settings and connections also live in Review.

**Find an earlier recording:** open **Review → Saved observations**. A new import keeps earlier observations; importing the same file again keeps the existing entry and its corrections. **Date needed** contains imports whose observed day is unknown. Open one to assign its day, time zone and whether it describes your own morning or test activity. Import time is never substituted for recording time.

An observation's detail keeps the original extraction separate from current notes. **Edit in Learn** changes the notes used for suggestions and clears the original's attached interpretation. **Delete this observation**, Learn's **Clear this observation**, or **Delete all observations** removes the stated observations and their retained originals/corrections. A pending update that depends on an edited/deleted source is invalidated; saved routines and any quotations already in them remain. A pending raw recording has its own Retry/Discard controls; see [retention](ARCHITECTURE.md#data-retention-today).

## Review or remove local data

In the current branch, open **Review → Settings & connections → Privacy & data**. This shows MORE's retained categories and the **Save app activity from Shortcuts** setting. Turning that setting off stops new journal writes without erasing existing records.

**Forget MORE’s local data → Forget local data** is the explicit full reset. It removes the current/previous routine, history, observations and retained quotations, thoughts, saved choices, pending suggestions, local receipts, activity and owned recording copies; it also cancels MORE's invitation. Cancel the confirmation to leave removal unstarted. After success, you can learn a new morning, and app activity remains off until you explicitly enable it.

If removal needs another try, ordinary work stays blocked. Retry in Privacy; an already-pending reset resumes after relaunch before the app reloads old content. Do not treat an empty-looking screen as proof of complete cleanup. Original Photos/Files media, exported files, Apple Calendar/Reminders items, permissions, installed voices, Shortcuts and backups remain separately managed. Developer evidence on the Mac is outside the app's reset. The [privacy guide](PRIVACY.md) lists exact scope and failure behavior. All three scoped simulator privacy journeys pass; physical recording shutdown remains unverified. This is not a secure-erasure or automatic-expiry feature.

## Update a routine from saved mornings

In **Review → Saved observations → Choose mornings**, select one to five dated observations from the same time zone. Choose either your mornings or synthetic samples; they cannot mix. Undated or unknown-origin entries show what needs correcting in their detail. The current routine stays unchanged while you choose and review.

Choose **Suggest an update** when the local model is available. Review the planned moments, exact supporting quotations and any omitted samples; **Compare with current routine** shows the existing plan. Preserved required rituals are labeled separately. **Done** keeps the suggestion for later, including after relaunch. **Keep current** discards it; without an existing routine, this button is **Discard**. **Approve update** saves the new approved version, then **Start my morning** remains a separate action. An active or paused morning blocks replacement.

To correct a source, open it from the suggestion and use **Edit in Learn**. Changing its text, date or origin—or changing the current routine—invalidates that dependent suggestion so you can request a fresh one. Candidate editing is not part of this sheet; ordinary routine editing remains under **Review → Your routine**. [The learning guide](ROUTINE-LEARNING.md) explains the input limits, citations and previous-version restoration. Planned minutes and selected dates do not establish measured app use or habit averages.

The unified flow (`48e5c95`) passed 235 shared checks with six optional skips, the native simulator build and three UI journeys with no skips: import preservation/relaunch, provenance → pending review → approval/relaunch, and setup-only rejection. No Apple model calls were made. Two further notice-review journeys passed across scoped runs, including review after a paused morning ends; the unsigned iPhone target also builds. Initial failures and corrected test setup remain in the verification record. The current UI remains uninstalled on the owner's phone; real model quality and capture/audio/route behavior are unverified. The preceding `4a2fd30` saved-mornings results remain separate in [verification](PHASE-ONE.md).

The earlier `8a640ea` build has run on the owner's iPhone 15 Pro Max with iOS 27.0.1; those physical results do not verify the V2 interface. One real short recording reached OCR, saved text, a visible draft and readable text after relaunch. Its habit interpretation was wrong: setup text became activities. A targeted evidence guard addresses that failure class, but accurate habit learning still requires the [controlled benchmark](https://github.com/gibouu/morning-operator/issues/23). See the [verification record](PHASE-ONE.md) for current results and earlier failures.

## Set up the development Mac

Use your own GitHub account and accept access to the private [repository](https://github.com/gibouu/morning-operator). Clone it into a folder you choose, or open the existing checkout. GitHub Desktop works too; never put access tokens in repository URLs or files.

```sh
git clone https://github.com/gibouu/morning-operator.git
cd morning-operator
git switch codex/more-quiet-morning
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
| Voice and audio | In Review → Settings & connections, choose an installed voice, preview it and choose an output route | Hear the actual output. A visible AirPlay picker does not prove sound or HomePod microphone access. |
| Calendar / Reminders | Read an authorized day; review an invented item before intentionally saving it | Verify permissions, date/timezone and the Apple app's result. A local note is not a system reminder. |
| Siri / Shortcuts | Discover Start morning and Quick capture, then verify the received request | They open app-owned review/start flows; invocation and locked-device behavior need their own checks. |
| App transitions | Configure Opened/Closed automations for selected Instagram, TikTok or Snapchat activity | Delivery is a separate hardware check. These callbacks are not complete usage, pickup or scrolling metrics. |
| HomePod | Route phone audio to the one available HomePod mini | Output is independent work. Room detection, microphone access and room-to-room handoff are not established. |

App-transition setup and clearing are in [Device setup](DEVICE-SETUP.md#optional-app-transition-logging). Disable its automations in Shortcuts to stop callbacks, or turn off **Save app activity from Shortcuts** in MORE's Privacy screen to refuse their writes. **Clear recorded app activity** removes the journal without deleting routine history or observations. Full forgetting also disables new activity collection. See the [retention matrix](ARCHITECTURE.md#data-retention-today) for each store and control.

## Choose the next useful change

Use the [roadmap](ROADMAP.md) and [V2 design work](https://github.com/gibouu/morning-operator/issues/25) to agree on one small outcome. The immediate priorities are reliable observation and a clear morning experience, followed by evidence-based weekly averages and continuous adaptation. Preserve the activities the person enjoys; productivity targets are optional.

Agree on file ownership before parallel work. Use short branches, review the concrete diff and record what actually passed. Keep first-use triggers, HomePod, narration/actions and research-data feasibility in their respective issues instead of treating a working recorder as proof of those integrations.

## Prepare Your day in V2

Open **Review → Settings & connections → Your day**, connect Calendar and select individual calendars. Optionally search for a weather city and choose a temperature unit. Refresh or hear the recap, then **Add to my morning** to create a draft that still requires review and approval. The app needs the WeatherKit capability on its App ID and provisioning profile for real weather; live Calendar/Weather and listener audibility remain separate checks. [Setup, freshness and data flow](YOUR-DAY.md).
