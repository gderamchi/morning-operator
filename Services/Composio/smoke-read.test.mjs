import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { argumentsMatch, readPlans, resultShape } from './smoke-read.mjs';

test('smoke argument checks reject changed array items, required fields and unsupported schema constructs', () => {
  const schema = { type: 'object', required: ['select'], properties: {
    select: { anyOf: [{ type: 'array', items: { type: 'string', minLength: 1 } }, { type: 'string', minLength: 1 }] },
    count: { type: 'integer', minimum: 1, maximum: 2 },
  } };
  assert.equal(argumentsMatch(schema, { select: ['id'], count: 1 }), true);
  assert.equal(argumentsMatch(schema, { select: [1] }), false);
  assert.equal(argumentsMatch(schema, { select: [''] }), false);
  assert.equal(argumentsMatch(schema, { select: 'id', count: 3 }), false);
  assert.equal(argumentsMatch(schema, {}), false);
  assert.equal(argumentsMatch(schema, { select: 'id', unexpected: true }), false);
  assert.equal(argumentsMatch({ type: 'object', properties: { select: { $ref: '#/$defs/Selection' } } }, { select: 'id' }), false);
});

test('smoke results distinguish wrapped successful reads from provider failures and empty receipts', () => {
  assert.equal(resultShape(readPlans.gmail, { data: { successful: true, data: { emailAddress: 'synthetic@example.test' } } }), 'verified');
  assert.equal(resultShape(readPlans.outlook, { id: 'wrapper-id', successful: true, data: { successful: false } }), 'provider_failure');
  assert.equal(resultShape(readPlans.outlook, { successful: true, data: {} }), 'unverified');
  assert.equal(resultShape(readPlans.slack, { ok: false, error: 'missing_scope' }), 'provider_failure');
  assert.equal(resultShape(readPlans.slack, { ok: true }), 'verified');
  assert.equal(resultShape(readPlans.calendly, { resource: {} }), 'unverified');
  assert.equal(resultShape(readPlans.calendly, { resource: { uri: 'https://api.calendly.com/users/synthetic' } }), 'verified');
});

test('bounded list smoke accepts empty lists but rejects oversized and malformed records', () => {
  assert.equal(resultShape(readPlans.facebook, { successful: true, data: { data: [] } }), 'empty');
  assert.equal(resultShape(readPlans.googledocs, { files: [{ id: 'synthetic-file' }] }), 'nonempty');
  assert.equal(resultShape(readPlans.googlesheets, { spreadsheets: [null] }), 'unverified');
  assert.equal(resultShape(readPlans.notion, { results: [{ id: 'one' }, { id: 'two' }] }), 'unverified');
});

test('execute smoke exits unsuccessfully when accounts are absent or ambiguous, without any execution request', () => {
  for (const count of [0, 2]) {
    const source = `
      import { main } from ${JSON.stringify(new URL('./smoke-read.mjs', import.meta.url).href)};
      process.argv = ['node', 'synthetic-smoke', '--execute'];
      globalThis.fetch = async (url, options) => {
        if (options.method !== 'GET') throw new Error('unexpected_execution');
        const path = new URL(url).pathname;
        const payload = path === '/v1/services' ? { services: [{ id: 'gmail' }] }
          : path === '/v1/connections' ? { connections: Array.from({length: ${count}}, () => ({ service: 'gmail', status: 'ACTIVE' })) }
          : { tools: [{ slug: 'GMAIL_GET_PROFILE', inputSchema: { type: 'object', properties: { user_id: { type: 'string' } } } }] };
        return Response.json(payload);
      };
      await main();
    `;
    const result = spawnSync(process.execPath, ['--input-type=module', '-e', source], { encoding: 'utf8', env: { MORE_SMOKE_BASE_URL: 'https://smoke.example', MORE_SMOKE_TOKEN: 'a'.repeat(43) } });
    assert.equal(result.status, 1);
    assert.equal(result.stderr, '');
    assert.equal(JSON.parse(result.stdout).status, count === 0 ? 'not_connected' : 'account_selection_required');
  }
});
