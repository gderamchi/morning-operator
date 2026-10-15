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
| Bounded Gmail mailbox read | 19:22:11.230 | **`GMAIL_FETCH_EMAILS` succeeded**: HTTP 200, `successful: true` at every exposed response layer; a valid nonempty `messages` array contained a normalized `messageId` of type string | One direct Composio call with the existing MORE account and pinned version `20261010_00`: `user_id: "me"`, `max_results: 1`, `ids_only: true`, `verbose: false`, `include_payload: false`, `include_spam_trash: false`, without a restrictive query. No identifier value, body, subject or address was printed or retained. This verifies bounded mailbox identifier access, not the phone/backend execution path. |

At 19:11:29 UTC, the existing connected account's OAuth-state metadata also declared Gmail read, Gmail send and Contacts-read scope groups as present (`state.val.scope`, also `data.scope`, distinct from requested scopes). Only booleans were returned. This is Composio account-state evidence, not Google token introspection or proof of sending. No extra provider call or broader grant was made.

The profile probe's public tool/schema was inspected before execution. The expected fields were `emailAddress`, `historyId`, `messagesTotal` and `threadsTotal`; **none of their values were printed or saved**. The separate mailbox probe used the previously inspected identifier-only schema. Each probe was executed once without a retry. No message content was read and no message was marked read, sent, modified or created. Both used direct project execution, so neither created a production MORE execution-journal row. No additional grant was requested.

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

Only the signed `MorningOperatorUITests-Runner.app` was installed. A local `.xctestrun` used the Xcode-documented `UseDestinationArtifacts=true`, explicit ordinary bundle identifier and existing destination artifacts, without app paths for installation or fixture arguments. A subsequent `devicectl` check instead found ordinary MORE **0.1.0 (1523)**, changed from the initial 1522 inventory during this coordinated multi-chat session. Our installation result lists only the runner. The runtime baseline must therefore be inspected again before attributing new outcomes; no preservation of build 1522 is claimed.

On launch, iOS displayed **“Enter iPhone Passcode for XCTest — Enable UI Automation.”** The owner was asked to validate directly on the phone; no passcode was requested in chat or entered by the test. The runner timed out while enabling automation mode, before any of the three acceptance tests initialized. **Zero functional test outcomes are claimed** from this attempt. The native Calendar/Reminders accesses and phone API account association remain unverified until the owner completes this system gate and the checks are rerun. No automatic retry was made.

## Configured phone candidate 1530

The coordinated automation workstream produced checkpoint `6f323e8`, incorporating merged main `c4da626`, and installed MORE **0.1.0 (1530)** in place. This candidate includes the Gmail/automation implementation, but not the separately ongoing proposal-editing UX correction. Independent read-only artifact checks confirmed the native Google client/callback match the local canonical configuration, the callback is registered, the production Worker origin is exact, app/widget versions and personal-team signatures agree, and strict/deep signature checks succeed. Public Google configuration remains outside Git.

An ordinary `devicectl` launch of the installed 1530 succeeded; the real phone Home was observed, without fixture arguments, reset or synthetic workspace. The Google project has Gmail API enabled and the owner is configured as a test user. The live native Google grant is still a separate gate; the owner was given the direct phone connection journey and asked to complete its consent/passkey if required. No grant, native mailbox read or send is claimed from configuration and launch alone. The separate Console scope-declaration Save is being completed in the coordinated workstream.

After the owner's first XCTest acknowledgement, a second runner attempt again timed out while enabling automation mode, before any functional test initialized. iOS displayed a fresh passcode request for that attempt. The owner was notified; no further automatic retry was made. The app is now left available for its normal Gmail connection, and the next test launch will be coordinated with the owner rather than allowed to expire during authentication.

Device Hub still rejects coordinate gestures after the new ordinary launch. A narrowly scoped attempt to copy the app's own preferences file returned a file-node error; no shortcut configuration inventory was obtained and no absence of all shortcuts is inferred. No app container, inbox content or raw media was copied. Native Calendar/Reminders permissions and effects, installed shortcut effects, provider ownership in this phone installation, acoustic interaction and a complete routine remain acceptance work.

## Owner acknowledgement and first initialized device checks

The owner subsequently reported Gmail connected in MORE and no visible XCTest prompt. The previous request had expired; it was not a currently pending passcode request. The next explicit runner launch initialized successfully without another owner prompt. MORE remained **1530**; only the UI-test runner had been updated, with destination artifacts and no app replacement or fixture arguments.

At **19:44–19:45 UTC**, all three original checks executed. The app exposed its live configured service catalog and the expected Outlook entry. However, the Gmail account-action row was not reached after expanding its disclosure; Calendar and Reminders navigation also failed. These are **three failed acceptance tests**, not three proven provider failures. Local recordings show the Gmail disclosure did expand, and the Calendar attempt returned to Home. Selector ambiguity and navigation through cached stack elements are being corrected before attributing those failures to product behavior. No consent or external effect was triggered.

At **19:47–19:48 UTC**, a separate native Gmail check opened the normal reader and waited for its automatic bounded load. It found `gmail.connect` present and `gmail.refresh` absent, and therefore **skipped** rather than start a new consent. This differs from the owner's reported connection and needs a direct reader-state check; it is not evidence of a completed native read. The test never opened a message, requested authorization, or sent mail. One skipped test with zero failures does **not** constitute a successful Gmail acceptance test.

The coordinated workstream has separately verified the Google Console's three declared scopes persisted after reload. A later candidate adds the approved self-addressed test-mail journey; it has not been installed or used by this QA step. No message has been sent. Complete native effects, authenticated websites and the full routine remain unverified.

## Precise phone account check and lost device connection

At **19:52 UTC**, the narrowed selector reached the actual Gmail account-actions page. Its loaded state displayed **“No account connected yet”**, a Connect Gmail button and Refresh my accounts, without a connection error. The explicit ACTIVE-account expectation failed. This establishes that **this phone installation did not list the separately verified project-level Gmail account**; it does not invalidate that project's grant or the owner's report about the separate native reader.

The three following tests skipped because the failed method left Gmail actions open. Those skips are navigation preconditions, **not Calendar/Reminders permission results or another reader-state result**. A guarded XCTest teardown now returns only from recognized connection pages, respects alerts and does not dismiss arbitrary owner screens. Calendar errors are checked before the no-inventory skip, so a failed read cannot be labeled missing access. The updated runner compiled successfully; this cleanup has not yet been rerun on the phone.

After this run, CoreDevice reported its trusted tunnel **unavailable** and could not launch the app. A narrow installed-app inventory before the disconnect found only one MORE app, build **1530**, plus its test runner. The owner was asked to reconnect the phone by USB and leave it unlocked with MORE open. There is no currently pending XCTest passcode prompt. The later app candidate remains uninstalled, and no routine or owner data was reset to work around this gate.

## Reconnected phone: native state, real crash and owner sign-in

The trusted phone connection returned. MORE **1530** was ordinarily relaunched with its existing data, and the runner alone was updated. At **20:13 UTC**, both the isolated test and direct phone image confirmed the native reader displayed **Connect Gmail** and **Enable replies during my morning**, with no saved-connection text, Retry, Refresh, busy state or visible error. This is a confirmed native saved-state discrepancy with the owner's earlier acknowledgement, not another observation of the Composio page. No mail was read or sent.

The subsequent native checks exposed two real acceptance failures:

- **Calendar presentation:** after pressing the hub's exact Calendar row, the phone returned to Settings without exposing `briefing.*`. No calendar-permission conclusion follows. The hub pushed a view that owns a separate NavigationStack; the coordinated workstream is changing this entry to the existing modal presentation and adding `connections.calendar`. The presentation cause remains to be confirmed by a device replay.
- **Reminder read crash, 20:15:06 UTC:** the normal **Show my reminders** control was enabled, establishing the existing permission precondition. One tap crashed ordinary MORE. Its narrowly retrieved local crash report identifies `EXC_BREAKPOINT` on `com.apple.eventkit.reminders.search`, with `_dispatch_assert_queue_fail`, Swift isolation checking and the `ReminderService.fetchUpcomingReminders` callback's `compactMap`. Usage-description text was present. The report itself, account data and device identifiers remain outside Git.

Commit `07f7589` explicitly marks that EventKit callback `@Sendable`, preventing it from inheriting the service's MainActor while EventKit executes it on its own search queue. Swift Package Manager compilation, **all four ReminderDraftTests**, and the signed iOS build-for-testing passed. The first unrelated filter matched zero tests and is not counted. The coordinated workstream incorporated the fix as `1eac920` for its next candidate. This does **not** yet prove the real reminder read succeeds; the physical replay must use that corrected candidate.

At **20:18 UTC**, a separately gated owner-assistance UI test made one deliberate tap on **Enable replies during my morning** in the native reader. The phone visibly presented **accounts.google.com → Sign in to continue to MORE**, including its normal credential/Face ID handoff. The test's cleanup was disabled only for this deliberate handoff; no grant button, password, biometric or account choice was accepted by the agent. The owner was asked to finish identification and read/send consent directly on the phone. The successful test proves **presentation only**, not consent, credential persistence, mailbox access or sending. No further app launch, backgrounding or installation is permitted while that owner flow is pending.

## Native Gmail grant completed and restored

The owner then confirmed completion. At **20:20 UTC**, the ordinary phone reader visibly showed **Connection saved securely on this iPhone**, Refresh Gmail and real unread headers. The owner sign-in gate was complete; the app was not replaced.

An ordinary termination/relaunch of **1530** followed by opening the reader restored the saved connection without consent and displayed a fresh Inbox count and bounded real headers. The initial test reached those success signals but miscounted rows because SwiftUI propagated the parent `gmail.messages` identifier over the CardButtons' `gmail.message.open` identifiers. Its failed row assertion is a test-selector defect, not a Gmail provider failure. The check now recognizes those same row buttons under either identifier.

At **20:23 UTC**, the updated physical check **passed: one test, zero failures, zero skips** after another ordinary relaunch. It verified a fresh Inbox count, a loaded list bounded to five headers, no partial/stale/error state and the absence of **Enable replies during my morning** under the explicit `MO_REAL_PHONE_EXPECT_GMAIL_SEND_ACCESS=1` gate. This establishes **native saved-credential restoration, real bounded mailbox reading and sending-scope state**. It does not establish message-body reading, a delivered send, voice interaction, Composio account ownership or a full routine. No message was opened, marked read or sent by these checks.

## Existing routine inspected and Mail connected without replacement

At **20:25 UTC**, a read-only physical inventory passed and observed all eight existing moments, totalling **45 planned minutes**, with draft approval available. All eight execution descriptions were user-led. In particular, a moment titled Mail was not already a Gmail action; app labels alone cannot establish connected execution. No moment was opened or edited by that inventory.

At **20:32 UTC**, the separately opted-in existing-Mail configuration check **passed on the phone in 43.238 seconds**. It verified the exact eight-row draft, opened only Mail at index 5, confirmed its unchanged title and seven-minute duration, chose **Read my mail and help me reply** in the ordinary action picker and saved that moment once. The complete post-save inventory verified the same eight indices, all seven unrelated labels including their actions unchanged, Mail still seven minutes with the Gmail Inbox execution description, and draft approval still available. Titles, budgets and order were preserved. This is a deliberate Gmail routing change, not a replacement routine or an inferred completion result. No approval, run or mail send was performed.

The phone is free for the coordinated corrected candidate. A full journey, actual native effect, the single approved self-mail, browser account grants and acoustic behavior still require separate outcomes. Neither the inventory nor an explicit Next traversal establishes 45 minutes of autonomous execution.
