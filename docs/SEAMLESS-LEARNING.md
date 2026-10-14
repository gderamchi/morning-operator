# Learning a real morning without feeling it

Written 14 October 2026 for [#105](https://github.com/gibouu/morning-operator/issues/105) (M2). The goal: MORE learns which apps the owner goes through each morning, how long he spends in each and what he checks, with so little friction that he doesn't notice it. The result feeds a routine and, later, a doom-scroll minimizer.

Each claim below is marked **proven on the phone**, **checked in the SDK** (read in the iOS 27.0 SDK interfaces or Apple's documentation, not run) or **assumed**.

## What each path gives

| Path | Timeline (order) | Minutes per app | Content (what he looked at) | Friction | Privacy |
|---|---|---|---|---|---|
| **A. Screen Time data access** (`DeviceActivityData.activityData`) | Coarse: the hour each app was first used, plus the first pickup | **Yes**, per app per hour, with pickups and notifications | No | **Once**: a Face ID approval. After that it is silent every day and needs no extension. | Aggregates only. App names are readable after approval. Stays on the phone. |
| **B. Shortcuts "App is opened/closed" automations** → `LogAppTransitionIntent` | **Yes**, the order of the apps he configured, timed when each callback ran | Roughly, from open/close pairs, for configured apps only | No | **Once per app**: one automation each, set to "Run Immediately", no notification. Silent after that. | Event times only. |
| **C. Screen recording** (ScreenCaptureKit picker, iOS 27) | Yes, inside the recorded stretch | Yes, inside the stretch | **Yes**: visible text, through OCR and the on-device model | **Every time**: the picker needs his confirmation. Today that is 5 taps. A one-step entry gets it down to 2 (see below). | Screen pixels, kept on the device until the text is saved. |
| D. DeviceActivityMonitor thresholds (one event every N minutes per app) | Coarse | Approximate, in whole threshold steps | No | Once | Opaque tokens inside the extension |
| E. Global tap capture | — | — | — | — | — |

**E is impossible and is dropped.** No App Store or development API lets an ordinary app see touches made in other apps. UIKit only delivers touches to the app's own windows. The only cross-app control is the XCTest runner on a tethered Mac, which drives the phone; it does not watch it. That is a development harness, not something to learn from.

**D is not needed if A works.** A returns the real number of minutes per app directly. D rebuilds an estimate from threshold callbacks. Those are opaque tokens unless the app also has A's data access, with roughly 20 monitored activities per app and a small extension memory budget. D stays as the fallback only if A cannot be provisioned. The `intervalDidStart` callback (first phone use inside a scheduled window) is still worth a later spike as the trigger for path C (see the issues below).

### A. Screen Time data access: checked in the SDK, phone proof pending

- iOS 26.4 added `DeviceActivityData.activityData(filteredBy:using:)`, `AuthorizationStatus.approvedWithDataAccess` and `FamilyActivityData`. Checked in the iOS 27.0 SDK swiftinterface.
- The app needs the entitlement `com.apple.developer.family-controls.app-and-website-usage` together with `com.apple.developer.family-controls`. The team's capability list (Xcode's cached `capabilities-27.0-U6Z87CS4W3`) shows "Family Controls App and Website Usage" as **public, editable and needing no approval**, for Development and App Store. "Family Controls (Development)" is public as well.
- Each result gives `ActivitySegment`s (**hourly** is the finest segment), and inside each segment, per category, an `ApplicationActivity` with `totalActivityDuration`, `numberOfPickups` and `numberOfNotifications`. Each segment also has `firstPickup` and `longestActivity`, and each result has `lastUpdatedDate`. With data access, `Application.localizedDisplayName` and `bundleIdentifier` are real values, not tokens.
- Conditions, from Apple's documentation: development works in any region. A customer install works only on a device in the EU signed in with an EU Apple Account; the owner qualifies. Only one app per device can hold data access: if another app gets it, MORE drops back to `.notDetermined`. `.live` may still return recently cached data.
- What it cannot give: order inside an hour, which screen inside an app, what he read or watched.
- **Prototype** (Debug builds only): Settings → Availability & device details → **Screen Time spike (debug)**. It asks for access, then reads 05:00–11:00 (adjustable) and shows "Instagram ≈ N min", a coarse order by hour, the first pickup and the data freshness. Nothing is saved or logged. The pure summary logic is `MorningCore/ScreenTimeMorning.swift`, with package tests.
- **Phone status: blocked, not run.** `xcodebuild -allowProvisioningUpdates` fails with *No Accounts*: Xcode on the Mac has no Apple ID signed in. The only cached `com.gibouu.morningoperator` profile contains WeatherKit only, so no build with Family Controls can be signed until the owner adds his account in Xcode → Settings → Accounts. To leave the main install alone, the spike installs beside it:

  ```
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
    -project MorningOperator.xcodeproj -scheme MorningOperator -destination 'id=<UDID>' \
    -derivedDataPath .build/iphone -allowProvisioningUpdates DEVELOPMENT_TEAM=<team> \
    MO_BUNDLE_ID_BASE=com.gibouu.morningoperator.screentime 'MO_DISPLAY_NAME=MORE ST' \
    MO_ENTITLEMENTS=Configuration/MorningOperator-ScreenTime.entitlements
  ```

  Release and ordinary Debug builds keep the original bundle ID and entitlements.

### B. App-transition order: implemented, delivery not yet proven

`LogAppTransitionIntent` runs in the background and logs "opened or switched to" and "closed or switched from" for Instagram, TikTok and Snapchat into a separate journal. The owner builds one personal automation per app and transition in Shortcuts, set to *Run Immediately* with *Notify When Run* off. After that it runs silently. The automation is the only way an app learns about other apps opening. Limits: only the apps in the enum, the callback time can lag the real switch, and any app without an automation is invisible between two that have one. Combined with A's hourly minutes, B gives the order and A gives the totals. Widening the app list is a follow-up issue.

### C. Recording, and how many taps it really takes

Today's flow (from the code, to be counted on the phone): open MORE → open the action dock → **Learn** → **Record** → **Start screen recording** → Apple's sharing sheet **Start** (Apple's own tap). That is about 5 taps by the owner, plus the 3-second countdown. Apple's panel may then stay on screen until he leaves it.

What can shorten it (checked in the SDK and the documentation, not run):

- A third-party app cannot start the picker from a Control Center control, a widget, a Live Activity button or a background App Intent without opening the app. `SCContentSharingPicker.present()` needs MORE in the foreground, and Apple's confirmation can never be skipped.
- What can be cut is MORE's own screens. The prototype adds a Debug route, **`more://watch-morning`**: MORE opens Learn → Record and presents Apple's picker straight away. Any foreground trigger can open that URL: a Shortcut on the **Action button** (the iPhone 15 Pro Max has one), a Control Center or Lock Screen Shortcut control, Back Tap, or the morning notification. That makes it **one press + Apple's Start = 2 taps**. Whether the picker shows without a tap inside MORE is still unproven on the phone (open issue). The Debug URL becomes a real `Watch my morning` App Intent only after that.
- The system Screen Recording control in Control Center is also 1 tap, but it saves to Photos and MORE has to import the file afterwards. That only moves the friction to later.

## Recommendation

1. **Every morning, silently: A, then B.** A gives minutes per app, pickups and the first pickup with no daily action, after one Face ID approval. B adds the real order for the apps that matter (social, messages, mail), after a one-time set of automations. Together they give the "which apps, how long, in what order" timeline without his noticing. The doom-scroll minimizer later uses the same data, with ManagedSettings shields from #17.
2. **Some mornings, for content: C in one step.** On a morning he chooses, one Action-button press plus Apple's Start records a short stretch, so MORE learns *what* he checked (the messages screen, the calendar, reels). This is the only path that sees content, and it is never silent.
3. **Drop** global tap capture, and keep the threshold monitor (D) only as the fallback if A cannot be provisioned.

The working hypothesis (Screen Time minutes + transition order + an occasional one-tap recording) holds. The one change is that the minutes come from the direct data API, not from threshold events.

## What the owner must do (only he can)

- Add his Apple ID in Xcode → Settings → Accounts (team U6Z87CS4W3) so Family Controls can be provisioned.
- On the phone, the first time: open **MORE ST** → Settings → Screen Time spike → Allow, and pass Face ID.
- For B, once: create the Shortcuts automations (App → Is Opened / Is Closed → Log an app transition; Run Immediately).
- For C: press Start in Apple's sharing sheet. That tap is always his.

## Phone results

Recorded at the end of the spike pull request. Nothing below the SDK level counts as proven until it has a phone result.
