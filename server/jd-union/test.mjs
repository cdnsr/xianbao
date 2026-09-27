import worker, { md5 } from './index.js';

const ENV = { JD_APP_KEY: 'ak_test', JD_APP_SECRET: 'secret_test', JD_SITE_ID: 'site_123', APP_TOKEN: 'tok' };
let captured = null;
let reply = null;

globalThis.fetch = async (url, init) => {
  captured = { url, body: Object.fromEntries(new URLSearchParams(init.body)) };
  return { status: 200, text: async () => reply };
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
check('posts to the router gateway', captured.url === 'https://router.jd.com/api', captured.url);
check('method is bysubunionid', sent.method === 'jd.union.open.promotion.bysubunionid.get');
check('app_key sent', sent.app_key === 'ak_test');
check('sign_method md5', sent.sign_method === 'md5');
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

console.log(fail === 0 ? '\nALL PASS' : `\n${fail} FAILURE(S)`);
process.exit(fail ? 1 : 0);
