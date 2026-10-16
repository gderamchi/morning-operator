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

Ordinary iPhone system permissions, native GPS, live WeatherKit entitlement/provider behavior, physical visual quality and VoiceOver remain [#187](https://github.com/gibouu/morning-operator/issues/187), alongside the existing [live-weather gate #13](https://github.com/gibouu/morning-operator/issues/13). No physical installation or actual Apple Weather response is claimed for this delivery. Follow [WeatherKit setup](WEATHERKIT-SETUP.md) for signing/service acceptance.
