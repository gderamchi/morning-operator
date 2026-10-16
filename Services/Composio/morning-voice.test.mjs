import test from 'node:test';
import assert from 'node:assert/strict';
import { morningVoiceToken } from './morning-voice.mjs';

const config = { apiKey: 'server-only-synthetic-key', agentID: 'synthetic-agent', installations: ['synthetic-owner'] };

test('voice refuses unconfigured and unapproved installations before contacting ElevenLabs', async () => {
  let calls = 0;
  const fetcher = async () => { calls++; throw new Error('Unexpected request'); };
  for (const [value, owner] of [[undefined, 'synthetic-owner'], [config, 'other-installation']]) {
    assert.equal((await morningVoiceToken(value, owner, fetcher)).status, 503);
  }
  assert.equal(calls, 0);
});

test('voice requests only the fixed private agent and returns only the ephemeral token', async () => {
  const result = await morningVoiceToken(config, 'synthetic-owner', async (url, request) => {
    assert.equal(url.origin, 'https://api.elevenlabs.io');
    assert.equal(url.pathname, '/v1/convai/conversation/token');
    assert.equal(url.searchParams.get('agent_id'), config.agentID);
    assert.equal(request.headers['xi-api-key'], config.apiKey);
    assert.equal(request.redirect, 'manual');
    assert.equal(request.body, undefined);
    return Response.json({ token: 'synthetic-ephemeral', conversation_id: 'private-provider-session', extra: 'private' });
  });
  assert.deepEqual(result, { status: 200, payload: { conversationToken: 'synthetic-ephemeral' } });
});

test('voice failures never expose provider bodies or secrets', async () => {
  for (const response of [new Response(null, { status: 302, headers: { Location: 'https://untrusted.example' } }), new Response('private-provider-body', { status: 401 }), Response.json({ token: '' }), Response.json({ token: 'x'.repeat(65_537) }), new Response('invalid-json')]) {
    const result = await morningVoiceToken(config, 'synthetic-owner', async () => response);
    assert.equal(result.status, 502);
    assert.ok(!JSON.stringify(result).includes('private-provider-body'));
    assert.ok(!JSON.stringify(result).includes(config.apiKey));
  }
  assert.equal((await morningVoiceToken(config, 'synthetic-owner', async () => { throw new Error('private-key'); })).status, 502);
});
