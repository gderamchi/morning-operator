# Home routine playback — 16 October 2026

## Current design: two transient glass controls

The owner's third review removes the idle Home panel too. A tap reveals only an 88-point central Play button and a 48-point Settings button at the top right, using the existing native Liquid Glass surface. Both disappear after five seconds without interaction; VoiceOver keeps revealed controls available. During playback, the central button becomes Pause/Resume. No close, Next, overflow menu, heading or countdown appears on Home. Reduced Transparency receives the existing opaque system surface.

Routine editing, learning, history, thoughts and completion details are reachable through Settings. Session commands (Next, extend, Interact, Stop) also live there; Interact still pauses the routine and preserves its explicit sheet. Required live weather attribution and meaningful execution notices remain visible.

Implementation: `31070db`. Simulator build-for-testing passed, followed by all five focused Home UI tests (0 failures): idle two-button layout and timeout, Settings-to-routine navigation, active control timeout/reset, largest text with Reduce Motion and Next in Settings, automatic progression, and actual local speech replacing the passage. Idle glass controls and largest-text playback captures were inspected. Xcode again emitted its diagnostic-collection warning after successful execution; this does not establish a full inherited-suite pass. Evidence: `.build/home-glass-ui.xcresult`, `.build/home-glass-ui.log`, `.build/home-glass-attachments/`.

### Physical installation: build 1537

Both existing MORE copies on the iPhone 17 / iOS 27.2 were updated in place to 0.1.0 (1537): ordinary `com.gibouu.morningoperator` and personal `com.gibouu.morningoperator.personal44jg2p8zr8`. No app was uninstalled. Both were launched without fixture arguments or injected test environment; the ordinary copy was relaunched last in the foreground. The two fresh container backups are private under `.build/iphone-before-glass-home-20261016T005144Z/`. Each saved workspace after launch is byte-for-byte identical to its own baseline.

The signed production build passed 13 current artifact checks and the personal build passed 29. Both contain the final Root, Home playback and Settings objects. Existing configuration and signing boundaries were preserved: production WeatherKit/Family Controls entitlements, personal reduced capabilities, personal Google configuration, common API origin. Native Google remains unconfigured in the production bundle. Private receipts and logs: `.build/home-minimal-device/*glass1537*` and `.build/relaunch-personal/1537/`. No credentials, private data or captures are committed.

No real routine or provider action was started on the physical phone. Owner acceptance of physical display/listening comfort and real third-party handoff remains under #171/#158. Inherited old Home selectors remain tracked in #168.

## Earlier design and installation: build 1536

The owner's second review removes the persistent step heading, countdown and transport row. Home shows only the current short spoken passage (up to 110 characters) with a gentle crossfade. Previous passages do not accumulate. Full speech content is preserved; ordinary speech remains one utterance, while duplex speech uses the same bounded passages as its existing sequential audio chunks.

One tap reveals Pause, Next and More for five seconds since the last interaction. VoiceOver keeps revealed controls available. Interact pauses the routine while its sheet is open; full source text is available there. The silent/preparing preview is short and explicitly uses an ellipsis when shortened. Important execution notices remain visible as text. Completion defaults to a short farewell; its recap and optional actions remain behind a tap.

The 18 targeted audio checks passed (6 caption checks and 12 existing audio ownership/playback checks). The iOS simulator test build and the signed physical build passed. All four current Home UI tests passed: no persistent controls/title/countdown; automatic progression; largest text with Reduce Motion; five-second inactivity with interaction restarting the deadline; and real local speech replacing the single passage without accumulating history. Captures of ordinary speech, largest text and temporarily revealed controls were inspected locally. The small "Test routine" marker in test captures is a DEBUG fixture identity and is absent from the ordinary device launch.

Current UI evidence: `.build/home-minimal-ui.xcresult` (4 tests, 0 failures), `.build/home-minimal-ui.log` and `.build/home-minimal-attachments/`. Xcode reported a simulator diagnostic-collection warning after the successful test suite; it did not fail test execution. This is not a full package or inherited UI-suite result.

### Physical installation

MORE 0.1.0 (1536) was installed in place into the ordinary `com.gibouu.morningoperator` app on the connected iPhone 17 / iOS 27.2, then launched in the foreground with no test arguments or fixture environment. A subsequent process query confirmed the app and widget running from the new installed bundle. No uninstall was used. The separate personal development copy was left intact.

The production signing identity and profiles were available locally. All 24 artifact checks passed: current source/object timestamps, app/widget versions and identifiers, strict/deep signatures, matching profile/device/certificate and main-app WeatherKit/Family Controls entitlements. These entitlement checks do not prove runtime authorization or live provider behavior. The common API server is configured; native Google OAuth is intentionally unconfigured because the local native client belongs to the separate personal bundle.

Both original containers were exported privately before installation. The ordinary app's saved workspace was copied again after launch and is byte-for-byte identical to its backup; the routine and saved observation are unchanged. Keychain contents were not exported. Private evidence is under `.build/home-minimal-device/`, with the two backups under `.build/iphone-before-simplified-home-20261016T003150Z/`. No private artifacts or signing configuration are committed.

No real routine was started on the phone. Listener-confirmed speech comfort and a real native-app handoff remain owner acceptance under #171/#158.

## Earlier implementation and evidence (554a614)

The routine now uses the existing Home landscape with spoken passages directly over it. The step card and inline service forms no longer appear during playback. Pause, Next and a small menu remain available; service forms open only through Interact. The background keeps its original colors, and night text has a light shadow for readability over the moon.

Local speech supplies the current passage: system utterance ranges for ordinary playback, and the audio chunk starting in the shared engine for hands-free playback. The visible history is bounded and stays in memory. A new step or background transition clears it. Reduce Motion disables animated scrolling; long text remains manually scrollable with transport controls outside the scroll area.

An automatic manual-browser moment returns to Home at its allotted deadline. It records no verified operation on the page. An external-app return consumes a matching foreground/background ticket and advances only the same running automatic moment; paused sessions, other routes and known launch failures are excluded. iOS is not forced to bring MORE forward, and no lesson/game completion is inferred.

### Earlier verification

- iOS simulator build-for-testing passed with Xcode 27, using an isolated iPhone 17 / iOS 26.5 simulator.
- 18 targeted package checks passed across separate runs: 4 caption progression checks, 12 existing speech audio ownership/playback checks, and 2 external-return policy checks. This is not a full package-suite result.
- Eight UI checks passed across the initial run and a targeted rerun: French largest text/Reduce Motion; pause, extend by exactly 120 seconds, resume, Next and Stop; explicit interaction sheet round trip; long-text independent scrolling at the largest size; manual browser timeout back to Home; actual local speech caption updates; automatic timed-step progression; and persisted completion recap.
- The first UI run passed six checks and stopped two long-text checks in their setup helper: tapping the field placed the caret before its existing text, so delete keys did not replace it. The helper now validates the actual saved long text; both targeted reruns passed. No app change was made to bypass those assertions.
- Captures were inspected locally. Private recordings, account data and signing configuration are not part of this change.
- A final night check required the first long narration passage itself to become history, rather than accepting the greeting as proof of progression. It passed in 55.287 seconds after removing only the isolated simulator's test runner and running the verified build directly. An earlier night attempt had replayed the removed setup assertion despite matching built/installed test binaries; that failed attempt is retained separately and is not counted as a pass.

Local evidence: `.build/home-playback-ui.xcresult` (initial 6 passes / 2 setup failures), `.build/home-playback-long-text-ui.xcresult` (2 passes), `.build/home-playback-night-speech-ui.xcresult` (stale setup failure), and `.build/home-playback-night-verified-ui.xcresult` (final night pass). The package-resolution attempt between the two night runs was interrupted before executing tests.

### Earlier device acceptance status

At that checkpoint physical installation and native Duolingo integration had not been performed. Installation is now confirmed above; owner acceptance of physical display/audio and a real third-party app return remain under [#171](https://github.com/gibouu/morning-operator/issues/171) and [#158](https://github.com/gibouu/morning-operator/issues/158). Older Home selectors in unrelated inherited journeys remain tracked in [#168](https://github.com/gibouu/morning-operator/issues/168).
