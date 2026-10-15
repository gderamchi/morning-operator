# MORE Composio connector

Small Node.js 22+ service with no runtime dependencies. It keeps the Composio project API key on the server, creates an opaque installation identity, and exposes only configured services. It invokes tools directly with an explicit account and version; there is no remote model, natural-language tool execution, generic proxy endpoint, or Composio instant-account fallback. A [Cloudflare Workers Free + D1 adapter](CLOUDFLARE.md) preserves the same mobile contract; its locked development tools are separate from the Node runtime.

**Deployed on Cloudflare Workers Free + D1 on 15 October 2026.** The live [connector](https://more-composio.more-gderamchi.workers.dev/health) serves 16 configured public tool catalogs, including YouTube and Reddit, with 1,152 tools; the deployment/runbook and CPU evidence are in [CLOUDFLARE.md](CLOUDFLARE.md). Local tests use a synthetic upstream. A completed provider OAuth flow, mailbox action and physical-iPhone journey remain unverified. The current activation status is recorded in [CONNECTIONS.md](../../docs/CONNECTIONS.md). Provider account eligibility, scopes and approval requirements still apply.

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
| `GET /v1/services` | — | `{services:[{id,name}]}` |
| `GET /v1/connections` | — | `{connections:[{id,service,name,status,accountLabel?}]}` |
| `POST /v1/connections` | `{service,callbackURL}` | `201 {id?,authorizationURL}` |
| `POST /v1/connections/complete` | `{sessionURI}` | `{id,service,status:"ACTIVE"}` |
| `DELETE /v1/connections/{id}` | — | `204`, requests provider grant revocation as well as account deletion |
| `GET /v1/tools?service=...` | — | `{tools:[{slug,name,description,inputSchema}]}` |
| `POST /v1/execute` | `{tool,arguments,connectionID,requestID}` | `{requestID,successful,data?,error?}`; `error` has `{code,message}` |

Connections are filtered both upstream and locally by owner, configured auth-config ID and toolkit. Credentials/state returned by Composio are discarded. Every execution rechecks active account ownership and tool toolkit/version before dispatch. Legacy property-map input descriptions are normalized to an object JSON Schema for the app; full argument/schema validation is performed by Composio. The local app's review/approval policy must decide whether to invoke a particular tool.

The Worker reads precomputed public catalog JSON from D1 using the configured toolkit/version pair, after installation authentication. It forwards that JSON without parsing and serializing the tool definitions again. A missing or stale pinned snapshot returns `503 catalog_unavailable`; there is no expensive provider fallback. The owner refreshes snapshots with the [catalog bootstrap](CLOUDFLARE.md#refresh-public-catalogs). These rows contain public tool descriptions and schemas, never connected accounts, execution arguments or provider results. The Node adapter still loads and normalizes the live public catalog dynamically. Execution always verifies fresh provider account/tool metadata, independently of catalog snapshots.

Deletion asks Composio to revoke upstream credentials asynchronously. A 204 here confirms the Composio deletion response, not completed provider-side revocation. A shared provider grant may affect sibling connections; provider settings remain the place to inspect final access.

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
