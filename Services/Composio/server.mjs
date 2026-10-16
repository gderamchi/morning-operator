import { randomBytes, randomUUID, createHash } from 'node:crypto';
import { mkdir, open, readFile, rename } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { morningSpeech, morningVoiceToken } from './morning-voice.mjs';

const token = () => randomBytes(32).toString('base64url');
const hash = value => createHash('sha256').update(value).digest('hex');
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const idPattern = /^[a-zA-Z0-9_-]{1,160}$/;
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

class HTTPError extends Error {
  constructor(status, code, message) { super(message); this.status = status; this.code = code; }
}
const fail = (status, code, message) => { throw new HTTPError(status, code, message); };
const envelope = error => ({ error: { code: error.code ?? 'internal_error', message: error instanceof HTTPError ? error.message : 'The service could not complete the request.' } });
function canonical(value) {
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
  if (object(value)) return `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`;
  return JSON.stringify(value);
}

const slackTimestamp = value => typeof value === 'string' && /^\d{10,16}\.\d{6}$/.test(value);
const slackIdentityID = (value, prefix) => typeof value === 'string' && new RegExp(`^[${prefix}][A-Z0-9]{2,79}$`).test(value);
const slackMarker = requestID => `more-reply-v1-${requestID}`;
function slackAccountRevision(account) {
  // These are the documented connected-account timestamps, not its editable alias
  // or credential material. Missing revision metadata disables this reply route.
  if (![account.created_at, account.updated_at].every(value => typeof value === 'string' && value.length <= 100 && Number.isFinite(Date.parse(value))) || Date.parse(account.updated_at) < Date.parse(account.created_at)) {
    fail(409, 'slack_identity_unavailable', 'Slack identity could not be verified. Reconnect and review this reply again.');
  }
  return hash(canonical({ id: account.id, userID: account.user_id, toolkit: account.toolkit.slug,
    authConfigID: account.auth_config.id, status: account.status, createdAt: account.created_at,
    updatedAt: account.updated_at, disabled: account.is_disabled === true, authDisabled: account.auth_config.is_disabled === true }));
}
function slackSubject(result) {
  const data = result?.data;
  if (result?.successful !== true || !object(data) || data.ok !== true ||
      !slackIdentityID(data.team_id, 'T') || !slackIdentityID(data.user_id, 'UW') ||
      (data.bot_id !== undefined && !slackIdentityID(data.bot_id, 'B')) ||
      ![data.team, data.user].every(value => typeof value === 'string' && value.trim().length > 0 && value.length <= 200)) {
    fail(409, 'slack_identity_unavailable', 'Slack identity could not be verified. Reconnect and review this reply again.');
  }
  return { teamID: data.team_id, userID: data.user_id, ...(data.bot_id === undefined ? {} : { botID: data.bot_id }), teamName: data.team, userName: data.user };
}
function sameSlackIdentity(actual, expected) {
  return actual.revision === expected.revision && actual.teamID === expected.teamID &&
    actual.userID === expected.userID && (actual.botID ?? null) === (expected.botID ?? null);
}
function validSlackReply(input) {
  exactKeys(input, ['connectionID', 'requestID', 'expectedIdentity', 'channelID', 'threadTS', 'body']);
  if (typeof input.connectionID !== 'string' || !idPattern.test(input.connectionID) || !uuidPattern.test(input.requestID ?? '') ||
      !object(input.expectedIdentity) || !slackIdentityID(input.channelID, 'CG') || !slackTimestamp(input.threadTS) ||
      typeof input.body !== 'string' || input.body.trim().length === 0 || input.body.length > 3000 ||
      Buffer.byteLength(input.body, 'utf8') > 12000 || /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/.test(input.body) || /<[@!#]/.test(input.body)) {
    fail(400, 'invalid_slack_reply', 'Review this Slack reply. A supported channel, thread and plain text without mentions are required.');
  }
  const expected = input.expectedIdentity;
  exactKeys(expected, ['revision', 'teamID', 'userID', 'botID']);
  if (typeof expected.revision !== 'string' || !/^[a-f0-9]{64}$/.test(expected.revision) ||
      !slackIdentityID(expected.teamID, 'T') || !slackIdentityID(expected.userID, 'UW') ||
      (expected.botID !== undefined && !slackIdentityID(expected.botID, 'B'))) {
    fail(400, 'invalid_slack_reply', 'Review the current Slack account before preparing this reply.');
  }
}
function verifiedSlackReply(result, input) {
  const data = result?.data, message = data?.message, blocks = message?.blocks;
  return result?.successful === true && object(data) && data.ok === true && data.channel === input.channelID && slackTimestamp(data.ts) &&
    object(message) && message.ts === data.ts && message.thread_ts === input.threadTS && message.user === input.expectedIdentity.userID &&
    (message.bot_id ?? null) === (input.expectedIdentity.botID ?? null) && Array.isArray(blocks) && blocks.length === 1 &&
    blocks[0]?.type === 'section' && blocks[0]?.block_id === slackMarker(input.requestID) &&
    blocks[0]?.text?.type === 'plain_text' && blocks[0]?.text?.text === input.body && blocks[0]?.text?.emoji === false;
}

export function configFromEnv(env = process.env) {
  if (!env.COMPOSIO_API_KEY) throw new Error('COMPOSIO_API_KEY is required.');
  const toolkits = JSON.parse(env.COMPOSIO_TOOLKITS_JSON ?? '{}');
  if (!object(toolkits)) throw new Error('COMPOSIO_TOOLKITS_JSON must be an object.');
  for (const [slug, toolkit] of Object.entries(toolkits)) {
    if (!/^[a-z0-9_]{1,80}$/.test(slug) || !object(toolkit) || !idPattern.test(toolkit.authConfigID ?? '') || typeof toolkit.name !== 'string' || !/^\d{8}_\d{2}$/.test(toolkit.version ?? '')) {
      throw new Error('Each toolkit needs a slug, name, authConfigID and pinned YYYYMMDD_NN version.');
    }
  }
  const callbacks = JSON.parse(env.MORE_CALLBACK_URLS_JSON ?? '["more://composio/callback","moreqa://composio/callback"]');
  if (!Array.isArray(callbacks) || callbacks.length === 0) throw new Error('Configure exact callback URLs.');
  for (const callback of callbacks) {
    const url = new URL(callback);
    if (!['https:', 'more:', 'moreqa:'].includes(url.protocol) || url.username || url.password || url.hash || url.search) throw new Error('Invalid callback URL.');
  }
  const callbackURL = env.MORE_AUTH_CALLBACK_URL ?? 'more://composio/callback';
  if (!callbacks.includes(callbackURL)) throw new Error('MORE_AUTH_CALLBACK_URL must be allowlisted.');
  const publicURL = env.MORE_PUBLIC_BASE_URL ? new URL(env.MORE_PUBLIC_BASE_URL) : null;
  if (publicURL && (publicURL.protocol !== 'https:' || publicURL.username || publicURL.password || publicURL.pathname !== '/' || publicURL.search || publicURL.hash)) throw new Error('MORE_PUBLIC_BASE_URL must be an HTTPS origin.');
  const timeout = Number(env.COMPOSIO_TIMEOUT_MS ?? 20000);
  const port = Number(env.PORT ?? 8787);
  if (!Number.isInteger(timeout) || timeout < 100 || timeout > 60000 || !Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Invalid timeout or PORT.');
  const voiceInstallations = JSON.parse(env.MORE_VOICE_INSTALLATIONS_JSON ?? '[]');
  if (!Array.isArray(voiceInstallations) || !voiceInstallations.every(value => typeof value === 'string' && /^more_[0-9a-f-]{36}$/i.test(value))) throw new Error('Voice installations must be explicit installation IDs.');
  const voice = { apiKey: env.ELEVENLABS_API_KEY, agentID: env.ELEVENLABS_AGENT_ID, installations: voiceInstallations };
  if (voice.agentID && !/^[a-zA-Z0-9_-]{1,160}$/.test(voice.agentID)) throw new Error('Invalid ElevenLabs agent ID.');
  return { apiKey: env.COMPOSIO_API_KEY, toolkits, callbacks, callbackURL, publicURL: publicURL?.origin, upstream: 'https://backend.composio.dev/api/v3.1/', dataDir: resolve(env.MORE_DATA_DIR ?? './data'), timeout, port, host: env.HOST ?? '127.0.0.1', voice };
}

async function syncDirectory(path) {
  const directory = await open(path, 'r');
  try { await directory.sync(); } finally { await directory.close(); }
}

async function durableJSON(path, value, exclusive = false) {
  const temporary = exclusive ? path : `${path}.${randomUUID()}.tmp`;
  const file = await open(temporary, 'wx', 0o600);
  try { await file.writeFile(JSON.stringify(value)); await file.sync(); }
  finally { await file.close(); }
  if (!exclusive) await rename(temporary, path);
  await syncDirectory(resolve(path, '..'));
}

async function loadJSON(path) {
  try { return JSON.parse(await readFile(path, 'utf8')); }
  catch (error) { if (error.code === 'ENOENT') return null; throw error; }
}

export class FileStorage {
  constructor(directory) { this.directory = directory; }
  installationPath(tokenHash) { return join(this.directory, 'installations', `${tokenHash}.json`); }
  executionPath(userID, requestID) { return join(this.directory, 'journal', userID, `${requestID}.json`); }
  async initialize() {
    for (const directory of ['installations', 'journal', 'voice-activation']) await mkdir(join(this.directory, directory), { recursive: true, mode: 0o700 });
  }
  async createInstallation(tokenHash, userID) { await durableJSON(this.installationPath(tokenHash), { userID }, true); }
  async getInstallation(tokenHash) { return loadJSON(this.installationPath(tokenHash)); }
  async requestVoiceActivation(userID) {
    await durableJSON(join(this.directory, 'voice-activation', `${userID}.json`), { requestedAt: new Date().toISOString() });
  }
  async reserveExecution(userID, requestID, fingerprint) {
    await mkdir(join(this.directory, 'journal', userID), { recursive: true, mode: 0o700 });
    try { await durableJSON(this.executionPath(userID, requestID), { fingerprint, state: 'pending' }, true); return true; }
    catch (error) { if (error.code === 'EEXIST') return false; throw error; }
  }
  async getExecution(userID, requestID) { return loadJSON(this.executionPath(userID, requestID)); }
  async saveExecution(userID, requestID, value) { await durableJSON(this.executionPath(userID, requestID), value); }
}

const responseHeaders = { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer' };
const header = (request, name) => typeof request.headers.get === 'function' ? request.headers.get(name) : request.headers[name];
const reply = (status, payload, headers = {}) => ({ status, payload, headers });
function send(response, status, payload, headers = {}) {
  response.writeHead(status, { ...responseHeaders, ...headers });
  response.end(payload === undefined ? undefined : JSON.stringify(payload));
}

async function body(request) {
  if (!/^application\/json(?:\s*;|$)/i.test(header(request, 'content-type') ?? '')) fail(415, 'json_required', 'Use application/json.');
  const raw = await (typeof request.headers.get === 'function' ? (async () => {
    let total = 0; const chunks = [];
    for await (const chunk of request.body ?? []) {
      total += chunk.length;
      if (total > 262144) fail(413, 'body_too_large', 'Request exceeds 256 KiB.');
      chunks.push(chunk);
    }
    return Buffer.concat(chunks).toString('utf8');
  })() : new Promise((accept, reject) => {
    let total = 0; const chunks = [];
    request.on('data', chunk => {
      total += chunk.length;
      if (total > 262144) reject(new HTTPError(413, 'body_too_large', 'Request exceeds 256 KiB.'));
      else chunks.push(chunk);
    });
    request.on('end', () => accept(Buffer.concat(chunks).toString('utf8')));
    request.on('error', reject);
  }));
  let value;
  try { value = JSON.parse(raw); } catch { fail(400, 'invalid_json', 'A JSON object is required.'); }
  if (!object(value)) fail(400, 'invalid_json', 'A JSON object is required.');
  return value;
}

function exactKeys(value, keys) {
  if (Object.keys(value).some(key => !keys.includes(key))) fail(400, 'unexpected_field', 'Request contains an unsupported field.');
}

async function providerRequest(config, path, { method = 'GET', payload, query } = {}) {
    const url = new URL(path, config.upstream);
    for (const [key, value] of Object.entries(query ?? {})) if (value !== undefined) url.searchParams.set(key, String(value));
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), config.timeout);
    try {
      const response = await fetch(url, { method, headers: { 'x-api-key': config.apiKey, 'Content-Type': 'application/json' }, body: payload === undefined ? undefined : JSON.stringify(payload), signal: controller.signal, redirect: 'manual' });
      if (response.status >= 300 && response.status < 400) fail(502, 'provider_rejected', 'The provider could not complete this request.');
      let size = 0; const chunks = [];
      for await (const chunk of response.body ?? []) {
        size += chunk.length;
        if (size > 4194304) { controller.abort(); fail(502, 'provider_response_too_large', 'Provider response exceeds the limit.'); }
        chunks.push(chunk);
      }
      if (!response.ok) fail(response.status === 429 ? 503 : 502, 'provider_rejected', 'The provider could not complete this request.');
      let result;
      try { result = JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}'); }
      catch { fail(502, 'invalid_provider_response', 'The provider returned an invalid response.'); }
      if (!object(result)) fail(502, 'invalid_provider_response', 'The provider returned an invalid response.');
      return result;
    } catch (error) {
      if (error instanceof HTTPError) throw error;
      fail(502, controller.signal.aborted ? 'provider_timeout' : 'provider_unavailable', 'The provider did not return a verified result.');
    } finally { clearTimeout(timer); }
}

async function providerPages(config, path, query) {
    const items = []; let cursor;
    for (let page = 0; page < 20; page++) {
      const result = await providerRequest(config, path, { query: { ...query, limit: 100, cursor } });
      if (!Array.isArray(result.items)) fail(502, 'invalid_provider_response', 'The provider returned an invalid list.');
      items.push(...result.items);
      if (!result.next_cursor) return items;
      if (typeof result.next_cursor !== 'string' || result.next_cursor === cursor) break;
      cursor = result.next_cursor;
    }
    fail(502, 'catalog_too_large', 'The provider list could not be loaded completely.');
}

export async function loadPublicTools(config, slug) {
  if (!Object.hasOwn(config.toolkits, slug)) fail(400, 'unsupported_service', 'This service is not configured.');
  const toolkit = config.toolkits[slug];
  const items = await providerPages(config, 'tools', { toolkit_slug: slug, [`toolkit_versions[${slug}]`]: toolkit.version, include_deprecated: false });
  return items.filter(tool => tool.toolkit?.slug === slug && !tool.is_deprecated).map(tool => {
    if (tool.version && tool.version !== toolkit.version) fail(502, 'tool_version_mismatch', 'The provider catalog did not match the configured version.');
    let inputSchema = tool.input_parameters;
    if (!object(inputSchema)) fail(502, 'invalid_provider_response', 'A tool schema was missing.');
    if (inputSchema.type !== 'object' || !object(inputSchema.properties)) {
      const properties = {}; const required = [];
      for (const [key, value] of Object.entries(inputSchema)) { if (!object(value)) fail(502, 'invalid_provider_response', 'Invalid tool schema.'); const { required: needed, ...schema } = value; properties[key] = schema; if (needed === true) required.push(key); }
      inputSchema = { type: 'object', properties, required };
    }
    return { slug: tool.slug, name: tool.name, description: tool.description ?? '', inputSchema };
  });
}

export async function createRequestHandler(config, { storage = new FileStorage(config.dataDir), catalogs } = {}) {
  await storage.initialize();
  const activeRequests = new Set();
  const upstream = (path, options) => providerRequest(config, path, options);
  const pages = (path, query) => providerPages(config, path, query);

  function service(slug) {
    if (typeof slug !== 'string' || !Object.hasOwn(config.toolkits, slug)) fail(400, 'unsupported_service', 'This service is not configured.');
    return config.toolkits[slug];
  }

  function owns(account, userID) {
    const slug = account.toolkit?.slug;
    if (typeof slug !== 'string' || !Object.hasOwn(config.toolkits, slug)) return false;
    const toolkit = config.toolkits[slug];
    return account.user_id === userID && toolkit && account.auth_config?.id === toolkit.authConfigID && account.experimental?.account_type !== 'SHARED';
  }

  async function accountFor(id, userID, active = false) {
    if (typeof id !== 'string' || !idPattern.test(id)) fail(400, 'invalid_connection', 'Invalid connection identifier.');
    const account = await upstream(`connected_accounts/${encodeURIComponent(id)}`);
    if (account.id !== id || !owns(account, userID)) fail(404, 'connection_not_found', 'Connection not found.');
    if (active && (account.status !== 'ACTIVE' || account.is_disabled || account.auth_config?.is_disabled)) fail(409, 'connection_inactive', 'Reconnect this account before using it.');
    return account;
  }

  async function identity(request) {
    const auth = header(request, 'authorization') ?? '';
    if (!/^Bearer [A-Za-z0-9_-]{43}$/.test(auth)) fail(401, 'unauthorized', 'A valid installation token is required.');
    const installation = await storage.getInstallation(hash(auth.slice(7)));
    if (!installation) fail(401, 'unauthorized', 'A valid installation token is required.');
    return installation.userID;
  }

  async function slackTool(slug, toolkit) {
    const tool = await upstream(`tools/${slug}`, { query: { version: toolkit.version } });
    if (tool.slug !== slug || tool.toolkit?.slug !== 'slack' || tool.is_deprecated || tool.version !== toolkit.version) {
      fail(400, 'tool_account_mismatch', 'The Slack operation is not available for this account version.');
    }
    return tool;
  }

  async function slackReplyIdentity(connectionID, userID) {
    try {
      const account = await accountFor(connectionID, userID, true);
      if (account.toolkit.slug !== 'slack') fail(400, 'tool_account_mismatch', 'Choose a Slack account for this reply.');
      const toolkit = service('slack'), revision = slackAccountRevision(account);
      await slackTool('SLACK_TEST_AUTH', toolkit);
      const result = await upstream('tools/execute/SLACK_TEST_AUTH', { method: 'POST', payload: {
        connected_account_id: connectionID, user_id: userID, version: toolkit.version, arguments: {} } });
      const subject = slackSubject(result);
      const after = await accountFor(connectionID, userID, true);
      if (slackAccountRevision(after) !== revision) fail(409, 'slack_identity_changed', 'The Slack account changed. Review this reply again before sending.');
      return { protocolVersion: 1, connectionID, revision, ...subject };
    } catch (error) {
      if (error instanceof HTTPError && ['invalid_connection', 'connection_not_found', 'connection_inactive', 'unsupported_service', 'tool_account_mismatch', 'slack_identity_unavailable', 'slack_identity_changed'].includes(error.code)) throw error;
      fail(409, 'slack_identity_unavailable', 'Slack identity could not be verified. Reconnect and review this reply again.');
    }
  }

  async function slackReply(userID, input) {
    validSlackReply(input);
    input.requestID = input.requestID.toLowerCase();
    const requestKey = `${userID}/${input.requestID}`;
    const fingerprint = hash(canonical({ kind: 'slack-reply-v1', ...input }));
    if (!await storage.reserveExecution(userID, input.requestID, fingerprint)) {
      let saved; try { saved = await storage.getExecution(userID, input.requestID); } catch { /* Never reclaim an unreadable reservation. */ }
      if (!saved || saved.fingerprint !== fingerprint) fail(409, saved ? 'request_mismatch' : 'execution_uncertain', 'This reply cannot be repeated; inspect its outcome first.');
      if (saved.state === 'complete') return saved.receipt;
      fail(409, activeRequests.has(requestKey) ? 'execution_pending' : 'execution_uncertain', 'This reply may already have been sent. Check its outcome before another attempt.');
    }
    activeRequests.add(requestKey);
    let effectStarted = false;
    try {
      const actual = await slackReplyIdentity(input.connectionID, userID);
      if (!sameSlackIdentity(actual, input.expectedIdentity)) fail(409, 'slack_identity_changed', 'The Slack account changed. Review this reply again before sending.');
      const toolkit = service('slack');
      await slackTool('SLACK_SEND_MESSAGE', toolkit);
      // Recheck after metadata. This is a preflight, not a Composio credential
      // lease: project administrators and provider token custody remain trusted.
      const account = await accountFor(input.connectionID, userID, true);
      if (slackAccountRevision(account) !== actual.revision) fail(409, 'slack_identity_changed', 'The Slack account changed. Review this reply again before sending.');
      const arguments_ = { channel: input.channelID, thread_ts: input.threadTS,
        blocks: [{ type: 'section', block_id: slackMarker(input.requestID), text: { type: 'plain_text', text: input.body, emoji: false } }],
        fallback_text: input.body, reply_broadcast: false, unfurl_links: false, unfurl_media: false };
      effectStarted = true;
      const result = await upstream('tools/execute/SLACK_SEND_MESSAGE', { method: 'POST', payload: {
        connected_account_id: input.connectionID, user_id: userID, version: toolkit.version, arguments: arguments_ } });
      if (!verifiedSlackReply(result, input)) fail(502, 'slack_receipt_unverified', 'Slack did not return a matching reply receipt.');
      const receipt = { status: 200, payload: { requestID: input.requestID, successful: true, data: result.data } };
      await storage.saveExecution(userID, input.requestID, { fingerprint, state: 'complete', receipt: {
        status: 200, payload: { requestID: input.requestID, successful: true, resultAvailable: false } } });
      return receipt;
    } catch (error) {
      if (effectStarted) {
        await storage.saveExecution(userID, input.requestID, { fingerprint, state: 'uncertain' });
        fail(409, 'execution_uncertain', 'This reply may already have been sent. Check its outcome before another attempt.');
      }
      // Metadata/read failures before dispatch are a verified refusal, so the
      // client need not retain a false "possibly posted" claim for this attempt.
      if (!(error instanceof HTTPError) || !['invalid_connection', 'connection_not_found', 'connection_inactive', 'unsupported_service', 'tool_account_mismatch', 'slack_identity_unavailable', 'slack_identity_changed'].includes(error.code)) {
        error = new HTTPError(409, 'slack_identity_unavailable', 'Slack identity could not be verified. Reconnect and review this reply again.');
      }
      const receipt = { status: error.status ?? 500, payload: envelope(error) };
      await storage.saveExecution(userID, input.requestID, { fingerprint, state: 'complete', receipt });
      return receipt;
    } finally { activeRequests.delete(requestKey); }
  }

  async function execution(userID, input) {
    exactKeys(input, ['tool', 'arguments', 'connectionID', 'requestID']);
    if (typeof input.tool !== 'string' || !/^[A-Z][A-Z0-9_]{1,200}$/.test(input.tool) || !object(input.arguments) || !uuidPattern.test(input.requestID ?? '') || typeof input.connectionID !== 'string' || !idPattern.test(input.connectionID)) fail(400, 'invalid_execution', 'A tool, arguments, connectionID and UUID requestID are required.');
    input.requestID = input.requestID.toLowerCase();
    const requestKey = `${userID}/${input.requestID}`;
    const fingerprint = hash(canonical(input));
    if (!await storage.reserveExecution(userID, input.requestID, fingerprint)) {
      let saved; try { saved = await storage.getExecution(userID, input.requestID); } catch { /* An unreadable reservation is never safe to replay. */ }
      if (!saved || saved.fingerprint !== fingerprint) fail(409, saved ? 'request_mismatch' : 'execution_uncertain', 'This request cannot be repeated; inspect its outcome first.');
      if (saved.state === 'complete') return saved.receipt;
      fail(409, activeRequests.has(requestKey) ? 'execution_pending' : 'execution_uncertain', 'This action may already have run. Reconcile it before another attempt.');
    }
    activeRequests.add(requestKey);
    let effectStarted = false;
    try {
      const account = await accountFor(input.connectionID, userID, true);
      const toolkit = service(account.toolkit.slug);
      const tool = await upstream(`tools/${encodeURIComponent(input.tool)}`, { query: { version: toolkit.version } });
      if (tool.slug !== input.tool || tool.toolkit?.slug !== account.toolkit.slug || tool.is_deprecated || (tool.version && tool.version !== toolkit.version)) fail(400, 'tool_account_mismatch', 'The tool does not belong to this configured account/version.');
      effectStarted = true;
      const result = await upstream(`tools/execute/${encodeURIComponent(input.tool)}`, { method: 'POST', payload: { connected_account_id: input.connectionID, user_id: userID, version: toolkit.version, arguments: input.arguments } });
      if (typeof result.successful !== 'boolean') fail(502, 'invalid_provider_response', 'Execution result was not verified.');
      const receipt = { status: 200, payload: { requestID: input.requestID, successful: result.successful, ...(result.successful ? { data: result.data ?? null } : { error: { code: 'tool_failed', message: 'The provider reported that the action failed. Inspect its state before another attempt.' } }) } };
      const { data: transientData, ...metadata } = receipt.payload;
      await storage.saveExecution(userID, input.requestID, { fingerprint, state: 'complete', receipt: { status: receipt.status, payload: { ...metadata, resultAvailable: false } } });
      return receipt;
    } catch (error) {
      if (effectStarted) {
        await storage.saveExecution(userID, input.requestID, { fingerprint, state: 'uncertain' });
        fail(409, 'execution_uncertain', 'This action may already have run. Reconcile it before another attempt.');
      }
      const receipt = { status: error.status ?? 500, payload: envelope(error) };
      await storage.saveExecution(userID, input.requestID, { fingerprint, state: 'complete', receipt });
      return receipt;
    } finally { activeRequests.delete(requestKey); }
  }

  return async request => {
    try {
      const url = new URL(request.url, 'http://localhost');
      if (request.method === 'POST' && url.pathname === '/v1/installations') {
        const input = await body(request); exactKeys(input, []);
        const bearer = token();
        await storage.createInstallation(hash(bearer), `more_${randomUUID()}`);
        return reply(201, { token: bearer });
      }
      if (request.method === 'GET' && url.pathname === '/health') return reply(200, { status: 'ok' });
      if (request.method === 'GET' && url.pathname === '/v1/oauth/callback') {
        const sessionURI = url.searchParams.get('session_uri');
        if (!sessionURI || sessionURI.length > 4096) fail(400, 'invalid_auth_session', 'Return to MORE and start a new connection.');
        const callback = new URL(config.callbackURL);
        callback.searchParams.set('session_uri', sessionURI);
        return reply(302, undefined, { Location: callback.href });
      }
      const userID = await identity(request);
      if (request.method === 'POST' && url.pathname === '/v1/voice/token') {
        const input = await body(request); exactKeys(input, []);
        const result = await morningVoiceToken(config.voice, userID);
        if (result.status === 503 && config.voice?.apiKey && config.voice?.agentID) {
          await storage.requestVoiceActivation(userID);
        }
        return reply(result.status, result.payload);
      }
      if (request.method === 'POST' && url.pathname === '/v1/voice/speech') {
        if (url.search) fail(400, 'invalid_speech', 'Use speech without extra parameters.');
        const input = await body(request); exactKeys(input, ['text', 'language', 'voiceGender']);
        const result = await morningSpeech(config.voice, userID, input);
        if (result.status === 503 && config.voice?.apiKey && config.voice?.agentID) await storage.requestVoiceActivation(userID);
        return result;
      }
      if (request.method === 'GET' && url.pathname === '/v1/slack/reply-identity') {
        if ([...url.searchParams.keys()].some(key => key !== 'connectionID') || url.searchParams.getAll('connectionID').length !== 1) {
          fail(400, 'invalid_slack_reply', 'Choose one Slack account for this reply.');
        }
        return reply(200, await slackReplyIdentity(url.searchParams.get('connectionID'), userID));
      }
      if (request.method === 'POST' && url.pathname === '/v1/slack/replies') {
        if (url.search) fail(400, 'invalid_slack_reply', 'Use the reviewed Slack reply without extra parameters.');
        const receipt = await slackReply(userID, await body(request));
        return reply(receipt.status, receipt.payload);
      }
      if (request.method === 'POST' && url.pathname === '/v1/connections/complete') {
        const input = await body(request); exactKeys(input, ['sessionURI']);
        if (typeof input.sessionURI !== 'string' || !input.sessionURI || input.sessionURI.length > 4096) fail(400, 'invalid_auth_session', 'A valid auth session is required.');
        const result = await upstream('connected_accounts/complete_auth', { method: 'POST', payload: { session_uri: input.sessionURI, user_id: userID } });
        const account = await accountFor(result.connected_account_id, userID, true);
        if (result.toolkit_slug !== account.toolkit.slug) fail(502, 'auth_identity_mismatch', 'Connection identity was not verified.');
        return reply(200, { id: account.id, service: account.toolkit.slug, status: account.status });
      }
      if (request.method === 'GET' && url.pathname === '/v1/services') return reply(200, { services: Object.entries(config.toolkits).map(([id, item]) => ({ id, name: item.name })) });
      if (request.method === 'GET' && url.pathname === '/v1/connections') {
        const accounts = await pages('connected_accounts', { user_ids: userID });
        const connections = accounts.filter(account => owns(account, userID)).map(account => ({ id: account.id, service: account.toolkit.slug, name: config.toolkits[account.toolkit.slug].name, status: account.is_disabled || account.auth_config?.is_disabled ? 'DISABLED' : account.status, ...(typeof account.alias === 'string' ? { accountLabel: account.alias } : {}) }));
        return reply(200, { connections });
      }
      if (request.method === 'POST' && url.pathname === '/v1/connections') {
        const input = await body(request); exactKeys(input, ['service', 'callbackURL']);
        const toolkit = service(input.service);
        if (!config.callbacks.includes(input.callbackURL) || input.callbackURL !== config.callbackURL) fail(400, 'invalid_callback', 'This callback URL is not allowed.');
        if (!config.publicURL) fail(503, 'auth_not_configured', 'The public OAuth callback is not configured.');
        const result = await upstream('connected_accounts/link', { method: 'POST', payload: { auth_config_id: toolkit.authConfigID, user_id: userID, callback_url: `${config.publicURL}/v1/oauth/callback` } });
        let redirect; try { redirect = new URL(result.redirect_url); } catch { fail(502, 'invalid_provider_response', 'The provider did not return an authorization URL.'); }
        if (redirect.protocol !== 'https:' || redirect.username || redirect.password) fail(502, 'invalid_provider_response', 'The provider returned an unsafe authorization URL.');
        return reply(201, { ...(result.connected_account_id ? { id: result.connected_account_id } : {}), authorizationURL: redirect.href });
      }
      if (request.method === 'DELETE' && /^\/v1\/connections\/[A-Za-z0-9_-]+$/.test(url.pathname)) {
        const id = url.pathname.split('/').at(-1); await accountFor(id, userID);
        await upstream(`connected_accounts/${encodeURIComponent(id)}`, { method: 'DELETE', query: { revoke_on_delete: true } });
        return reply(204);
      }
      if (request.method === 'GET' && url.pathname === '/v1/tools') {
        const slug = url.searchParams.get('service'); const toolkit = service(slug);
        if (catalogs) {
          let rawJSON;
          try { rawJSON = await catalogs.getCatalog(slug, toolkit.version); } catch { /* No expensive provider fallback on Workers Free. */ }
          if (typeof rawJSON !== 'string' || !rawJSON) fail(503, 'catalog_unavailable', 'This pinned catalog is not available. Ask the service owner to refresh it.');
          return { status: 200, rawJSON, headers: {} };
        }
        const tools = await loadPublicTools(config, slug);
        return reply(200, { tools });
      }
      if (request.method === 'POST' && url.pathname === '/v1/execute') {
        const receipt = await execution(userID, await body(request));
        return reply(receipt.status, receipt.payload);
      }
      fail(404, 'not_found', 'Route not found.');
    } catch (error) { return reply(error.status ?? 500, envelope(error)); }
  };
}

export async function createFetchService(config, options) {
  const handle = await createRequestHandler(config, options);
  return { async fetch(request) {
    const receipt = await handle(request);
    return new Response(receipt.audio ?? receipt.rawJSON ?? (receipt.payload === undefined ? null : JSON.stringify(receipt.payload)), { status: receipt.status, headers: { ...responseHeaders, ...receipt.headers } });
  } };
}

export async function createService(config, options) {
  const { createServer } = await import('node:http');
  const handle = await createRequestHandler(config, options);
  const server = createServer(async (request, response) => {
    const receipt = await handle(request);
    if (receipt.audio !== undefined || receipt.rawJSON !== undefined) { response.writeHead(receipt.status, { ...responseHeaders, ...receipt.headers }); response.end(receipt.audio ?? receipt.rawJSON); }
    else send(response, receipt.status, receipt.payload, receipt.headers);
  });
  server.requestTimeout = 15000;
  server.headersTimeout = 10000;
  return server;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    const config = configFromEnv();
    const server = await createService(config);
    server.listen(config.port, config.host, () => process.stdout.write(`MORE connector listening on ${config.host}:${config.port}\n`));
  } catch (error) { process.stderr.write(`Connector startup failed: ${error.message}\n`); process.exitCode = 1; }
}
