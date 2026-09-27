# 京东联盟转链服务

把京东商品链接换成**你自己联盟账号**的推广链。App 侧默认关闭，配置了这里的地址之后才会生效。

```
App  ──商品链接──▶  本服务  ──签名请求──▶  京东联盟开放平台
      ◀──推广链────          ◀──clickURL───
```

## 为什么要自己部署

签名需要 `appSecret`。它**不能放进 APK** —— 反编译拿到就能冒充你的账号刷你的额度。所以换链必须放在一个你能控制的地方，App 只拿到一个地址和口令。

## 1. 拿到联盟凭据

在 [京东联盟开放平台](https://union.jd.com/) 申请开发者，创建应用后得到：

| 值 | 用途 | 在本服务里的变量名 |
|---|---|---|
| `appKey` | 应用标识 | `JD_APP_KEY` |
| `appSecret` | 签名密钥 | `JD_APP_SECRET` |
| 推广位 / 网站 ID | 归因到哪个位置 | `JD_SITE_ID` |
| 子联盟 ID（可选） | 细分渠道标识 | `JD_SUB_UNION_ID` |
| positionId（可选） | 推广位 ID | `JD_POSITION_ID` |

## 2. 部署到 Cloudflare Workers

```bash
cd server/jd-union
npx wrangler login
npx wrangler secret put JD_APP_KEY
npx wrangler secret put JD_APP_SECRET
npx wrangler secret put JD_SITE_ID
npx wrangler secret put APP_TOKEN      # 自己定一个口令，防止别人白用你的额度
npx wrangler deploy
```

部署完会得到一个 `https://xxxx.workers.dev` 地址。

想部署在自己的 VPS 上也行：`index.js` 用的是标准 `fetch` / `Request` / `Response`，Node 18+ 直接能跑，套个 `http` 适配层即可。

## 3. 先用手测确认能换链

```bash
curl -s "https://xxxx.workers.dev/?token=你的APP_TOKEN&url=https://item.jd.com/100288670988.html"
# 成功：{"url":"https://u.jd.com/xxxx"}
# 失败：{"error":"...","raw":"<京东原始返回>"}
```

失败时加 `&debug=1` 会回显实际用的网关、方法名和 materialId，方便和京东文档对照。

## 4. 填进 App

App → 首页左上角菜单 → **京东转链**，填服务地址和口令。

## 5. 自测脚本

```bash
node test.mjs
```

覆盖 MD5（对拍 Node `crypto`，含多分组、长度边界、UTF-8）、签名拼接、鉴权、参数形状、以及几种京东响应结构的解析。**它不校验京东接口本身** —— 接口名和字段以京东文档为准，见下。

## 常见问题

**控制台弹「无访问权限：logpush is not enabled for this account」**

这是 Cloudflare 控制台的日志页报的，不是 Worker 本身出错。原因是 `wrangler.toml` 里开了
`[observability]`，控制台的 Worker 日志页会去查 Logpush —— 那是 Enterprise 功能，免费账号没有。

本仓库的 `wrangler.toml` 已经把 `[observability]` 去掉了。如果你之前已经部署过带这项的版本，
删掉那几行重新 `npx wrangler deploy` 即可。**不管有没有这个提示，接口都能正常调用** ——
用下面的 curl 直接验证。

**京东返回 `{"error_response":{"code":"12","zh_desc":"无效签名"}}`**

这是好消息：请求已经到京东并被受理了，只是签名对不上。**先用 `probe=1` 一次分清是哪种问题**：

```bash
curl -s "https://xxxx.workers.dev/?token=你的APP_TOKEN&url=https://item.jd.com/100276929104.html&probe=1"
```

它会用同一份参数分别以「配置的 secret」和「appKey 当 secret」各调京东一次：

```json
{
  "probe": [
    { "tried": "JD_APP_SECRET", "length": 32, "jdCode": "12", "accepted": false },
    { "tried": "JD_APP_KEY（若把 key 误当 secret）", "length": 32, "jdCode": "0", "accepted": true }
  ],
  "hint": "有候选通过：是凭据问题，请按通过的那一档重设 secret。"
}
```

- **有候选通过** → 凭据问题：secret 取错、和 appKey 互换、或多带了空白。按通过的档位
  重新 `npx wrangler secret put JD_APP_SECRET`。
- **全部都是 `code 12`** → 更像是签名算法或参与签名的字段不对，看点 3。

probe 只回报「哪一档通过了」和长度，**不会回显任何密钥内容**。查完记得不要长期暴露这个接口。

进一步排查：

1. **凭据带了空白。** `wrangler secret put` 会把 stdin 的换行一起存进密钥 —— 尾部带 `\n`
   的 secret 产生的正是「无效签名」。本服务已对配置做 trim，重新部署即可排除。
2. **凭据取错或填反了。** 确认没有把 siteId 填成 appKey、或用了别个应用的 appSecret。
3. **算法或字段不同。** 加 `&debug=1`，返回里会多出 `signedParams` / `signatureBase` / `sign`。
   把 `signedParams` 填进京东开放平台的 API 测试工具，对比它生成的 `sign`：
   - **不一致** → 改 `index.js` 的 `signatureBase()`（注意 `sign` 本身必须排除在签名外）
   - **一致** → 回到第 1、2 条查凭据

   `debug=1` 会带出 `app_key`，排查完就别再用它了。

**怎么确认服务真的能用**

```bash
curl -s "https://xxxx.workers.dev/?token=你的APP_TOKEN&url=https://item.jd.com/100288670988.html" \
     -w '\nHTTP %{http_code}\n'
```

返回 `{"url":"https://u.jd.com/xxxx"}` 就是通的。返回 `{"error":...}` 才是真的有问题。

## 已知不确定点

- **接口名 / 字段**：默认用 `jd.union.open.promotion.bysubunionid.get` + `promotionCodeReq`。京东改过几版，如果报签名错或参数错，用 `?debug=1` 看实际请求再对照文档调整 `METHOD` / 请求体。
- **归因是否生效**：本服务只负责换一条合法的推广链。佣金有没有记到你名下，**必须用一笔小额订单在自己的联盟后台确认** —— 这个我无法替你验证。
- **覆盖率**：只有能从短链还原出商品页的链接才换得了（随机抽样约三分之一）。领券/活动类短链的目标是加密的，拆不出来，详见 `lib/services/short_link_resolver.dart` 的类注释。
- 每换一条链都会消耗你的联盟接口调用额度，所以 `APP_TOKEN` 建议一定设置。
