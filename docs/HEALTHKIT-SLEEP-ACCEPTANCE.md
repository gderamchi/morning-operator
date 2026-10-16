# Optional HealthKit sleep — 16 October 2026

Tracks [issue #15](https://github.com/gibouu/morning-operator/issues/15). This report keeps engineering checks separate from the owner’s actual iPhone checks. No device identifiers, Health values, personal usage, screenshots, signing files or credentials belong here.

## Delivered behavior

The ordinary app links `MorningHealth`; the widget does not. Apple Health sleep analysis is read-only and off by default. Only the explained inclusion action requests permission. The app displays recorded asleep duration, measurement window, inferred source categories and local read time, and uses the same sentence in the briefing. Apple does not disclose a read-authorization decision; a handled prompt or empty result is never labeled granted or denied.

Existing overlap/window rules remain unchanged. No time-in-bed total, recovery score, diagnosis, clinical records, background delivery, health writes or remote-model fallback was added. Samples and prose stay transient; only the inclusion choice is saved. Disabling sleep, background return, privacy reset and empty/failed rereads withdraw prior playback admission. Disabling also cancels a pending local voice response. Other app data and source settings are preserved.

## Evidence

Source baseline: `36fede6` from freshly fetched `origin/main`, including required widget correction `99ea980b0ec4df434c0b9282a2c501b16c9b6fcb`. Dedicated worktree and branch `guillaume/healthkit-sleep`; implementation pushed in `a6a6da8` and `0db5f7e`.

| Check | Result | Scope |
|---|---|---|
| Native capability configuration | PASS | Generated app target links MorningHealth; widget does not. App source requests exactly standard HealthKit, WeatherKit and the two Screen Time capabilities. |
| XML/catalog validation and diff review | PASS | Plists parse; focused independent review covered native reader, controller lifecycle, UI and speech callers. |
| Package tests | PASS | 99 targeted tests: 95 MorningApple + 4 HealthKit mapping, including 8 new lifecycle tests. Synthetic fixtures only; no Health store or personal data. |
| iOS simulator build | PASS | Ordinary app + widget + UI-test target compile (`build-for-testing`, exit 0). No live-provider claim. |
| Simulator UI checks | PASS | Two isolated native tests: sleep starts off and remains off on unavailable reader; selected calendar/weather preview contributes no sleep fact. Screenshots inspected for off, error and recap states. No real-provider claim. |
| Ordinary signed iPhone build | PASS | MORE 0.1.0 (1563), Xcode 27.0 (27A266a), ordinary MorningOperator scheme; target-specific manual Development signing. |
| Strict app/widget signatures and embedded profiles | PASS | Strict/deep codesign; exact Development identity and profiles; all four expected app capabilities, no Health extras/PCC and no app capabilities in widget; Google public configuration matches the local kit. |
| Private backup / in-place installation / ordinary launch | PASS | Private backups before both upgrades (1552 → 1561 → 1563). Final installed version and ordinary running process verified. Personal Team variant unchanged. No uninstall/reset. |
| Real sleep consent, reading and visible/vocal integration | PENDING — owner action | Final 1563 is installed/open. Owner must handle the Apple sheet in Settings → Calendar, weather & sleep → Include recorded sleep, then Refresh sleep and Hear this recap. No real sample or audibility confirmation has been received; never report this as a pass. |
| Weather and Screen Time regression check | PENDING — owner action | Requested on final 1563. Prior 1552/1541 results do not establish the new build’s behavior. |

The final signed build used clean source `18115f0f4c2a3116c08c932f1a6bd152f2943818`, combining current main `92528f3` (compact access onboarding) with Health and the discoverable **Calendar, weather & sleep** source entry. The 99 package tests passed again on the combined code (`293baa8`); the following product change is source-entry text only. The two UI tests passed after the scoped test helper was updated for the current Home → Settings route (`36c1738`). Later report changes do not alter compiled behavior.

Targeted command (dedicated worktree):

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --scratch-path /tmp/more-health-controller-spm --filter '(HealthConnectionLifecycleTests|SleepBriefingControllerTests|SleepObservationTests|SleepIntervalBoundaryTests|ConcurrentBriefingSourceTests|MorningBriefingControllerTests|MorningBriefingPersistenceRaceTests|MorningBriefingTests|MorningAppStepExecutorTests|HealthKitSleepReaderTests)'
```

Raw logs, result bundles, installation evidence and any backup stay in a private local directory. Remote-main containment is verified as part of delivery; the final commit is recorded in issue #15. Issue #15 remains open until the real-device acceptance is complete.

The first UI attempt used an obsolete date/Review helper and failed before reaching the changed screen. The focused helper was updated; one subsequent simulator attempt was blocked by the runner still installing. The final two-test run completed successfully. The complete historical UI suite was not run. No owner data was erased to test forgetting; that path was exercised with local test workspaces only.
