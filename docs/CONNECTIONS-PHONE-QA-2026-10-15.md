# MORE connections: real-phone acceptance ledger

15 October 2026. This ledger separates provider access, the production backend, and the phone journey. No private account identity, credential, message content or provider response values are retained here.

## Backend and provider API

Production origin: `https://more-composio.more-gderamchi.workers.dev`.

| Check | UTC observation | Verified result | Boundary |
| --- | --- | --- | --- |
| Production D1 installation count | 19:04:09.983 | **11 installations** | Count only; this does not identify eleven phones or people. No token hash, installation identity or receipt was returned. |
| Production D1 execution states | 19:04:09.983 | **0 executions**: pending 0, complete 0, uncertain 0 | Two read-only aggregate SELECTs were used for these D1 checks. No database state was changed. |
| Configured project accounts | 19:04:53.140 | Complete Composio account list returned HTTP 200: **one account**, Gmail **ACTIVE**, matching MORE's configured auth config and not disabled/shared. Its owner has the backend-generated identity format. | This is the actual MORE project, using its existing server configuration, not the chat plugin's grants. No identity or raw account record was printed. |
| Existing QA installation | 19:04:53.839 | Authenticated production `/v1/connections` returned HTTP 200 with **zero connections** | This existing QA bearer is distinct from the Gmail account's owner. It does not establish the physical phone's installation identity. No installation was created. |
| Service discovery | During this check, before 19:04:31 | Authenticated production `/v1/services` returned HTTP 200 with **16 services** | Configured services and their public catalogs are not completed user grants. |
| Actual Gmail provider read | During this check, before 19:04:31; exact execution timestamp was not separately retained | **`GMAIL_GET_PROFILE` succeeded**: HTTP 200, `successful: true`; expected profile field types verified in memory | One direct Composio call with the actual MORE account and pinned version `20261010_00`, arguments `{"user_id":"me"}`. This proves this grant can retrieve a Gmail profile, not mailbox-message reading, native Gmail authorization or the complete phone/backend journey. |

At 19:11:29 UTC, the existing connected account's OAuth-state metadata also declared Gmail read, Gmail send and Contacts-read scope groups as present (`state.val.scope`, also `data.scope`, distinct from requested scopes). Only booleans were returned. This is Composio account-state evidence, not Google token introspection or proof of sending. No extra provider call or broader grant was made.

The Gmail probe's public tool/schema was inspected before execution. The expected fields were `emailAddress`, `historyId`, `messagesTotal` and `threadsTotal`; **none of their values were printed or saved**. No message was read, marked read, sent, modified or created. The probe was executed once without a retry. It used direct project execution, so it did not create a production MORE execution-journal row.

At the complete project snapshot above, the other **15 configured services had no connected account**: Google Calendar, Outlook, Google Drive, Google Docs, Google Sheets, Notion, Slack, Calendly, Instagram, WhatsApp, LinkedIn, Discord, Facebook, YouTube and Reddit. No provider tool was attempted for those unconnected services. Account eligibility still applies: Instagram professional accounts, WhatsApp Business Platform and Facebook Pages are distinct from personal website access.

### Remaining evidence

- Confirm the physical iPhone's **Gmail account-actions** screen actually lists an ACTIVE account. That screen uses its own Keychain installation bearer; the unrelated QA installation's empty result is not evidence that the phone is disconnected.
- Run one reviewed harmless read through **the production mobile backend from the phone**. The direct Composio profile read above does not establish that path.
- Complete each other intended service's actual consent and verify ACTIVE ownership before testing its bounded read. No connections, grants or broader scopes were created by this verification.
- Verify the **native Gmail reader separately**. Its Google iOS OAuth configuration/credential is independent from Composio Gmail actions; neither a public catalog nor the profile probe authorizes that reader.
- Native permissions, installed Shortcuts and their effects, website sessions/scrolling, and a complete approved phone routine require their own acceptance records. No such outcome is claimed by this backend section.

Only existing configuration was read. The moving shared checkout was not edited; no provider write, OAuth flow, installation creation, build or phone control was performed for this section. The local Composio CLI was unavailable, so the existing MORE REST contract and project API were used; the hosted chat connector was not used as a substitute.

## Physical iPhone: first ordinary-build inspection

Observed on 15 October 2026 around 21:01–21:07 Europe/Paris, on the paired iPhone 17 running iOS 27.2. `devicectl` confirmed MORE 0.1.0 (1522), personal development bundle. The ordinary app was already open; no fixture flags, seeded workspace, reset or replacement routine was used. Private screenshots remain outside Git.

| Route | Observation in the installed app | Result and limit |
| --- | --- | --- |
| API account configuration | Settings → Apps & accounts → Your accounts displays “Account connections are not available in this version yet.” | **Blocked in build 1522**: the production backend origin was not injected into this build. A working backend and a project-level Gmail grant do not establish this phone path. The next signed build must include the existing production origin, then be tested again. |
| Instagram website | Real `www.instagram.com` shows its welcome page with Log in / sign up. | Website loaded; no authenticated Instagram session established. No readiness flag forced. |
| TikTok website | Real `www.tiktok.com` loaded its cookie choice and app-promotion modal. Declined optional cookies and chose Not now. A public video loaded; one visible swipe changed to a second distinct video. | **Public playback and manual scrolling observed in MORE on the phone**. This is not a signed-in account, approved-like test, or proof of autonomous scrolling by MORE. |
| X website | Real `x.com` displayed the login form. | Website loaded; no authenticated X session established. |
| WhatsApp website | Real `web.whatsapp.com` offered Continue to WhatsApp Web; following it displayed the QR association page. | Not linked. The desktop page exceeded the embedded viewport and clipped the QR horizontally. No code was scanned, grant accepted or readiness flag forced. |
| Shortcuts setup | Messages guide and empty exact-shortcut-name field visible. | No preconfigured shortcut name was observed for Messages. This does not inventory the separate Apple Shortcuts app or prove a native effect. |

The Google/OAuth configuration and new routine implementation are being prepared in the separately coordinated workstream. Neither the future build nor its voice/routine features are certified by these 1522 observations.

Device Hub subsequently stopped accepting coordinate gestures with `noWindowsAvailable`, despite fresh state, reacquisition and compact/full-window checks. Its Mac accessibility commands and phone image remained available, but physical iOS accessibility nodes were not exposed. This is a **test-control limitation**, not an app-success claim. Ordinary real-device XCTest checks are being prepared in the UI-test target without fixture or reset arguments; no new native permission or external write was accepted during this first inspection.

## Ordinary-phone XCTest gate

The isolated UI-test source and its four project references were compiled with the full installed Xcode toolchain: **build-for-testing succeeded**. Independent review found no routine edits, grant acceptance or external writes. The test app artifact separately passed local configuration checks for the matching native Google client/callback and backend origin, but that app artifact was **not installed**.

Only the signed `MorningOperatorUITests-Runner.app` was installed. A local `.xctestrun` used the Xcode-documented `UseDestinationArtifacts=true`, explicit ordinary bundle identifier and existing destination artifacts, without app paths for installation or fixture arguments. A subsequent `devicectl` check confirmed the ordinary MORE app remained **0.1.0 (1522)**.

On launch, iOS displayed **“Enter iPhone Passcode for XCTest — Enable UI Automation.”** The owner was asked to validate directly on the phone; no passcode was requested in chat or entered by the test. The runner timed out while enabling automation mode, before any of the three acceptance tests initialized. **Zero functional test outcomes are claimed** from this attempt. The native Calendar/Reminders accesses and phone API account association remain unverified until the owner completes this system gate and the checks are rerun. No automatic retry was made.
