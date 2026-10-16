# Subscription entry verification — 16 October 2026

The source includes the current adaptive Settings design and the separate permission setup. The subscription entry builds the existing root only after verified StoreKit access; no permission implementation was duplicated in this workstream.

## Observed results

| Check | Result and boundary |
| --- | --- |
| Integrated app and UI-test build | `xcodebuild build-for-testing` passed using Xcode 27, deployment target iOS 26.0 and the installed iOS 26.5 simulator. App, widget, shared modules and UI tests compiled. |
| Welcome interface suite | Four native XCTest journeys passed: three intro pages plus offer in day/night and French/English; Back/skip and Terms/Privacy sheets; purchase/restore failure recovery; ineligible trial, unavailable offer and pending state; accessibility XXXL portrait/landscape reachability. A fifth existing Settings → routine/accounts/voice journey also passed after integration. Welcome transactions use explicitly labelled simulated previews. |
| Native StoreKit suite | Initial local-store calls failed with `SKInternalErrorDomain Code=3`, including configuration and transaction setup. The installed iOS 26.5 runtime has the reported StoreKit Test connection problem. The original eight and, after adding declined-request recovery, all nine native purchase cases were explicitly skipped. **No native purchase test passed; transaction behavior remains unverified.** The supported-runtime assertions are retained. |
| Shared package tests | Not rerun for this app-only workstream. Package compilation was part of the Xcode build; it is not a package-test result. |
| Live offer and physical iPhone | App Store Connect configuration, Apple sandbox purchases, production billing and physical-device purchase flows were not performed. No physical app installation was replaced. |

Apple references: [reported StoreKit CLI failure and DTS replies](https://developer.apple.com/forums/thread/826971), [iOS 26.6 release notes](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-26_6-release-notes). Re-run `MORESubscriptions` with a compatible simulator before treating native purchase coverage as complete.

## Local evidence

- Final build: `/tmp/more-onboarding-final-build.log` (passed after the declined-request recovery fix).
- First full UI run: `/tmp/more-onboarding-ui-verified.xcresult` and `.log` (4 passed, 8 explicitly skipped).
- Combined UI run: `/tmp/more-onboarding-integrated-ui.xcresult` and `.log` (5 passed, 0 failures).
- Final targeted UI and StoreKit environment check: `/tmp/more-onboarding-final-ui.xcresult` and `.log` (3 UI cases passed, 9 native StoreKit cases explicitly skipped). This rerun covers the compact intro layout, large-text navigation and explicit pending-request recovery.
- Synthetic screenshot matrix: the chat's local `visualizations/2026/10/16/01a1423f-d371-7551-a0e0-b2c66997f472/onboarding/` directory, outside Git. It includes 16 standard introduction/paywall captures and accessibility/error-state captures. No screenshots, recordings or private account contents are committed.

The first new simulator stalled during system migration and was removed. Checks ran on a dedicated clone of an initialized iPhone 17 Pro simulator, with isolated UUID workspaces. Other chats' simulators were left alone. The visual review identified and corrected large-text header compression and an oversized debug-only preview marker; text remains on opaque surfaces at sunset, and changing pages returns to the top. Intro artwork and spacing were shortened so the example card fits above the action area at ordinary text sizes. A source review identified that declined Ask to Buy requests do not produce callbacks; explicit retry now reconciles verified access before making a new user-requested purchase attempt.

Live release prerequisites and the purchase-to-permission acceptance journey are tracked in [issue #191](https://github.com/gibouu/morning-operator/issues/191).
