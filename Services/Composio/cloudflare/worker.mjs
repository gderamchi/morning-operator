import { createHash } from 'node:crypto';
import { configFromEnv, createFetchService } from '../server.mjs';
import { D1Storage } from './storage.mjs';

// Production validation evaluates this module before runtime D1 bindings exist.
// Initialize from the actual fetch bindings, then keep one router per isolate.
let handlerPromise;
async function handlerFor(bindings) {
  if (!handlerPromise) {
    const storage = new D1Storage(bindings.DB);
    handlerPromise = createFetchService(configFromEnv(bindings), { storage, catalogs: storage })
      .catch(error => { handlerPromise = undefined; throw error; });
  }
  return handlerPromise;
}
const digest = value => createHash('sha256').update(value).digest('hex');
const rejected = (status, code, message) => Response.json({ error: { code, message } }, { status, headers: { 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer', ...(status === 429 ? { 'Retry-After': '60' } : {}) } });

export default {
  async fetch(request, bindings, context) {
    const path = new URL(request.url).pathname;
    if (path !== '/health') {
      // Counters are approximate and local to an edge location. They limit abuse;
      // only the atomic D1 reservation decides whether an effect may be sent.
      const enrollment = request.method === 'POST' && path === '/v1/installations';
      const limiter = enrollment ? bindings.ENROLLMENT_LIMITER : bindings.REQUEST_LIMITER;
      const actor = enrollment ? null : request.headers.get('Authorization');
      const key = digest(actor || `anonymous:${request.headers.get('CF-Connecting-IP') ?? 'unknown'}`);
      try {
        if (!limiter || typeof limiter.limit !== 'function') throw new Error('Missing rate limit binding.');
        if (!(await limiter.limit({ key })).success) return rejected(429, 'rate_limited', 'Too many requests. Wait before trying again.');
      } catch { return rejected(503, 'rate_limit_unavailable', 'The request limit could not be verified.'); }
    }
    let handler;
    try { handler = await handlerFor(bindings); }
    catch { return rejected(503, 'service_not_configured', 'The connector runtime could not be initialized.'); }
    return handler.fetch(request, bindings, context);
  },
};
