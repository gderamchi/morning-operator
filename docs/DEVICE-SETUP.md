# Personal device setup

This is a development prototype for the owner's iPhone 15 Pro Max, MacBook Air M4 and one HomePod mini. The Mac package can be built independently. Installing the iPhone app and running XCUI tests requires full Xcode; Command Line Tools are insufficient. No App Store submission or distribution entitlement approval is needed for this setup.

## What was actually checked

On 9 October 2026, `scripts/check-environment.sh` reported macOS **27.0.1**, Apple Swift **6.4**, XcodeGen **2.45.3**, and developer directory `/Library/Developer/CommandLineTools`. Full Xcode was not selected. The iPhone's installed OS, pairing, Developer Mode, signing and Apple Intelligence readiness have not been checked. No iPhone or HomePod test has run.

The project targets iOS 26.0 and the Swift package targets iOS/macOS 26.0. This is a minimum, not an assertion about the phone's installed software. Newer SDK-only experiments need separate availability checks.

## Prepare Xcode and the phone

1. Install/open a full Xcode version that supports the phone's OS and install its iOS platform support. Complete any first-launch component setup. In Xcode Settings → Locations, select that Xcode as Command Line Tools.
2. Connect the phone by USB, unlock it and complete Trust/Developer Mode prompts. Inspect its status in Xcode → Window → Devices and Simulators. Do not run against a locked or unidentified phone.
3. Run `scripts/check-environment.sh` from this repository. Record Xcode, iOS, device model and build numbers in the local test notes. Its exit code 2 means full Xcode is unavailable, not that an iPhone test failed.
4. Run `scripts/generate-project.sh`, then open `MorningOperator.xcodeproj`. The iOS application uses the local package's `MorningCore` and `MorningApple` products; XCUI code belongs only to `MorningOperatorUITests`.
5. Select your own development team for the application and UI-test targets in Xcode. The repository deliberately contains no team ID or signing credentials. The app bundle is `com.gibouu.morningoperator`; the test bundle is `com.gibouu.morningoperator.uitests`. Resolve signing through Xcode before invoking command-line tests. The script does not register devices or modify provisioning automatically.
6. Build/run the app on the explicitly selected phone. Verify the native interface first. A Mac package build does not validate the iOS SDK or device installation.

The iOS/macOS configuration plists declare microphone and speech-recognition purpose strings plus Calendar access for the user-initiated read-only briefing integration. EventKit reading requires full calendar permission even when the app chooses not to modify events. A purpose string is not permission approval. There are no HealthKit, Family Controls, HomeKit, ReplayKit, background-audio or other capability entitlements in this first configuration; add only the capability required by a concrete integration and validate it. Audio currently playing in a foreground app does not establish background operation.

## Run the fixture journey

Find the exact device identifier with the full Xcode device UI or `xcrun devicectl list devices`. Supply that identifier and your development team explicitly:

```sh
scripts/run-device-tests.sh --device YOUR_DEVICE_ID --team YOUR_TEAM_ID --suite fixture
```

The fixture test starts the app with `--ui-testing --fixture-mode`, then exercises approve → start → next → pause → resume → stop. It checks the actual displayed run state and preserved current item. This is synthetic app data; it does not inspect a personal inbox or prove external-app control.

The test runner uses an amended local `.xctestrun` file so environment settings reach XCTest. It builds once and runs without rebuilding. Results and screenshots are in a unique `work/device-runs/.../Results.xcresult`; build/test logs are beside the result. Open that result in Xcode and distinguish **passed**, **failed** and **skipped**. An exit status alone must not turn a skipped hardware check into a pass.

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
