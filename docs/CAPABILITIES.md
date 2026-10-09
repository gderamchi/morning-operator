# Apple capabilities and implementation boundaries

Updated 9 October 2026. This is a personal native prototype targeting iOS 26 and macOS 26 or later. The native recorder uses iOS 27 APIs behind an availability check; iOS 26 retains file import. See [PHASE-ONE.md](PHASE-ONE.md) for recorded verification and [DEVICE-SETUP.md](DEVICE-SETUP.md) for the development harness.

## What the source implements

| Area | Implemented behavior | Evidence still needed |
|---|---|---|
| Routine learning | Explicitly recorded or deliberately selected screenshot/video/text → local extraction → reviewable text → constrained Apple model proposal → editable, unapproved routine. | Successful model inference when Apple reports the local model available; real observation quality. |
| Local notes | Typed or Siri-prefilled thoughts, dreams, reminder requests, and calendar ideas can enter an editable capture flow. Saved items stay in the app's local workspace. | New UI and installed Siri walkthrough, cancellation and restart checks. |
| Suggested dates | A small deterministic English/French parser recognizes trailing relative hours/minutes and next/tomorrow morning. All scheduling dates remain reviewable suggestions. | Broader language support and a more complete date grammar. |
| Reminders | Explicit full-access request, bounded reads of incomplete dated reminders, and one reviewed reminder creation. An alert is attached only when the supplied draft enables it and has a due time. | Permission denial/revocation, default-list availability, one owner-confirmed real write/read on intended hardware. |
| Calendar | Existing day snapshot reader uses full access. New single-event creation requests write-only access when possible and requires a reviewed start/end/time zone. | Actual consent and event checks, including the destination account and time zone. |
| Spoken guidance | Real system speech with pause/resume/stop and completion callbacks. | Audible output on the intended Mac, iPhone, and speaker; interruption and route-change rehearsal. |
| Automatic progression | An approved running session dispatches one supported app action at a time. Briefing/calendar speech can complete after the matching speech callback. Unavailable adapters and real-world activities wait for the user. | Integrated UI/device verification and additional concrete action adapters. |
| Siri / Shortcuts | Custom App Intents request a start or open a capture draft in the app. They do not approve a routine or write to EventKit themselves. | Installed app metadata discovery, phrase recognition, locked-device behavior, cold launch, and completion handling. |
| Device control | A separate Xcode UI-test harness contains bounded fixture and external-app navigation experiments. | Signed app installed and launched on iPhone; see PHASE-ONE for individual test results. This is not an app-runtime controller. |
| Daily review | Local terminal-session records support day/week summaries; a stopped run is distinguishable from a completed run. | New review UI walkthrough and intentional long-term retention controls. |

“Implemented” describes source behavior, not proof that every OS permission, device, account or service is connected. The current app has no live email/message connector, HealthKit pipeline, Screen Time shield, Live Activity extension, HomeKit control, autonomous robot, or billing implementation.

## Capture and semantic learning

Learn offers **Record my morning** on iOS 27 and **Choose a recording or file** on all supported platforms. Capture begins only after the person starts the flow and confirms Apple’s picker. The importer reads only the selected local file, uses security-scoped access while reading, samples at most 24 video frames, and uses Vision to extract visible text. Fast transitions may be missed; OCR does not provide a historical touch stream or establish why the user acted. The selected source file remains the user's file. The app does not keep exported sampled frames. [Vision text recognition](https://developer.apple.com/documentation/vision/recognizetextrequest).

The OS 26 semantic path sends reviewed text to `SystemLanguageModel` and checks availability first. Dynamic guided-generation schemas constrain the response; validation then rejects unknown action categories, out-of-range durations, and evidence quotes absent from the supplied text. Every accepted proposal is unapproved. Model availability is a runtime state, not a consequence of the framework importing successfully. Manual setup remains available when the model is unavailable. [SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel).

This implements one-observation interpretation. Multi-day habit clustering, confidence tracking, contextual exceptions, and general cross-app visual understanding are future work. No model-generated proposal is permission to perform an external effect.

### iOS 27 native recording

Apple now documents ScreenCaptureKit on iOS 27. Its sample presents `SCContentSharingPicker` for either the full display or the app's own content, then captures with `SCStream`. `SCRecordingOutput` encodes a recording to a file. A full-display stream surviving backgrounding uses the `screen-capture` background mode; microphone capture has its own audio-session/background requirements and follows the person's picker choice. This repository implements that screen-only path: no microphone or camera, an explicit Stop control, a ten-minute/256 MB bound, and a review step before extraction. The app-owned temporary video is removed after extraction or discard; an imported original is not deleted. Hardware recording validation is recorded separately in PHASE-ONE. It is not the iOS 26 baseline. [Apple's iOS screen-capture sample](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-on-ios).

Apple describes ScreenCaptureKit as the successor to ReplayKit for streaming/mirroring, without requiring a broadcast extension on its supported newer platforms. Do not carry forward a blanket claim that system-wide screen capture always requires a ReplayKit extension. Imported recordings remain the fallback on older supported systems. [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit).

Neither the importer nor this picker path is an automatic morning first-pickup detector, invisible continuous monitor, or global tap-event feed.

## Siri, voice, and speakers

The app's intents use `supportedModes = .foreground(.immediate)`, which requests foreground execution after the system resolves parameters. A custom `@Parameter` String can collect capture text; Siri may ask for a missing value. App Shortcuts include the application-name token in trigger phrases. The source routes a capture to review and returns a “ready for review” dialog; it does not claim the text has already been durably saved. Keep that distinction if the design changes. [Intent modes](https://developer.apple.com/documentation/appintents/appintent/supportedmodes), [Creating an App Intent](https://developer.apple.com/documentation/appintents/creating-your-first-app-intent), [App Shortcuts guidance](https://developer.apple.com/videos/play/wwdc2025/244/).

The app bundle must contain discoverable intent metadata. A Swift type-check alone does not prove Siri registration. App-only foreground execution avoids an extension's separate process, but does not make in-memory state durable; the review flow still needs its explicit Save. If background extensions are added, use appropriate shared storage and process coordination. OS 27's `LongRunningIntent` can extend certain tasks with progress reporting; it is not an unlimited background agent or the baseline for this short capture flow. [Runtime behavior](https://developer.apple.com/documentation/appintents/configuring-the-runtime-behavior-of-your-app-intents), [Shared data](https://developer.apple.com/documentation/technologyoverviews/shared-data), [LongRunningIntent](https://developer.apple.com/documentation/appintents/longrunningintent).

The current voice implementation is **speech output**. It does not record the microphone or run continuous spoken-command recognition. Siri's own input path is controlled by the system; local app storage does not imply every Siri request is processed offline. A future local Speech adapter must check `supportsOnDeviceRecognition` before requiring on-device recognition. [Speech availability](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition), [On-device recognition requests](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition).

On iOS the app exposes a real `AVRoutePickerView`; the user selects an available output. On macOS this prototype directs the user to system sound controls. AirPlay can deliver media to compatible speakers, but output routing is separate from input capture and does not establish access to a HomePod microphone. The route, audible result and behavior after disconnection still need a physical test. [AVRoutePickerView](https://developer.apple.com/documentation/avkit/avroutepickerview), [Supporting AirPlay](https://developer.apple.com/documentation/avfoundation/supporting-airplay-in-your-app).

Automatic room detection, person tracking and room-to-room transfer are not implemented. HomePod's documented cloud media integration targets media services and is not a generic microphone API for this app. [SiriKit Cloud Media](https://developer.apple.com/documentation/sirikitcloudmedia).

## EventKit permission and effect boundaries

Calendar reading requires full access; creation can use write-only access. Reminders uses full access for both reads and writes. Required purpose strings are `NSCalendarsFullAccessUsageDescription`, `NSCalendarsWriteOnlyAccessUsageDescription`, and `NSRemindersFullAccessUsageDescription` according to the enabled flow. Sandboxed macOS EventKit builds also need the calendars personal-information entitlement. [Event-store access](https://developer.apple.com/documentation/eventkit/accessing-the-event-store).

`ReminderService` never requests permission inside a read or create method. Its explicit permission methods must be called by the app's user-driven flow. Draft validation occurs before writes. New events have no recurrence, attendees or invitations; reminder alerts are explicit draft values. Reminder due components use a Gregorian calendar and the chosen time zone. [Creating events and reminders](https://developer.apple.com/documentation/eventkit/creating-events-and-reminders), [Reminder due components](https://developer.apple.com/documentation/eventkit/ekreminder/duedatecomponents).

The app retains a successful write receipt to prevent an ordinary retry from creating the same item again. A crash between the system write and local receipt persistence remains a recovery boundary: inspect Calendar/Reminders before retrying an uncertain effect. An EventKit success reports a local system-store save, not proof that a cloud account has completed syncing or that an alert was heard. Content deliberately saved to those apps follows their configured accounts and sync policies.

The date parser recognizes a limited grammar. “Tomorrow morning” means a proposed 09:00 on the next local calendar day; “in four hours” means four elapsed hours. Unsupported or ambiguous recognized expressions remain unresolved. The parser retains the original in its transient parse result; the saved capture contains the text the person reviewed and saved. The user can edit the proposed time or keep a reminder undated; there is no silent universal language/date understanding.

## Development automation remains a separate execution environment

`XCUIApplication(bundleIdentifier:)` and XCUI elements provide a genuine development route for inspecting and interacting with an installed app in a UI-test runner. That should be tested on the owner's paired device with the selected target, accessibility surface and expected postcondition. These testing APIs are not ordinary app-runtime permission to control other apps. [XCUIApplication bundle initializer](https://developer.apple.com/documentation/xcuiautomation/xcuiapplication/init(bundleidentifier:)), [XCUIElement](https://developer.apple.com/documentation/xcuiautomation/xcuielement).

The harness and its screenshots/result bundles can contain personal screen content. Keep them local and out of source control. A USB cable or successful pairing alone does not create a persistent app-to-app observation/control protocol. The current bounded tests are not yet the proposed continuous screen → semantic action → verified navigation loop.

## Voice choice and custom companions

Settings offers the installed Apple speech voices, a system-language default, and a short preview. Selection is persisted locally. This is AVSpeechSynthesizer speech output, not Foundation Models voice generation. A selected voice that is no longer installed falls back visibly to the default. Personal Voice access, a family member’s recordings and licensed actor voices remain a separate consent and feasibility project tracked in [issue #20](https://github.com/gibouu/morning-operator/issues/20). [Apple speech voices](https://developer.apple.com/documentation/avfaudio/avspeechsynthesisvoice).

## Evidence and future analytics

History currently measures runs inside Morning Operator. Synthetic runs are excluded from personal averages; interrupted timing is unknown rather than guessed. The core data model can hold app observations with evidence references, coverage and optional counts, but the recorder does not yet populate a longitudinal per-app analytics store. A visible message does not prove the user read it, and OCR alone does not establish an exact reel, like or swipe count.

[Issue #21](https://github.com/gibouu/morning-operator/issues/21) covers timestamped extraction, day/week aggregation, corrections and uncertainty. No sale, export pipeline, tracking SDK or third-party analytics collection is implemented. Any future aggregate-data product is a separate product/consent decision; raw recordings, private messages and HealthKit data are not a monetization feed in this prototype.

## Verification

Use [PHASE-ONE.md](PHASE-ONE.md) for the dated build and device results. Package checks validate core history, state transitions, parser dates, action cancellation, draft validation and real Vision OCR; they do not prove OS permission flows, Siri phrase recognition or speaker output. Each device integration needs its own observed result.
