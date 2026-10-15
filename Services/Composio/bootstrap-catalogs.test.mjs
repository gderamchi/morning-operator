import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtemp, mkdir, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const script = fileURLToPath(new URL('./cloudflare/bootstrap-catalogs.mjs', import.meta.url));
async function fixture(t, version = '20261001_00') {
  const directory = await mkdtemp(join(tmpdir(), 'more-public-catalog-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const cli = join(directory, 'node_modules/.bin/wrangler');
  await mkdir(dirname(cli), { recursive: true });
  await writeFile(cli, '#!/usr/bin/env node\nconsole.log(JSON.stringify(process.argv[2]==="auth"?{type:"oauth",token:"synthetic-cloudflare-token"}:{accounts:[{id:"a".repeat(32)}]}));\n', { mode: 0o700 });
  await writeFile(join(directory, 'wrangler.jsonc'), JSON.stringify({ account_id: 'a'.repeat(32), d1_databases: [{ binding: 'DB', database_id: '11111111-2222-4333-8444-555555555555' }] }));
  const payload = JSON.stringify({ tools: [{ slug: 'GMAIL_READ_PUBLIC_SCHEMA', name: 'Public tool', description: 'public-definition-'.repeat(12000), inputSchema: { type: 'object', properties: {} } }] });
  await writeFile(join(directory, 'snapshot.json'), JSON.stringify([{ slug: 'gmail', version, payload }]));
  await writeFile(join(directory, 'mock.mjs'), `import assert from 'node:assert/strict';
globalThis.fetch = async (url, options) => {
  assert.equal(url, 'https://api.cloudflare.com/client/v4/accounts/' + 'a'.repeat(32) + '/d1/database/11111111-2222-4333-8444-555555555555/query');
  assert.equal(options.headers.Authorization, 'Bearer synthetic-cloudflare-token');
  const body = JSON.parse(options.body);
  assert.ok(body.sql.length < 1000 && !body.sql.includes('public-definition'));
  assert.equal(body.params[0], 'gmail'); assert.equal(body.params[1], '20261001_00');
  assert.ok(body.params[2].length > 100000);
  assert.equal(JSON.parse(body.params[2]).tools[0].slug, 'GMAIL_READ_PUBLIC_SCHEMA');
  return Response.json({ success:true, result:[{success:true}] });
};`);
  return { directory, env: { ...process.env, COMPOSIO_API_KEY: 'synthetic-composio-key', COMPOSIO_TOOLKITS_JSON: JSON.stringify({ gmail: { name: 'Gmail', authConfigID: 'ac_synthetic', version: '20261001_00' } }) } };
}

test('catalog bootstrap applies large public JSON as a parameter and keeps credentials out of output', async t => {
  const f = await fixture(t);
  const output = execFileSync(process.execPath, ['--import', './mock.mjs', script, '--apply', 'snapshot.json'], { cwd: f.directory, env: f.env, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  assert.match(output, /"applied":1/);
  assert.ok(!output.includes('synthetic-cloudflare-token') && !output.includes('synthetic-composio-key') && !output.includes('public-definition'));
});

test('catalog bootstrap rejects a stale pin before obtaining OAuth or writing remote data', async t => {
  const f = await fixture(t, '20260901_00');
  assert.throws(() => execFileSync(process.execPath, ['--import', './mock.mjs', script, '--apply', 'snapshot.json'], { cwd: f.directory, env: f.env, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }), error => {
    assert.equal(error.status, 1);
    assert.match(String(error.stderr), /snapshot_validation/);
    assert.ok(!String(error.stderr).includes('synthetic-'));
    return true;
  });
});
