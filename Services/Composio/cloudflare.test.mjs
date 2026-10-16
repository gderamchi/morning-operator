import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash, randomUUID } from 'node:crypto';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Miniflare, NoOpLog, Response as MiniflareResponse, convertV4MiniflareOptions } from 'miniflare';
import { D1Storage } from './cloudflare/storage.mjs';

const root = dirname(fileURLToPath(import.meta.url));
const hash = value => createHash('sha256').update(value).digest('hex');
const callbacks = ['more://composio/callback', 'moreqa://composio/callback'];
const toolkits = {
  gmail: { authConfigID: 'ac_synthetic_gmail', name: 'Gmail', version: '20261001_00' },
  github: { authConfigID: 'ac_synthetic_github', name: 'GitHub', version: '20261001_00' },
};

// Every outbound request is intercepted. These tests exercise workerd, the actual
// native Fetch router and D1 SQL, with synthetic provider accounts and effects only.
async function fixture(t, { enrollmentLimit = 100, limiters = true, withDatabase = true, slack = false, voice = false, voiceInstallations = [] } = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'more-worker-test-'));
  const configured = { ...toolkits, ...(slack ? { slack: { authConfigID: 'ac_synthetic_slack', name: 'Slack', version: '20261014_00' } } : {}) };
  const state = { accounts: new Map(), calls: [], executions: 0, mode: 'success', executionGate: null, executionStarted: null,
    slackSends: 0, slackAuth: { ok: true, team_id: 'T12345678', user_id: 'U12345678', bot_id: 'B12345678', team: 'Synthetic team', user: 'synthetic-user' }, changeSlackOnSendMetadata: false };
  const json = (status, data) => new MiniflareResponse(JSON.stringify(data), { status, headers: { 'Content-Type': 'application/json' } });
  const tool = { slug: 'GMAIL_SEND_EMAIL', toolkit: { slug: 'gmail' }, name: 'Send email', description: 'Synthetic email action', version: '20261001_00', input_parameters: { recipient: { type: 'string', required: true } } };
  async function upstream(request) {
    const url = new URL(request.url);
    if (url.origin === 'https://api.elevenlabs.io') {
      assert.equal(url.pathname, '/v1/convai/conversation/token');
      assert.equal(url.searchParams.get('agent_id'), 'synthetic-agent');
      assert.equal(request.headers.get('xi-api-key'), 'synthetic-voice-key');
      assert.equal(request.method, 'GET');
      state.calls.push({ method: request.method, url });
      return json(200, { token: 'synthetic-webrtc-token', conversation_id: 'private-provider-session' });
    }
    assert.equal(url.origin, 'https://backend.composio.dev');
    assert.equal(request.headers.get('x-api-key'), 'synthetic-worker-key');
    const raw = await request.text();
    const input = raw ? JSON.parse(raw) : undefined;
    state.calls.push({ method: request.method, url, input });
    if (url.pathname === '/api/v3.1/connected_accounts/link') return json(201, { connected_account_id: 'ca_new', redirect_url: 'https://connect.composio.dev/auth/synthetic' });
    if (url.pathname === '/api/v3.1/connected_accounts/complete_auth') {
      if (input.session_uri !== `session-${input.user_id}`) return json(400, { error: 'private-auth-detail-must-not-escape' });
      const account = [...state.accounts.values()].find(item => item.user_id === input.user_id);
      return json(200, { connected_account_id: account.id, toolkit_slug: account.toolkit.slug });
    }
    if (url.pathname === '/api/v3.1/connected_accounts') return json(200, { items: [...state.accounts.values()], next_cursor: null });
    if (url.pathname.startsWith('/api/v3.1/connected_accounts/')) {
      const id = url.pathname.split('/').at(-1);
      const account = state.accounts.get(id);
      if (!account) return json(404, {});
      if (request.method === 'DELETE') { state.accounts.delete(id); return json(200, { success: true }); }
      return json(200, account);
    }
    if (url.pathname === '/api/v3.1/tools') return state.redirectCatalog ? new MiniflareResponse(null, { status: 302, headers: { Location: 'https://untrusted.example/collect' } }) : json(200, { items: [tool], next_cursor: null });
    if (url.pathname === '/api/v3.1/tools/GMAIL_SEND_EMAIL') return json(200, tool);
    if (['/api/v3.1/tools/SLACK_TEST_AUTH', '/api/v3.1/tools/SLACK_SEND_MESSAGE'].includes(url.pathname)) {
      if (url.pathname.endsWith('SLACK_SEND_MESSAGE') && state.changeSlackOnSendMetadata) {
        [...state.accounts.values()].find(account => account.toolkit.slug === 'slack').updated_at = '2026-10-15T10:01:00.000Z';
      }
      return json(200, { ...tool, slug: url.pathname.split('/').at(-1), toolkit: { slug: 'slack' }, version: configured.slack.version });
    }
    if (url.pathname === '/api/v3.1/tools/execute/SLACK_TEST_AUTH') return json(200, { successful: true, data: state.slackAuth });
    if (url.pathname === '/api/v3.1/tools/execute/SLACK_SEND_MESSAGE') {
      state.executions++; state.slackSends++; state.executionStarted?.resolve();
      if (state.executionGate) await state.executionGate.promise;
      if (state.mode === 'timeout') await new Promise(resolve => setTimeout(resolve, 2000));
      const args = input.arguments, ts = '1792058400.000123';
      return json(200, { successful: true, data: { ok: true, channel: args.channel, ts, message: { ts,
        user: state.slackAuth.user_id, bot_id: state.slackAuth.bot_id, thread_ts: args.thread_ts,
        blocks: state.mode === 'wrongMarker' ? [{ ...args.blocks[0], block_id: 'unrelated-block' }] : args.blocks } } });
    }
    if (url.pathname.startsWith('/api/v3.1/tools/execute/')) {
      state.executions++;
      state.executionStarted?.resolve();
      if (state.executionGate) await state.executionGate.promise;
      if (state.mode === 'timeout') await new Promise(resolve => setTimeout(resolve, 2000));
      return json(200, state.mode === 'malformed' ? { data: 'unverified-result' } : { successful: true, data: { status: 'queued', privateResult: 'private-provider-result-sentinel' } });
    }
    assert.fail(`Unexpected synthetic upstream path: ${url.pathname}`);
  }
  function options() {
    const workers = ['primary', 'secondary'].map(name => ({
      name,
      modulesRoot: root,
      modules: ['cloudflare/worker.mjs', 'server.mjs', 'morning-voice.mjs', 'cloudflare/storage.mjs'].map(path => ({ type: 'ESModule', path: join(root, path) })),
      compatibilityDate: '2026-10-15',
      compatibilityFlags: ['nodejs_compat', 'enable_nodejs_http_server_modules'],
      bindings: { COMPOSIO_API_KEY: 'synthetic-worker-key', COMPOSIO_TOOLKITS_JSON: JSON.stringify(configured), MORE_PUBLIC_BASE_URL: 'https://connector.example', MORE_AUTH_CALLBACK_URL: callbacks[0], MORE_CALLBACK_URLS_JSON: JSON.stringify(callbacks),
        // Reach the intended post-dispatch deadline even on a loaded development machine.
        COMPOSIO_TIMEOUT_MS: '1000', ...(voice ? { ELEVENLABS_API_KEY: 'synthetic-voice-key', ELEVENLABS_AGENT_ID: 'synthetic-agent', MORE_VOICE_INSTALLATIONS_JSON: JSON.stringify(voiceInstallations) } : {}) },
      ...(withDatabase ? { d1Databases: { DB: 'synthetic-shared-database' } } : {}),
      ...(limiters ? { ratelimits: {
        ENROLLMENT_LIMITER: { namespace_id: '1001', simple: { limit: enrollmentLimit, period: 60 } },
        REQUEST_LIMITER: { namespace_id: '1002', simple: { limit: 1000, period: 60 } },
      } } : {}),
      outboundService: async request => {
        try { return await upstream(request); }
        catch (error) { state.mockError = String(error); throw error; }
      },
    }));
    return convertV4MiniflareOptions({ workers, resourcePersistencePath: directory, log: new NoOpLog(), telemetry: { enabled: false } });
  }
  let runtime = new Miniflare(options());
  t.after(async () => { state.executionGate?.resolve(); await runtime.dispose(); await rm(directory, { recursive: true, force: true }); });
  const database = async (worker = 'primary') => runtime.getD1Database('DB', worker);
  if (withDatabase) {
    const db = await database();
    for (const name of ['0001_storage.sql', '0002_public_catalogs.sql', '0003_voice_activation.sql']) {
      const migration = await readFile(join(root, 'cloudflare/migrations', name), 'utf8');
      await db.batch(migration.split(';').map(sql => sql.trim()).filter(Boolean).map(sql => db.prepare(sql)));
    }
    const catalog = { tools: [{ slug: tool.slug, name: tool.name, description: tool.description, inputSchema: { type: 'object', properties: { recipient: { type: 'string' } }, required: ['recipient'] } }] };
    await db.prepare('INSERT INTO public_catalogs VALUES (?, ?, ?)').bind('gmail', toolkits.gmail.version, JSON.stringify(catalog)).run();
  }
  async function api(path, { method = 'GET', bearer, data, headers = {}, worker = 'primary' } = {}) {
    const target = await runtime.getWorker(worker);
    const response = await target.fetch(`https://connector.example${path}`, { method, redirect: 'manual', headers: { ...(bearer ? { Authorization: `Bearer ${bearer}` } : {}), ...(data === undefined ? {} : { 'Content-Type': 'application/json' }), ...headers }, body: data === undefined ? undefined : JSON.stringify(data) });
    const raw = await response.text();
    return { status: response.status, headers: response.headers, data: raw ? JSON.parse(raw) : null, raw };
  }
  async function install() {
    const result = await api('/v1/installations', { method: 'POST', data: {} });
    assert.equal(result.status, 201);
    return result.data.token;
  }
  async function addAccount(bearer, id = 'ca_mine', service = 'gmail') {
    const link = await api('/v1/connections', { method: 'POST', bearer, data: { service, callbackURL: callbacks[0] } });
    assert.equal(link.status, 201, JSON.stringify({ response: link.data, calls: state.calls, mockError: state.mockError }));
    const call = state.calls.findLast(item => item.url.pathname.endsWith('/link'));
    const account = { id, toolkit: { slug: service }, auth_config: { id: configured[service].authConfigID }, status: 'ACTIVE', user_id: call.input.user_id, alias: 'Synthetic account', state: { access_token: 'private-provider-token-sentinel' },
      ...(service === 'slack' ? { created_at: '2026-10-14T10:00:00.000Z', updated_at: '2026-10-15T10:00:00.000Z' } : {}) };
    state.accounts.set(id, account);
    return account;
  }
  const rows = async table => (await (await database()).prepare(`SELECT * FROM ${table}`).all()).results;
  return { api, install, addAccount, database, rows, state, ready: async () => runtime.ready, restart: async () => { await runtime.dispose(); runtime = new Miniflare(options()); await runtime.ready; } };
}

test('Worker voice refuses unapproved installations and persists only D1 activation metadata without provider calls', async t => {
  const f = await fixture(t, { voice: true });
  assert.equal((await f.api('/v1/voice/token', { method: 'POST', data: {} })).status, 401);
  assert.deepEqual(await f.rows('voice_activation_requests'), []);
  const bearer = await f.install();
  assert.equal((await f.api('/v1/voice/token', { method: 'POST', bearer, data: { agent_id: 'client-selected' } })).status, 400);
  assert.deepEqual(await f.rows('voice_activation_requests'), []);
  for (const worker of ['primary', 'secondary']) {
    const refused = await f.api('/v1/voice/token', { method: 'POST', bearer, data: {}, worker });
    assert.equal(refused.status, 503);
    assert.equal(refused.data.error.code, 'voice_not_configured');
    assert.equal(refused.headers.get('cache-control'), 'no-store');
  }
  const rows = await f.rows('voice_activation_requests');
  assert.equal(rows.length, 1);
  assert.deepEqual(Object.keys(rows[0]).sort(), ['requested_at', 'user_id']);
  const installation = await (await f.database()).prepare('SELECT user_id FROM installations WHERE token_hash = ?').bind(hash(bearer)).first();
  assert.equal(rows[0].user_id, installation.user_id);
  assert.ok(Number.isFinite(Date.parse(rows[0].requested_at)));
  assert.ok(!JSON.stringify(rows).includes(bearer) && !JSON.stringify(rows).includes('synthetic-voice-key'));
  await f.restart();
  assert.equal((await f.rows('voice_activation_requests')).length, 1);
  assert.equal(f.state.calls.length, 0);
  assert.equal(f.state.mockError, undefined);
});

test('Worker returns only a WebRTC token for an explicitly activated installation', async t => {
  const userID = 'more_00000000-0000-0000-0000-000000000001';
  const f = await fixture(t, { voice: true, voiceInstallations: [userID] });
  const bearer = 'a'.repeat(43);
  await new D1Storage(await f.database()).createInstallation(hash(bearer), userID);
  const result = await f.api('/v1/voice/token', { method: 'POST', bearer, data: {} });
  assert.equal(result.status, 200, JSON.stringify({ response: result.data, calls: f.state.calls, mockError: f.state.mockError }));
  assert.deepEqual(result.data, { conversationToken: 'synthetic-webrtc-token' });
  assert.equal(result.headers.get('cache-control'), 'no-store');
  assert.equal(f.state.calls.length, 1);
  assert.equal(f.state.mockError, undefined);
  assert.deepEqual(await f.rows('voice_activation_requests'), []);
});

test('D1 reservations are atomic across sessions, scoped by installation and immutable after completion', async t => {
  const f = await fixture(t);
  const first = new D1Storage(await f.database());
  const second = new D1Storage(await f.database('secondary'));
  const requestID = randomUUID();
  await first.createInstallation(hash('synthetic-token'), 'user-a');
  assert.deepEqual(await second.getInstallation(hash('synthetic-token')), { userID: 'user-a' });
  const reservations = await Promise.all(Array.from({ length: 12 }, (_, i) => (i % 2 ? first : second).reserveExecution('user-a', requestID, 'fingerprint')));
  assert.equal(reservations.filter(Boolean).length, 1);
  assert.equal(await second.getExecution('user-b', requestID), null);
  assert.equal(await second.reserveExecution('user-b', requestID, 'different-user'), true);
  assert.deepEqual(await first.getExecution('user-a', requestID), { fingerprint: 'fingerprint', state: 'pending' });
  await assert.rejects(second.saveExecution('user-a', requestID, { fingerprint: 'changed', state: 'uncertain' }), /receipt/);
  await assert.rejects(first.saveExecution('user-a', requestID, { fingerprint: 'fingerprint', state: 'complete', receipt: { payload: { data: 'private' } } }), /cannot be persisted/);
  const receipt = { status: 200, payload: { requestID, successful: true, resultAvailable: false } };
  await second.saveExecution('user-a', requestID, { fingerprint: 'fingerprint', state: 'complete', receipt });
  await assert.rejects(first.saveExecution('user-a', requestID, { fingerprint: 'fingerprint', state: 'uncertain' }), /receipt/);
  assert.deepEqual(await second.getExecution('user-a', requestID), { fingerprint: 'fingerprint', state: 'complete', receipt });
});

test('Worker HTTP contract and installation hashes survive a fresh runtime', async t => {
  const f = await fixture(t);
  assert.equal((await f.api('/health')).status, 200);
  assert.equal((await f.api('/v1/installations', { method: 'POST' })).status, 415);
  assert.equal((await f.api('/v1/installations', { method: 'POST', data: { user_id: 'chosen-by-client' } })).status, 400);
  assert.equal((await f.api('/v1/installations', { method: 'POST', data: { oversized: 'x'.repeat(262144) } })).status, 413);
  const bearer = await f.install();
  assert.match(bearer, /^[A-Za-z0-9_-]{43}$/);
  assert.equal((await f.api('/v1/services')).status, 401);
  assert.equal((await f.api('/v1/services', { bearer: 'a'.repeat(43) })).status, 401);
  const services = await f.api('/v1/services', { bearer, worker: 'secondary' });
  assert.deepEqual(services.data.services, [{ id: 'gmail', name: 'Gmail' }, { id: 'github', name: 'GitHub' }]);
  for (const [header, expected] of [['cache-control', 'no-store'], ['x-content-type-options', 'nosniff'], ['referrer-policy', 'no-referrer']]) assert.equal(services.headers.get(header), expected);
  const catalog = await f.api('/v1/tools?service=gmail', { bearer });
  assert.equal(catalog.status, 200, JSON.stringify({ response: catalog.data, calls: f.state.calls, mockError: f.state.mockError }));
  assert.deepEqual(catalog.data.tools[0].inputSchema, { type: 'object', properties: { recipient: { type: 'string' } }, required: ['recipient'] });
  assert.equal(f.state.calls.length, 0);
  f.state.redirectCatalog = true;
  const redirected = await f.api('/v1/tools?service=gmail', { bearer });
  assert.equal(redirected.status, 200);
  assert.equal(f.state.calls.length, 0);
  assert.equal(f.state.mockError, undefined);
  const saved = await f.rows('installations');
  assert.equal(saved.length, 1);
  assert.equal(saved[0].token_hash, hash(bearer));
  assert.ok(!JSON.stringify(saved).includes(bearer));
  await f.restart();
  assert.equal((await f.api('/v1/services', { bearer })).status, 200);
});

test('independent Worker isolates dispatch one effect and only replay a content-free receipt after restart', async t => {
  const f = await fixture(t); const bearer = await f.install(); const account = await f.addAccount(bearer);
  f.state.executionGate = Promise.withResolvers(); f.state.executionStarted = Promise.withResolvers();
  const data = { tool: 'GMAIL_SEND_EMAIL', arguments: { recipient: 'private-recipient-sentinel@example.com' }, connectionID: account.id, requestID: randomUUID() };
  const first = f.api('/v1/execute', { method: 'POST', bearer, data });
  await f.state.executionStarted.promise;
  const concurrent = await f.api('/v1/execute', { method: 'POST', bearer, data, worker: 'secondary' });
  assert.equal(concurrent.status, 409);
  assert.equal(concurrent.data.error.code, 'execution_uncertain');
  f.state.executionGate.resolve();
  const completed = await first;
  assert.equal(completed.status, 200);
  assert.equal(completed.data.successful, true);
  assert.equal(completed.data.data.status, 'queued');
  assert.equal(f.state.executions, 1);
  const mismatch = await f.api('/v1/execute', { method: 'POST', bearer, data: { ...data, arguments: { recipient: 'changed@example.com' } }, worker: 'secondary' });
  assert.equal(mismatch.data.error.code, 'request_mismatch');
  const stored = JSON.stringify(await f.rows('executions'));
  assert.ok(!stored.includes('private-provider-result-sentinel') && !stored.includes('private-recipient-sentinel'));
  await f.restart();
  const replay = await f.api('/v1/execute', { method: 'POST', bearer, data, worker: 'secondary' });
  assert.deepEqual(replay.data, { requestID: data.requestID, successful: true, resultAvailable: false });
  assert.equal(f.state.executions, 1);
  const call = f.state.calls.find(item => item.url.pathname.includes('/tools/execute/'));
  assert.equal(call.input.user_id, account.user_id);
  assert.equal(call.input.connected_account_id, account.id);
  assert.equal(call.input.version, '20261001_00');
});

test('Worker timeout and malformed acknowledgements persist uncertainty without repeating effects', async t => {
  const f = await fixture(t); const bearer = await f.install(); const account = await f.addAccount(bearer);
  for (const mode of ['malformed', 'timeout']) {
    f.state.mode = mode;
    const data = { tool: 'GMAIL_SEND_EMAIL', arguments: { recipient: 'never-persist-this@example.com' }, connectionID: account.id, requestID: randomUUID() };
    const before = f.state.executions;
    const result = await f.api('/v1/execute', { method: 'POST', bearer, data });
    assert.equal(result.status, 409);
    assert.equal(result.data.error.code, 'execution_uncertain');
    await f.restart();
    const replay = await f.api('/v1/execute', { method: 'POST', bearer, data });
    assert.equal(replay.data.error.code, 'execution_uncertain');
    assert.equal(f.state.executions, before + 1);
  }
  const stored = await f.rows('executions');
  assert.ok(stored.every(row => row.state === 'uncertain' && row.receipt_json === null));
  assert.ok(!JSON.stringify(stored).includes('never-persist-this'));
});

test('Worker Slack guard checks live identity and grant revision before one durable cross-isolate send', async t => {
  const f = await fixture(t, { slack: true }); const bearer = await f.install(); const account = await f.addAccount(bearer, 'ca_slack', 'slack');
  assert.equal((await f.api(`/v1/slack/reply-identity?connectionID=${account.id}`)).status, 401);
  const identity = await f.api(`/v1/slack/reply-identity?connectionID=${account.id}`, { bearer });
  assert.equal(identity.status, 200, JSON.stringify(identity.data));
  assert.equal(identity.data.protocolVersion, 1); assert.match(identity.data.revision, /^[a-f0-9]{64}$/);
  const expectedIdentity = { revision: identity.data.revision, teamID: identity.data.teamID, userID: identity.data.userID, botID: identity.data.botID };
  const data = { connectionID: account.id, requestID: randomUUID(), expectedIdentity,
    channelID: 'C12345678', threadTS: '1792058300.000001', body: 'private-worker-slack-body-sentinel' };
  f.state.slackAuth.user_id = 'U87654321';
  const changed = await f.api('/v1/slack/replies', { method: 'POST', bearer, data });
  assert.equal(changed.data.error.code, 'slack_identity_changed'); assert.equal(f.state.slackSends, 0);
  f.state.slackAuth.user_id = expectedIdentity.userID;
  f.state.changeSlackOnSendMetadata = true;
  const replaced = await f.api('/v1/slack/replies', { method: 'POST', bearer, data: { ...data, requestID: randomUUID() } });
  assert.equal(replaced.data.error.code, 'slack_identity_changed'); assert.equal(f.state.slackSends, 0);
  f.state.changeSlackOnSendMetadata = false; account.updated_at = '2026-10-15T10:00:00.000Z';
  const sending = { ...data, requestID: randomUUID() };
  f.state.executionGate = Promise.withResolvers(); f.state.executionStarted = Promise.withResolvers();
  const first = f.api('/v1/slack/replies', { method: 'POST', bearer, data: sending });
  await f.state.executionStarted.promise;
  const concurrent = await f.api('/v1/slack/replies', { method: 'POST', bearer, data: sending, worker: 'secondary' });
  assert.equal(concurrent.status, 409); assert.equal(concurrent.data.error.code, 'execution_uncertain');
  f.state.executionGate.resolve();
  const complete = await first;
  assert.equal(complete.status, 200); assert.equal(complete.data.data.message.blocks[0].text.text, data.body);
  assert.equal(f.state.slackSends, 1);
  const send = f.state.calls.find(item => item.url.pathname.endsWith('/execute/SLACK_SEND_MESSAGE'));
  assert.equal(send.input.version, '20261014_00'); assert.equal(send.input.user_id, account.user_id);
  assert.deepEqual(send.input.arguments, { channel: data.channelID, thread_ts: data.threadTS,
    blocks: [{ type: 'section', block_id: `more-reply-v1-${sending.requestID}`, text: { type: 'plain_text', text: data.body, emoji: false } }],
    fallback_text: data.body, reply_broadcast: false, unfurl_links: false, unfurl_media: false });
  const stored = JSON.stringify(await f.rows('executions'));
  for (const raw of [data.body, data.channelID, data.threadTS, identity.data.userName]) assert.ok(!stored.includes(raw));
  await f.restart();
  const replay = await f.api('/v1/slack/replies', { method: 'POST', bearer, data: sending, worker: 'secondary' });
  assert.deepEqual(replay.data, { requestID: sending.requestID, successful: true, resultAvailable: false });
  const mismatch = await f.api('/v1/slack/replies', { method: 'POST', bearer, data: { ...sending, body: 'changed body' } });
  assert.equal(mismatch.data.error.code, 'request_mismatch'); assert.equal(f.state.slackSends, 1);
});

test('Worker Slack missing revision refuses without dispatch and lost or mismatched receipts stay uncertain after restart', async t => {
  const f = await fixture(t, { slack: true }); const bearer = await f.install(); const account = await f.addAccount(bearer, 'ca_slack', 'slack');
  const identity = (await f.api(`/v1/slack/reply-identity?connectionID=${account.id}`, { bearer })).data;
  const expectedIdentity = { revision: identity.revision, teamID: identity.teamID, userID: identity.userID, botID: identity.botID };
  const data = { connectionID: account.id, requestID: randomUUID(), expectedIdentity, channelID: 'C12345678', threadTS: '1792058300.000001', body: 'never-persist-slack-body' };
  delete account.updated_at;
  const unavailable = await f.api('/v1/slack/replies', { method: 'POST', bearer, data });
  assert.equal(unavailable.data.error.code, 'slack_identity_unavailable'); assert.equal(f.state.slackSends, 0);
  account.updated_at = '2026-10-15T10:00:00.000Z';
  for (const mode of ['wrongMarker', 'timeout']) {
    f.state.mode = mode;
    const sending = { ...data, requestID: randomUUID() }, before = f.state.slackSends;
    const result = await f.api('/v1/slack/replies', { method: 'POST', bearer, data: sending });
    assert.equal(result.status, 409); assert.equal(result.data.error.code, 'execution_uncertain');
    await f.restart();
    const replay = await f.api('/v1/slack/replies', { method: 'POST', bearer, data: sending, worker: 'secondary' });
    assert.equal(replay.data.error.code, 'execution_uncertain'); assert.equal(f.state.slackSends, before + 1);
  }
  const stored = await f.rows('executions');
  assert.equal(stored.filter(row => row.state === 'uncertain').length, 2);
  assert.ok(!JSON.stringify(stored).includes(data.body));
});

test('Worker callback completion and account access remain bound to the authenticated installation', async t => {
  const f = await fixture(t); const alice = await f.install(); const bob = await f.install();
  const account = await f.addAccount(alice); await f.addAccount(bob, 'ca_other');
  f.state.accounts.set('ca_wrong_config', { ...account, id: 'ca_wrong_config', auth_config: { id: 'ac_other_project' } });
  f.state.accounts.set('ca_shared', { ...account, id: 'ca_shared', experimental: { account_type: 'SHARED' } });
  const list = await f.api('/v1/connections', { bearer: alice });
  assert.deepEqual(list.data.connections.map(item => item.id), [account.id]);
  assert.ok(!JSON.stringify(list.data).includes('private-provider-token-sentinel'));
  const sessionURI = `session-${account.user_id}`;
  const redirect = await f.api(`/v1/oauth/callback?session_uri=${encodeURIComponent(sessionURI)}`);
  const nativeURL = new URL(redirect.headers.get('location'));
  assert.equal(redirect.status, 302);
  assert.equal(`${nativeURL.protocol}//${nativeURL.host}${nativeURL.pathname}`, callbacks[0]);
  assert.equal(nativeURL.searchParams.get('session_uri'), sessionURI);
  assert.equal((await f.api('/v1/connections/complete', { method: 'POST', data: { sessionURI } })).status, 401);
  const stolen = await f.api('/v1/connections/complete', { method: 'POST', bearer: bob, data: { sessionURI } });
  assert.equal(stolen.status, 502);
  assert.ok(!JSON.stringify(stolen.data).includes('private-auth-detail'));
  const completed = await f.api('/v1/connections/complete', { method: 'POST', bearer: alice, data: { sessionURI } });
  assert.deepEqual(completed.data, { id: account.id, service: 'gmail', status: 'ACTIVE' });
  const calls = f.state.calls.length;
  assert.equal((await f.api('/v1/connections', { method: 'POST', bearer: alice, data: { service: 'gmail', callbackURL: 'more://composio/callback?steal=1' } })).status, 400);
  assert.equal(f.state.calls.length, calls);
  const effect = { tool: 'GMAIL_SEND_EMAIL', arguments: {}, connectionID: account.id, requestID: randomUUID() };
  assert.equal((await f.api('/v1/execute', { method: 'POST', bearer: bob, data: effect })).status, 404);
  assert.equal(f.state.executions, 0);
  assert.equal((await f.api(`/v1/connections/${account.id}`, { method: 'DELETE', bearer: bob })).status, 404);
  assert.equal((await f.api(`/v1/connections/${account.id}`, { method: 'DELETE', bearer: alice })).status, 204);
  assert.equal(f.state.calls.at(-1).url.searchParams.get('revoke_on_delete'), 'true');
});

test('Worker enrollment limits reject excess traffic and missing rate-limit bindings fail closed', async t => {
  const limited = await fixture(t, { enrollmentLimit: 1 });
  await limited.install();
  const rejected = await limited.api('/v1/installations', { method: 'POST', data: {} });
  assert.equal(rejected.status, 429);
  assert.equal(rejected.data.error.code, 'rate_limited');
  assert.equal(rejected.headers.get('retry-after'), '60');
  assert.equal((await limited.rows('installations')).length, 1);
  const missing = await fixture(t, { limiters: false });
  assert.equal((await missing.api('/health')).status, 200);
  const unavailable = await missing.api('/v1/installations', { method: 'POST', data: {} });
  assert.equal(unavailable.status, 503);
  assert.equal(unavailable.data.error.code, 'rate_limit_unavailable');
  assert.equal((await missing.rows('installations')).length, 0);
});

test('Worker module loads without runtime D1 bindings and reports sanitized configuration failure on fetch', async t => {
  const f = await fixture(t, { withDatabase: false });
  await assert.doesNotReject(f.ready());
  const result = await f.api('/health');
  assert.equal(result.status, 503);
  assert.deepEqual(result.data, { error: { code: 'service_not_configured', message: 'The connector runtime could not be initialized.' } });
  assert.equal(result.headers.get('cache-control'), 'no-store');
  assert.ok(!JSON.stringify(result.data).includes('synthetic-worker-key'));
  assert.equal(f.state.calls.length, 0);
});

test('Worker serves a large public catalog verbatim only for its configured pin and never falls back to provider data', async t => {
  const f = await fixture(t); const bearer = await f.install(); const db = await f.database();
  const payload = ` { "tools" : [{"slug":"GMAIL_PUBLIC_TOOL","name":"Public tool","description":${JSON.stringify('public-schema-'.repeat(60000))},"inputSchema":{"type":"object","properties":{}}}] }\n`;
  await db.prepare('UPDATE public_catalogs SET payload_json = ? WHERE toolkit_slug = ? AND toolkit_version = ?').bind(payload, 'gmail', toolkits.gmail.version).run();
  assert.equal((await f.api('/v1/tools?service=gmail')).status, 401);
  const served = await f.api('/v1/tools?service=gmail', { bearer });
  assert.equal(served.status, 200);
  assert.equal(served.raw, payload);
  assert.equal(f.state.calls.length, 0);
  await db.prepare('UPDATE public_catalogs SET toolkit_version = ? WHERE toolkit_slug = ?').bind('20261002_00', 'gmail').run();
  const unavailable = await f.api('/v1/tools?service=gmail', { bearer });
  assert.equal(unavailable.status, 503);
  assert.equal(unavailable.data.error.code, 'catalog_unavailable');
  assert.equal((await f.api('/v1/tools?service=github', { bearer })).status, 503);
  assert.equal(f.state.calls.length, 0);
  assert.ok(!JSON.stringify(await f.rows('public_catalogs')).includes(bearer));
});
