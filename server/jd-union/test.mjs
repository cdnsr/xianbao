import crypto from 'node:crypto';
import worker, { md5, signatureBase, REQUEST_PROFILES } from './index.js';

const METHOD_EXPECT = 'jd.union.open.promotion.bysubunionid.get';
const ENV = { JD_APP_KEY: 'ak_test', JD_APP_SECRET: 'secret_test', JD_SITE_ID: 'site_123', APP_TOKEN: 'tok' };
let captured = null;
let reply = null;
let replyQueue = [];

globalThis.fetch = async (url, init) => {
  captured = { url, rawBody: init.body, body: Object.fromEntries(new URLSearchParams(init.body)) };
  const body = replyQueue.length ? replyQueue.shift() : reply;
  return { status: 200, text: async () => body };
};

let fail = 0;
const check = (label, cond, extra = '') => {
  if (!cond) fail++;
  console.log(`${cond ? 'PASS' : 'FAIL'} ${label}${extra ? ' :: ' + extra : ''}`);
};
const call = async (qs, env = ENV) => {
  const res = await worker.fetch(new Request('https://w.dev/?' + qs), env);
  return { status: res.status, body: JSON.parse(await res.text()) };
};

// --- guard rails ---
check('401 without token', (await call('url=https://item.jd.com/1.html')).status === 401);
check('400 without url', (await call('token=tok')).status === 400);
check('400 when url is not http', (await call('token=tok&url=ftp://x')).status === 400);
check('500 when secrets missing', (await call('token=tok&url=https://item.jd.com/1.html', { APP_TOKEN: 'tok' })).status === 500);

// --- success path, JD's nested "result as JSON string" shape ---
reply = JSON.stringify({
  jd_union_open_promotion_bysubunionid_get_responce: {
    code: '0',
    result: JSON.stringify({ code: 200, data: { clickURL: 'https://u.jd.com/mycode' } }),
  },
});
captured = null;
let r = await call('token=tok&url=https://item.jd.com/100288670988.html');
check('200 on success', r.status === 200, JSON.stringify(r.body));
check('returns clickURL', r.body.url === 'https://u.jd.com/mycode');

// --- the outgoing request must be correctly signed and shaped ---
const sent = captured.body;
check('posts to the gateway the API doc specifies', captured.url === 'https://api.jd.com/routerjson', captured.url);
check('omits sign_method by default (not in the doc param table)', !('sign_method' in sent), JSON.stringify(sent).slice(0, 80));
check('method is bysubunionid', sent.method === 'jd.union.open.promotion.bysubunionid.get');
check('app_key sent', sent.app_key === 'ak_test');
check('v is sent', sent.v === '1.0');
const recomputed = md5('secret_test' + Object.keys(sent).filter(k => k !== 'sign').sort().map(k => k + sent[k]).join('') + 'secret_test').toUpperCase();
check('signature matches secret', sent.sign === recomputed, `${sent.sign} vs ${recomputed}`);
const payload = JSON.parse(sent['360buy_param_json']);
check('materialId is the product url', payload.promotionCodeReq.materialId === 'https://item.jd.com/100288670988.html');
check('siteId sent', payload.promotionCodeReq.siteId === 'site_123');
check('timestamp looks like Beijing time', /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/.test(sent.timestamp), sent.timestamp);

// --- JD error passthrough ---
reply = JSON.stringify({ error_response: { code: 10001, msg: 'signature check error' } });
r = await call('token=tok&url=https://item.jd.com/1.html');
check('502 on JD error', r.status === 502);
check('raw JD response surfaced', (r.body.raw || '').includes('signature check error'), JSON.stringify(r.body).slice(0, 160));

// --- non-JSON body (JD HTML error page) ---
reply = '<html>502 Bad Gateway</html>';
r = await call('token=tok&url=https://item.jd.com/1.html');
check('502 on HTML error page', r.status === 502, JSON.stringify(r.body).slice(0, 120));

// --- flat clickURL shape also parsed ---
reply = JSON.stringify({ data: { clickUrl: 'https://u.jd.com/flat' } });
r = await call('token=tok&url=https://item.jd.com/1.html');
check('parses flat clickUrl too', r.body.url === 'https://u.jd.com/flat', JSON.stringify(r.body));

// --- regression: secret pasted with surrounding whitespace ---
// `wrangler secret put` keeps a trailing newline from stdin, and a secret
// carrying one produces exactly the 无效签名 error JD returned.
captured = null;
await call('token=tok&url=https://item.jd.com/1.html', {
  JD_APP_KEY: ' ak_test ', JD_APP_SECRET: '\nsecret_test\n', JD_SITE_ID: 'site_123 ', APP_TOKEN: 'tok',
});
const trimmed = captured.body;
check('trims appKey', trimmed.app_key === 'ak_test', trimmed.app_key);
check('trims siteId', JSON.parse(trimmed['360buy_param_json']).promotionCodeReq.siteId === 'site_123');
check('signs the trimmed secret', trimmed.sign === md5('secret_test' + Object.keys(trimmed).filter(k => k !== 'sign').sort().map(k => k + trimmed[k]).join('') + 'secret_test').toUpperCase(), trimmed.sign);

// --- regression: the timestamp space must not be sent as "+" ---
// URLSearchParams encodes a space as "+", which only decodes back to a space
// under form rules; "%20" is unambiguous, so JD decodes what we signed.
check('timestamp space sent as %20', /timestamp=[^&]*%20[^&]*/.test(captured.rawBody), captured.rawBody.slice(0, 80));
check('no bare + in the body', !captured.rawBody.includes('+'), captured.rawBody.slice(0, 80));

// --- signing details are debug-only ---
reply = JSON.stringify({ error_response: { code: '12', zh_desc: 'invalid sign' } });
const quiet = await call('token=tok&url=https://item.jd.com/1.html');
check('sign details hidden by default',
  quiet.body.signedParams === undefined && quiet.body.sign === undefined && quiet.body.signatureBase === undefined,
  Object.keys(quiet.body).join(','));

const loud = await call('token=tok&url=https://item.jd.com/1.html&debug=1');
check('debug exposes signed params', !!(loud.body.signedParams && loud.body.signedParams.method === METHOD_EXPECT));
check('debug exposes the signature base', (loud.body.signatureBase || '').includes('app_keyak_test'), loud.body.signatureBase);
check('debug reports the gateway used', typeof loud.body.gateway === 'string' && loud.body.gateway.startsWith('https://'), loud.body.gateway);
check('debug exposes the sign', typeof loud.body.sign === 'string' && loud.body.sign.length === 32);

// --- signatureBase must never include "sign" itself ---
// It used to, because the debug output computed it after attaching sign,
// which made the diagnostic useless for comparing against JD's own tool.
check('signatureBase excludes sign', signatureBase({ method: 'm', app_key: 'k', sign: 'DEADBEEF' }) === 'app_keykmethodm',
  signatureBase({ method: 'm', app_key: 'k', sign: 'DEADBEEF' }));

const dbg = await call('token=tok&url=https://item.jd.com/1.html&debug=1');
check('debug base has no sign value in it', !(dbg.body.signatureBase || '').includes(dbg.body.sign), dbg.body.signatureBase);

const okReply = JSON.stringify({ jd_union_open_promotion_bysubunionid_get_responce: { code: '0', result: JSON.stringify({ code: 200, data: { clickURL: 'https://u.jd.com/ok' } }) } });
const badSignReply = JSON.stringify({ error_response: { code: '12', zh_desc: 'invalid sign' } });

// --- probe mode: let JD tell us which signing scheme is right ---
replyQueue = [badSignReply, okReply];
let pr = await call('token=tok&url=https://item.jd.com/1.html&probe=1');
check('probe stops at the first accepted profile', pr.body.attempts.length === 2, JSON.stringify(pr.body.attempts));
check('probe reports the rejected attempt', pr.body.attempts[0].accepted === false && pr.body.attempts[0].jdCode === '12');
check('probe reports the winner', pr.body.attempts[1].accepted === true && typeof pr.body.winner.profile === 'string', JSON.stringify(pr.body.winner));
check('probe returns the link it got', pr.body.attempts[1].url === 'https://u.jd.com/ok');
check('probe never echoes a secret', !JSON.stringify(pr.body).includes('secret_test'), JSON.stringify(pr.body).slice(0, 120));

replyQueue = Array(12).fill(badSignReply);
pr = await call('token=tok&url=https://item.jd.com/1.html&probe=1');
check('probe exhausts every secret x profile', pr.body.attempts.length === REQUEST_PROFILES.length * 2, String(pr.body.attempts.length));
check('probe explains the dead end', pr.body.hint.includes('API 测试工具'), pr.body.hint);
check('no winner reported when all fail', pr.body.winner === undefined);
replyQueue = [];

console.log(fail === 0 ? '\nALL PASS' : `\n${fail} FAILURE(S)`);
process.exit(fail ? 1 : 0);
