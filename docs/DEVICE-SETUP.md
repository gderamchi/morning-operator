# Personal device setup

The iPhone 15 Pro Max is the sole active product client; the MacBook Air M4 runs Xcode, shared package tests and optional tethered development control. The separate native Mac app was removed at the owner's request. One HomePod mini remains the audio test target. Installing the iPhone app and running XCUI tests requires full Xcode; Command Line Tools are insufficient. Full Xcode 27 is now installed, and a signed development build has been installed on the owner's phone. No App Store submission is needed for this personal setup.

## What was actually checked

On 9 October 2026, **full Xcode 27 is installed** on the development Mac, the physical **iPhone 15 Pro Max running iOS 27.0.1** was detected with **Developer Mode enabled**, and the iOS application **built, signed and installed successfully**.

The app launched successfully. Four core fixture journeys passed on the physical phone, as did a real Foundation Models proposal from synthetic notes and a bounded read-only Clock navigation/scroll test. Editing/recovery checks passed; recording validation is tracked separately; Siri, EventKit writes and HomePod audio have not been proved by these tests. [PHASE-ONE.md](PHASE-ONE.md) holds the detailed verification record as checks finish.

The project targets iOS 26.0 and the Swift package targets iOS/macOS 26.0. The tested installation used iOS 27.0.1 and Xcode 27; support for every older deployment-target/device combination has not been demonstrated. Newer SDK-only experiments need separate availability checks.

## Prepare Xcode and the phone

1. Install/open a full Xcode version that supports the phone's OS and install its iOS platform support. Complete any first-launch component setup. In Xcode Settings → Locations, select that Xcode as Command Line Tools.
2. Connect the phone by USB, unlock it and complete Trust/Developer Mode prompts. Inspect its status in Xcode’s device manager (Device Hub in Xcode 27; Devices and Simulators in older Xcode). Do not run against a locked or unidentified phone.
3. Run `scripts/check-environment.sh` from this repository. Record Xcode, iOS, device model and build numbers in the local test notes. Its exit code 2 means full Xcode is unavailable, not that an iPhone test failed.
4. Open the checked-in `MorningOperator.xcodeproj`. Regenerate it with `scripts/generate-project.sh` after source additions/removals or `project.yml` changes; generation needs XcodeGen. The command-line device-test runner regenerates the project automatically and therefore requires XcodeGen. The iOS application uses the local package's `MorningCore` and `MorningApple` products; XCUI code belongs only to `MorningOperatorUITests`.
5. Select your own development team for the application and UI-test targets in Xcode. The repository deliberately contains no team ID or signing credentials. The app bundle is `com.gibouu.morningoperator`; the test bundle is `com.gibouu.morningoperator.uitests`. Resolve signing through Xcode before invoking command-line tests. The script does not register devices or modify provisioning automatically.
6. Build/run the app on the explicitly selected phone. Verify the native interface first. A Mac package build does not validate the iOS SDK or device installation.

The owner's current checkout has completed signed installation and launch; leave the phone unlocked for test runs. A partner repeats setup on their own Mac and phone, with their own account, development team and device selection. Keep those identifiers in local configuration and test evidence rather than shared documentation.

## Check the installed app

The current native interface has **Morning**, **Review** and **Notes** tabs. Morning contains the day strip, routine timeline and run controls; **Learn & refine** opens learning, and the toolbar opens **Settings**. Use synthetic content for the first device walkthrough.

- [x] Unlock the selected phone and confirm the installed app launches. Record an actual launch result separately from installation.
- [x] Review and approve a sample, start it, move to another step, pause and continue without losing the current step. Open **Morning controls → End morning** and confirm the stopped state.
- [x] In Notes, create a **Dream** with invented text and choose **Save my dream**. Confirm it appears under the Dream filter and survives switching tabs. This path saves locally and does not write to Calendar or Reminders.
- [x] Swipe Morning to yesterday. An empty day must show an empty-history message rather than today's draft. Swipe back to today. Review should distinguish missing history from measured activity; no cross-app usage is implied.
- [ ] Check Learn and Settings on the physical screen, including unavailable-model messaging. A successful routine proposal requires a separate real model test.
- [ ] Exercise automatic progression separately: a supported spoken briefing can advance after synthesis finishes; interactive steps wait for the user. Pausing, stopping, interruptions and unavailable adapters must not count as completed actions.
- [ ] Verify Siri/Shortcuts discovery and foreground routing separately. **Start morning** requests an already approved routine; **Quick capture** takes a thought, dream, reminder request or calendar idea into the app for review. The intent itself does not approve a draft, save a system item or prove that Siri worked on this phone.
- [ ] In Settings, test voice audibly and use the real iPhone audio-output picker. Confirm the selected speaker/headphones and actual sound. AirPlay output does not expose the HomePod microphone; the Mac companion instead points to Control Center.

Checked items have recorded device evidence; unchecked items are still pending. Calendar/Reminders permissions and writes, microphone input, HomePod transfer and external-app observation are separate deliberate tests. A local dream fixture must not request or exercise those integrations.

Permission purpose strings explain user-initiated microphone, speech and EventKit requests; they are not permission approval. The Calendar briefing reads events. EventKit reading requires full calendar permission even when the current operation does not modify events. Saving a reviewed reminder/calendar capture is a separate explicit write and needs its corresponding authorization. Validate each integration separately rather than inferring HealthKit, Screen Time, HomeKit or recording support from successful app installation. Audio playing in a foreground app does not establish background operation.

## Run the fixture journey

Find the exact device identifier with the full Xcode device UI or `xcrun devicectl list devices`. Supply that identifier and your development team explicitly:

```sh
scripts/run-device-tests.sh --device YOUR_DEVICE_ID --team YOUR_TEAM_ID --suite fixture
```

The fixture suite starts the app with `--ui-testing --fixture-mode`, which creates an isolated temporary workspace and disables automatic progression and speech. It exercises approve → start → next → pause → resume → Morning controls → stop, checking the actual displayed state and preserved current item. Additional tests save a synthetic local dream, verify its category and tab navigation, and swipe to an empty past day and back. They request no external permissions and create no Calendar or Reminders items. All four journeys passed, including editing, approved-version restoration and recovery across relaunch. See PHASE-ONE for the latest full run. They do not inspect a personal inbox or prove external-app control.

The test runner uses an amended local `.xctestrun` file so environment settings reach XCTest. It reuses `.build/iphone` across suites, builds incrementally, then runs without rebuilding. Results and screenshots are in a unique `work/device-runs/.../Results.xcresult`; build/test logs are beside the result. Open that result in Xcode and distinguish **passed**, **failed** and **skipped**. An exit status alone must not turn a skipped hardware check into a pass.

## Local model and Clock checks

```sh
scripts/run-device-tests.sh --device YOUR_DEVICE_ID --team YOUR_TEAM_ID --suite learning
scripts/run-device-tests.sh --device YOUR_DEVICE_ID --team YOUR_TEAM_ID --suite clock
```

The learning test supplies synthetic calendar/chess notes to the actual local model. It explicitly skips if unavailable; once an attempt begins, generation failure is a failure. A result must be a new unapproved draft. This passed on the owner's phone on 9 October 2026.

The Clock test switches between World Clock and Alarms, performs one upward list gesture, compares visible row positions, and returns to World Clock. It never changes alarms or starts timers. It passed on the owner's phone. This proves bounded developer-test control, not unrestricted control from the ordinary app.

## Record a short morning

The following describes the latest working source, not a completed hardware test. On iOS 27, open **Learn my morning → Record a little of my morning**. Choose a 5, 10, 20 or 30-minute limit, tap **Start screen recording**, review Apple’s picker and select the scope yourself. Keep the first clip short and use harmless content. The app-owned Record/Learn sheets are designed to close after acknowledged capture starts; a compact recording status and Stop control remain. Apple’s system panel may still require the person to dismiss it: no verified automatic dismissal or public dismissal API is established.

Use the in-app or system Stop control, or let the duration/256 MiB bound request a stop. The latest source moves a finalized recording into recovery directly from the service callback, including while the UI is backgrounded. The foreground app then processes a same-session recording when no analysis or routine session is active; a recovered recording after relaunch requires Retry. The final iPhone build-for-testing succeeded and two recovery storage checks passed after the latest metadata change; actual background handoff and recording ingestion still need device verification. It extracts and persists visible text, then requests an unapproved model proposal if the model is available. The normal revised path needs no separate Use step. Review/correct the draft before approval. If the model is unavailable, review the saved text and use Suggest a routine later. Selected file imports retain their explicit Suggest a routine step.

The revised recovery contract keeps an app-owned recording after OCR, cancellation or persistence failure and offers Retry/Discard. Successful persistence of extracted text permits video removal even if model generation later fails. User-selected originals are not deleted. Latest extracted text survives relaunch; **Clear this observation** removes it, while routine evidence quotes remain. The source restores one retained recording from its local RecordingRecovery slot on launch, without starting analysis automatically. Discard recording removes that file; Clear this observation removes extracted text. Validate relaunch, retry, each failure and cleanup path on hardware before claiming it works.

Recording is screen-only and can include personal material shown on screen; it does not request microphone/camera input. On iOS 26, choose an existing recording, screenshot or text file. Extraction samples up to 24 moments and does not prove every transition, message read or minute of app usage. No first-use trigger, Screen Time data access or automatic learning schedule is implemented.

The earlier recording test failed after approximately 244 seconds: Apple’s panel remained visible in the captured screen and notes were empty after Use. A later owner-confirmed record → system Stop → Use sequence showed the Home-screen recording indicator, then an Observation loaded banner. The owner then checked the ordinary-app Learn field and found it empty. This is an unresolved failed end-to-end user check; the banner does not establish usable extracted text, persistence or a model draft. Preserve that distinction when rerunning the new flow; [PHASE-ONE.md](PHASE-ONE.md) records the evidence.

## Optional app-transition logging

The new action and Review card have an initial successful phone build-for-testing and nine passing focused transition checks. Installed Shortcuts discovery/delivery and the new Today card still need device verification. They do not require or start screen recording.

1. In **Review → Connect app activity**, read the setup instructions. In Apple Shortcuts, create an **App** automation for one supported app: Instagram, TikTok or Snapchat. Choose **Is Opened** and **Run Immediately** if automatic execution is desired.
2. Add **Log an app transition**, select that same app and **Opened or switched to**. Leave Event ID empty for normal use. A caller intentionally retrying one event can supply and reuse its UUID; unrelated events need distinct IDs.
3. Create a separate **Is Closed** automation with **Closed or switched from**. Repeat only for the apps the person wants included. No personal automations are silently installed by the app.
4. Use two configured apps and return to the first, then open Review. Check the Today entry/return counts against what actually ran; verify that logging itself never brings Morning Operator forward. Repeat after cold launch and record any delayed/missing callbacks.
5. Disable the corresponding Shortcuts automations to stop future collection. Existing events remain in local `app-transitions.json` until **Clear recorded app activity** is used in the setup sheet. This clear flow still needs device verification; export and automatic retention limits remain future work.

This records callback-time app entries/exits for configured apps. It is not an operating-system app-launch log or physical pickup count. The Today card can show returns after another tracked app, but intermediate unconfigured apps and missing events may be absent. The logger stores event IDs, app/transition, timestamp, time zone and source; it does not read messages or screens. Background intent delivery and separate-journal persistence require their own tests, independent of recording and routine history. [Apple App-trigger definitions](https://support.apple.com/guide/shortcuts/setting-triggers-apde31e9638b/ios).

## Settings smoke test

Return Settings to its main page before starting. This avoids a prior session's nested screen causing a skip. The default navigation labels are English. Use the actual labels on the phone; the test does not change the device's language.

```sh
scripts/run-device-tests.sh --device YOUR_DEVICE_ID --team YOUR_TEAM_ID --suite settings
```

For a French-language phone, for example, supply the exact General/About labels as displayed on that device using `--general-label` and `--about-label`. Do not assume translated labels from this document.

The suite launches installed Settings, captures the initial screen, finds General through at most three scrolls, re-queries the target immediately before tapping, verifies About appears, then navigates to About and verifies its navigation title. It changes no setting. A second test deliberately requests a missing target and confirms the executor stops without tapping. Unsupported/localized/unavailable screens produce a skip or failure, not coordinate guessing.

## Explicit external-app observation

Find the actual installed app's bundle ID through Xcode/device inventory. If using `devicectl`, inspect `xcrun devicectl device info apps --help` for the installed tool version. Choose one app/account intentionally and dismiss unrelated prompts yourself before starting.

```sh
scripts/run-device-tests.sh --device YOUR_DEVICE_ID --team YOUR_TEAM_ID \
  --suite external --external-bundle ACTUAL.INSTALLED.BUNDLE
```

This starts the selected app and captures one screenshot. It performs no gesture by default. To investigate one read-only navigation step, supply both `--navigate-label` and `--expect-label`. The navigation label must be one of `Inbox`, `All Inboxes`, `Mailboxes`, `Chats`, `Messages`, `Settings` or `About`. The expected label must be a semantic element absent before the action and present afterwards. A locale/custom interface outside that small list needs a reviewed test change, not a hidden coordinate fallback.

```sh
# Example shape only: substitute labels that actually exist in the chosen app.
scripts/run-device-tests.sh --device YOUR_DEVICE_ID --team YOUR_TEAM_ID \
  --suite external --external-bundle ACTUAL.INSTALLED.BUNDLE \
  --navigate-label Inbox --expect-label 'A label unique to the opened screen'
```

The driver requires foreground state, a unique exact semantic match, a hittable element, stable geometry and a fresh re-query. It refuses unexpected app/system alerts and sheets. It never types, sends, deletes, purchases, accepts dialogs, replays screenshot coordinates or retries an ambiguous action. These are bounded capability tests, not an autonomous cross-app agent.

Screenshots can contain account names and personal content even in Settings. `--capture-ui-tree` additionally records the accessibility hierarchy in the local test result and is off by default. Keep `work/`, derived data and `.xcresult` files out of Git and public attachments. Review evidence locally before sharing anything.

## Real HomePod spike

With one HomePod mini, prove **phone → HomePod** or **Mac → HomePod** audio continuation. Identify the actual audio origin and microphone; two-HomePod room handoff is not possible with this inventory alone.

1. Confirm the HomePod's name/software/network in the Home app. Use a known Wi-Fi network that allows the devices to discover one another. Record the actual iPhone, Mac and HomePod versions.
2. Prove ten seconds of native text-to-speech from the app is audible on the phone or Mac. Then use the system output selector to choose the HomePod and verify real sound there.
3. On iPhone, investigate an app-owned `AVAudioSession` with `.playAndRecord` and `.allowAirPlay` for iPhone microphone input plus HomePod output. Test modes explicitly; do not assume `.voiceChat` works with AirPlay. Pause speech during initial listening turns. AirPlay is an **output**, not permission to record from the HomePod microphone.
4. In the owner's Shortcuts app, create and inspect a routing-only **Set Playback Destination** shortcut targeting this HomePod. Prove it works manually first. Do not include a message-send action or private message text in this routing shortcut.
5. In a later integration, run that saved shortcut from the native app using Apple's URL scheme, with success/cancel/error callbacks. Preserve the current routine item. A successful callback is not proof of the resulting audio route: inspect the actual route and verify audible continuation before marking the transfer complete. `AVRoutePickerView` remains a truthful manual fallback.
6. Test cancellation, an unavailable HomePod, connection loss, speaker latency and microphone self-echo. Keep private speech paused if the output disappears rather than unexpectedly playing it publicly from another speaker.
7. Treat proactive room detection as a separate spike. An available HomePod does not prove the owner moved rooms. A named Siri Shortcut on HomePod is an optional command path, not continuous raw HomePod microphone access. A per-home autoapproval preference grants product consent only; it cannot supply a missing presence/routing capability.

These HomePod steps are a test plan; this repository has not demonstrated them. No saved personal Shortcut is installed or invoked by the device test scripts.

Official references: [Apple output/Handoff guide](https://support.apple.com/guide/iphone/homepod-and-other-wireless-speakers-iph315e0d58d/ios), [AirPlay option](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/allowairplay), [route selection](https://developer.apple.com/documentation/avkit/avroutepickerview), [Set Playback Destination](https://developer.apple.com/videos/play/wwdc2021/10283/), [run a saved Shortcut](https://support.apple.com/guide/shortcuts/apd624386f42/ios), [Shortcut callbacks](https://support.apple.com/guide/shortcuts/apdcd7f20a6f/ios), [route-change observation](https://developer.apple.com/documentation/avfaudio/responding-to-audio-route-changes), [Siri Shortcuts](https://support.apple.com/guide/shortcuts/apd07c25bb38/ios).
