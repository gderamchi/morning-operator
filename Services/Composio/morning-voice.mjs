import { Buffer } from 'node:buffer';

const speechVoices = { male: 'CwhRBWXzGAHq8TQ4Fs17', female: 'EXAVITQu4vr4xnSDxMaL' };
const speechFailure = () => ({ status: 502, payload: { error: { code: 'speech_unavailable', message: 'Online speech is unavailable. Use the device voice or try again shortly.' } } });

// This route synthesizes only the text explicitly selected by the app. It has
// no conversation, microphone, tools or business-effect execution journal.
export async function morningSpeech(config, userID, input, fetcher = fetch, deadlineMS = 20_000) {
  if (!config?.apiKey || !config?.agentID || !config.installations?.includes(userID)) {
    return { status: 503, payload: { error: { code: 'voice_not_configured', message: 'Online speech is not activated for this installation yet.' } } };
  }
  if (!input || Object.keys(input).sort().join(',') !== 'language,text,voiceGender' ||
      typeof input.text !== 'string' || !input.text.trim() || Buffer.byteLength(input.text, 'utf8') > 32_768 ||
      /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/u.test(input.text) ||
      !['fr', 'en'].includes(input.language) || !['male', 'female'].includes(input.voiceGender)) {
    return { status: 400, payload: { error: { code: 'invalid_speech', message: 'Choose French or English, a voice and at most 32 KiB of text.' } } };
  }
  const controller = new AbortController();
  let reader, timer;
  try {
    const deadline = new Promise((_, reject) => {
      timer = setTimeout(() => { controller.abort(); reject(new Error('Speech deadline')); }, deadlineMS);
    });
    const operation = (async () => {
      const url = new URL(`https://api.elevenlabs.io/v1/text-to-speech/${speechVoices[input.voiceGender]}`);
      url.searchParams.set('output_format', 'mp3_44100_128');
      url.searchParams.set('enable_logging', 'false');
      const response = await fetcher(url, {
        method: 'POST', headers: { 'xi-api-key': config.apiKey, 'Content-Type': 'application/json', Accept: 'audio/mpeg' },
        body: JSON.stringify({ text: input.text, model_id: 'eleven_turbo_v2_5', language_code: input.language }),
        redirect: 'manual', signal: controller.signal,
      });
      if (controller.signal.aborted) throw new Error('Speech deadline');
      if (!response.ok || !response.body || response.headers.get('content-type')?.split(';')[0].trim().toLowerCase() !== 'audio/mpeg') throw new Error('Speech unavailable');
      const maximum = 8_388_608;
      const declaredLength = response.headers.get('content-length');
      if (declaredLength !== null && (!/^\d+$/.test(declaredLength) || Number(declaredLength) > maximum)) throw new Error('Speech response too large');
      reader = response.body.getReader();
      const chunks = []; let length = 0;
      while (true) {
        const { done, value } = await reader.read();
        if (controller.signal.aborted) throw new Error('Speech deadline');
        if (done) break;
        length += value.byteLength;
        if (length > maximum) throw new Error('Speech response too large');
        chunks.push(value);
      }
      const audio = Buffer.concat(chunks);
      if (audio.length < 3 || !(audio.subarray(0, 3).toString('ascii') === 'ID3' || (audio[0] === 0xff && (audio[1] & 0xe0) === 0xe0))) throw new Error('Invalid MPEG audio');
      return { status: 200, audio, headers: { 'Content-Type': 'audio/mpeg', 'Content-Length': String(audio.length) } };
    })();
    return await Promise.race([operation, deadline]);
  } catch {
    // Never expose provider bodies or retry without enable_logging=false.
    return speechFailure();
  } finally {
    clearTimeout(timer); controller.abort();
    // A provider stream may ignore abort; cancellation must not extend the deadline.
    if (reader) void reader.cancel().catch(() => {});
  }
}

// Long-lived credentials stay on the server. The mobile app receives one WebRTC token.
export async function morningVoiceToken(config, userID, fetcher = fetch) {
  if (!config?.apiKey || !config?.agentID || !config.installations?.includes(userID)) {
    return { status: 503, payload: { error: { code: 'voice_not_configured', message: 'ElevenLabs conversation is not activated for this installation yet.' } } };
  }
  try {
    const url = new URL('https://api.elevenlabs.io/v1/convai/conversation/token');
    url.searchParams.set('agent_id', config.agentID);
    const response = await fetcher(url, {
      method: 'GET', headers: { 'xi-api-key': config.apiKey },
      redirect: 'manual', signal: AbortSignal.timeout(10_000),
    });
    if (!response.ok || !response.body) throw new Error('Voice token unavailable');
    const reader = response.body.getReader();
    const chunks = []; let length = 0;
    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        length += value.byteLength;
        if (length > 65_536) throw new Error('Voice token response too large');
        chunks.push(value);
      }
    } finally { await reader.cancel().catch(() => {}); }
    const data = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    if (typeof data.token !== 'string' || !data.token || data.token.length > 32_768) throw new Error('Invalid voice token');
    return { status: 200, payload: { conversationToken: data.token } };
  } catch {
    // Provider failures can contain private agent configuration or credentials.
    return { status: 502, payload: { error: { code: 'voice_unavailable', message: 'ElevenLabs could not open the conversation. Try again shortly.' } } };
  }
}
