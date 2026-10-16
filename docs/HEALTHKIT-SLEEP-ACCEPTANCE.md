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
| Simulator UI checks | RUNNING | Separate isolated tests; no real Health, weather or Screen Time claim. |
| Ordinary signed iPhone build | PASS | MORE 0.1.0 (1561), Xcode 27.0 (27A266a), ordinary MorningOperator scheme; target-specific manual Development signing. |
| Strict app/widget signatures and embedded profiles | PASS | Strict/deep codesign; exact Development identity and profiles; all four expected app capabilities, no Health extras/PCC and no app capabilities in widget; Google public configuration matches the local kit. |
| Private backup / in-place installation / ordinary launch | PASS | Private backup of previously installed 1552; in-place upgrade to 1561, installed version and running process verified. Personal Team variant unchanged. No uninstall/reset. |
| Real sleep consent, reading and visible/vocal integration | PENDING | Owner must interact directly on iOS 27.2; report only the outcome, never the measurements. |
| Weather and Screen Time regression check | PENDING | Prior build results do not establish the new build’s behavior. |

The signed build used `0db5f7e0d92b1037b804b9c706fbdd8c98e75361` plus one nonfunctional correction to the default-reader comment in SleepObservationService. Later report/comment changes do not alter the compiled behavior.

Targeted command (dedicated worktree):

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --scratch-path /tmp/more-health-controller-spm --filter '(HealthConnectionLifecycleTests|SleepBriefingControllerTests|SleepObservationTests|SleepIntervalBoundaryTests|ConcurrentBriefingSourceTests|MorningBriefingControllerTests|MorningBriefingPersistenceRaceTests|MorningBriefingTests|MorningAppStepExecutorTests|HealthKitSleepReaderTests)'
```

Raw logs, result bundles, installation evidence and any backup stay in a private local directory. The final delivery commit and remote-main containment must be checked after integration. Issue #15 remains open until the real-device acceptance is complete.
