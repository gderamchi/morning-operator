# One MORE direction

15 October 2026. The combined integration in PR #172 brings together main `322f77b`, every existing connection and the latest quiet solar Home from PR #170. It preserves both branches; upstream merge status must be checked on GitHub. Use [MORE feedback](https://github.com/gibouu/morning-operator/issues/new/choose) for problems and design notes; include the commit, iPhone/iOS and what actually happened.

**Native integration research:** the consumer product must run on an ordinary App Store iPhone, without a Mac or Developer Mode. Explore public system APIs, provider connections and user-installed Shortcuts rather than assuming screen control. The [dated capability/workaround matrix](NATIVE-INTEGRATIONS.md) includes the newly verified iOS 26/27 Mail, Messages and notification actions; it is research, not implemented or device-verified coverage.

**Current connection implementation:** [Apps & accounts](CONNECTIONS.md) presents named apps and services in MORE’s visual language. TikTok and X browsing uses MORE’s visible browser, alongside Instagram, WhatsApp, YouTube Shorts and Le Monde; Reddit, Facebook and Threads are additional personal website destinations. No developer app or API setup is needed for that browsing. Native iOS actions/Shortcuts, visible browser activities and Composio operations remain internal routes. The live Cloudflare backend keeps the project key out of the iPhone and validates per-installation account ownership for sixteen configured API services. Shortcuts have guided examples and WhatsApp explains personal Web access versus Business Platform actions. User sign-in and ordinary-phone source checks remain separate evidence. The native research inventory is not a claim that all its adapters shipped.

## The first story

1. Open MORE normally. In Learn, start with **See your rhythm → Connect Screen Time**. Review actual dates and app minutes, then the proposed morning. Unknown coverage and estimated order stay explicit.
2. Record or import a short real morning if you want to add visible evidence. Review its text and uncertain screens. Screen Time and recording proposals remain separate suggestions; neither silently replaces an approved routine.
3. Review/edit the moments, their destinations and budgets; approve. Use **Apps & accounts** to choose a named app, sign in to a supported website or authorize a connected account. Apple sources request their own permissions. Browser “Ready” is your confirmation; a connected account is shown as connected only after an ACTIVE response.
4. After a site is ready, **Learn my pace** starts an explicit lesson in MORE's browser. Stop, review the numeric rhythm, and choose **Save to Learn**. No page text, field entries or tap targets are saved by this collector. This is a partial cadence sample, not gesture replay.
5. Start the morning normally. A supported page opens inside MORE or a native app opens through its supported URL. One saved step timer follows it. Use +2 minutes or Next, then finish.

The native Gmail reader uses explicit read-only Google consent, a saved Keychain refresh credential, bounded plaintext messages and optional local editable reply preparation. Gmail routine moments use this reader and remain excluded from embedded website sign-in. Its local OAuth settings are described in `AGENTS.md`. The owner's configured ordinary build has earlier sign-in/count/reading confirmation; generated reply/copy and a complete run remain separate gates. The Composio Gmail account-action route also remains available in Apps & accounts, with separate authorization. [Native Gmail flow and limits](GMAIL-READING.md), [current connection evidence](CONNECTIONS.md).

The hackathon proof is the owner doing this in the ordinary app, with actual permissions/data and no test launch arguments. Unit tests and earlier scripted phone checks remain engineering evidence only. Do not present sample routines or automated taps as learned autonomous behavior.

## Design

Home opens with a small dotted landscape at the bottom: trees, a sun following a left-to-right arc, a decorative crescent and night stars. Its daylight calculation uses the selected weather city's coordinates and the iPhone's date/time zone; without a city it discloses an approximate reference cycle. Night system appearance stays scoped to Home. DM Serif Display supplies the titles and Raleway supplies the reading text and controls, including the connection screens. Both bundled fonts follow Dynamic Type.

Current source: Home is the root of one native navigation stack, with no persistent tab bar or bottom dock. Touching the landscape reveals the scrollable controls, including Settings and My routine; revealing the menu does not start playback. Settings and Learn open Apps & accounts. Begin starts the saved routine through the existing approval policy, or opens Learn when there is no routine. Active API/shortcut status and notices remain in the new control panel. The old dock's reserved bottom spacing is removed. Main's removal of the routine import/export controls and standalone Settings Shortcuts/timers and Lock Screen cards is preserved; the separate integration guides remain in Apps & accounts.

The app icon and Live Activity use the dotted sunrise. The Lock Screen stays cream. The Island uses cream/rust marks, a native live countdown and dotted native progress. iOS owns its black enclosure. Custom sun position changes on published state, not a claimed continuous background animation. A quiet-moon concept is an optional comparison, not the chosen production treatment.

## Prior verification on PR #131

- Complete local package suite: **1,209 tests** (4 Health, 572 Core, 633 Apple) across **131 suites** pass.
- Normal signed iOS app and widget build pass with Screen Time and WeatherKit entitlements. Ordinary MORE was installed on the connected iPhone; its existing data was backed up locally before the update. No XCTest runner, test arguments or sample-seeding launch was used for this installation.
- Browser collector has real JavaScript execution checks for nested scrolling, inputs, untrusted events and credential/visibility boundaries. The +2 request now transports an exact string token and preserves replay/stale-deadline rejection.
- Native component renders and two Island concept plates were inspected. They are design proofs, not final iPhone navigation or system-control proof.
- Prior owner evidence: Instagram sign-in in MORE QA and an unread result matching a real unread message. That QA site's session is separate from ordinary MORE.
- Prior device engineering evidence: AlarmKit authorization, schedule and cancellation passed in QA and normal-storage Lab. An older design passed native journeys. These do not prove the final normal-use story.

## Still needs a person on the phone

- Screen Time suggestion approval is now owner-confirmed; retain that source scope and separately validate quality/coverage on additional real observations.
- One real recording/import → local analysis → review → approval, and browser sign-ins/pace lesson.
- Alarm ringing → open MORE, spoken Siri start/Next, audible speech and live Calendar/Weather permissions/data.
- +2 from the Lock Screen after the exact-token fix, then Next/Finish and the visible Island layout.
- End-to-end rehearsal with the chosen real morning, no test runner.

Screen Time is aggregate usage, not every tap. Screen recording supplies visible media, not native touch events. MORE cannot silently monitor or drive all other apps. Detailed recording recognition is sampled and may miss quick actions. Browser rhythm measurement does not yet adapt automatic playback speed. [Apple API conditions and limits](SCREEN-TIME-INTEGRATION.md).
