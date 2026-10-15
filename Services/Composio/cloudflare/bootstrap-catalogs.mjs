import { execFileSync } from 'node:child_process';
import { mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { configFromEnv, loadPublicTools } from '../server.mjs';

// Preparation only calls Composio GET /tools. Applying requires the explicit
// --apply switch and writes public definitions to the existing D1 database.
// Parameterized D1 queries avoid its 100 KB SQL-statement limit.
const [mode, argument] = process.argv.slice(2);
const path = resolve(argument ?? '.wrangler/public-catalogs.json');
let stage = 'configuration';
try {
  if (mode && !['--output', '--apply'].includes(mode)) throw new Error();
  const config = configFromEnv();
  const slugs = Object.keys(config.toolkits);
  if (!slugs.length) throw new Error();
  if (mode !== '--apply') {
    stage = 'catalog_preparation';
    const catalogs = [];
    for (const slug of slugs) {
      const tools = await loadPublicTools(config, slug);
      const payload = JSON.stringify({ tools });
      const bytes = Buffer.byteLength(payload);
      if (!tools.length || bytes > 1900000) throw new Error();
      catalogs.push({ slug, version: config.toolkits[slug].version, payload });
      process.stdout.write(`${JSON.stringify({ service: slug, tools: tools.length, bytes })}\n`);
    }
    await mkdir(dirname(path), { recursive: true, mode: 0o700 });
    await writeFile(`${path}.tmp`, JSON.stringify(catalogs), { mode: 0o600 });
    await rename(`${path}.tmp`, path);
    process.stdout.write(`${JSON.stringify({ prepared: catalogs.length, snapshot: path, remoteWrites: 0 })}\n`);
  } else {
    stage = 'snapshot_validation';
    const catalogs = JSON.parse(await readFile(path, 'utf8'));
    const seen = new Set();
    if (!Array.isArray(catalogs) || catalogs.length !== slugs.length) throw new Error();
    for (const item of catalogs) {
      if (!item || !Object.hasOwn(config.toolkits, item.slug) || item.version !== config.toolkits[item.slug].version || seen.has(item.slug) || typeof item.payload !== 'string' || Buffer.byteLength(item.payload) > 1900000) throw new Error();
      const content = JSON.parse(item.payload);
      if (Object.keys(content).length !== 1 || !Array.isArray(content.tools) || !content.tools.length || content.tools.some(tool => !tool || Object.keys(tool).some(key => !['slug', 'name', 'description', 'inputSchema'].includes(key)) || typeof tool.slug !== 'string' || typeof tool.name !== 'string' || typeof tool.description !== 'string' || tool.inputSchema?.type !== 'object')) throw new Error();
      seen.add(item.slug);
    }
    stage = 'cloudflare_authentication';
    const childEnv = { ...process.env, WRANGLER_SEND_METRICS: 'false' }; delete childEnv.WRANGLER_LOG;
    const cli = resolve('node_modules/.bin/wrangler');
    const cliJSON = args => JSON.parse(execFileSync(cli, args, { encoding: 'utf8', env: childEnv, stdio: ['ignore', 'pipe', 'pipe'], timeout: 20000 }).trim());
    const auth = cliJSON(['auth', 'token', '--json']);
    if (!['oauth', 'api_token'].includes(auth.type) || !auth.token) throw new Error();
    const wrangler = JSON.parse(await readFile('wrangler.jsonc', 'utf8'));
    const identity = cliJSON(['whoami', '--json']);
    const accountID = wrangler.account_id ?? (identity.accounts?.length === 1 ? identity.accounts[0].id : null);
    const databaseID = wrangler.d1_databases?.find(database => database.binding === 'DB')?.database_id;
    if (!/^[a-f0-9]{32}$/.test(accountID ?? '') || !/^[a-f0-9-]{36}$/.test(databaseID ?? '')) throw new Error();
    stage = 'catalog_apply';
    for (const item of catalogs) {
      const response = await fetch(`https://api.cloudflare.com/client/v4/accounts/${accountID}/d1/database/${databaseID}/query`, {
        method: 'POST', headers: { Authorization: `Bearer ${auth.token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ sql: 'INSERT INTO public_catalogs (toolkit_slug, toolkit_version, payload_json) VALUES (?, ?, ?) ON CONFLICT (toolkit_slug, toolkit_version) DO UPDATE SET payload_json = excluded.payload_json', params: [item.slug, item.version, item.payload] }),
        signal: AbortSignal.timeout(30000), redirect: 'manual',
      });
      const result = await response.json();
      if (!response.ok || result.success !== true || result.result?.[0]?.success !== true) throw new Error();
      process.stdout.write(`${JSON.stringify({ service: item.slug, applied: true })}\n`);
    }
    process.stdout.write(`${JSON.stringify({ applied: catalogs.length })}\n`);
  }
} catch {
  process.stderr.write(`${JSON.stringify({ successful: false, stage, privateDetailsOmitted: true })}\n`);
  process.exitCode = 1;
}
