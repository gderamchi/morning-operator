# Location, access preparation and weather Home

16 October 2026. Product direction: [MORE](../MORE.md). Implementation starts from upstream `7d912aa`; source checkpoint `f98d1e0` includes the first-opening persistence correction and reduced-accuracy location support.

## Delivered behavior

At first opening, a static explanation precedes each supported iPhone permission. Allowing, denying or skipping one access leaves the next available; speech and microphone are separate steps. Completion survives relaunch independently of routine learning, with a revisit entry in Settings. Unsupported Screen Time builds disclose that limitation. Permission preparation does not start listening/recording, create events/reminders or schedule an invitation/alarm.

Weather defaults to a bounded foreground location fix after explained when-in-use consent. Passive location refresh is limited to once per five minutes; changed settings, cancellation, revoked access and privacy removal invalidate pending results. Device coordinates remain transient. Existing chosen cities migrate to explicit manual mode; a city remains a fallback, with source selection visible in Your day.

WeatherKit current conditions retain available wind speed/gust/direction, rain rate, cloud cover, humidity, visibility, apparent temperature/dew point, UV, pressure and daylight. Measured values drive dotted breaths, clouds, precipitation, atmospheric depth and ground motion. Gusts remain visible even with zero sustained wind. Background/covered Home pauses its atmospheric clock; Reduce Motion freezes it.

## Shared checks

The full check before the final approximate-location adjustment, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/test.sh --no-parallel`, passed: **1,330 passed, six optional model/media tests skipped**, across Core, Apple and Health targets. This includes permission-progress ordering, approximate/invalid fixes, passive denial, transient coordinates/privacy clearing, retry throttling, late city/settings results, detailed measurement validation and scene normalization.

An earlier concurrent run retained three city-race wall-deadline failures under MainActor contention. All 12 tests in that suite passed when isolated; the final serial full run passed. Native location-manager construction was made lazy so ordinary controller construction does no GPS work. These results do not establish native system-dialog behavior or a real location/weather response.

After the final accuracy-aware adjustment, **24 focused location, permission-progress, weather-admission and scene tests passed**. Reduced-accuracy fixes may be up to 20 minutes old with bounded uncertainty; precise fixes retain the five-minute/five-kilometer policy. No precise-location escalation was added. [Apple reduced-accuracy reference](https://developer.apple.com/documentation/corelocation/kcllocationaccuracyreduced).

## Native and remaining acceptance

Xcode 27 / iOS 26.5 simulator build-for-testing succeeded, including final app source `f98d1e0`. **Ten distinct targeted UI tests passed across the corrected runs:**

| Surface | Result |
| --- | --- |
| Quiet arrival/menu, French largest-text controls, landscape orientation, rain/snow, measured wind/direction and Reduce Motion | Six landscape tests passed. The French largest-text menu also passed again after the final Home wording update. Native wind images differ for calm/brisk/gust-only/direction fixtures and remain identical under Reduce Motion. Six exported wind/humidity captures were visually inspected without clipping or legibility defects. |
| Explained allow/deny queue, completion/relaunch/Settings revisit, French largest text and skip/separate speech/microphone | Three permission tests passed after correcting first-launch persistence. The original bounded file read returned Cocoa missing-file code 4, while setup only handled code 260; both are now handled without accepting corrupt records. |
| Current Home → Settings → Your day → manual city selection → relaunch | Final targeted test passed, including restored city and manual-mode search row. Its first assertion was corrected to read the native combined labeled row rather than a nonexistent standalone city label. |

The full historical UI suite is not a pass: the older selected-briefing journey below remains blocked by obsolete navigation. Simulator permission outcomes and weather sources in these journeys are explicitly synthetic. Screenshots, logs and xcresults remain local under ignored `work/weather-validation/`; no captures or personal device records belong in Git.

The historical selected-briefing journey fails before source setup because its helper still expects retired Home navigation. This pre-existing mismatch is tracked in [#186](https://github.com/gibouu/morning-operator/issues/186); current permission/city checks use the current Home menu directly.

The initial simulator-only checkpoint above is superseded for ordinary iPhone access, native current location and live Apple Weather by the physical run below. The broader physical denial/revocation, alternate-weather and accessibility matrix remains in [#187](https://github.com/gibouu/morning-operator/issues/187). Follow [WeatherKit setup](WEATHERKIT-SETUP.md) for signing/service acceptance.


## Physical iPhone acceptance — 16 October 2026

MORE **0.1.0 (1540)** was installed in place into the ordinary app on iPhone 17 / iOS 27.2, using Xcode 27. App source is `d114a64`: it combines the latest floating glass Home, the access/location/weather changes and the registered Live Activity widget identifier from upstream `99ea980`. The integration also prevents an existing hands-free listener from starting or handling late utterances behind access preparation, and suspends that listener when the preparation is opened. The Home stays free of a Weather logo; attribution remains in Your day.

The ordinary app and widget built and their strict signatures passed. The main app's signed WeatherKit, Family Controls and app-and-website-usage entitlements were verified against the current device-covered profile; WeatherKit is genuinely available in this build. No personal signing records are shared. An additional **30 targeted shared tests passed** after the main Home integration (15 Core, 15 Apple); this is not a new full-package result for all integrated routine work.

| Physical check | Observed result |
| --- | --- |
| Explained access queue | All eight supported explanations were reached across the original run and its continuation: location, calendar, reminders, Screen Time, speech, microphone, notifications and alarms. New native location, speech, microphone, notification and alarm dialogs were accepted. Calendar, reminders and Screen Time reported ready from their existing grants on continuation; no grants or app data were reset. Speech and microphone were separate native requests. |
| Completion and persistence | The corrected ordinary-device permission test passed in 51.601s, including finish and ordinary relaunch without repeating setup. This check requested no event/reminder/alarm creation, routine start or recording. |
| Native current location → Apple Weather | The full ordinary-device weather test passed on integrated build 1539 in 85.373s: Current location resolved without typing a city; native detailed measurements and Apple Weather attribution were present in Your day. A fresh process admitted Current location / Clear on Home. Condition, temperature, feels-like, wind, gusts, direction, rain rate, cloud cover, humidity, visibility, dew point, UV, pressure and day/night were inspected. Observation time was a few minutes before the screen capture. No fixture arguments, theme overrides or alternate data directory were used. |
| Real-weather motion | Five native frames across 12s on build 1539 show the night landscape and intermittent small dotted breaths with actual light wind/gusts. The final build 1540 smoke passed in 21.584s, checking fresh native weather admission and foreground state with five more frames over 12s. Source status stayed Current location / Clear at every capture. The moon and trees remain legible; breaths move and subside. |
| Data and final install | A private app-container export preceded replacement. The saved workspace after install and access checks is byte-for-byte identical to its original export; the selected manual-city fallback is unchanged and automatic location is now selected. Final ordinary launch and process/app-inventory checks are separate from test-runner execution. |

The first permission attempt stopped because iOS exposed duplicate nested native buttons; the test driver now accepts only duplicates sharing the same label, identifier and frame. It is retained as a skipped attempt, not a pass. During the initial build 1538 weather capture, another ongoing Home task installed a different build; its later App Library frames are excluded. The final 1539/1540 checks include foreground assertions and complete ordinary-app frame sequences. The newer Home changes were integrated before final delivery.

These are genuine current-location/provider checks, not fixture weather. The captures establish changing wind poses and the current night appearance; they do not measure continuous frame rate or prove strong-wind, rain, snow, fog, daytime, VoiceOver or French largest-text behavior on this physical phone. Those conditions were not manufactured by resetting grants or changing the device's location. The Core/simulator checks above remain separate evidence for those variants. Native screen-recording via this CoreDevice version is unsupported, so no continuous device-video proof is claimed.

Private evidence remains under ignored `work/phone-weather-20261016/`: signed-build logs, artifact checks, container exports, `permissions-resume.xcresult`, `final-1539-weather.xcresult` and `final-1540-smoke.xcresult`, with locally exported attachments. No coordinates, calendar content, screenshots or signing credentials are committed.
