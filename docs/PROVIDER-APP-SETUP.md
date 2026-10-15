# Prepare MORE developer apps: TikTok and X

**Archived optional API preparation.** The current product choice uses MORE’s embedded browser for TikTok/X scrolling. Creating developer apps, finishing the portal sign-ins and activating these API configs are not required for that browsing flow. The notes below remain available only for a future explicit API use case.

Prepared 15 October 2026. These are copy-ready application fields and remaining checks, not connected accounts. No developer app, credential, grant, paid balance or production review has been created by this preparation. Private working state is kept in ignored `.build/provider-app-setup/`.

## Common fields

| Field | Prepared value or missing item |
| --- | --- |
| Brand / app name | **MORE** |
| Short description | A personal morning companion for iPhone with routines you review and control. |
| Existing icon | `Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`: PNG, 1024 × 1024. Check upload size and rendered appearance before submission. |
| Canonical bundle ID | `com.gibouu.morningoperator`, from the Xcode project. The personally signed prototype uses a different bundle; do not represent it as an App Store listing. |
| Public product website | **Missing verified URL.** The connection server's health endpoint is not a product website. |
| Public privacy policy | **Missing published policy URL.** `docs/PRIVACY.md` is implementation documentation, not a verified public legal policy. |
| Public terms | **Missing published terms URL.** Do not invent legal text or an owner/entity. |
| App Store URL | **Missing.** No published listing was verified. |
| Owner, country, contact / entity | Select the actual owner when the portal requires it; do not infer a company or US availability. |

## TikTok: prepare Sandbox first

**App name:** `MORE`

**Description:**

> MORE is an iPhone morning companion. Its planned TikTok connection lets a person explicitly connect their own account and choose to view their profile and recent public videos within a reviewed morning routine.

**Products:** Login Kit + Display API. **Initial scopes:** `user.info.basic` for the connected profile; `video.list` for that person's public videos. Do not request posting/upload/profile statistics merely because Composio selects them by default. Display API exposes profile and the user's own videos; this is not the personal For You feed. [TikTok Display API](https://developers.tiktok.com/docs/en/display-api-overview)

**OAuth topology:** Composio hosts the confidential server flow, opened from MORE on iPhone. Prepare Login Kit **Web** for that actual server callback; this does not turn MORE into a browser-only product. Native TikTok SDK integration is a separate iOS flow. Login Kit Web requires an exact static HTTPS redirect, no query or fragment, fewer than 512 characters, at most ten URLs. [Login Kit Web](https://developers.tiktok.com/docs/en/login-kit-web)

**Portal state:** Safari reached the official developer login page. A developer email/password is required; no active developer session was available, so no remote draft was saved. The local fields are ready.

**Sandbox path after sign-in:** Manage apps → Connect an app → choose the real owner → Sandbox → Create Sandbox → `MORE development` → configure Login Kit and Display API. TikTok documents five sandboxes and ten target users without production review. Adding a target account is a separate login/consent step. Sandbox configuration does not prove that an empty iOS App Store URL is accepted by the current form. [Sandbox guide](https://developers.tiktok.com/docs/en/add-a-sandbox)

**Production later:** register the real iOS bundle and App Store URL, publish and verify website/privacy/terms ownership, and record the implemented consent-to-result journey for review. New apps start as Draft; their credentials are available before review. Production guidelines require a launched external product and reject apps that remain in development/testing or only serve private/personal use. Sandbox is the appropriate initial preparation. [Register an app](https://developers.tiktok.com/docs/en/getting-started-create-an-app), [review guidelines](https://developers.tiktok.com/docs/en/app-review-guidelines)

## X: prepare a confidential Web App

**App name:** `MORE`

**Description / use case:**

> MORE is an iPhone morning companion. Its planned X connection lets a person explicitly connect their own account, view their profile, and read a limited reverse-chronological timeline from accounts they follow during a routine they review and control.

**Authentication:** OAuth 2.0 authorization code with PKCE, **Web App / confidential client**, because Composio holds the secret on the server. Initial scopes are `tweet.read`, `users.read`, `offline.access`; the last permits refresh without asking the person to reconnect every two hours. No DM or write permission is needed for this first reading flow. Exact allowlisted HTTPS callback matching is required. [X OAuth 2.0](https://docs.x.com/fundamentals/authentication/oauth-2-0/authorization-code)

**Credentials needed later:** OAuth Client ID + Client Secret, and the Application Bearer Token from the **same X app** for Composio actions that use app-only authentication. Keep these in the provider/Composio secret configuration, never the iPhone bundle or this document. [Composio X setup](https://docs.composio.dev/kb/guide/toolkits-twitter)

**Creation path:** Developer Console → New App → name, description and factual use case → authentication configuration. App creation and paid API use are separate. X uses prepaid credits for usage; no credit purchase, auto-recharge or paid execution is part of this preparation. Creating credentials or accepting the Developer Agreement requires a separate final action. [Developer apps](https://docs.x.com/fundamentals/developer-apps), [console guide](https://docs.x.com/fundamentals/developer-portal), [pricing](https://docs.x.com/x-api/getting-started/pricing)

**Portal state:** `console.x.com` returned a blank page in Safari, including after one reload. A subsequent in-app browser check rendered X's sign-in form (phone, Google, Apple or email/username), with no authenticated developer session. That tab was retained for user handoff. The local fields are ready; no remote draft was saved.

The supported following timeline is reverse chronological, rather than the app's algorithmic For You feed. [X timelines](https://docs.x.com/x-api/posts/timelines/introduction)

## Exact callback pair for the new configurations

The current MORE dashboard's **custom TikTok auth-config form** was inspected directly on 15 October. Its disabled Redirect URI field displayed:

`https://backend.composio.dev/api/v1/auth-apps/add`

Composio's current programmatic setup documentation explains the difference: some toolkits retain this supported legacy default. For these **new** custom configurations, prepare the explicit pair below in both places:

| Location | Exact value |
| --- | --- |
| Provider application's authorized redirect URI | `https://backend.composio.dev/api/v3/toolkits/auth/callback` |
| Composio custom credentials `oauth_redirect_uri` | `https://backend.composio.dev/api/v3/toolkits/auth/callback` |

Leaving `oauth_redirect_uri` unset instead requires the actual toolkit default, which may be v1. Do not register v3 at the provider while leaving a v1 default in Composio. The disabled dashboard field inspected above does not offer this override; use Composio's documented custom configuration path that explicitly sets the value. This pair is documented and prepared, **not yet saved or tested by a live grant**. [Programmatic auth configs](https://docs.composio.dev/docs/authentication/programmatic-auth-configs), [custom auth config redirect matching](https://docs.composio.dev/docs/auth-configuration/custom-auth-configs)

The provider callback is separate from MORE's `more://composio/callback` mobile return and the connection server's `/v1/oauth/callback` session verifier. Neither is a replacement for Composio's provider redirect.

## Ready-to-complete checklist

1. Sign into the developer portals with the intended owner; inspect existing apps before making another.
2. Explicitly set the same v3 provider redirect in both the provider app and Composio custom config, with the reviewed minimum scopes.
3. Create a TikTok Sandbox draft and an X app draft where the portal allows a reversible save without issuing credentials or accepting new terms.
4. Obtain the real public website, privacy/terms and App Store URLs for production fields. Do not invent values to pass validation.
5. Present the exact final creation/terms/access action for confirmation, then store any credentials directly in the secure provider/Composio configuration.

Configuration availability, approved products/scopes, a connected account, and a successful live provider action are separate milestones. None of the last three is established here.
