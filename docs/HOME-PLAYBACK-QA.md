# Home routine playback — 16 October 2026

## Current design: text only by default

The owner's second review removes the persistent step heading, countdown and transport row. Home shows only the current short spoken passage (up to 110 characters) with a gentle crossfade. Previous passages do not accumulate. Full speech content is preserved; ordinary speech remains one utterance, while duplex speech uses the same bounded passages as its existing sequential audio chunks.

One tap reveals Pause, Next and More for five seconds since the last interaction. VoiceOver keeps revealed controls available. Interact pauses the routine while its sheet is open; full source text is available there. The silent/preparing preview is short and explicitly uses an ellipsis when shortened. Important execution notices remain visible as text. Completion defaults to a short farewell; its recap and optional actions remain behind a tap.

The 18 targeted audio checks passed (6 caption checks and 12 existing audio ownership/playback checks). Simulator UI and signed physical installation results are recorded below once complete.

## Earlier implementation and evidence (554a614)

The routine now uses the existing Home landscape with spoken passages directly over it. The step card and inline service forms no longer appear during playback. Pause, Next and a small menu remain available; service forms open only through Interact. The background keeps its original colors, and night text has a light shadow for readability over the moon.

Local speech supplies the current passage: system utterance ranges for ordinary playback, and the audio chunk starting in the shared engine for hands-free playback. The visible history is bounded and stays in memory. A new step or background transition clears it. Reduce Motion disables animated scrolling; long text remains manually scrollable with transport controls outside the scroll area.

An automatic manual-browser moment returns to Home at its allotted deadline. It records no verified operation on the page. An external-app return consumes a matching foreground/background ticket and advances only the same running automatic moment; paused sessions, other routes and known launch failures are excluded. iOS is not forced to bring MORE forward, and no lesson/game completion is inferred.

## Verification

- iOS simulator build-for-testing passed with Xcode 27, using an isolated iPhone 17 / iOS 26.5 simulator.
- 18 targeted package checks passed across separate runs: 4 caption progression checks, 12 existing speech audio ownership/playback checks, and 2 external-return policy checks. This is not a full package-suite result.
- Eight UI checks passed across the initial run and a targeted rerun: French largest text/Reduce Motion; pause, extend by exactly 120 seconds, resume, Next and Stop; explicit interaction sheet round trip; long-text independent scrolling at the largest size; manual browser timeout back to Home; actual local speech caption updates; automatic timed-step progression; and persisted completion recap.
- The first UI run passed six checks and stopped two long-text checks in their setup helper: tapping the field placed the caret before its existing text, so delete keys did not replace it. The helper now validates the actual saved long text; both targeted reruns passed. No app change was made to bypass those assertions.
- Captures were inspected locally. Private recordings, account data and signing configuration are not part of this change.
- A final night check required the first long narration passage itself to become history, rather than accepting the greeting as proof of progression. It passed in 55.287 seconds after removing only the isolated simulator's test runner and running the verified build directly. An earlier night attempt had replayed the removed setup assertion despite matching built/installed test binaries; that failed attempt is retained separately and is not counted as a pass.

Local evidence: `.build/home-playback-ui.xcresult` (initial 6 passes / 2 setup failures), `.build/home-playback-long-text-ui.xcresult` (2 passes), `.build/home-playback-night-speech-ui.xcresult` (stale setup failure), and `.build/home-playback-night-verified-ui.xcresult` (final night pass). The package-resolution attempt between the two night runs was interrupted before executing tests.

## Remaining device acceptance

Physical display, listener-confirmed audio and a real third-party app return remain under [#171](https://github.com/gibouu/morning-operator/issues/171) and [#158](https://github.com/gibouu/morning-operator/issues/158). No physical-device installation or native Duolingo integration is claimed here. Older Home selectors in unrelated inherited journeys remain tracked in [#168](https://github.com/gibouu/morning-operator/issues/168).
