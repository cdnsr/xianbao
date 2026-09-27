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

这是好消息：请求已经到京东并被受理了，只是签名对不上。**已经按文档修过两处**（见「已知不确定点」）：
网关改为 `api.jd.com/routerjson`、默认不再发送文档参数表里没有的 `sign_method`。
重新部署后先直连试一次：

```bash
curl -s "https://xxxx.workers.dev/?token=你的APP_TOKEN&url=https://item.jd.com/100276929104.html"
```

仍然报 12 的话，用 `probe=1` 把「请求档案 × secret」逐个打一遍京东，让京东说哪种能过：

```bash
curl -s "https://xxxx.workers.dev/?token=你的APP_TOKEN&url=https://item.jd.com/100276929104.html&probe=1"
```

```json
{
  "attempts": [
    { "secret": "JD_APP_SECRET", "profile": "文档网关 + 不传 sign_method（文档参数表里没有它）", "gateway": "https://api.jd.com/routerjson", "jdCode": "12", "accepted": false },
    { "secret": "JD_APP_SECRET", "profile": "文档网关 + 传 sign_method=md5", "jdCode": null, "accepted": true, "url": "https://u.jd.com/xxx" }
  ],
  "winner": { "secret": "JD_APP_SECRET", "profile": "文档网关 + 传 sign_method=md5" },
  "hint": "把 index.js 里 REQUEST_PROFILES 的第一项换成……"
}
```

候选档案定义在 `index.js` 的 `REQUEST_PROFILES`（网关地址 × 是否带 `sign_method`）。
**有 winner** → 把它挪到第一位再部署。**全部被拒** → 签名规则已由文档确认，问题更可能
在凭据本身（appKey/appSecret 不是同一对、取错应用、已重置）或接口路径与账号权限不匹配。

probe 只回报哪一档通过和长度，**不回显任何密钥内容**，但会消耗若干次联盟接口调用
（最多 8 次），查完别长期暴露这个接口。

**怎么确认服务真的能用**

```bash
curl -s "https://xxxx.workers.dev/?token=你的APP_TOKEN&url=https://item.jd.com/100288670988.html" \
     -w '\nHTTP %{http_code}\n'
```

返回 `{"url":"https://u.jd.com/xxxx"}` 就是通的。返回 `{"error":...}` 才是真的有问题。

## 已知不确定点

依据仓库里那两份官方文档（`../api调用详解.doc`、`../平台网关系统错误码.doc`）更新如下：

**已经确定**

- **网关**：`https://api.jd.com/routerjson`（文档「三、调用入口」）。错误码 12「无效签名」
  属于这个 1.0 网关，所以必须打这个地址 —— 之前用的 `router.jd.com/api` 已改为仅作对照。
- **签名算法**：参数按名升序 → `key+value` 直接相连 → appSecret 夹两端 → MD5 → 转大写；
  文档明确写了「**value 无需编码**」，即签名用原始值，只有拼进 URL 时才 encode。
  这与代码默认实现一致。
- **`sign_method` 不是文档里的参数**：文档「四、调用参数」的系统参数表只有
  `method / access_token / app_key / sign / timestamp / format / v`，签名示例里也没有
  `sign_method`。默认请求已不再发送它。
- **access_token**：文档标注「采用 OAuth 授权方式是必填」。转链接口是非授权的，不传。

**仍不确定**

- **接口名 / 字段**：`jd.union.open.promotion.bysubunionid.get` + `promotionCodeReq` 仍以
  京东联盟自己的接口文档为准（那两份文档讲的是网关通用规则，不含具体接口字段）。
- **归因是否生效**：本服务只负责换一条合法的推广链。佣金有没有记到你名下，
  **必须用一笔小额订单在自己的联盟后台确认**。
- **覆盖率**：只有能从短链还原出商品页的链接才换得了（随机抽样约三分之一）。
  领券/活动类短链的目标是加密的，拆不出来，详见 `lib/services/short_link_resolver.dart`。
- 每换一条链都会消耗你的联盟接口调用额度，所以 `APP_TOKEN` 建议一定设置。
