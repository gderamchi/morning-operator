# Optional HealthKit sleep — 16 October 2026

Tracks [issue #15](https://github.com/gibouu/morning-operator/issues/15). This report keeps engineering checks separate from the owner’s actual iPhone checks. No device identifiers, Health values, personal usage, screenshots, signing files or credentials belong here.

## Owner feedback and expanded scope

The owner reports that Weather and Screen Time work on installed build 1563. Apple asked only for sleep access, and an older sleep record was returned. The owner rejected the long explanations, the date-led presentation and the robotic spoken experience. This is partial source evidence, not acceptance of the complete Health or voice journey. No Health value or date is retained in this report.

Continuation `4e66385` adds separately consented VFC/HRV SDNN, resting heart rate and breathing rate, with the writing app’s name, exact observation time and per-type freshness/error handling. Existing sleep-only choices stay sleep-only until explicit upgrade. All new source scopes start off. **113 targeted shared/native mapping tests pass** with serial test scheduling; no real Health store was read by those tests. The direct Health entry and compact presentation are app changes awaiting the combined native/UI/device checks below.

The owner also authorized an explicit temporary Debug cross on onboarding/paywall, remembered across launches. It grants development access without a fake StoreKit transaction; Release retains verified subscription access. This removes the prototype’s blocked product-configuration gate while preserving the full onboarding presentation. Natural conversation is tracked separately in [NATURAL-VOICE.md](NATURAL-VOICE.md).

## Combined delivery

Remote main contains all thirteen listed PR histories at source `43d1d04`. **MORE 0.1.0 (2026101610)** is compiled, signed, strictly verified and frozen from that clean source. Its in-place installation is waiting for other active physical test hosts to finish; the guard stopped before backup, installation or launch. The older phone checkpoints below are historical evidence.

Swift Testing reports 1,961 tests without failures at `4577ff4`; seven optional replay/live-model declarations are skipped. Thirteen distinct synthetic UI checks pass across the recorded runs: the ten previous checks plus three connection navigation/retry/title checks, including French largest text. Ordinary app/widget/UI-test and separate Demo compilation pass at final `43d1d04`; the Demo build preserves 112 ordinary test-product files. The final 34 Python tests pass, and 133 restored English resource units are verified in compiled app/package resources with French preserved. Nine numeric PCM conversion cases pass without an iPhone engine or microphone. No full package rerun is claimed for the iOS-only Demo delta. See the [combined evidence](ALL-PR-INTEGRATION-2026-10-16.md) for source-specific boundaries.

Strict final signatures have exactly standard HealthKit, WeatherKit and the two Screen Time capabilities in the app, none in the widget; Google configuration and the real app-only Worker URL match the local kit. No extra Health records/background/PCC grant, provider credential, enabled fixture argument or StoreKit test configuration is present.

No real Health values or microphone transcript were read by these checks. Expanded Health consent/freshness/source acceptance and audible natural conversation remain owner checks, separate from installation. The actual voice installation awaits its first explicit Use ElevenLabs request and individual activation; QA authorization does not activate the phone. See [natural voice](NATURAL-VOICE.md), #15 and #116.

## Earlier sleep checkpoint (historical)

The remaining sections describe the earlier sleep delivery. Their references to installed 1563 and a still-gated newer build are historical evidence, not the current device inventory.

## Delivered behavior

The ordinary app links `MorningHealth`; the widget does not. Apple Health sleep analysis is read-only and off by default. Only the explained inclusion action requests permission. The app displays recorded asleep duration, measurement window, inferred source categories and local read time, and uses the same sentence in the briefing. Apple does not disclose a read-authorization decision; a handled prompt or empty result is never labeled granted or denied.

Existing overlap/window rules remain unchanged. No time-in-bed total, recovery score, diagnosis, clinical records, background delivery, health writes or remote-model fallback was added. Samples and prose stay transient; only the inclusion choice is saved. Disabling sleep, background return, privacy reset and empty/failed rereads withdraw prior playback admission. Disabling also cancels a pending local voice response. Other app data and source settings are preserved.

## Evidence

Source baseline: `36fede6` from freshly fetched `origin/main`, including required widget correction `99ea980b0ec4df434c0b9282a2c501b16c9b6fcb`. Dedicated worktree and branch `guillaume/healthkit-sleep`; implementation pushed in `a6a6da8` and `0db5f7e`.

| Check | Result | Scope |
|---|---|---|
| Native capability configuration | PASS | Generated app target links MorningHealth; widget does not. App source requests exactly standard HealthKit, WeatherKit and the two Screen Time capabilities. |
| XML/catalog validation and diff review | PASS | Plists parse; focused independent review covered native reader, controller lifecycle, UI and speech callers. |
| Package tests | PASS | 100 targeted tests: 96 MorningApple + 4 HealthKit mapping, including 9 new lifecycle tests. Synthetic fixtures only; no Health store or personal data. |
| iOS simulator build | PASS | Ordinary app + widget + UI-test target compile (`build-for-testing`, exit 0). No live-provider claim. |
| Simulator UI checks | PASS | Two isolated native tests: sleep starts off and remains off on unavailable reader; selected calendar/weather preview contributes no sleep fact. Screenshots inspected for off, error and recap states. No real-provider claim. |
| Latest main combined signed build | PASS | MORE 0.1.0 (1565), Xcode 27.0 (27A266a), ordinary MorningOperator scheme; target-specific manual Development signing. No StoreKit test configuration or enabled test arguments. This binary has not been installed. |
| Strict app/widget signatures and embedded profiles | PASS | Strict/deep codesign; exact Development identity and profiles; all four expected app capabilities, no Health extras/PCC and no app capabilities in widget; Google public configuration matches the local kit. |
| Private backup / in-place installation / ordinary launch | PASS | Private backups before both upgrades (1552 → 1561 → 1563). Final installed version and ordinary running process verified. Personal Team variant unchanged. No uninstall/reset. |
| Real sleep consent and reading | PARTIAL — owner report | 1563 requested sleep only and returned an older record. The owner rejected the presentation/voice; current measurements and matching audible facts are not accepted. |
| Weather and Screen Time on 1563 | PASS — owner report | The owner explicitly confirmed both work. This is not proof for a later installed build. |

The latest signed build used clean source `3369115e44bcb0058687f8ffd1b46db10f2cb9e4`, combining main `2adf69e` (subscription entry from #192), compact access onboarding and Health. All 100 targeted package tests passed on the combined shared logic; the final app-only fixes withdraw shortcut notices/audio and retained Home captions at privacy boundaries. The two focused UI tests passed on the Health/settings interface; they use an isolated fixture and do not prove the ordinary subscription gate.

The phone retains **1563**, the installed, ordinarily launched Health checkpoint from before #192. Current main requires verified StoreKit access before entering the app; live billing/access is separately unverified in [#191](https://github.com/gibouu/morning-operator/issues/191). No purchase or bypass was introduced for Health QA. Installing the newer gated binary and completing its normal subscription-to-Health journey remains a separate owner/device gate. The owner subsequently confirmed Weather/Screen Time and a returned older sleep record on 1563; the Health presentation and voice were rejected. See the continuation above.

On access withdrawal, the app clears transient briefing work and stops speech. Real backgrounding cancels pending initial Health setup and stops Health speech. Health-containing shortcut recaps leave a generic notice rather than personal sleep prose on Home; disabling Health clears the retained Home passage. Durable choices and other app data remain intact.

Targeted command (dedicated worktree):

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --scratch-path /tmp/more-health-controller-spm --filter '(HealthConnectionLifecycleTests|SleepBriefingControllerTests|SleepObservationTests|SleepIntervalBoundaryTests|ConcurrentBriefingSourceTests|MorningBriefingControllerTests|MorningBriefingPersistenceRaceTests|MorningBriefingTests|MorningAppStepExecutorTests|HealthKitSleepReaderTests)'
```

Raw logs, result bundles, installation evidence and any backup stay in a private local directory. Remote-main containment is verified as part of delivery; the final commit is recorded in issue #15. Issue #15 remains open until the real-device acceptance is complete.

The first UI attempt used an obsolete date/Review helper and failed before reaching the changed screen. The focused helper was updated; one subsequent simulator attempt was blocked by the runner still installing. The final two-test run completed successfully. The complete historical UI suite was not run. No owner data was erased to test forgetting; that path was exercised with local test workspaces only.

This task performed no App Store/TestFlight upload, Distribution CSR, private-key export, account change or revocation. All profile/certificate/configuration files and raw evidence remain outside Git.
