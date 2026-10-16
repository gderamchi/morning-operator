# MORE subscription entry

The owner selected **€4.99 per month with a one-week free trial** on 16 October 2026. The entry flow explains learning, reviewing and delegating the morning before showing the offer. Actual prices and trial eligibility come from StoreKit. There are no permission requests or paid visual-theme features in this flow.

## Native flow and setup handoff

`MorningOperatorApp` presents `MorningSubscriptionEntryView`. It checks verified StoreKit entitlements before building `MorningRootView`, so routine setup and permission presenters cannot run before access is confirmed. This is the handoff point for the separate permission workstream. It does not itself implement that workstream's explanations or requests.

`MorningWelcomeFlow` owns the three introduction pages and paywall presentation. `MorningSubscriptionStore` loads the configured monthly auto-renewable product, checks exact one-week trial eligibility, verifies purchases, listens for transaction changes, restores through `AppStore.sync()` and checks expiration. Verified billing grace is honored when Apple supplies a future grace expiry. A changed price or trial requires another tap after the offer updates. Pending, cancelled, missing, failed or unverified purchases never unlock setup. Revocation pauses an active morning and stops hands-free listening; existing local data is retained. Privacy controls remain accessible from the paywall.

All four screens use the Home landscape and clock without location permission. Native semantic surfaces, typography and shared buttons follow the latest app design system; day/night remains independent of subscription state. Text stays on opaque reading surfaces, including at sunset. Accessibility text sizes move the action area into the scroll view and page changes reset its position. The existing privacy-data screen follows the same solar appearance.

## App Store configuration still required

The default configured product identifier is `com.gibouu.more.monthly`, overridable with the `MORE_SUBSCRIPTION_PRODUCT_ID` Xcode build setting. It is a configuration contract, not evidence that an App Store product exists. Create or select the actual auto-renewable monthly subscription in App Store Connect, set its French price to €4.99 and its introductory free trial to one week, and use its real identifier in the build. Complete Apple's agreements, availability and review requirements and the app's published privacy policy before release. The app never silently substitutes a fixed marketing price if the product is unavailable.

`Configuration/MORE.storekit` is an opt-in **local test fixture**: €4.99 monthly, one-week free trial, French storefront. It is bundled only in the UI-test target. The ordinary run scheme does not activate a simulated store or grant trial access. `MorningSubscriptionPurchaseTests` starts its own `SKTestSession` against this fixture. A DEBUG-only `--preview-onboarding` renders fixed, labelled sample pricing and simulated purchase failures; it cannot unlock the app. Other existing `--ui-testing` journeys bypass the gate only in DEBUG. `--ui-testing-real-subscription` explicitly exercises the real coordinator against the local StoreKit session.

The dedicated `MORESubscriptions` scheme activates the fixture for manual runs and selects only `MorningSubscriptionPurchaseTests` for testing. The initial CLI run on iOS 26.5 Simulator (23F77) failed before the purchase assertions: `SKTestSession` could not save its configuration or apply overrides (`SKInternalErrorDomain Code=3`). Apple confirms the matching issue in [FB22237318](https://developer.apple.com/forums/thread/826971); [iOS 26.6 release notes](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-26_6-release-notes) list the Simulator connection fix as FB22500243. The native StoreKit tests explicitly skip on iOS 26.5 Simulator and retain their assertions on other runtimes. A skip is unverified purchase behavior, not a passing purchase test. Use iOS 26.6 or later for the native purchase proof.

## Verification

Generate the project with `scripts/generate-project.sh`. Build and run `MorningWelcomeFlowTests` and `MorningSubscriptionPurchaseTests` on a dedicated simulator. `MO_ONBOARDING_SCREENSHOT_DIR` exports synthetic review images outside Git. Local StoreKit results do not establish a live App Store product, sandbox payment, physical-device purchase or production entitlement behavior. Record observed results in the delivery PR.
