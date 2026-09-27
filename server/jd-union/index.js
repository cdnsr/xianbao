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
// 京东签名
// ---------------------------------------------------------------------------

function timestamp() {
  const d = new Date(Date.now() + 8 * 3600 * 1000); // 京东按北京时间
  const p = (n) => String(n).padStart(2, '0');
  return (
    `${d.getUTCFullYear()}-${p(d.getUTCMonth() + 1)}-${p(d.getUTCDate())} ` +
    `${p(d.getUTCHours())}:${p(d.getUTCMinutes())}:${p(d.getUTCSeconds())}`
  );
}

/** 参与签名的参数，按 key 升序，且始终排除 sign。 */
function signedPairs(params) {
  return Object.keys(params)
    .filter((k) => k !== 'sign')
    .sort()
    .map((k) => [k, String(params[k])]);
}

/** 默认方案待签的字符串：`key+value` 直接拼接，值为原值。
 *  `sign` 永远排除，所以签名附加之后再调用也依然正确。 */
function signatureBase(params) {
  return signedPairs(params)
    .map(([k, v]) => k + v)
    .join('');
}

function sign(params, secret) {
  return md5(secret + signatureBase(params) + secret).toUpperCase();
}

async function hmacSha256Hex(secret, message) {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    'raw',
    enc.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const mac = await crypto.subtle.sign('HMAC', key, enc.encode(message));
  return [...new Uint8Array(mac)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

/**
 * 候选签名方案。
 *
 * 京东的签名规则在平台换代时变过（值是否先 URL 编码、拼接是否用 `k=v&`、
 * MD5 还是 HMAC-SHA256），而文档在登录墙后面、外部查不到。与其猜，不如让
 * `?probe=1` 拿同一份参数把每种方案都打一遍，由京东告诉我们哪种能过。
 *
 * 第一项是默认方案，跑起来就用它。
 */
const SIGN_VARIANTS = [
  {
    label: 'md5 / key+value / 原值 / 大写（默认）',
    signMethod: 'md5',
    base: (p) => signedPairs(p).map(([k, v]) => k + v).join(''),
    hash: (secret, base) => md5(secret + base + secret).toUpperCase(),
  },
  {
    label: 'md5 / key+value / 值先 URL 编码 / 大写',
    signMethod: 'md5',
    base: (p) => signedPairs(p).map(([k, v]) => k + encodeURIComponent(v)).join(''),
    hash: (secret, base) => md5(secret + base + secret).toUpperCase(),
  },
  {
    label: 'md5 / query 形式 k=v&k=v / 大写',
    signMethod: 'md5',
    base: (p) => signedPairs(p).map(([k, v]) => `${k}=${encodeURIComponent(v)}`).join('&'),
    hash: (secret, base) => md5(secret + base + secret).toUpperCase(),
  },
  {
    label: 'md5 / key+value / 原值 / 小写',
    signMethod: 'md5',
    base: (p) => signedPairs(p).map(([k, v]) => k + v).join(''),
    hash: (secret, base) => md5(secret + base + secret),
  },
  {
    label: 'hmac-sha256 / key+value / 原值',
    signMethod: 'hmac-sha256',
    base: (p) => signedPairs(p).map(([k, v]) => k + v).join(''),
    hash: (secret, base) => hmacSha256Hex(secret, base),
  },
];

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

/** Builds the signed parameter set for one JD call under [variant]. */
async function buildParams(materialId, cfg, secret, variant = SIGN_VARIANTS[0]) {
  const params = {
    method: METHOD,
    app_key: cfg.appKey,
    timestamp: timestamp(),
    format: 'json',
    v: '1.0',
    sign_method: variant.signMethod,
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
  params.sign = await variant.hash(secret, variant.base(params));
  return params;
}

/** Percent-encodes by hand rather than via URLSearchParams: the timestamp
 *  contains a space and URLSearchParams writes it as "+", which only decodes
 *  back to a space under form rules. "%20" is unambiguous, so whatever JD
 *  decodes matches the value we signed. */
function encodeBody(params) {
  return Object.entries(params)
    .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`)
    .join('&');
}

/** JD reports failures as `{"error_response":{"code":"12",...}}`. */
function jdErrorCode(parsed) {
  const err = parsed && parsed.error_response;
  return err && err.code != null ? String(err.code) : null;
}

async function callJd(params) {
  const res = await fetch(GATEWAY, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: encodeBody(params),
  });
  const raw = await res.text();

  let parsed = null;
  try {
    parsed = JSON.parse(raw);
  } catch {
    /* 京东偶尔直接返回 HTML 错误页 */
  }
  return { status: res.status, raw, parsed, url: findClickUrl(parsed) };
}

async function convert(materialId, env) {
  const cfg = config(env);
  const params = await buildParams(materialId, cfg, cfg.appSecret);
  const { status, raw, parsed, url } = await callJd(params);
  if (url) return { url };

  return {
    error: '京东未返回推广链接',
    status,
    jdCode: jdErrorCode(parsed),
    raw: raw.slice(0, 800),
    // ?debug=1 才返回，见 fetch 里对这几个字段的处理。
    signedParams: params,
    signatureBase: signatureBase(params),
    sign: params.sign,
  };
}

/**
 * 拿同一份参数，把每个候选 secret × 每种签名方案都打一遍京东，看哪种能过。
 *
 * 这是为「没有文档、无法本地复现」准备的：京东自己会告诉我们哪套规则对。
 * 只回报「哪一档通过」和长度，不回显任何密钥内容。
 * 最坏情况会消耗 secret 数 × 方案数 次联盟接口调用，成功即提前结束。
 */
async function probeSigning(materialId, env) {
  const cfg = config(env);
  const secrets = [
    { label: 'JD_APP_SECRET', value: cfg.appSecret },
    { label: 'JD_APP_KEY（若把 key 误当 secret）', value: cfg.appKey },
  ].filter((s) => s.value);

  const attempts = [];
  for (const secret of secrets) {
    for (const variant of SIGN_VARIANTS) {
      const entry = { secret: secret.label, variant: variant.label };
      try {
        const params = await buildParams(materialId, cfg, secret.value, variant);
        const r = await callJd(params);
        entry.jdCode = jdErrorCode(r.parsed);
        entry.accepted = Boolean(r.url);
        if (r.url) entry.url = r.url;
      } catch (e) {
        entry.error = String((e && e.message) || e);
      }
      attempts.push(entry);
      if (entry.accepted) {
        return {
          attempts,
          winner: { secret: secret.label, variant: variant.label },
          hint: `把 index.js 里的 SIGN_VARIANTS 顺序调整成这一档（${
            variant.label
          }）+ 使用 ${secret.label}，收到的链接就是对的。`,
        };
      }
    }
  }

  return {
    attempts,
    hint:
      '所有组合都被拒，且基本都是 code 12。这说明问题不在签名方案的排列组合：' +
      '要么凭据本身不是这两个值（appKey/appSecret 取错应用或已重置），' +
      '要么请求还缺字段（例如 access_token）。' +
      '下一步用 &debug=1 拿到 signedParams，填进京东开放平台的 API 测试工具对拍：' +
      '工具算出的 sign 与返回的 sign 一致 → 凭据问题；不一致 → 方案问题。',
  };
}

export { md5, sign, signatureBase, SIGN_VARIANTS };

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
      if (reqUrl.searchParams.get('probe') === '1') {
        return json(await probeSigning(materialId, env), 200);
      }

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
