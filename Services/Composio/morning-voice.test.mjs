import test from 'node:test';
import assert from 'node:assert/strict';
import { morningSpeech, morningVoiceToken } from './morning-voice.mjs';

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

const speechInput = { text: 'Synthetic morning.', language: 'en', voiceGender: 'female' };
const mp3 = Uint8Array.from([0x49, 0x44, 0x33, 4, 0, 0]);
const audioResponse = () => new Response(mp3, { headers: { 'Content-Type': 'audio/mpeg' } });

test('speech is gated by the same private installation allowlist and validates bounded exact input', async () => {
  let calls = 0;
  const fetcher = async () => { calls++; return audioResponse(); };
  assert.equal((await morningSpeech(config, 'another-owner', speechInput, fetcher)).status, 503);
  assert.equal((await morningSpeech(undefined, 'synthetic-owner', speechInput, fetcher)).status, 503);
  for (const input of [null, {}, { ...speechInput, voice_id: 'arbitrary' }, { ...speechInput, language: 'de' }, { ...speechInput, voiceGender: 'other' }, { ...speechInput, text: '' }, { ...speechInput, text: '  ' }, { ...speechInput, text: '\u0000' }, { ...speechInput, text: 'é'.repeat(16385) }]) {
    assert.equal((await morningSpeech(config, 'synthetic-owner', input, fetcher)).status, 400);
  }
  assert.equal(calls, 0);
});

test('speech fixes voices/model/output and disables provider logging for both genders and languages', async () => {
  for (const language of ['fr', 'en']) for (const voiceGender of ['male', 'female']) {
    const input = { ...speechInput, language, voiceGender, text: 'é'.repeat(16384) };
    const result = await morningSpeech(config, 'synthetic-owner', input, async (url, request) => {
      assert.equal(url.origin, 'https://api.elevenlabs.io');
      assert.equal(url.pathname, '/v1/text-to-speech/' + (voiceGender === 'male' ? 'CwhRBWXzGAHq8TQ4Fs17' : 'EXAVITQu4vr4xnSDxMaL'));
      assert.equal(url.searchParams.get('enable_logging'), 'false');
      assert.equal(url.searchParams.get('output_format'), 'mp3_44100_128');
      assert.equal(request.method, 'POST');
      assert.equal(request.redirect, 'manual');
      assert.equal(request.headers['xi-api-key'], config.apiKey);
      assert.equal(request.headers.Accept, 'audio/mpeg');
      assert.deepEqual(JSON.parse(request.body), { text: input.text, model_id: 'eleven_turbo_v2_5', language_code: language });
      return audioResponse();
    });
    assert.equal(result.status, 200);
    assert.deepEqual([...result.audio], [...mp3]);
    assert.equal(result.headers['Content-Type'], 'audio/mpeg');
    assert.equal(result.payload, undefined);
  }
});

test('speech provider errors and redirects fail closed without retrying with logging enabled', async () => {
  for (const response of [new Response('private-provider-body', { status: 403 }), new Response(null, { status: 302 }), Response.json({ secret: config.apiKey }), new Response('', { headers: { 'Content-Type': 'audio/mpeg' } }), new Response('not-an-mp3', { headers: { 'Content-Type': 'audio/mpeg' } }), new Response(mp3, { headers: { 'Content-Type': 'audio/mpeg', 'Content-Length': '8388609' } }), new Response(new Uint8Array(8388609), { headers: { 'Content-Type': 'audio/mpeg' } })]) {
    let calls = 0;
    const result = await morningSpeech(config, 'synthetic-owner', speechInput, async () => { calls++; return response; });
    assert.equal(result.status, 502);
    assert.equal(calls, 1);
    assert.ok(!JSON.stringify(result).includes('private-provider-body'));
    assert.ok(!JSON.stringify(result).includes(config.apiKey));
  }
});

test('speech deadline bounds both provider headers and a stream that ignores abort', async () => {
  for (const fetcher of [async () => new Promise(() => {}), async () => new Response(new ReadableStream({ start() {} }), { headers: { 'Content-Type': 'audio/mpeg' } })]) {
    const start = Date.now();
    const result = await morningSpeech(config, 'synthetic-owner', speechInput, fetcher, 20);
    assert.equal(result.status, 502);
    assert.ok(Date.now() - start < 1000);
  }
});
