// Default: backend metadata only. --execute performs the reviewed read allowlist
// once, without retries, OAuth creation, installation creation or provider writes.
// Supply MORE_SMOKE_BASE_URL and MORE_SMOKE_TOKEN (or MORE_SMOKE_TOKEN_FILE).
// Tokens, account IDs, account labels and provider results are never printed.
import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';

export const readPlans = {
  gmail: { tool: 'GMAIL_GET_PROFILE', arguments: { user_id: 'me' }, field: 'emailAddress' },
  googlecalendar: { tool: 'GOOGLECALENDAR_GET_CURRENT_USER', arguments: {}, field: 'primary_calendar_id' },
  outlook: { tool: 'OUTLOOK_GET_PROFILE', arguments: { user_id: 'me', select: ['id'], include_proxy_addresses: false }, field: 'id' },
  googledrive: { tool: 'GOOGLEDRIVE_GET_ABOUT', arguments: { fields: 'kind' }, field: 'kind' },
  googledocs: { tool: 'GOOGLEDOCS_SEARCH_DOCUMENTS', arguments: { max_results: 1, response_detail: 'minimal', include_shared_drives: false, include_trashed: false }, array: 'files', coverage: 'discovery' },
  googlesheets: { tool: 'GOOGLESHEETS_SEARCH_SPREADSHEETS', arguments: { max_results: 1, include_shared_drives: false, include_trashed: false }, array: 'spreadsheets', coverage: 'discovery' },
  notion: { tool: 'NOTION_SEARCH_NOTION_PAGE', arguments: { page_size: 1, filter_value: 'page', filter_properties: ['title'] }, array: 'results' },
  slack: { tool: 'SLACK_TEST_AUTH', arguments: {}, boolean: 'ok' },
  calendly: { tool: 'CALENDLY_GET_USER', arguments: { uuid: 'me' }, object: 'resource', objectField: 'uri' },
  instagram: { tool: 'INSTAGRAM_GET_USER_INFO', arguments: { ig_user_id: 'me', fields: 'id,account_type' }, field: 'id' },
  whatsapp: { tool: 'WHATSAPP_GET_BUSINESS_ACCOUNT_DETAILS', arguments: { fields: 'id,name' }, field: 'id' },
  linkedin: { tool: 'LINKEDIN_GET_MY_INFO', arguments: {}, field: 'id' },
  discord: { tool: 'DISCORD_GET_MY_USER', arguments: {}, field: 'id' },
  // The provider default includes page access tokens. Always project id only.
  facebook: { tool: 'FACEBOOK_LIST_MANAGED_PAGES', arguments: { user_id: 'me', fields: 'id', limit: 1 }, array: 'data' },
};

const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const safeCode = value => typeof value === 'string' && /^[a-z_]{1,80}$/.test(value) ? value : 'unverified_response';

export function argumentsMatch(schema, args) {
  if (!object(schema) || schema.type !== 'object' || !object(schema.properties) || !object(args)) return false;
  // This checks the primitive/array subset used by the fixed read plans. Stop if
  // a future catalog replaces it with a schema requiring unsupported resolution.
  const match = (rule, value) => {
    if (!object(rule) || ['$ref', 'allOf', 'oneOf', 'not', 'if', 'pattern', 'format'].some(key => Object.hasOwn(rule, key))) return false;
    if (rule.anyOf) return Array.isArray(rule.anyOf) && rule.anyOf.some(variant => match({ ...rule, anyOf: undefined, ...variant }, value));
    if (!['string', 'boolean', 'integer', 'number', 'array'].includes(rule.type)) return false;
    if (!(rule.type === 'array' ? Array.isArray(value) : rule.type === 'integer' ? Number.isInteger(value) : rule.type === 'number' ? Number.isFinite(value) : typeof value === rule.type)) return false;
    if (rule.enum && (!Array.isArray(rule.enum) || !rule.enum.includes(value))) return false;
    if (typeof value === 'number' && ((rule.minimum !== undefined && value < rule.minimum) || (rule.maximum !== undefined && value > rule.maximum) || (rule.exclusiveMinimum !== undefined && value <= rule.exclusiveMinimum) || (rule.exclusiveMaximum !== undefined && value >= rule.exclusiveMaximum))) return false;
    if (typeof value === 'string' && ((rule.minLength !== undefined && [...value].length < rule.minLength) || (rule.maxLength !== undefined && [...value].length > rule.maxLength))) return false;
    if (Array.isArray(value) && ((rule.minItems !== undefined && value.length < rule.minItems) || (rule.maxItems !== undefined && value.length > rule.maxItems) || !object(rule.items) || !value.every(item => match(rule.items, item)))) return false;
    return true;
  };
  if (schema.required !== undefined && !Array.isArray(schema.required)) return false;
  if ((schema.required ?? []).some(name => !Object.hasOwn(args, name))) return false;
  return Object.entries(args).every(([name, value]) => match(schema.properties[name], value));
}

export function resultShape(plan, data) {
  for (let depth = 0; depth < 5 && object(data); depth++, data = data.data) {
    if (data.successful === false || data.ok === false || (data.error !== undefined && data.error !== null && data.error !== '')) return 'provider_failure';
    if (Object.hasOwn(data, 'successful')) {
      if (data.successful !== true || !object(data.data)) return 'unverified';
      continue;
    }
    if (plan.array && Array.isArray(data[plan.array])) {
      const count = data[plan.array].length;
      const maximum = plan.arguments?.max_results ?? plan.arguments?.page_size ?? plan.arguments?.limit;
      if ((maximum !== undefined && count > maximum) || !data[plan.array].every(item => object(item) && typeof item.id === 'string' && item.id.length)) return 'unverified';
      return count ? 'nonempty' : 'empty';
    }
    if (plan.field && typeof data[plan.field] === 'string' && data[plan.field].length) return 'verified';
    if (plan.boolean && data[plan.boolean] === true) return 'verified';
    if (plan.object && object(data[plan.object]) && typeof data[plan.object][plan.objectField] === 'string' && data[plan.object][plan.objectField].length) return 'verified';
  }
  return 'unverified';
}

export async function main() {
  const flags = process.argv.slice(2);
  if (flags.some(flag => flag !== '--execute')) throw new Error('unsupported_option');
  const execute = flags.includes('--execute');
  const base = new URL(process.env.MORE_SMOKE_BASE_URL ?? process.env.MORE_PUBLIC_BASE_URL ?? '');
  if (base.protocol !== 'https:' || base.username || base.password || base.pathname !== '/' || base.search || base.hash) throw new Error('https_origin_required');
  const token = process.env.MORE_SMOKE_TOKEN ?? (process.env.MORE_SMOKE_TOKEN_FILE ? (await readFile(process.env.MORE_SMOKE_TOKEN_FILE, 'utf8')).trim() : '');
  if (!/^[A-Za-z0-9_-]{43}$/.test(token)) throw new Error('installation_token_required');
  async function api(path, body) {
    const response = await fetch(new URL(path, base), { method: body ? 'POST' : 'GET', headers: { Authorization: `Bearer ${token}`, ...(body ? { 'Content-Type': 'application/json' } : {}) }, body: body ? JSON.stringify(body) : undefined, redirect: 'manual', signal: AbortSignal.timeout(30000) });
    let value;
    try { value = await response.json(); } catch { throw new Error('invalid_backend_response'); }
    if (!response.ok) throw new Error(safeCode(value?.error?.code));
    return value;
  }
  const services = await api('/v1/services');
  const connections = await api('/v1/connections');
  if (!Array.isArray(services.services) || !Array.isArray(connections.connections)) throw new Error('invalid_backend_response');
  let failed = false;
  for (const { id: service } of services.services) {
    const plan = Object.hasOwn(readPlans, service) ? readPlans[service] : null;
    if (!plan) { if (execute) failed = true; process.stdout.write(`${JSON.stringify({ service: 'unplanned_service', status: 'skipped' })}\n`); continue; }
    const active = connections.connections.filter(account => account.service === service && account.status === 'ACTIVE');
    let requestID;
    try {
      const catalog = await api(`/v1/tools?service=${encodeURIComponent(service)}`);
      const tool = catalog.tools?.find(item => item.slug === plan.tool);
      if (!tool || !argumentsMatch(tool.inputSchema, plan.arguments)) throw new Error('live_schema_mismatch');
      const report = { service, tool: plan.tool, activeAccounts: active.length, schemaVerified: true, coverage: plan.coverage ?? 'bounded_read' };
      if (!execute || active.length !== 1) {
        if (execute) failed = true;
        process.stdout.write(`${JSON.stringify({ ...report, status: !execute ? 'plan_only' : active.length ? 'account_selection_required' : 'not_connected' })}\n`);
        continue;
      }
      requestID = randomUUID();
      const result = await api('/v1/execute', { tool: plan.tool, arguments: plan.arguments, connectionID: active[0].id, requestID });
      const shape = resultShape(plan, result.data);
      const verified = result.requestID === requestID && result.successful === true && ['verified', 'empty', 'nonempty'].includes(shape);
      if (!verified) failed = true;
      process.stdout.write(`${JSON.stringify({ ...report, status: verified ? 'read_verified' : 'read_unverified', shape, requestID })}\n`);
    } catch (error) {
      failed = true;
      process.stdout.write(`${JSON.stringify({ service, tool: plan.tool, status: 'stopped_without_retry', code: safeCode(error.message), ...(requestID ? { requestID } : {}) })}\n`);
    }
  }
  if (failed) process.exitCode = 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch(error => { process.stderr.write(`${JSON.stringify({ status: 'stopped', code: safeCode(error.message) })}\n`); process.exitCode = 1; });
}
