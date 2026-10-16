# Native UI regression checks after PR #215

PR #215 was merged before its complete UI workflow finished. Its package tests
and simulator build passed in [CI run 38869019446](https://github.com/gibouu/morning-operator/actions/runs/38869019446).
The proposals shard of [UI run 38869019394](https://github.com/gibouu/morning-operator/actions/runs/38869019394)
then failed 14 journeys that still opened history through the removed Home date
control. This is an actual failed run, not a successful check.

The corrective branch follows the current product navigation: tap Home for Play
and Settings, then use Settings for history, the routine and session commands.
Learning uses native Back navigation. Tests keep approval, persistence, source
quotations, timer continuity and exact session/step assertions. Draft readiness
is checked by opening the editor and verifying its approval state; the presence
of Play alone cannot prove approval.

During `DEBUG` UI tests only, the app exposes a JSON accessibility value containing
the real session state, step title, opening phase, opening speech/start counts,
completed-step count and remaining timer seconds. It adds no visible panel and
does not seed or change the session. Ordinary launches expose no diagnostic data.
The reading surface's existing two-UUID identity value remains unchanged.

## Verification

- Xcode 27 `build-for-testing`: app, widget and UI-test target passed on the
  dedicated iPhone 17 Pro simulator (iOS 26.5).
- Runtime and hosted workflow results will be recorded after their completion.

Physical-device and audible tests retain their existing opt-in guards. In
particular, the opt-in Live Activity settings tests still require `setup.activity`,
which has no entry in the current Settings screen. These tests are not proof of
working physical-device setup; no synthetic replacement or new skip hides that
limitation.
