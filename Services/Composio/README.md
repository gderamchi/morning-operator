# MORE Composio connector

Small Node.js 22+ service with no runtime dependencies. It keeps the Composio project API key on the server, creates an opaque installation identity, and exposes only configured services. It invokes tools directly with an explicit account and version; Composio routes use no remote model, natural-language tool execution, generic proxy endpoint, or instant-account fallback. A separate optional ElevenLabs broker issues WebRTC tokens for explicitly activated installations. A [Cloudflare Workers Free + D1 adapter](CLOUDFLARE.md) preserves the same mobile contract; its locked development tools are separate from the Node runtime.

**Updated on Cloudflare Workers Free + D1 on 16 October 2026.** The live [connector](https://more-composio.more-gderamchi.workers.dev/health) serves 16 configured public tool catalogs, including YouTube and Reddit, with 1,152 tools; the deployment/runbook and CPU evidence are in [CLOUDFLARE.md](CLOUDFLARE.md). Local tests use a synthetic upstream. A completed provider OAuth flow, mailbox action and physical-iPhone journey remain unverified. The current activation status is recorded in [CONNECTIONS.md](../../docs/CONNECTIONS.md). Provider account eligibility, scopes and approval requirements still apply.

## Run

```sh
cd Services/Composio
cp .env.example .env
# Edit .env with real server configuration, then:
node --env-file=.env server.mjs
# Full Node + Worker test suite (separate terminal):
npm ci
npm test
```

`GET /health` confirms the process is running, not provider readiness. The default bind address is loopback. The Node server needs no runtime package installation; the full test suite uses the locked development dependencies.

## Configuration

| Variable | Meaning |
| --- | --- |
| `COMPOSIO_API_KEY` | Required real project secret. Never embed in the iPhone app or logs. |
| `COMPOSIO_TOOLKITS_JSON` | Object keyed by actual Composio toolkit slug. Each value requires `name`, `authConfigID` and a supported dated `version` in `YYYYMMDD_NN` form. Empty `{}` exposes no services. Obtain real values from the configured project/catalog; this repository supplies none. |
| `MORE_PUBLIC_BASE_URL` | Public HTTPS origin of this server, required before connecting. Paths/query/credentials are forbidden. |
| `MORE_AUTH_CALLBACK_URL` | Exact installed-app return URL, default `more://composio/callback`. Use `moreqa://composio/callback` for a dedicated QA deployment. |
| `MORE_CALLBACK_URLS_JSON` | Exact callback allowlist. Default includes the two native callback URLs above. A request must also match this deployment's `MORE_AUTH_CALLBACK_URL`; arbitrary client HTTPS destinations are rejected. |
| `MORE_DATA_DIR` | Persistent private directory, default `./data`, ignored by Git. Must survive restarts. |
| `COMPOSIO_TIMEOUT_MS` | Upstream deadline in milliseconds, 100–60000, default 20000. No automatic upstream retries. |
| `ELEVENLABS_API_KEY`, `ELEVENLABS_AGENT_ID` | Optional server-only private agent credentials. Missing either disables cloud voice. |
| `MORE_VOICE_INSTALLATIONS_JSON` | Explicit generated installation-ID allowlist, default `[]`. Public enrollment does not activate voice. |
| `HOST`, `PORT` | Default `127.0.0.1:8787`. Configure the host explicitly for a container/reverse proxy. |

One installation's random bearer token lives in the iPhone Keychain; only its SHA-256 hash and a generated stable Composio user ID are stored here. The client never supplies `user_id`, auth-config IDs, versions, API keys, arbitrary upstream URLs, or provider credentials. Losing the installation token loses access to its server identity; account recovery and multi-device identity are not implemented.

Custom OAuth toolkits use the same explicit map. X (`twitter`) and TikTok (`tiktok`) currently require MORE's own provider developer credentials and auth configs; neither is enabled by a placeholder or an empty config. The pinned versions, exact required fields and provider approval/billing constraints are recorded in [COMPOSIO-SERVICES.md](../../docs/COMPOSIO-SERVICES.md). Adding a catalog or auth config never establishes a user grant.

## OAuth setup is required

1. Configure each real auth config/toolkit in the Composio project and set the environment map.
2. **Enable Composio project callback identity verification** in Dashboard → Settings → General → Configuration. Set the verifier URL to `https://YOUR_DEPLOYED_ORIGIN/v1/oauth/callback` (with your real origin).
3. The app calls `POST /v1/connections` with its installation bearer, a configured service and its exact native callback URL, then opens `authorizationURL` with `ASWebAuthenticationSession`.
4. After provider consent, Composio redirects to this server's verifier with an opaque `session_uri`. This server forwards it to the configured native callback. The redirect alone does not complete authorization.
5. The app extracts `session_uri` and calls **`POST /v1/connections/complete` with its Keychain bearer** and `{ "sessionURI": "..." }`. The server redeems it with the authenticated installation's user ID, then verifies the returned account is active and owned by that same user/configuration.
6. The app reloads its connection list. Composio's completion URI is single-use; on ambiguous completion reload accounts, and start a new connection if needed rather than retrying the URI.

The authenticated completion step prevents a forwarded OAuth link from silently binding another person's account to the initiator's installation. A browser cookie or the authorization link itself does not independently prove identity. This service cannot inspect your project's dashboard setting: enabling the verifier correctly is a deployment requirement. If the project leaves it off, the upstream OAuth account may activate before verification; do not release that configuration.

## Mobile REST contract

All `/v1` routes except installation creation and the browser verifier require `Authorization: Bearer <installation token>`. JSON request bodies are limited to 256 KiB. Errors use `{ "error": { "code": "...", "message": "..." } }`; private upstream error bodies and account credentials are never forwarded.

| Method/path | Request | Response |
| --- | --- | --- |
| `POST /v1/installations` | `{}` | `201 {token}` |
| `POST /v1/voice/token` | `{}` | `200 {conversationToken}` for an activated installation; otherwise `503 voice_not_configured` |
| `POST /v1/voice/speech` | `{text,language:"fr"\|"en",voiceGender:"male"\|"female"}` | `200 audio/mpeg` for the same activated installation; otherwise sanitized JSON error |
| `GET /v1/services` | — | `{services:[{id,name}]}` |
| `GET /v1/connections` | — | `{connections:[{id,service,name,status,accountLabel?}]}` |
| `POST /v1/connections` | `{service,callbackURL}` | `201 {id?,authorizationURL}` |
| `POST /v1/connections/complete` | `{sessionURI}` | `{id,service,status:"ACTIVE"}` |
| `DELETE /v1/connections/{id}` | — | `204`, requests provider grant revocation as well as account deletion |
| `GET /v1/tools?service=...` | — | `{tools:[{slug,name,description,inputSchema}]}` |
| `POST /v1/execute` | `{tool,arguments,connectionID,requestID}` | `{requestID,successful,data?,error?}`; `error` has `{code,message}` |
| `GET /v1/slack/reply-identity?connectionID=...` | — | `{protocolVersion:1,connectionID,revision,teamID,userID,botID?,teamName,userName}` |
| `POST /v1/slack/replies` | `{connectionID,requestID,expectedIdentity:{revision,teamID,userID,botID?},channelID,threadTS,body}` | `{requestID,successful:true,data}` only with an exact Slack reply receipt; metadata-only replay as below |

Connections are filtered both upstream and locally by owner, configured auth-config ID and toolkit. Credentials/state returned by Composio are discarded. Every execution rechecks active account ownership and tool toolkit/version before dispatch. Legacy property-map input descriptions are normalized to an object JSON Schema for the app; full argument/schema validation is performed by Composio. The local app's review/approval policy must decide whether to invoke a particular tool.

The Worker reads precomputed public catalog JSON from D1 using the configured toolkit/version pair, after installation authentication. It forwards that JSON without parsing and serializing the tool definitions again. A missing or stale pinned snapshot returns `503 catalog_unavailable`; there is no expensive provider fallback. The owner refreshes snapshots with the [catalog bootstrap](CLOUDFLARE.md#refresh-public-catalogs). These rows contain public tool descriptions and schemas, never connected accounts, execution arguments or provider results. The Node adapter still loads and normalizes the live public catalog dynamically. Execution always verifies fresh provider account/tool metadata, independently of catalog snapshots.

Deletion asks Composio to revoke upstream credentials asynchronously. A 204 here confirms the Composio deletion response, not completed provider-side revocation. A shared provider grant may affect sibling connections; provider settings remain the place to inspect final access.

### Contextual Slack replies

The dedicated reply route uses this same handler in Node and the Cloudflare Worker. It is implemented and tested locally; deploying it and proving a real account/receipt are separate checks. Contextual replies never fall back to generic execution if this protocol is unavailable. Existing reads and previously reviewed generic actions retain their contract.

The identity checks are a preflight, **not an atomic credential lease or compare-and-swap at Composio**. Composio resolves provider credentials during execution; MORE trusts its token custody and project administrators. A project-key holder can update credentials or execute tools outside MORE. MORE exposes no credential-update or same-account reauthentication endpoint: its connection routes create an auth-link session, redeem its user-bound completion URI, or delete an owned connection. Composio describes the auth-link result as a newly created account ([hosted authentication](https://docs.composio.dev/docs/tools-direct/authenticating-tools#redirecting-users-after-authentication)); ordinary `link()` refuses another active account for the same user/auth configuration without `allowMultiple`, which MORE does not request ([account lifecycle](https://docs.composio.dev/docs/auth-configuration/connected-accounts)). No ordinary MORE route that swaps the subject of an active account under the same ID has been demonstrated. A future such route must invalidate the reviewed reply before it can be enabled; the final receipt check alone cannot prevent an effect under replaced credentials.

Identity comes from pinned `SLACK_TEST_AUTH` ([Slack contract](https://docs.slack.dev/reference/methods/auth.test/)), not the account alias. The opaque SHA-256 `revision` includes the documented account ID, owner, auth configuration, toolkit, active/disabled state, `created_at` and `updated_at` ([Composio account schema](https://docs.composio.dev/reference/v3/api-reference/connected-accounts/getConnectedAccountsByNanoid)). Missing or invalid timestamps refuse this capability. Both the read and send handler check current ownership and active grant metadata around `auth.test`; the send handler compares the reviewed revision/team/user/bot and checks account metadata again immediately before provider dispatch. A mismatch returns `slack_identity_changed`; missing identity or metadata returns `slack_identity_unavailable`. These are explicit refusals before any send. The client must still pin the source channel/thread/message and revalidate it before review and sending.

Only named-channel IDs (`C…`/`G…`), string thread timestamps, a UUID request ID and bounded plain text are accepted. The server constructs one `section`/`plain_text` block with `emoji:false` and `block_id:more-reply-v1-<lowercase request UUID>`, plus exact `fallback_text`, disabled unfurls and `reply_broadcast:false`. It accepts no caller-supplied blocks or extra tool arguments and rejects Slack entity/mention tokens. An exact echoed account actor, channel, thread, timestamp, marker and body are required before success. The marker supports receipt verification; a [section block ID](https://docs.slack.dev/reference/block-kit/blocks/section-block/) is **not** a Slack idempotency key.

The send fingerprint includes the expected identity, destination and exact body. The same atomic reservation and content-free journal described below apply to this route, including D1 across Worker isolates. A timeout, inner Slack failure, mismatched echo or lost durable receipt after dispatch stays `execution_uncertain` and is never retried automatically. There is no reconciliation endpoint in this slice. The local tests exercise the real Worker router and D1 with intercepted synthetic upstream calls; they do not establish Slack account access or a live post.

## Optional cloud conversation

The voice route requests an [ElevenLabs WebRTC session token](https://elevenlabs.io/docs/eleven-agents/api-reference/conversations/get-webrtc-token) for one server-configured private agent. It does not use the WebSocket signed-URL endpoint. The app receives only `conversationToken`; the API key, agent configuration and provider conversation ID stay out of the response. The broker sends no source text, Health samples or audio. A separate app session can send microphone audio and selected spoken context to ElevenLabs and its configured model only after the app's per-session cloud consent. Connecting Health alone does not grant that consent.

A configured deployment records a refused authenticated request as the generated installation ID and last request time only (`voice_activation_requests` in D1; `voice-activation` metadata files in Node). Invalid bodies and unauthenticated requests create no activation request. A request is not an entitlement or automatic approval: an operator must verify the intended installation through a trusted owner channel before adding its ID to the private allowlist. Public enrollment, catalog access and a database row alone never authorize a paid conversation. Receipt-backed subscription enforcement and identity recovery are not implemented by this broker.

The provider request has a ten-second deadline, a 64 KiB response bound and no retry. Redirects are refused with Fetch `manual` and a status check; Cloudflare does not support `redirect: "error"`. Provider errors become a generic `502 voice_unavailable`, without private response bodies. Token responses are `no-store`; do not log their contents. The deployment and activation runbook is in [CLOUDFLARE.md](CLOUDFLARE.md#activate-cloud-conversation).

## Bounded text-to-speech

`/v1/voice/speech` sends only selected text to ElevenLabs TTS, without a microphone, conversation or tool execution. It uses the same private activation allowlist as the token broker. Unknown JSON fields and query parameters are refused. Text must be nonempty and at most 32,768 UTF-8 bytes; language and gender are closed enums. The server selects public premade Roger/Sarah voice IDs and `eleven_turbo_v2_5`; callers cannot supply an arbitrary voice, model or provider URL.

The provider call sets `language_code`, `output_format=mp3_44100_128` and `enable_logging=false`. It refuses redirects, has one total 20-second deadline including the body stream, and accepts at most 8 MiB of MPEG audio. No request is retried with logging enabled. A provider failure becomes `502 speech_unavailable`; successful audio and JSON errors are `no-store`. Text and audio are never persisted or logged by this route. An explicit repeat synthesizes another audio response and may incur another provider charge; it never reserves or dispatches a business effect. Provider metadata and configuration checks are recorded in [NATURAL-VOICE.md](../../docs/NATURAL-VOICE.md#provider-configuration-contract).

## Replay and uncertainty

`requestID` must be a UUID retained by the client for the same reviewed action. Before any effect, an exclusive file creation (Node) or unique D1 insertion (Worker) reserves `(userID, requestID)` durably. Concurrent duplicates cannot dispatch twice. A SHA-256 fingerprint detects a changed tool/account/arguments with the same ID. Receipt metadata is atomically saved before responding and replayed after restart. Provider `data` is returned only on the original response and never written to the journal; a replay adds `resultAvailable:false` and omits `data`. Re-read the provider through a separate reviewed read action when results are needed again.

Once dispatch starts, a timeout, transport error, oversized/malformed reply or lost durable acknowledgement produces `409 execution_uncertain`. Same-ID retries remain blocked. An in-progress call produces `409 execution_pending`; changed payload produces `409 request_mismatch`. **A new UUID must never be used merely to bypass uncertainty.** Reconcile the actual provider effect and let the person review any subsequent attempt. There is no automated reconciliation/reset endpoint or exactly-once guarantee at the external provider.

The journal retains only generated user/request IDs, argument fingerprints, execution state and sanitized receipt/error metadata. Provider results and raw arguments are transient. Disconnecting does not delete deduplication metadata; forgetting the iPhone's token does not erase server installation/journal metadata or revoke grants. Define metadata retention/erasure with the product before public release. For the Node filesystem adapter, use an encrypted, access-controlled persistent volume; files are mode 0600 and new directories 0700, and existing directory permissions are the operator's responsibility. Run that adapter as one service with one durable filesystem. The Cloudflare adapter uses one shared D1 database and atomic unique reservations across Worker instances. Keep runtime data outside version control. Deleting the journal or replacing/restoring its storage can lose duplicate protection.

## Deployment requirements and limits

- For the Node adapter, terminate HTTPS at a trusted reverse proxy. Disable request/response-body, Authorization-header and query-string logging, including for `session_uri`. The service itself logs only startup/address and configuration errors. The Worker uses HTTPS directly and keeps observability/preview URLs disabled.
- The Worker has native enrollment/API rate-limit bindings; these counters are approximate per location and do not replace the D1 execution reservation. The Node adapter needs external edge limits. App Attest, identity rotation/revocation, user accounts and comprehensive abuse controls are not implemented here.
- Preserve the data volume and configure backups/access/retention appropriate to private account metadata. Use a dedicated Composio project with the least project API-key permissions needed.
- Check actual auth-config scopes, toolkit versions, provider eligibility and callback identity verification with a harmless end-to-end connection before release. Do not treat the local mock tests as that evidence.
- Real operator configuration is separate from source implementation and synthetic tests. Never equate auth-config creation or live catalog reads with a user OAuth grant or external tool action; record that evidence separately.

## Upstream contract checked 15 October 2026

The service uses [Composio v3.1](https://docs.composio.dev/reference/changelog), explicit connected accounts and pinned tool versions. The old managed-OAuth create endpoint was retired in 2026; [auth-link sessions](https://docs.composio.dev/reference/api-reference/connected-accounts/postConnectedAccountsLink) provide the hosted authorization URL instead.

- [Account listing](https://docs.composio.dev/reference/api-reference/connected-accounts/getConnectedAccounts), [account details](https://docs.composio.dev/reference/api-reference/connected-accounts/getConnectedAccountsByNanoid), [deletion/revocation option](https://docs.composio.dev/reference/api-reference/connected-accounts/deleteConnectedAccountsByNanoid).
- [Callback identity verification](https://docs.composio.dev/reference/api-reference/connected-accounts) and [authenticated completion](https://docs.composio.dev/reference/api-reference/connected-accounts/postConnectedAccountsCompleteAuth).
- [Tool catalog and version parameter](https://docs.composio.dev/reference/api-reference/tools/getTools), [individual tool metadata](https://docs.composio.dev/reference/api-reference/tools/getToolsByToolSlug), [structured execution](https://docs.composio.dev/reference/api-reference/tools/postToolsExecuteByToolSlug).
