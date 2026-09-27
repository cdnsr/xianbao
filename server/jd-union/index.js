/**
 * 京东联盟转链服务
 * ------------------------------------------------------------------
 * App 把商品地址发过来，这里用你自己的联盟账号签名换一条推广链接回去，
 * 这样通过 App 下单的佣金会算到你的账号上，而不是原帖作者的。
 *
 * 部署（Cloudflare Workers）：
 *   1. 安装 wrangler，`npx wrangler login`
 *   2. 设置密钥（不要写进代码）：
 *        npx wrangler secret put JD_APP_KEY
 *        npx wrangler secret put JD_APP_SECRET
 *        npx wrangler secret put JD_SITE_ID
 *        npx wrangler secret put APP_TOKEN        # 自定义口令，防止别人白用你的额度
 *     可选：npx wrangler secret put JD_POSITION_ID
 *   3. `npx wrangler deploy`，拿到形如 https://xxx.workers.dev 的地址
 *   4. 把这个地址 + APP_TOKEN 填进 App 的设置里
 *
 * 接口：
 *   GET /?url=<商品地址>&token=<APP_TOKEN>
 *   200 {"url":"https://u.jd.com/xxxx"}      换链成功
 *   400/401/502 {"error":"...","raw":"..."}  失败，raw 是京东原始返回，便于排查
 *
 * 注意：京东联盟的接口字段会变。如果报签名错或字段错，用 ?debug=1 看
 * 实际发出的参数，再对照京东联盟开放平台的最新文档调整 METHOD / 请求体。
 */

// ---------------------------------------------------------------------------
// 配置
// ---------------------------------------------------------------------------

/** 京东联盟开放平台网关。老网关是 https://api.jd.com/routerjson */
const GATEWAY = 'https://router.jd.com/api';

/** 转链接口。按京东联盟文档可能需要在 bysubunionid / common / byunionid 之间切换。 */
const METHOD = 'jd.union.open.promotion.bysubunionid.get';

// ---------------------------------------------------------------------------
// MD5（Workers 的 crypto.subtle 不提供 MD5，只能用纯 JS 实现）
// ---------------------------------------------------------------------------

function md5(input) {
  const bytes = new TextEncoder().encode(input);
  const len = bytes.length;

  const withPadding = new Uint8Array((((len + 8) >> 6) + 1) * 64);
  withPadding.set(bytes);
  withPadding[len] = 0x80;
  const bitLen = len * 8;
  new DataView(withPadding.buffer).setUint32(withPadding.length - 8, bitLen >>> 0, true);
  new DataView(withPadding.buffer).setUint32(withPadding.length - 4, Math.floor(bitLen / 0x100000000), true);

  let a0 = 0x67452301;
  let b0 = 0xefcdab89;
  let c0 = 0x98badcfe;
  let d0 = 0x10325476;

  const S = [
    7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
    5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
    6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
  ];
  const K = [];
  for (let i = 0; i < 64; i++) K.push(Math.floor(Math.abs(Math.sin(i + 1)) * 0x100000000) >>> 0);

  const view = new DataView(withPadding.buffer);
  for (let chunk = 0; chunk < withPadding.length; chunk += 64) {
    const M = [];
    for (let i = 0; i < 16; i++) M.push(view.getUint32(chunk + i * 4, true));

    let [A, B, C, D] = [a0, b0, c0, d0];

    for (let i = 0; i < 64; i++) {
      let F, g;
      if (i < 16) {
        F = (B & C) | (~B & D);
        g = i;
      } else if (i < 32) {
        F = (D & B) | (~D & C);
        g = (5 * i + 1) % 16;
      } else if (i < 48) {
        F = B ^ C ^ D;
        g = (3 * i + 5) % 16;
      } else {
        F = C ^ (B | ~D);
        g = (7 * i) % 16;
      }
      F = (F + A + K[i] + M[g]) >>> 0;
      A = D;
      D = C;
      C = B;
      B = (B + ((F << S[i]) | (F >>> (32 - S[i])))) >>> 0;
    }

    a0 = (a0 + A) >>> 0;
    b0 = (b0 + B) >>> 0;
    c0 = (c0 + C) >>> 0;
    d0 = (d0 + D) >>> 0;
  }

  const hex = (n) =>
    [0, 8, 16, 24].map((s) => ((n >>> s) & 0xff).toString(16).padStart(2, '0')).join('');
  return hex(a0) + hex(b0) + hex(c0) + hex(d0);
}

// ---------------------------------------------------------------------------
// 京东签名：secret + 按 key 排序拼接的 key+value + secret，MD5 后转大写
// ---------------------------------------------------------------------------

function timestamp() {
  const d = new Date(Date.now() + 8 * 3600 * 1000); // 京东按北京时间
  const p = (n) => String(n).padStart(2, '0');
  return (
    `${d.getUTCFullYear()}-${p(d.getUTCMonth() + 1)}-${p(d.getUTCDate())} ` +
    `${p(d.getUTCHours())}:${p(d.getUTCMinutes())}:${p(d.getUTCSeconds())}`
  );
}

/** The string JD signs: `key+value` pairs sorted by key, no separators. */
function signatureBase(params) {
  return Object.keys(params)
    .sort()
    .map((k) => k + params[k])
    .join('');
}

function sign(params, secret) {
  return md5(secret + signatureBase(params) + secret).toUpperCase();
}

// ---------------------------------------------------------------------------
// 转链
// ---------------------------------------------------------------------------

/** 从京东返回里挖出 clickURL —— 响应结构换过几版，所以递归找而不是写死路径。 */
function findClickUrl(value) {
  if (value == null) return null;
  if (typeof value === 'string') {
    if (value.startsWith('{') || value.startsWith('[')) {
      try {
        return findClickUrl(JSON.parse(value));
      } catch {
        return null;
      }
    }
    return value.startsWith('http') ? value : null;
  }
  if (typeof value !== 'object') return null;

  for (const key of ['clickURL', 'clickUrl', 'shortURL', 'shortUrl']) {
    if (typeof value[key] === 'string' && value[key].startsWith('http')) return value[key];
  }
  for (const child of Object.values(value)) {
    const found = findClickUrl(child);
    if (found) return found;
  }
  return null;
}

/** Reads config, trimming it - `wrangler secret put` keeps a trailing newline
 *  from stdin, and a secret with a stray "\n" produces exactly the
 *  "无效签名" error JD just returned. */
function config(env) {
  return {
    appKey: (env.JD_APP_KEY || '').trim(),
    appSecret: (env.JD_APP_SECRET || '').trim(),
    siteId: (env.JD_SITE_ID || '').trim(),
    positionId: (env.JD_POSITION_ID || '').trim(),
    subUnionId: (env.JD_SUB_UNION_ID || '').trim(),
  };
}

async function convert(materialId, env) {
  const cfg = config(env);
  const params = {
    method: METHOD,
    app_key: cfg.appKey,
    timestamp: timestamp(),
    format: 'json',
    v: '1.0',
    sign_method: 'md5',
    '360buy_param_json': JSON.stringify({
      promotionCodeReq: {
        materialId,
        siteId: cfg.siteId,
        ...(cfg.positionId ? { positionId: Number(cfg.positionId) } : {}),
        ...(cfg.subUnionId ? { subUnionId: cfg.subUnionId } : {}),
        chainType: 1,
      },
    }),
  };
  params.sign = sign(params, cfg.appSecret);

  // Encode by hand rather than with URLSearchParams: the timestamp contains a
  // space and URLSearchParams turns it into "+", which only decodes back to a
  // space under form rules. "%20" is unambiguous, so whatever JD decodes
  // matches the value we signed.
  const body = Object.entries(params)
    .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`)
    .join('&');

  const res = await fetch(GATEWAY, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body,
  });
  const raw = await res.text();

  let parsed = null;
  try {
    parsed = JSON.parse(raw);
  } catch {
    /* 京东偶尔直接返回 HTML 错误页 */
  }

  const url = findClickUrl(parsed);
  if (url) return { url };
  return {
    error: '京东未返回推广链接',
    status: res.status,
    raw: raw.slice(0, 800),
    // 排查用：JD 返回「无效签名」时，把 params 填进京东开放平台的 API 测试工具，
    // 对比它生成的 sign 与这里的 sign。algorithmMismatch 说明算法/字段不对，
    // 一致则说明 appSecret 或 appKey 不对（含多余空白、取错应用等）。
    signedParams: params,
    signatureBase: signatureBase(params),
    sign: params.sign,
  };
}

export { md5, sign, signatureBase };

export default {
  async fetch(request, env) {
    const reqUrl = new URL(request.url);
    const materialId = (reqUrl.searchParams.get('url') || '').trim();

    // 口令是防止别人白用你的联盟额度；没配就跳过（不建议）。
    if (env.APP_TOKEN && reqUrl.searchParams.get('token') !== env.APP_TOKEN) {
      return json({ error: 'token 不正确' }, 401);
    }
    if (!materialId.startsWith('http')) {
      return json({ error: '缺少 url 参数（http 开头的商品地址）' }, 400);
    }
    const cfg = config(env);
    const missing = [];
    if (!cfg.appKey) missing.push('JD_APP_KEY');
    if (!cfg.appSecret) missing.push('JD_APP_SECRET');
    if (!cfg.siteId) missing.push('JD_SITE_ID');
    if (missing.length) {
      return json({ error: `服务端未配置 ${missing.join('、')}` }, 500);
    }

    try {
      const result = await convert(materialId, env);
      if (reqUrl.searchParams.get('debug') === '1') {
        result.method = METHOD;
        result.gateway = GATEWAY;
        result.materialId = materialId;
      } else {
        // 签名相关的内容只在 debug 模式返回，避免默认把 app_key 暴露出去。
        delete result.signedParams;
        delete result.signatureBase;
        delete result.sign;
      }
      return json(result, result.url ? 200 : 502);
    } catch (e) {
      return json({ error: String((e && e.message) || e) }, 502);
    }
  },
};

function json(body, status) {
  return new Response(JSON.stringify(body, null, 2), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8' },
  });
}
