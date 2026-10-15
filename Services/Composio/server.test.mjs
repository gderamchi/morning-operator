import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { once } from 'node:events';
import { mkdtemp, rm, readdir, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { createService, configFromEnv } from './server.mjs';

const listen = async server => { server.listen(0, '127.0.0.1'); await once(server, 'listening'); return `http://127.0.0.1:${server.address().port}`; };
const close = server => new Promise(resolve => { server.closeAllConnections(); server.close(resolve); });

async function fixture(t) {
  const directory = await mkdtemp(join(tmpdir(), 'more-composio-test-'));
  const state = { accounts: new Map(), calls: [], executions: 0, delay: 0, invalidExecution: false, linkCalls: 0 };
  const mock = createServer(async (request, response) => {
    let raw = ''; for await (const chunk of request) raw += chunk;
    const input = raw ? JSON.parse(raw) : undefined;
    const url = new URL(request.url, 'http://mock');
    state.calls.push({ method: request.method, url, input });
    assert.equal(request.headers['x-api-key'], 'server-only-test-key');
    const result = (status, data) => { response.writeHead(status, { 'content-type': 'application/json' }); response.end(JSON.stringify(data)); };
    const accountID = url.pathname.split('/').at(-1);
    if (url.pathname === '/api/v3.1/connected_accounts/link') {
      state.linkCalls++;
      return result(201, { connected_account_id: 'ca_new', redirect_url: 'https://connect.composio.dev/auth/test' });
    }
    if (url.pathname === '/api/v3.1/connected_accounts/complete_auth') {
      if (input.session_uri !== `session-${input.user_id}`) return result(400, { error: 'private upstream auth details' });
      const account = [...state.accounts.values()].find(item => item.user_id === input.user_id);
      return result(200, { connected_account_id: account.id, toolkit_slug: account.toolkit.slug });
    }
    if (url.pathname === '/api/v3.1/connected_accounts') return result(200, { items: [...state.accounts.values()], next_cursor: null });
    if (url.pathname.startsWith('/api/v3.1/connected_accounts/')) {
      const account = state.accounts.get(accountID);
      if (!account) return result(404, {});
      if (request.method === 'DELETE') { state.accounts.delete(accountID); return result(200, { success: true }); }
      return result(200, account);
    }
    const tool = { slug: 'GMAIL_SEND_EMAIL', toolkit: { slug: 'gmail' }, name: 'Send email', description: 'Send a message', version: '20261001_00', input_parameters: { recipient: { type: 'string', required: true } } };
    if (url.pathname === '/api/v3.1/tools') return result(200, { items: [tool], next_cursor: null });
    if (url.pathname.startsWith('/api/v3.1/tools/execute/')) {
      state.executions++;
      if (state.delay) await new Promise(resolve => setTimeout(resolve, state.delay));
      return result(200, state.invalidExecution ? { data: 'missing receipt' } : { successful: true, data: { messageID: 'test-message' } });
    }
    if (url.pathname === '/api/v3.1/tools/GMAIL_SEND_EMAIL') return result(200, tool);
    if (url.pathname === '/api/v3.1/tools/GITHUB_CREATE_ISSUE') return result(200, { ...tool, slug: 'GITHUB_CREATE_ISSUE', toolkit: { slug: 'github' } });
    return result(404, {});
  });
  const upstream = await listen(mock);
  const config = { apiKey: 'server-only-test-key', upstream: `${upstream}/api/v3.1/`, dataDir: directory, callbacks: ['more://composio/callback', 'moreqa://composio/callback'], callbackURL: 'more://composio/callback', publicURL: 'https://connector.example', timeout: 2000, toolkits: { gmail: { authConfigID: 'ac_gmail', name: 'Gmail', version: '20261001_00' }, github: { authConfigID: 'ac_github', name: 'GitHub', version: '20261001_00' } } };
  let server = await createService(config);
  let base = await listen(server);
  t.after(async () => { await close(server); await close(mock); await rm(directory, { recursive: true, force: true }); });
  async function api(path, { method = 'GET', bearer, data, headers = {} } = {}) {
    const response = await fetch(`${base}${path}`, { method, redirect: 'manual', headers: { ...(bearer ? { Authorization: `Bearer ${bearer}` } : {}), ...(data === undefined ? {} : { 'Content-Type': 'application/json' }), ...headers }, body: data === undefined ? undefined : JSON.stringify(data) });
    const raw = await response.text();
    return { status: response.status, headers: response.headers, data: raw ? JSON.parse(raw) : null };
  }
  const install = async () => (await api('/v1/installations', { method: 'POST', data: {} })).data.token;
  async function addAccount(bearer, id = 'ca_mine', service = 'gmail') {
    await api('/v1/connections', { method: 'POST', bearer, data: { service, callbackURL: config.callbackURL } });
    const call = state.calls.findLast(item => item.url.pathname.endsWith('/link'));
    const account = { id, toolkit: { slug: service }, auth_config: { id: config.toolkits[service].authConfigID }, status: 'ACTIVE', user_id: call.input.user_id, alias: 'My account', state: { access_token: 'must-never-reach-client' } };
    state.accounts.set(id, account); return account;
  }
  return { api, install, addAccount, state, config, directory, restart: async () => { await close(server); server = await createService(config); base = await listen(server); } };
}

test('config requires server secret and explicit pinned toolkit versions', () => {
  assert.throws(() => configFromEnv({}), /COMPOSIO_API_KEY/);
  assert.throws(() => configFromEnv({ COMPOSIO_API_KEY: 'test', COMPOSIO_TOOLKITS_JSON: '{"gmail":{"name":"Gmail","authConfigID":"ac_test","version":"latest"}}' }), /pinned/);
  assert.throws(() => configFromEnv({ COMPOSIO_API_KEY: 'test', MORE_PUBLIC_BASE_URL: 'http://example.com' }), /HTTPS/);
  const config = configFromEnv({ COMPOSIO_API_KEY: 'test' });
  assert.equal(config.callbackURL, 'more://composio/callback');
});

test('installations are isolated and only token hashes persist', async t => {
  const f = await fixture(t); const alice = await f.install(); const bob = await f.install();
  assert.notEqual(alice, bob);
  assert.equal((await f.api('/v1/services')).status, 401);
  assert.equal((await f.api('/v1/services', { bearer: 'a'.repeat(43) })).status, 401);
  assert.equal((await f.api('/v1/installations', { method: 'POST', data: { user_id: 'victim' } })).status, 400);
  const files = await readdir(join(f.directory, 'installations'));
  const stored = await Promise.all(files.map(name => readFile(join(f.directory, 'installations', name), 'utf8')));
  assert.ok(stored.every(value => !value.includes(alice) && !value.includes(bob)));
  const account = await f.addAccount(alice);
  await f.addAccount(bob, 'ca_other');
  f.state.accounts.set('ca_wrong_config', { ...account, id: 'ca_wrong_config', auth_config: { id: 'ac_someone_else' } });
  const result = await f.api('/v1/connections', { bearer: alice });
  assert.equal(result.data.connections.length, 1);
  assert.equal(result.data.connections[0].id, 'ca_mine');
  assert.ok(!JSON.stringify(result.data).includes('must-never-reach-client'));
  const listCall = f.state.calls.findLast(item => item.url.pathname === '/api/v3.1/connected_accounts');
  assert.equal(listCall.url.searchParams.get('user_ids'), account.user_id);
  assert.equal((await f.api('/v1/services', { bearer: alice })).data.services.length, 2);
});

test('connections enforce configured services and exact native callbacks', async t => {
  const f = await fixture(t); const bearer = await f.install();
  for (const callbackURL of ['https://attacker.example', 'more://composio/callback?steal=1', 'more://elsewhere/callback', 'javascript:alert(1)']) {
    assert.equal((await f.api('/v1/connections', { method: 'POST', bearer, data: { service: 'gmail', callbackURL } })).status, 400);
  }
  assert.equal(f.state.linkCalls, 0);
  const connect = await f.api('/v1/connections', { method: 'POST', bearer, data: { service: 'gmail', callbackURL: f.config.callbackURL } });
  assert.equal(connect.status, 201);
  assert.equal(connect.data.authorizationURL, 'https://connect.composio.dev/auth/test');
  const call = f.state.calls.at(-1);
  assert.equal(call.input.auth_config_id, 'ac_gmail');
  assert.equal(call.input.callback_url, 'https://connector.example/v1/oauth/callback');
  assert.equal((await f.api('/v1/connections', { method: 'POST', bearer, data: { service: 'not_configured', callbackURL: f.config.callbackURL } })).status, 400);
});

test('custom social OAuth is exposed only when explicitly configured and keeps account isolation', async t => {
  const f = await fixture(t); const alice = await f.install(); const bob = await f.install();
  for (const service of ['twitter', 'tiktok']) {
    assert.equal((await f.api('/v1/connections', { method: 'POST', bearer: alice, data: { service, callbackURL: f.config.callbackURL } })).status, 400);
  }
  assert.equal(f.state.linkCalls, 0);
  const configured = configFromEnv({ COMPOSIO_API_KEY: 'server-only-test-key', COMPOSIO_TOOLKITS_JSON: JSON.stringify({
    twitter: { name: 'X', authConfigID: 'ac_synthetic_twitter', version: '20261007_00' },
    tiktok: { name: 'TikTok', authConfigID: 'ac_synthetic_tiktok', version: '20260917_00' }
  }) });
  Object.assign(f.config.toolkits, configured.toolkits);
  const services = (await f.api('/v1/services', { bearer: alice })).data.services;
  assert.ok(services.some(service => service.id === 'twitter' && service.name === 'X'));
  assert.ok(services.some(service => service.id === 'tiktok' && service.name === 'TikTok'));
  await f.addAccount(alice, 'ca_social_x', 'twitter');
  await f.addAccount(bob, 'ca_social_tiktok_other_user', 'tiktok');
  const links = f.state.calls.filter(call => call.url.pathname.endsWith('/link'));
  assert.equal(links.at(-2).input.auth_config_id, configured.toolkits.twitter.authConfigID);
  assert.equal(links.at(-1).input.auth_config_id, configured.toolkits.tiktok.authConfigID);
  const mine = (await f.api('/v1/connections', { bearer: alice })).data.connections;
  assert.deepEqual(mine.map(account => account.id), ['ca_social_x']);
  assert.equal(f.state.executions, 0);
});

test('OAuth completion binds the returning app installation, not a forwarded auth link', async t => {
  const f = await fixture(t); const alice = await f.install(); const bob = await f.install();
  const account = await f.addAccount(alice);
  const sessionURI = `session-${account.user_id}`;
  const redirect = await f.api(`/v1/oauth/callback?session_uri=${encodeURIComponent(sessionURI)}`);
  assert.equal(redirect.status, 302);
  assert.equal(new URL(redirect.headers.get('location')).searchParams.get('session_uri'), sessionURI);
  assert.equal((await f.api('/v1/connections/complete', { method: 'POST', data: { sessionURI } })).status, 401);
  const forbidden = await f.api('/v1/connections/complete', { method: 'POST', bearer: bob, data: { sessionURI } });
  assert.equal(forbidden.status, 502);
  assert.ok(!JSON.stringify(forbidden.data).includes('private upstream'));
  const completed = await f.api('/v1/connections/complete', { method: 'POST', bearer: alice, data: { sessionURI } });
  assert.deepEqual(completed.data, { id: 'ca_mine', service: 'gmail', status: 'ACTIVE' });
});

test('catalog is limited to configured services and normalizes input schemas', async t => {
  const f = await fixture(t); const bearer = await f.install();
  const result = await f.api('/v1/tools?service=gmail', { bearer });
  assert.equal(result.status, 200);
  assert.deepEqual(result.data.tools[0].inputSchema, { type: 'object', properties: { recipient: { type: 'string' } }, required: ['recipient'] });
  assert.equal(f.state.calls.at(-1).url.searchParams.get('toolkit_versions[gmail]'), '20261001_00');
  assert.equal((await f.api('/v1/tools?service=unconfigured', { bearer })).status, 400);
});

test('execution rejects cross-user accounts, inactive accounts and toolkit mismatch', async t => {
  const f = await fixture(t); const alice = await f.install(); const bob = await f.install();
  const account = await f.addAccount(alice);
  const request = () => ({ tool: 'GMAIL_SEND_EMAIL', arguments: { recipient: 'test@example.com' }, connectionID: account.id, requestID: randomUUID() });
  assert.equal((await f.api('/v1/execute', { method: 'POST', bearer: bob, data: request() })).status, 404);
  account.status = 'EXPIRED';
  assert.equal((await f.api('/v1/execute', { method: 'POST', bearer: alice, data: request() })).status, 409);
  account.status = 'ACTIVE';
  assert.equal((await f.api('/v1/execute', { method: 'POST', bearer: alice, data: { ...request(), tool: 'GITHUB_CREATE_ISSUE' } })).status, 400);
  assert.equal((await f.api('/v1/execute', { method: 'POST', bearer: alice, data: { ...request(), user_id: account.user_id } })).status, 400);
  assert.equal(f.state.executions, 0);
});

test('concurrent duplicate execution reserves once, replays receipt and rejects changed payload', async t => {
  const f = await fixture(t); const bearer = await f.install(); const account = await f.addAccount(bearer);
  f.state.delay = 100;
  const data = { tool: 'GMAIL_SEND_EMAIL', arguments: { recipient: 'test@example.com' }, connectionID: account.id, requestID: randomUUID() };
  const results = await Promise.all([f.api('/v1/execute', { method: 'POST', bearer, data }), f.api('/v1/execute', { method: 'POST', bearer, data })]);
  assert.deepEqual(results.map(item => item.status).sort(), [200, 409]);
  assert.equal(f.state.executions, 1);
  const replay = await f.api('/v1/execute', { method: 'POST', bearer, data });
  assert.equal(replay.status, 200);
  assert.equal(replay.data.successful, true);
  assert.equal(replay.data.resultAvailable, false);
  assert.equal(replay.data.data, undefined);
  const journalFiles = await readdir(join(f.directory, 'journal', account.user_id));
  const journal = await readFile(join(f.directory, 'journal', account.user_id, journalFiles[0]), 'utf8');
  assert.ok(!journal.includes('test-message') && !journal.includes('test@example.com'));
  const mismatch = await f.api('/v1/execute', { method: 'POST', bearer, data: { ...data, arguments: { recipient: 'changed@example.com' } } });
  assert.equal(mismatch.data.error.code, 'request_mismatch');
  const call = f.state.calls.find(item => item.url.pathname.includes('/tools/execute/'));
  assert.equal(call.input.user_id, account.user_id);
  assert.equal(call.input.version, '20261001_00');
  assert.equal(call.input.connected_account_id, account.id);
  assert.equal(f.state.executions, 1);
  await f.restart();
  assert.equal((await f.api('/v1/execute', { method: 'POST', bearer, data })).status, 200);
  assert.equal(f.state.executions, 1);
});

test('an execution timeout remains uncertain across restart and is never retried', async t => {
  const f = await fixture(t); const bearer = await f.install(); const account = await f.addAccount(bearer);
  f.config.timeout = 30; f.state.delay = 100;
  const data = { tool: 'GMAIL_SEND_EMAIL', arguments: {}, connectionID: account.id, requestID: randomUUID() };
  const result = await f.api('/v1/execute', { method: 'POST', bearer, data });
  assert.equal(result.status, 409);
  assert.equal(result.data.error.code, 'execution_uncertain');
  await f.restart();
  const replay = await f.api('/v1/execute', { method: 'POST', bearer, data });
  assert.equal(replay.data.error.code, 'execution_uncertain');
  assert.equal(f.state.executions, 1);
});

test('a malformed provider execution receipt is uncertain rather than fabricated success', async t => {
  const f = await fixture(t); const bearer = await f.install(); const account = await f.addAccount(bearer);
  f.state.invalidExecution = true;
  const data = { tool: 'GMAIL_SEND_EMAIL', arguments: {}, connectionID: account.id, requestID: randomUUID() };
  const result = await f.api('/v1/execute', { method: 'POST', bearer, data });
  assert.equal(result.data.error.code, 'execution_uncertain');
  assert.equal((await f.api('/v1/execute', { method: 'POST', bearer, data })).status, 409);
  assert.equal(f.state.executions, 1);
});

test('deletion verifies ownership and requests upstream grant revocation', async t => {
  const f = await fixture(t); const alice = await f.install(); const bob = await f.install();
  const account = await f.addAccount(alice);
  assert.equal((await f.api(`/v1/connections/${account.id}`, { method: 'DELETE', bearer: bob })).status, 404);
  assert.equal((await f.api(`/v1/connections/${account.id}`, { method: 'DELETE', bearer: alice })).status, 204);
  assert.equal(f.state.calls.at(-1).url.searchParams.get('revoke_on_delete'), 'true');
  assert.equal((await f.api('/v1/connections', { bearer: alice })).data.connections.length, 0);
});

test('request size and JSON boundaries reject invalid client input', async t => {
  const f = await fixture(t); const bearer = await f.install();
  assert.equal((await f.api('/v1/installations', { method: 'POST' })).status, 415);
  const result = await f.api('/v1/execute', { method: 'POST', bearer, data: { contents: 'a'.repeat(270000) } });
  assert.equal(result.status, 413);
  assert.equal(f.state.executions, 0);
});
