# Learning a real morning without feeling it

Written 14 October 2026 for [#105](https://github.com/gibouu/morning-operator/issues/105) (M2). The goal: MORE learns which apps the owner goes through each morning, how long he spends in each and what he checks, with so little friction that he doesn't notice it. The result feeds a routine and, later, a doom-scroll minimizer.

Each claim is marked **proven on the phone** (iPhone 15 Pro Max, iOS 27, 14 October 2026), **checked in the SDK** (iOS 27.0 SDK interfaces or Apple's documentation, not run) or **not proven**. No personal app names or minutes are recorded here; they stay on the phone.

## The answer in short

**Screen Time data access alone can draft the morning from day one.** After one approval (Continue + Face ID, once), MORE can read per-app minutes for each hour, with real bundle identifiers and categories, for yesterday evening and this morning, silently, with no extension and no daily tap. On the phone it found the morning's start to the second and listed every app used, with its minutes. What it cannot give is the order of apps *within* an hour, or what was on screen. Those are the jobs of the app-transition log (#108's timeline) and the occasional recording, which become future work, not prerequisites.

## What Screen Time data access really returns (proven on the phone)

The query `DeviceActivityData.activityData(filteredBy: .hourly(during: 18:00 yesterday → now), using: .live)` returned one result with 118–145 rows, about one second after the approval. `AuthorizationCenter.authorizationStatus` read `approvedWithDataAccess`.

| Field | What came back |
|---|---|
| `ActivitySegment.dateInterval` | One segment per **hour**. Hourly is the finest the API offers (`hourly`, `daily`, `weekly`). Hours with no use simply return no segment. |
| `ActivitySegment.totalActivityDuration` | Seconds of use in the hour. It can exceed the sum of the apps (the Home Screen and the Lock Screen count too). |
| `ActivitySegment.firstPickup` | **A timestamp to the second.** In the first hour of the morning it is the real wake-up pickup. In later hours it is often exactly hh:00:00, meaning use carried over from the previous hour. |
| `ActivitySegment.longestActivity` | A `DateInterval` to the second: the longest continuous session in that hour. This is the only within-hour timing besides the first pickup. |
| `ActivitySegment.totalPickupsWithoutApplicationActivity` | Pickups with no app opened (glances at the Lock Screen). |
| `CategoryActivity.category.localizedDisplayName` | Real names, for example Social, Entertainment, Games, Productivity & Finance, System, Utilities, Creativity, Other. |
| `ApplicationActivity.application.bundleIdentifier` | **Real bundle IDs** (for example `net.whatsapp.WhatsApp`, `com.apple.MobileSMS`), not tokens. |
| `ApplicationActivity.application.localizedDisplayName` | **nil on every row.** `FamilyActivityData.installedApplications` did not fill the names either, so MORE needs its own bundle-ID → name table (#108 already has one for its signatures). |
| `ApplicationActivity.totalActivityDuration` | Seconds per app per hour. |
| `ApplicationActivity.numberOfPickups` | Pickups that went straight into that app. In the morning's first hour, it shows **which app he opened first**. |
| `ApplicationActivity.numberOfNotifications` | **0 on every row** this morning; not reliable as a signal yet. |
| `WebDomainActivity` | **None returned**, even with long Safari use. No websites. |
| `DeviceActivityData.lastUpdatedDate` | Equal to the time of the read (`.live`). |

It also counts system helpers as apps (Face ID sheet `LocalAuthenticationUIService`, `ScreenshotServicesService`, `AuthKitUIService`, `ServicesPaymentAngel`) and **XCTest-driven use**: the hours when the tethered demo drove MORE show up as MORE usage. A routine must filter out system services and MORE itself; the summary already excludes MORE.

**What it does not give:** order inside an hour, per-session timestamps (other than the longest one), screens inside an app, content (messages, reels, articles), taps, or website domains.

## From this morning's data to a draft routine (proven on the phone)

The owner's rule (implemented in `MorningCore/MorningStartDetection.swift`, with package tests): **the morning starts at the first phone use after at least 3 hours without use**, and ends after a 20-minute pause or 3 hours, whichever comes first. A short check before 05:00 that is followed by another 3-hour gap is skipped as a night-time check. A HealthKit sleep end, when given, moves the start to the first session after waking (the hint is not wired in the app yet).

Hourly data turns into timed evidence in three ways, from exact to coarse:

1. `firstPickup` and `longestActivity` are timed to the second.
2. **An hour whose use leaves less idle time than the pause threshold** (for example 59 minutes of use with a 20-minute rule) has no room for a pause, so it is continuous use. That is arithmetic, not a guess.
3. Any other hour with use adds only its start as a coarse point.

On the phone this found the start of the morning at the exact second of the first pickup, after a night with no use. It carried the morning through two busy hours and ended it at the first hour with too little use to prove continuity (end reason `pause`). The minutes per app then come from the hours inside that morning. The first hour's pickups name the first app opened.

The draft routine has the shape *first app (from the pickup) → apps of hour 1 by minutes → apps of hour 2 by minutes → …*, for example "Messages 1 min → Browser 54 min → Messages 3 min, Mail 2 min → Video 28 min → Chess 21 min".

- **Measured:** the start time, minutes per app (summed over whole hours), category, the first app opened, the hour each app was used, and the longest session in each hour.
- **Guessed:** the order of apps inside each hour (sorted by minutes here), and whether two uses of the same app in one hour were one stretch or several. The end of the morning is exact only to the hour when the last hour was light.
- **What fills the gap cheaply:** the app-transition log. PR #108 makes *Log an app transition* accept any app and builds a timeline from it. With one Shortcuts automation per app the owner cares about (silent, set up once), it gives the order to the second; Screen Time gives the minutes and catches every app the automations miss. A recording is only needed to learn *what* he looked at.

## Paths compared

| Path | Order | Minutes | Content | Friction | Status |
|---|---|---|---|---|---|
| **A. Screen Time data access** | By hour, plus the first app and the longest session | Yes, per app per hour | No | Once (Continue + Face ID) | **Proven on the phone** |
| **B. Shortcuts app automations** → `LogAppTransitionIntent` (#108: any app) | To the second, for configured apps | From open/close pairs | No | Once per app | Implemented; silent delivery on this phone not proven here |
| **C. Screen recording** (ScreenCaptureKit picker) | Yes, inside the stretch | Yes, inside the stretch | **Yes** | Every time: 5 taps today; 2 with the one-step route (Action button + Apple's Start) | Recording works (earlier phone runs); the one-step route is **not proven** (see below) |
| D. DeviceActivityMonitor thresholds | Coarse | Approximate | No | Once | Not needed now that A works |
| E. Global tap capture | — | — | — | — | **Impossible**: iOS delivers touches only to the app's own windows. Dropped. |

### Recording taps (C)

From the code: open MORE (1) → Morning actions (2) → Learn (3) → Record (4) → Start screen recording (5) → Apple's Start (the owner's tap), then a 3-second countdown. A third-party app cannot present the picker without being in front, and Apple's confirmation can never be skipped. The Debug route `more://watch-morning` opens Learn and the recorder and presents the picker straight away. Any Shortcut can open that URL from the Action button, Control Center, the Lock Screen or Back Tap, which would make it **2 taps**. The phone check (`UITests/SeamlessLearningSpikeTests.swift`) did not run: the UI-test runner exited before connecting, three times. One of those runs overlapped another agent's live demo by mistake.

## Day-one product path (recommendation)

The shortest change that delivers "one approval → one analysis of the last few mornings → a proposed routine for review", reusing what exists:

1. **Ship the entitlements** (`com.apple.developer.family-controls` and `.app-and-website-usage`) in the main app. Both are self-service for the team, with no Apple request. They are now provisioned for the spike bundle.
2. **One card in Learn: "Learn from Screen Time".** It explains the scope (minutes per app, no content, stays on the phone, only one app can hold this access), then calls `requestAuthorization(for: .individual)`.
3. **One analysis:** query hourly data for the last 3–7 days (`.hourly(during:)`), split it into local days, and run `MorningStartDetector` on each day. Summarize each morning with `ScreenTimeMorningSummary` (filtering system services), and turn the mornings into a pending routine proposal: apps that recur on most mornings, in first-hour order, with their median minutes. The existing proposal review (Choose mornings / Suggest a routine) shows it, labelled "from Screen Time, order within the hour estimated", and nothing changes until approval.
4. **Later, without blocking:** merge #108's transition timeline to fix the order, add the HealthKit sleep end as the start hint, and use recordings only to learn content.

How far back the data goes (3–7 mornings) has not been measured yet: this spike only read from 18:00 yesterday.

## How to run the spike

The spike installs beside the main app as **MORE ST**, with its own bundle, URL scheme and entitlements. An Apple ID must be signed in to Xcode (Settings → Accounts) for automatic signing.

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project MorningOperator.xcodeproj -scheme MorningOperator -destination 'id=<UDID>' \
  -derivedDataPath .build/iphone-st -allowProvisioningUpdates DEVELOPMENT_TEAM=<team> \
  MO_BUNDLE_ID_BASE=com.gibouu.morningoperator.screentime 'MO_DISPLAY_NAME=MORE ST' \
  MO_URL_SCHEME=more-st MO_ENTITLEMENTS=Configuration/MorningOperator-ScreenTime.entitlements
xcrun devicectl device install app --device <UDID> .build/iphone-st/Build/Products/Debug-iphoneos/MorningOperator.app
xcrun devicectl device process launch --device <UDID> --terminate-existing \
  com.gibouu.morningoperator.screentime --screen-time-spike-auto
```

In the app: Settings → Availability & device details → **Screen Time spike (debug)**. With `--screen-time-spike-auto`, the screen opens at launch, asks for access if needed, reads once, and writes a plain summary to the app's temporary folder (`tmp/screen-time-spike.txt`, overwritten on every run), which a tethered Mac can copy with `devicectl device copy from`. That file holds personal app names and minutes: keep it local, never commit it, and delete the spike app when done. Ordinary Debug and Release builds keep the original bundle ID and entitlements, and include none of this unless the Debug screen is opened.
