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

/** 文档（open.jd.com/v2/#/doc/guide?listId=1909）给出的正式网关。
 *  错误码 12「无效签名」属于这个 1.0 网关，之前的地址是错的。 */
const DOC_GATEWAY = 'https://api.jd.com/routerjson';

/** 之前误用的地址，仅留给 probe 对照。 */
const LEGACY_GATEWAY = 'https://router.jd.com/api';

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

/**
 * 文档确认的签名规则（api调用详解 五、签名算法 + 七、注意事项）：
 *   1. 所有请求参数按参数名升序
 *   2. 参数名与参数值直接相连，`key+value`，不加分隔符
 *   3. appSecret 夹在拼接串两端
 *   4. MD5 后转大写
 *   并且明确写了「value 无需编码」—— 签名用原始值，只有拼进 URL 时才 encode。
 * 下面这几项就是按这个来的，不再保留猜测性的变体。
 */

/**
 * 文档没有正面回答、但会影响签名结果的两个维度，做成候选让 probe 逐个试：
 *
 *  - 网关地址：文档写的是 api.jd.com/routerjson，而之前用的是 router.jd.com/api。
 *    换网关意味着换一套验签实现，所以值得对照。
 *  - sign_method：文档「系统参数」表里根本没有这个参数，签名示例里也没有；
 *    很多 JD SDK 却会带上。若网关只对识别到的参数验签，多传一个就会导致对不上。
 *
 * 第一项是现在的默认值。
 */
const REQUEST_PROFILES = [
  {
    label: '文档网关 + 不传 sign_method（文档参数表里没有它）',
    gateway: DOC_GATEWAY,
    signMethod: null,
  },
  {
    label: '文档网关 + 传 sign_method=md5',
    gateway: DOC_GATEWAY,
    signMethod: 'md5',
  },
  {
    label: '旧地址 router.jd.com/api + 不传 sign_method',
    gateway: LEGACY_GATEWAY,
    signMethod: null,
  },
  {
    label: '旧地址 router.jd.com/api + 传 sign_method=md5',
    gateway: LEGACY_GATEWAY,
    signMethod: 'md5',
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

/** Builds the signed parameter set for one JD call under [profile]. */
function buildParams(materialId, cfg, secret, profile = REQUEST_PROFILES[0]) {
  const params = {
    method: METHOD,
    app_key: cfg.appKey,
    timestamp: timestamp(),
    format: 'json',
    v: '1.0',
    ...(profile.signMethod ? { sign_method: profile.signMethod } : {}),
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
  params.sign = sign(params, secret);
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

async function callJd(params, gateway = DOC_GATEWAY) {
  const res = await fetch(gateway, {
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
  const profile = REQUEST_PROFILES[0];
  const params = buildParams(materialId, cfg, cfg.appSecret, profile);
  const { status, raw, parsed, url } = await callJd(params, profile.gateway);
  if (url) return { url };

  return {
    error: '京东未返回推广链接',
    status,
    jdCode: jdErrorCode(parsed),
    raw: raw.slice(0, 800),
    // ?debug=1 才返回，见 fetch 里对这几个字段的处理。
    gateway: profile.gateway,
    signedParams: params,
    signatureBase: signatureBase(params),
    sign: params.sign,
  };
}

/**
 * 逐个候选「请求档案 × secret」打一遍京东，让京东自己说哪种能过。
 *
 * 文档已经确认了签名规则（MD5、key+value 升序、值不编码、secret 夹两端），
 * 剩下的不确定性只有两个：网关地址，以及文档参数表里没有的 sign_method。
 * 只回报哪一档通过和长度，不回显任何密钥内容。
 * 最坏消耗 档案数 × secret 数 次联盟调用，成功即停。
 */
async function probeSigning(materialId, env) {
  const cfg = config(env);
  const secrets = [
    { label: 'JD_APP_SECRET', value: cfg.appSecret },
    { label: 'JD_APP_KEY（若把 key 误当 secret）', value: cfg.appKey },
  ].filter((s) => s.value);

  const attempts = [];
  for (const secret of secrets) {
    for (const profile of REQUEST_PROFILES) {
      const entry = {
        secret: secret.label,
        profile: profile.label,
        gateway: profile.gateway,
      };
      try {
        const params = buildParams(materialId, cfg, secret.value, profile);
        const r = await callJd(params, profile.gateway);
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
          winner: { secret: secret.label, profile: profile.label },
          hint:
            `把 index.js 里 REQUEST_PROFILES 的第一项换成「${profile.label}」，` +
            `并确保 secret 用 ${secret.label}，重新部署即可。`,
        };
      }
    }
  }

  return {
    attempts,
    hint:
      '所有档案 × secret 组合都被拒（多为 code 12）。签名规则已由文档确认，' +
      '所以更可能是凭据本身不对（appKey/appSecret 取错应用、已重置、或不是同一对），' +
      '或者接口路径不对（METHOD 与账号开通的接口不一致）。' +
      '下一步：用 &debug=1 的 signedParams 填进京东开放平台的 API 测试工具对拍 —— ' +
      '工具算出的 sign 与返回的 sign 一致 → 凭据问题；不一致 → 再回来查算法。',
  };
}

export { md5, sign, signatureBase, REQUEST_PROFILES };

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
