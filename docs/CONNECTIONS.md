# Apps and accounts

15 October 2026. Settings → **Apps & accounts** is a service-first page using MORE’s paper, cards and typography. People choose **Connect Instagram**, **Connect WhatsApp**, Gmail or another named service. Apple sources and Shortcuts have their own simple destinations. Professional Instagram/WhatsApp/Facebook accounts sit behind an explicit disclosure. **iOS native**, **Browser** and **API** remain internal execution routes for an operation; a browser session or installed app does not grant API access.

## Current activation

The connection service is live at [more-composio.more-gderamchi.workers.dev](https://more-composio.more-gderamchi.workers.dev/health), with an EU D1 database, applied migration and a server-only Composio Worker secret. The same personally signed MORE bundle was updated and launched on the physical iPhone. No Mac or local server is needed to run its API connections; this development installation still has its existing signing requirements.

| Evidence | Verified result |
| --- | --- |
| Public HTTPS | `/health` returned 200; an unauthenticated protected request returned 401 |
| Installation identity | `/v1/installations` returned 201; the same QA bearer still authenticated after redeployment, confirming its D1 identity survived |
| Enabled services | After deployment `164a0ca0-39f8-4d6b-b944-ff1b7bfa9496`, authenticated `/v1/services` returned 200 with exactly 16 services, including YouTube/Reddit and excluding unconfigured X/TikTok |
| Tool catalogs | Sixteen pinned public catalogs (1,152 tools) are installed in production. Latest YouTube and Reddit requests returned 200 with 59 and 33 normalized schemas; catalog availability does not establish account eligibility or execution rights |
| Account state | Earlier QA `/v1/connections` was empty. A subsequent complete project-metadata read at 16:11 UTC found one ACTIVE account under an enabled toolkit configuration; no identity was exposed and no provider tool was executed |
| OAuth verifier | The MORE project configuration was saved with the deployed `/v1/oauth/callback` URL; missing-session requests returned 400 and an innocuous test session redirected 302 to `more://composio/callback` |
| Physical iPhone | Signed build contains this HTTPS origin, the personal bundle and `more` scheme; install and launch returned success, and the launched process remained present |

The callback probe did not perform OAuth. No physical-phone screen was inspected, provider consent completed, native permission granted, installed shortcut verified or real provider action confirmed in these checks. The next user step is **Settings → Apps & accounts → Connect [service]**, finish the provider's consent, then inspect its active account and review a harmless read. An empty account list is expected until this happens.

Sixteen managed auth configurations are enabled: Gmail, Google Calendar, Outlook, Drive, Docs, Sheets, Notion, Slack, Calendly, Instagram Business/Creator, WhatsApp Business Cloud, LinkedIn profile/posts, Discord profile/servers, Facebook Pages, YouTube and Reddit. Real IDs remain outside shared source; scope labels and catalog pins are in [COMPOSIO-SERVICES.md](COMPOSIO-SERVICES.md). Google Contacts is excluded because managed OAuth is unavailable; Gmail contact-reading tools are a narrower alternative. Configuring a toolkit cannot expand the provider's account eligibility, scopes or production approval requirements.

## Implemented behavior

- **iOS native:** Calendar/Weather source setup and reviewed Calendar/Reminder capture. Calendar briefing requires full permission and an explicit calendar selection; event creation can use write-only permission. The native screen reads at most 50 incomplete dated reminders due in the next seven days and can complete a displayed reminder after checking freshness and changes. Undated/overdue items are excluded. Messages, Mail, Notes, Clock and Other shortcut cards run separately prepared Apple Shortcuts or add them to a routine draft. Names alone prove neither installation nor actions; a validated callback confirms return from the shortcut, not its external effect. Input/output are bounded and returned text is transient.
- **Browser:** the visible, persistent WebKit browser opens TikTok, X, Instagram, WhatsApp, YouTube Shorts and Le Monde. Reddit, personal Facebook and Threads are grouped under more websites. New sites support manual navigation and scrolling, with no invented unread/video automation. They are also routine destinations. Human browsing is distinct from MORE's calibrated unread/headline/scroll scripts. Automatic stories/likes/comments and hidden browsing are not supplied. Browser sessions are separate from Composio accounts.
- **API:** native HTTPS client, system-browser consent, server-verified account ownership/status, catalogs, schema fields, explicit action review/execution, disconnect and volatile result display. Reviewed actions can enter a routine draft. Approval and Start are separate; dispatch uses a stable request UUID. Pause/advance/reset invalidate pending work, and resume/relaunch do not automatically repeat a dispatched action.

Model proposals cannot assign executable targets. Portable routine exports/imports omit account/action authority. API and Shortcut steps use generic Lock Screen labels. The [native research inventory](NATIVE-INTEGRATIONS.md) includes future adapters and must not be read as an implemented feature list.

## Social accounts and Shortcuts

The current choice for TikTok/X scrolling is the **visible browser**, with normal personal website sign-in. MORE does not require their developer portals for this use. Reddit, Facebook and Threads also have website destinations; Reddit's separate Composio connector and Facebook's professional Pages connector remain available for API actions. More advanced API use is optional and does not provide the full consumer interface.

| Service | Composio route and boundary |
| --- | --- |
| Reddit / YouTube | Managed OAuth configurations can expose their pinned account actions after the person authorizes access. This is separate from the existing YouTube Shorts browsing route. |
| X / Twitter | Browse `x.com/home` in MORE. The optional [Composio API toolkit](https://docs.composio.dev/toolkits/twitter) remains unconfigured and is not needed for browsing. |
| TikTok | Browse `tiktok.com` in MORE. The optional [Composio API toolkit](https://docs.composio.dev/toolkits/tiktok) remains unconfigured and is not needed for browsing. |
| Facebook / Threads | Browse the personal websites in MORE. The separate configured Facebook API toolkit targets managed Pages and their professional conversations, not personal Messenger or the personal home feed. |
| Instagram | Professional account actions use Composio; the existing visible website serves personal browsing. |
| WhatsApp | Composio supports [Business Platform accounts](https://docs.composio.dev/toolkits/whatsapp), not personal accounts. Personal website access is an additional linked device. Existing sign-in to the native WhatsApp app does not grant MORE its conversations. |

The WhatsApp card explains this distinction and offers an explicit handoff to the installed app. WhatsApp documents linking the Web client by [phone number and code](https://faq.whatsapp.com/1324084875126592/?cms_platform=web) as well as QR. The iPhone's embedded browser may be restricted by WhatsApp; a successful personal association is still unverified. QR linking needs another display, so it is not represented as an autonomous single-iPhone setup.

Shortcut setup provides a guided example for each app, an exact name to copy, and separate save, test and add-to-routine actions. Testing runs the person's actual shortcut. Adding saves a routine draft and still requires review/approval/start. The guide does not install shortcuts or prove their effects. Optional input and return text stay explained separately from the first example.

## Service and operating limits

Microsoft Graph, Gmail and similar integrations are remote APIs. MORE calls its own service, which uses Composio with an explicit connected account and pinned toolkit version. The project key stays in a Worker secret; the app keeps an opaque installation bearer in Keychain. The server derives the user identity, checks ownership/configuration and exposes no arbitrary upstream proxy.

Workers uses a shared D1 installation/execution store. A unique action reservation commits before dispatch; replay uses sanitized receipt metadata, and changed arguments under the same UUID are rejected. An uncertain effect must be reconciled with the provider before another attempt; changing UUIDs does not resolve it. Approximate edge enrollment/request limits fail closed, but are not public enrollment attestation or a complete abuse-control system. Account recovery, multi-device identity, credential rotation and consumer distribution are not established.

The Cloudflare Workers plan page confirms Free ($0), with no paid upgrade applied. Public, pinned tool definitions are prepared outside the Worker and served from a separate D1 catalog table; no account content is cached there. Measured catalog CPU fell substantially, although one Outlook sample remained at 13.340 ms against the nominal 10 ms Free limit. This is not universal CPU headroom or an unlimited-service guarantee. Composio/provider charges and limits remain separate. See the [Cloudflare runbook](../Services/Composio/CLOUDFLARE.md) and [server contract](../Services/Composio/README.md).

## Privacy

API arguments/results transit the connection service, Composio and the provider. Apple inference and captured screens remain local. MORE's backend D1 journal stores hashes, IDs, execution state and sanitized receipts, never raw arguments or provider results; app results are volatile. Exact arguments become local routine/history content when the person saves an action.

**This is not an end-to-end zero-retention guarantee.** Composio's default execution logging can retain request arguments and results. Its [Zero Data Retention option](https://docs.composio.dev/docs/security/zero-data-retention) requires paid eligibility and has coverage restrictions, including Enterprise requirements for managed OAuth apps. No applicable ZDR guarantee has been established for this project. Provider and hosting policies remain separate; disabling MORE's Worker observability does not change them.

Local forgetting removes the installation credential, unresolved local receipts and saved shortcut names. It does not erase D1 metadata or revoke remote grants. Disconnect or use provider settings for those effects; define metadata retention/erasure before public release.

## Validation boundary

Backend tests cover concurrent isolates, durable reservations/metadata-only receipts, restart persistence, uncertainty, ownership/callback isolation, body limits, public catalog version matching and throttling. The Worker initializes lazily from actual request bindings and uses a native Fetch transport. Synthetic tests and public catalog reads do not establish a provider account grant.

Earlier Swift shared-logic tests, device/simulator builds and an unconfigured simulator route/draft check also passed. The latest personal device build succeeded and its app/widget signatures passed strict verification. Those results, the live catalogs, callback configuration and a running phone process do not substitute for the still-unverified OAuth and provider action journey.

## Consumer interface verification

The checkout was fast-forwarded to main `1b9c168`, preserving the local integration work. Earlier complete shared Swift suites passed: Health 4, Core 585 and Apple 666, with six optional model/media cases skipped. This includes recognition of the new MORE wording while retaining earlier recorded wording. After the guide/social-account changes, 37 targeted Swift tests in four suites passed. The backend suite now passes 26 tests, including conditional custom-toolkit activation and per-user isolation.

The French simulator interface uses real production service discovery, with no account fixture or provider consent. An unsigned simulator build could not use Keychain; the signed simulator build loaded the actual services. The hub, Gmail destination, Reminders and Shortcuts screens were inspected. Instagram and WhatsApp pages opened, and their confirmation footer was checked after reserving space for the root dock. Large-text checks covered the visible hub and native screens; the automation tool could not scroll those screens, so offscreen large-text content is not claimed as verified. Text size was restored afterward.

The consumer interface also passed the signed physical-iPhone build; app and widget signatures were verified strictly. It was installed over the same personal bundle without uninstalling, then launched with the existing process terminated and without test arguments or fixtures. This is installation/startup evidence, not a physical-screen or provider-consent check.

Account status remains based on ACTIVE responses, and browser readiness remains the person’s confirmation. Physical-phone OAuth and provider actions are still unverified.

The subsequent Shortcuts guide passed a signed simulator build and actual French UI checks: Notes guide opening/closing, suggested name and copy feedback, optional fields collapsed, large visible text wrapping and accessible Done control. The WhatsApp explanation and native-app handoff button were also inspected. After deployment, the actual YouTube and Reddit account links appeared and the YouTube service page loaded with its empty-account state. Text size was restored to its initial value.

This earlier build was installed in place on the physical iPhone, then relaunched without test arguments. The new process was confirmed present and the previous one absent. These checks did not run any shortcut, open WhatsApp or grant a provider account. The later TikTok/X browser route supersedes developer-app preparation for ordinary browsing.

## Main refresh and personal websites

The checkout was subsequently fast-forwarded to main `f59e293` (four commits), preserving the local Composio/native work and the MORE paper/navigation design. The string catalog was merged semantically, retaining both new Gmail reader text and connection translations. Gmail has an explicit native-reader entry using the same saved connection as Gmail routine moments; Composio Gmail actions sit under a separate disclosure and cannot imply that the native reader is authorized. The native reader's canonical local OAuth configuration is absent on this host; the build retains its honest configuration-unavailable state.

TikTok/X/Reddit/Facebook/Threads have exact secure URL mappings and saved-route compatibility. Their available automatic task lists stay empty. Sign-in guards now also cover TikTok Passport and X flow/onboarding URLs; credential-form guards remain in the collector. Website setup and consent do not automatically begin rhythm learning. New routine drafts can select the sites without changing already approved routines. Actual page/session behavior is a separate device check.

The main refresh passed the complete shared suite (Health 4, Core 591, Apple 702; six optional local-model/media cases skipped). After the final learned-route changes, 105 targeted cases passed (59 Core, 46 Apple), including Gmail, website guards, numeric rhythm and preservation of saved routines. Signed simulator and physical builds were checked separately from package tests.

Actual French simulator checks opened all five destinations: TikTok, Facebook and Threads displayed their cookie screens, Reddit displayed public content, and X initially stayed blank with the mobile browser profile. X's desktop Safari profile then displayed its actual French sign-in form. These pages remained inside MORE with its footer above the dock. No cookie decision, account consent, credential entry or Ready confirmation was made. The automation tool could not perform its native scroll gesture (`noWindowsAvailable`), so authenticated feed scrolling is not claimed as observed. Visible large-text layout passed and the original text size was restored.

The native Gmail reader and Composio Gmail-action destinations were both opened and distinguished. The absent native OAuth configuration is shown once after removing a duplicated error display. No Gmail account was disconnected and no mailbox content was read in this UI check.

The final signed physical-iPhone build succeeded after these changes. Strict app/widget signature, team/profile, callback-scheme and HTTPS-origin checks passed, and the app was installed over the existing personal bundle without uninstalling. The final launch was blocked by the phone locking: CoreDevice reported `FBSOpenApplicationErrorDomain` code 7. The person subsequently confirmed unlocking the phone and opening MORE manually. Inventory on the target phone found one matching MORE application, with the expected personal bundle and `MorningOperator` executable. Remote process inspection still found only its widget, and one reconciled launch after the manual-opening confirmation again returned `Locked`. This is an installed build and a user-reported opening; automated physical-device startup remains unverified. No reinstall, credential action or crash diagnosis followed from the absent main-process observation.

## Native sun design refresh

The next refresh fast-forwarded main from `f59e293` to `322f77b` (twelve commits), then restored the local integrations on `guillaume/main-design-connections-20261015`. The backup stash was retained. Main's native sun Home, navigation stack without a dock/tab bar, new bundled DM Serif Display/Raleway fonts, simplified Settings and routine controls are preserved. Apps & accounts and its native/API guides use the new typography. Active connected-action status is passed into the new Home; shortcut callbacks, validation, privacy cleanup and the existing server origin remain wired.

The string catalog merged without semantic conflicts, retaining both branches' wording. Project and app plist validation passed, as did the complete shared Swift suite: Health 4, Core 594 and Apple 702, with six optional local-model/media cases skipped. The signed simulator build succeeded. Physical build/install and actual screen checks are recorded separately below when available; these results do not establish provider sign-in or new API execution.

Actual French simulator inspection confirmed the new sun Home and Settings, with no old dock. At the largest checked text size, the visible Settings cards wrapped cleanly. The new main had labeled the entire destination scroll container, which hid its child controls from accessibility navigation. Removing that redundant label restored the Settings buttons, and Apps & accounts opened with the new typography. The original text size was restored. Review also found Home no longer displayed `store.notice`; the existing dismissible NoticeView is now presented in its bottom safe area, preserving shortcut/start failure visibility without adding a dock. Its nonempty error state has not been exercised on the physical phone.

GitHub reports the connected account has pull permission and no push permission on the original repository; its branch push returned 403. To follow the repository's new remote-backup rule, the source was saved on the same named branch in the account's public fork, [gderamchi/morning-operator](https://github.com/gderamchi/morning-operator/tree/guillaume/main-design-connections-20261015). The original `origin` remote is preserved. Keys, local deployment/signing configuration, media and private notes remain excluded. Remaining native-home device acceptance is tracked in [#167](https://github.com/gibouu/morning-operator/issues/167), with provider journeys separately tracked in [#139](https://github.com/gibouu/morning-operator/issues/139).

Final simulator and physical builds succeeded after both interface fixes. The final simulator artifact was installed without resetting its isolated store; Home → Settings → Apps & accounts and return navigation passed. TikTok's public/cookie page, X's French sign-in page and the Notes guide opened, with the website footer visible at normal and large text sizes. No account, cookie, Ready, permission or routine action was taken. The native Gmail reader and a nonempty Home notice were not retested in this last visual pass.

The final phone app was installed in place at 17:20 UTC. Strict signatures, app/widget identity and provisioning, backend origin, callback scheme and both registered font files passed verification. No launch was attempted after the preceding locked-phone refusal, so this final installation does not establish physical-screen or automatic-startup evidence. No additional unlock request was made.
