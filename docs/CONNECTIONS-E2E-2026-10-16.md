# Connection acceptance — 16 October 2026

This ledger distinguishes the live MORE backend, provider access and the ordinary
iPhone journey. A successful catalog or consent-link response is not a completed
user connection. No private account content, bearer, authorization URL, provider
identifier or credentials are included here.

## Live API checkpoint

The deployed origin is `https://more-composio.more-gderamchi.workers.dev`.
The existing isolated QA installation authenticated successfully: `/health`,
`/v1/services` and `/v1/connections` returned HTTP 200. Its connection list was
empty. This bearer is separate from any ordinary iPhone installation.

All 16 deployed catalogs returned HTTP 200. Their 1,152 tool definitions each
contained a tool slug and normalized object input schema. This checks catalog
availability and basic schema shape, not all semantic arguments or provider
operations.

| Service | Catalog tools | ACTIVE accounts in the actual MORE project |
| --- | ---: | ---: |
| Gmail | 61 | 1 |
| Google Calendar | 47 | 0 |
| Outlook | 306 | 0 |
| Google Drive | 92 | 0 |
| Google Docs | 46 | 0 |
| Google Sheets | 50 | 0 |
| Notion | 57 | 0 |
| Slack | 161 | 0 |
| Calendly | 53 | 0 |
| Instagram | 32 | 0 |
| WhatsApp | 58 | 0 |
| LinkedIn | 25 | 0 |
| Discord | 23 | 0 |
| Facebook | 49 | 0 |
| YouTube | 59 | 0 |
| Reddit | 33 | 0 |

These counts came from complete, unpaginated-final project account and auth-config
responses. All 16 exact configured auth configurations existed, were ENABLED and
used managed OAuth2. No account belonging to an unrelated chat connector was
used as evidence.

### Actual Gmail provider read

The single active Gmail account belonged to a generated MORE installation
identity, but not the locally recoverable isolated QA bearer. Without changing
ownership or server storage, an explicitly account-bound, version-pinned
`GMAIL_GET_PROFILE` was executed using the actual MORE project API key.
HTTP 200, `successful:true`, an email-address field containing `@` and a numeric
message-count field were verified in memory. The address and counts were not printed or
retained in this report. No mailbox messages were read and no email was sent in
this initial profile-only checkpoint. The subsequent self-send is recorded below.

A subsequent read-only, parameterized production D1 query found exactly one
installation row for that account's existing owner. The account is therefore
associated with an installation in the current deployed database; its private
bearer was not recovered or replaced by this test.

This establishes actual Gmail provider access under the MORE project. It does
**not** establish execution through an authenticated MORE installation, completion
of the app's OAuth callback, a spoken operation or a physical iPhone journey.

### Actual Gmail self-send and readback

One administrator-level provider test was explicitly authorized using the actual
MORE project's existing active Gmail account. The current pinned schemas for
profile, send, search and message reading were fetched and inspected first.
A fresh profile supplied the only permitted recipient: that same connected
account. A random UUID identified the one local test record and the unique
`MORE-QA-COMPOSIO-20261016-…` subject; the fixed test body contained no private data.
The send payload set From and To to that exact profile address, supplied empty
CC/BCC/additional-recipient arrays, and included no attachment.

| Check | Live result |
| --- | --- |
| Unique-marker search before sending | HTTP 200; zero matching messages; no further page |
| Single send dispatch | HTTP 200; `successful:true`; provider message ID and SENT label present |
| Fresh unique-marker search | HTTP 200; exactly one matching message; no further page |
| Full readback of that provider message | HTTP 200; exact subject/body, From=self, To=only self, no CC/BCC/attachments, SENT label and send-receipt ID match |

There was exactly **one send dispatch**, no retry and no deletion or trash action.
The private local ledger was reserved exclusively before preparation and retained
the request UUID, address, body, provider identifiers and results outside Git in a
mode-0600 file. Composio's direct execution contract exposes no request-id or
idempotency field; this UUID identifies the local test, not provider deduplication.
Any uncertain response would require read-only reconciliation before another
action. [Direct execution contract](https://docs.composio.dev/reference/api-reference/tools/postToolsExecuteByToolSlug).

This is a verified **provider administrator self-send** through the actual MORE
project. It bypasses the app installation bearer and MORE's execution journal,
so it does not certify the ordinary iPhone, spoken send, native Gmail route or
user-bound Worker send journey.

A separate request to the ordinary deployed Worker attempted only
`GMAIL_GET_PROFILE` for this account with the unrelated isolated QA installation's
valid bearer. It returned **HTTP 404 `connection_not_found`**, correctly refusing
cross-installation ownership. No database identity or account ownership was
modified to bypass that boundary.

### Consent initiation for the 15 missing providers

A fresh isolated QA installation was created through the ordinary deployed
`POST /v1/installations` route, returning HTTP 201. It authenticated normally.
For each service other than Gmail, `POST /v1/connections` with this deployment's
exact native callback returned HTTP 201 and an HTTPS authorization link.
The authenticated connection list then contained 15 `INITIALIZING` accounts,
and zero `ACTIVE` accounts. Those are unfinished consent sessions, not grants.
An authenticated read roughly sixteen minutes later returned 15 `EXPIRED`
accounts and still zero active grants. The prepared authorization links are
therefore expired and must not be presented as currently usable.

No provider consent page was opened, grant completed, scope expanded or account
ownership changed during this checkpoint. The test installation's private bearer
and short-lived links remain outside Git. A consent initiated for this test
identity cannot be completed with a different iPhone installation's Keychain
bearer. For app acceptance, start each connection inside the ordinary app and
finish its same-installation authenticated completion.

## Remaining live gates

- Recover the legitimate owning installation journey for the existing Composio
  Gmail account, or initiate a fresh Gmail grant from the actual ordinary app.
  Never rewrite account ownership or D1 identity to make a test pass.
- Complete the intended user's OAuth grant for each of the other 15 services.
  Google/Slack/Microsoft/Notion workspace policies and professional Meta account
  eligibility still constrain the available accounts and scopes.
- Execute a useful bounded read against every granted account and compare the
  real result to the app's presentation. For writes, use a uniquely identified,
  self-owned QA artifact with provider readback and stable request identity.
- Verify the ordinary app's native, browser and spoken journeys separately.
  Project API reads and synthetic test receipts cannot close those gates.

The operator's authorization to pay for API calls does not supply missing user
OAuth grants or eligible provider accounts. No paid plan, subscription, provider
developer application or billing setting was changed by this API checkpoint.

## Ordinary physical iPhone checkpoint

The current app and UI-test runner compiled and signed successfully for the
physical iPhone. The ordinary `com.gibouu.morningoperator` application was installed
without uninstalling or resetting data. Its signed HealthKit, WeatherKit, Family
Controls and App and Website Usage entitlements were checked, together with its
configured Google client and deployed backend origin. This verifies build and
configuration, not the individual services' runtime permission or data access.

The new physical-only `OrdinaryConnectionsAcceptanceTests` requires the explicit
runner opt-in `MORE_PHYSICAL_CONNECTIONS_ACCEPTANCE=1`. It terminates and launches
the ordinary app with empty app arguments and environment, without a test
workspace, StoreKit fixture or injected subscription. The launch guard was also
reviewed independently. Simulator and ordinary CI runs skip this opt-in suite.

Two actual phone runs reached the normal subscription screen. In the final
fresh-launch run, the configured StoreKit offer still did not expose
`paywall.price` after 45 seconds; the app's accessibility state displayed the
App Store unavailable notice and its Try again control. The result was **one
failed live-offer check and one skipped native Gmail check**, not a passing
physical acceptance run. The first run had the same outcome. A screenshot from
the first run captured an unrelated system permission overlay and is not used
as paywall evidence; the ordinary app's accessibility hierarchy establishes the
observed state.

No purchase, restore, subscription bypass or permission grant was performed.
The paywall prevented access to the normal connections screen, so current-build
native Gmail, Calendar, Reminders, Health, Weather, browser and spoken execution
remain unverified. Earlier physical results in the individual service reports
remain dated evidence and do not replace this checkpoint.

App Store Connect's apps page redirected to a signed-out login form. Existing
local credentials did not establish API access, so the owner must sign into the
Apple team to inspect the actual product and sandbox setup. The observed failure
does not by itself establish whether the cause is product configuration, account
state or Apple availability. [Issue #191](https://github.com/gibouu/morning-operator/issues/191)
tracks that live release gate. No Apple account, agreement or billing settings
were changed.

## Synthetic backend regression

[#196](https://github.com/gibouu/morning-operator/issues/196) was traced to the
test fixture's shared 100 ms provider deadline. The two successful cross-isolate
checks hold the first provider response until a second Worker/D1 request finishes;
that coordination can exceed 100 ms. Holding the response for 150 ms with the old
deadline reproduced both failures exactly: the original Gmail and Slack requests
returned HTTP 409 `execution_uncertain` instead of HTTP 200. This was correct
timeout handling under an incorrectly short success-test deadline.

[Commit 12d8768](https://github.com/gibouu/morning-operator/commit/12d8768) gives
ordinary success fixtures 2,000 ms, keeps explicit 100 ms deadlines in both
deliberate timeout cases, and retains the 150 ms overlap in the concurrent tests.
Production deadlines, duplicate-dispatch guards and durable receipt assertions
were not changed.

On Node 25.6.1 after `npm ci --ignore-scripts --no-audit --no-fund`, the four
affected Worker checks passed **4/4**. The final complete `npm test` passed
**38/38**, with zero failures or skips, in 58.60 seconds under concurrent Mac load.
Every upstream request in these checks was intercepted by a synthetic provider;
they prove Worker/D1 timeout, concurrency and receipt behavior, not real account
access, provider effects or the ordinary iPhone journey.
