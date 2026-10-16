import { Buffer } from 'node:buffer';

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
