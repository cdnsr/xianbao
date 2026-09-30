# 线报酷 (new.xianbao.fun) 接口分析报告

> 生成时间：2026-07-11
> 分析方式：HTTP 请求 + HTML/JS 源码解析

---

## 一、站点技术栈

| 项目 | 值 |
|---|---|
| CMS | Z-BlogPHP |
| 主题 | xianbao_theme |
| 用户插件 | mochu_us |
| 渲染方式 | 服务端渲染 (SSR) + Web Worker 轮询刷新 |
| 域名白名单 | new.xianbao.fun, new.ixbk.net, new.ixbk.fun, news.xianbao.fun, news.ixbk.net, news.ixbk.fun |

---

## 二、接口清单

按 AGENT.md 优先级排序：JSON API > XHR/Ajax > HTML 解析 > 局部 WebView。

### 1. 文章列表（首页 / 分类页 / 搜索页）

**类型：SSR HTML 解析（第二优先级）**

| 项 | 值 |
|---|---|
| URL（首页） | `GET /` （第 1 页） |
| URL（分页） | `GET /page/{n}/` （n = 2, 3, ... 2980） |
| URL（分类） | `GET /category-{slug}/` 或 `GET /category-{slug}/page/{n}/` |
| URL（搜索） | `POST /zb_system/cmd.php?act=search`，body `q={关键词}`，302 跳转到搜索结果页 |
| Content-Type | `text/html; charset=utf-8` |
| 缓存 | 首页由 Xianbaoku Cache 生成，约 1 分钟刷新 |

**列表项 HTML 结构：**

```html
<li class="article-list">
  <span class="figure cg30"></span>
  <p class="title">
    <time class="badge red" datetime="2026-07-11" title="2026-07-11 15:55">15:55</time>
    <span class="badge com"><i class="iconfont icon-comment"></i>0</span>
    <a href="/haodan/6614199.html"
       title="乐百氏天然矿泉水360ml*24瓶 23.9元"
       data-catename="好单线报-饮料-淘宝"
       data-content="23.9一箱 乐百氏天然矿泉水360ml*24瓶"
       data-comments="0"
       data-louzhu="发报员Z">
      乐百氏天然矿泉水360ml*24瓶 23.9元
    </a>
  </p>
</li>
```

**可提取字段（data-* 属性）：**

| 字段 | 属性 / 标签 | 说明 |
|---|---|---|
| 文章 URL | `a@href` | 相对路径，如 `/haodan/6614199.html` |
| 标题 | `a@title` | |
| 分类 | `a[data-catename]` | 如 "好单线报-饮料-淘宝" |
| 摘要 | `a[data-content]` | 文案内容 |
| 评论数 | `a[data-comments]` | |
| 发布时间 | `time@datetime` + `time@title` | datetime=日期, title=日期时间 |
| 楼主 | `a[data-louzhu]` | 发报员 |

**分页 HTML 结构：**

```html
<div class="pagebar">
  <div class="nav-links">
    <span class="page-numbers current">1</span>
    <a class="page-numbers" href="/page/2/">2</a>
    <a class="page-numbers" href="/page/3/">3</a>
    <span class="next"><a href="/page/2/">下一页</a></span>
    <a class="page-numbers" href="/page/2980/">尾页</a>
    <label>共 2980 页</label>
  </div>
</div>
```

分页规律：`/page/{n}/`，总页数从 `.pagebar` 中提取。

> **分类页分页另走一套格式（2026-09 改版）**：分类页的下一页链接是
> `/category-{slug}/{n}/`（如 `/category-haodan/2/`），**不是**首页那套
> `/category-{slug}/page/{n}/`。旧地址现在不会报错，而是安静地给出错的内容：
>
> | 地址 | 结果 |
> |---|---|
> | `/category-haodan/2/` | 正常，100 条 |
> | `/category-haodan/page/2/` | 0 条 |
> | `/category-guanzhu1/page/2/` | 静默返回**第 1 页**内容（列表会无限重复首页） |
>
> 取路径见 `lib/services/http_client.dart` 的 `categoryPagePath()`。

---

### 2. 实时推送 JSON API（自动刷新）

**类型：JSON API（第一优先级）**

| 项 | 值 |
|---|---|
| URL | `GET /plus/json/push.json` |
| Content-Type | `application/json` |
| 用途 | Web Worker 轮询获取最新推送文章，用于首页自动刷新 |
| 轮询间隔 | 5 秒（`postjson.jiangeshijian=5`） |
| Worker | `/plus/worker.js?v=24011` |

**JSON 结构：**

```json
[
  {
    "id": 6614204,
    "title": "新鲜贝贝南瓜5斤 7.99元",
    "content": "7.99元！新鲜贝贝南瓜5斤 ",
    "content_html": "7.99元！...<br><a href=\"https://u.jd.com/91ta2WH\">...</a><br><img ...>",
    "datetime": "2026-07-11",
    "shorttime": "15:55",
    "shijianchuo": 1783756559,
    "cateid": "30",
    "catename": "好单线报-果蔬-京东",
    "comments": 0,
    "louzhu": "发报员Z",
    "louzhuregtime": null,
    "url": "/haodan/6614204.html"
  }
]
```

> **注意：** 此接口仅返回最新推送的少量文章（增量更新），不是完整分页列表。可用于首页"新文章提示"功能，但不能替代分页列表。

#### 2.1 用户筛选规则（2026-09 全面改版）

> **旧协议已废弃**：老版本靠 `listfilter(xindata, 11个字符串)` / `liebiaoshaixuan(...)`
> 传位置参数，现在脚本里只剩 worker 中一处参数全空的 `listfilter(...)` 调用。
> 仍然按它解析会得到 11 条空规则，等于**关键词屏蔽整体失效**。

网站把筛选拆成三层，全部在浏览器里执行；App 必须自己取脚本、解析规则、对列表与
增量逐条判定。

**① 全局筛选** `window.xb_global_filter`（Ucenter「全局筛选」，首页/分类页/文章页
的 `meta.php` 里下发）：

```json
{"status":0,"bankuai":[],"louzhuregtime":"","rows":[],"legacy":{"kw":0,"keywords":[],"fanwei":[]}}
```

- `status != 1` → 未启用，直接放行；
- `rows[]`：每行 `{fanwei,title_gjc,title_pbc,category_gjc,category_pbc,louzhu_gjc,louzhu_pbc,Miprice,Mxprice}`，
  `fanwei` 是该行生效的板块范围（空 = 全部）。**行间 OR**：条目被任一行通过才保留，
  全空行直通；预筛后没有任何行声明当前板块 → 本板块直通（避免板块规则互相清空）；
- `legacy`：老键兜底，只在 `rows` 为空且 `kw == 1` 时生效，语义是"屏蔽"——`keywords`
  任一词命中标题/内容/楼主即移除，`fanwei` 非空时仅对 catename 以其为前缀的条目生效；
- `louzhuregtime`：楼主注册天数小于该值 → 移除。

范围 token（`fanwei` 与当前页面的匹配口径）：

| 页面 | scope |
|---|---|
| 首页 | `主列表` / `首页` |
| 分类页 | `主列表` / `分类页` / `分类页:{标题各段}`（如「赚客吧-线报酷」→ `分类页:赚客吧`、`分类页:线报酷`） |
| 推送增量 | `推送` |
| 侧栏我的关注（`/plus/` 侧栏） | `我的关注`（旧值 `侧栏我的关注` 仍兼容） |

`分类页:` token 支持前缀宽松命中（范围词 `微博` 命中 `分类页:微博线报`）。

**② 页面级筛选** `window.xb_config`（分类页/频道页，`type=category` 的 `meta.php`）：

- 形态既可能是数组 `[{...}]`，也可能是对象 `{"zdmdefault":{...}}`，网站用
  `Object.values()` 遍历，两种都能吃；
- 字段与全局筛选的行一致，另有 `Status`（`=== 1` 才生效）与 `brand_*`/`mall_*`；
- URL 带 `?k=&kp=&cate=&mall=&mip=&mxp=` 时脚本会**整份覆盖**成一行 `xbquick`
  （字段值是裸 JS 变量）。App 不带这些参数，解析时应跳过这类裸变量行；
- 页面一旦带 `window.xb_page_flag`，网站就**跳过全局筛选**（`xb_global_mainfilter`
  见到它直接 return），只走这一层；
- 分支按页面类型选：`guanzhu`（我的关注：价格 → 标题 → 分类 → 商城 → 楼主，分类用
  完整 catename 匹配）、频道页（微博/好单：catename 拆「中段=分类 / 尾段=商城」，
  无价条目放行）、值得买（`data-type=smzdm`）。

**③ 关注页召回守卫** `window.xb_guanzhu_recall`（只作用于**推送条目**）：

```json
{"keywords":["线报活动","赚客吧","新赚吧","小嘀咕","豆瓣线报"],"authors":[],"excludes":[],"operator":"OR"}
```

- 只用在推送上；SSR 列表已由服务端按同一条件召回，网站不会二次过滤；
- 匹配文本是「标题 + 分类名」直接拼接，再接换行 + 正文；`authors` 匹配楼主；
  `excludes` 任一命中即丢弃；
- 组合语义：`keywords` 与 `authors` 并存时 `AND` = 全部关键词命中且作者命中、
  `OR`/其他 = 任一命中；只有 `keywords` 时 `AND` = 全部、`OR` = 任一；全空 → 放行。

**关键词匹配方式（全站统一）**：按 `#` / `|` / `<br>` / 换行拆词，逐词做**字面量**
包含匹配（`indexOf`，大小写敏感，空词丢弃）。改版后正则已下线，词内的 `.` `?` `+`
等符号一律按普通字符处理。（旧版是 `RegExp`，大小写也不敏感。）

**「我的关注」页的真实数据**（`type=category&cateid=5&catename=guanzhu1`）：该页拉的是
**站级** `/plus/json/push.json`，逐条过 `召回守卫 → xb_config → ["推送"] 全局筛选`
后才插入列表。实测某账号的 `xb_config` 只有一行
`category_gjc = 赚客吧#新赚吧#微博线报#豆瓣线报#小嘀咕`，当时 20 条推送里只有 5 条
该出现——不做过滤就会把好单/值得买/酷安等全混进来。

该页的 **SSR 列表是跟着 Cookie 变的**（同一时刻实测：登录 34 条 / 未登录 101 条），
所以 App 必须带上登录 Cookie 请求分类页，拿到的才是服务端按召回条件筛过的列表。

**其他注意**：

- `li.article-list.top`（置顶）豁免主列表的两种筛选；
- SSR 列表路径**不校验价格**，推送路径才校验 `Miprice`/`Mxprice` vs 条目 `price`
  （网站自身的不对称，照搬）；行带价格约束时「无价」条目在该行不通过；
- 注册天数：网站两条路径口径不同（推送认 10 位秒级时间戳，DOM 只认 `2014-2-11`
  这类日期串）。
- 搜索页不带全局筛选脚本，搜索结果不做筛选。

Flutter 侧实现见 `lib/models/site_filter.dart`，接线见 `lib/services/api_service.dart`。

---

### 3. 排行榜 JSON API

**类型：JSON API（第一优先级）**

| 接口 | URL | 缓存 |
|---|---|---|
| 一小时排行 | `GET /plus/json/rank/yixiaoshi-hot.json` | 5 分钟 |
| 三小时排行 | `GET /plus/json/rank/sanxiaoshi-hot.json` | 10 分钟 |
| 六小时排行 | `GET /plus/json/rank/liuxiaoshi-hot.json` | 60 分钟 |
| 十二小时排行 | `GET /plus/json/rank/shierxiaoshi-hot.json` | 60 分钟 |
| 猜你喜欢 | `GET /plus/json/rank/guesslike.json` | 30 分钟 |

JSON 结构与 push.json 相同。

---

### 4. 文章详情

**类型：SSR HTML 解析（第二优先级）**

| 项 | 值 |
|---|---|
| URL | `GET /{category}/{id}.html` |
| 示例 | `GET /haodan/6614199.html` |
| Content-Type | `text/html; charset=utf-8` |

**正文 HTML 结构：**

```html
<article class="art-main br mb sb">
  <div class="art-head mb">
    <h1 class="art-title">乐百氏天然矿泉水360ml*24瓶 23.9元</h1>
    <div class="head-info">
      <span class="author"><a href="/record/haodan/发报员Z.html">发报员Z</a></span>
      <time class="time" datetime="2026-07-11" title="2026-07-11 15:55:20">2026年07月11日 15:55</time>
      <span class="comment">0</span>
      <span class="report">举报</span>
    </div>
  </div>
  <div class="art-content">
    <div class="article-content">
      23.9一箱 <br>
      乐百氏天然矿泉水360ml*24瓶<br>
      https://m.tb.cn/h.RAuPQcQ<br>
      <img src="..." />
    </div>
  </div>
</article>
```

**可提取字段：**

| 字段 | 选择器 | 说明 |
|---|---|---|
| 标题 | `h1.art-title` | |
| 作者 | `span.author a` | |
| 发布时间 | `time.time@title` | 完整时间 "2026-07-11 15:55:20" |
| 正文 | `div.article-content` | 含 `<br>`, `<a>`, `<img>` 等富文本 |
| 评论数 | `span.comment` | 数字 |

---

### 5. 评论

**类型：SSR HTML 解析（列表）+ POST 表单（发评论）**

#### 5.1 评论列表

评论直接嵌入在文章详情页 HTML 中（SSR），非 Ajax 加载。

```html
<div class="comment-list">
  <div class="title">评论列表</div>
  <div class="ul">
    <div class="li transition">
      <span class="louzhutoux"></span>
      <div class="clbody">
        <div class="cinfo clearfix">
          <span class="author">白菜<span class="level-mark level-louzu">楼主</span></span>
          <span class="c-time">2026-07-11 15:39:29</span>
          <span class="c-ip">广东</span>
        </div>
        <div class="c-neirong">
          https://m.tb.cn/h.RBCc0Y8
          <!-- 点评（嵌套回复） -->
          <div class="c-dianping">
            <span class="dianpingming">白菜</span>
            <span class="dianpingshijian">2026-07-11 15:39:34</span>
            <div class="dianpingneirong">打不开的复制...</div>
          </div>
        </div>
      </div>
    </div>
  </div>
</div>
```

**评论字段：**

| 字段 | 选择器 |
|---|---|
| 作者 | `.author`（首层文本节点） |
| 楼主标记 | `.level-mark` |
| 时间 | `.c-time` |
| 地区 | `.c-ip` |
| 内容 | `.c-neirong`（首层文本节点） |
| 点评/回复 | `.c-dianping` > `.dianpingming`, `.dianpingshijian`, `.dianpingneirong` |

> 无评论时 `.comment-list` 有 `style="display:none;"`。

#### 5.2 发评论

**类型：POST 表单（需要 Cookie 登录状态）**

| 项 | 值 |
|---|---|
| URL | `POST /zb_system/cmd.php?act=cmt&postid={文章ID}&key={key}` |
| Key 来源 | 文章详情页 form action 中的 `key` 参数 |
| Content-Type | `application/x-www-form-urlencoded` |

**表单字段：**

| 字段 | 说明 |
|---|---|
| `inpId` | 文章 ID |
| `inpRevID` | 回复目标评论 ID（0=新评论） |
| `inpName` | 用户名（隐藏，已登录时自动填充） |
| `inpEmail` | 邮箱（隐藏） |
| `inpHomePage` | 主页（隐藏） |
| `txaArticle` | 评论内容 |

> 发评论依赖登录 Cookie，且 key 是每篇文章唯一的防 CSRF token。
> 根据 AGENT.md 第三优先级，发评论建议使用局部 WebView。

---

### 6. 登录

**类型：JSON API + 验证码（需要 WebView）**

#### 6.1 独立登录页

| 项 | 值 |
|---|---|
| 页面 URL | `GET /login.html` |
| 登录 API | `POST /zb_users/plugin/mochu_us/cmd.php?act=verify` |
| 验证码图片 | `GET /zb_users/plugin/mochu_us/function/yanzhengcode.php?r={random}` |
| 密码加密 | MD5（前端 `md5.js`） |

**请求参数：**

```
username  : 用户名
password  : MD5(明文密码)
vercode   : 验证码计算结果
savedate  : 保持天数（默认 30）
```

**响应：**

```json
{ "code": "1", "msg": "..." }
// 或
{ "code": "2", "msg": "...", "href": "跳转URL" }
// 或 code != "1" && code != "2" → 登录成功，刷新页面
```

#### 6.2 内嵌登录（弹窗）

| 项 | 值 |
|---|---|
| API | `POST /zb_users/plugin/mochu_us/cmd.php?act=themelogins` |
| 参数 | `username`, `password`(MD5), `savedate` |
| 注意 | 此接口无验证码，但可能仅在特定页面可用 |

> 根据 AGENT.md，登录页面建议使用 WebView，以处理验证码图片和 Cookie。

---

### 7. 用户中心

**类型：WebView（登录后状态）**

| 项 | 值 |
|---|---|
| URL | `GET /login.html`（登录后显示用户中心） |
| 判断方式 | 访问 `/login.html`，若页面含登录表单（`#LAY-user-login`）则未登录；否则为用户中心 |
| 登录成功后 | 页面自动 reload，显示用户中心内容 |

> 用户中心依赖登录 Cookie，无法在未登录状态下分析其具体内容。
> 根据 AGENT.md，用户中心使用 WebView + Flutter"返回首页"按钮。

---

### 8. 搜索

**类型：SSR HTML 解析**

| 项 | 值 |
|---|---|
| 提交方式 | `POST /zb_system/cmd.php?act=search` |
| 参数 | `q={关键词}` |
| 结果 | 302 跳转到搜索结果页，结构同首页列表 |
| 高亮 | 关键词被 `<em>` 标签包裹 |
| 分页 | 搜索结果页分页结构同首页 |

---

## 三、Cookie 机制

| 项 | 值 |
|---|---|
| Cookie 存储 | 浏览器标准 Cookie |
| 登录 Cookie | mochu_us 插件设置，`savedate` 控制有效期 |
| 共享需求 | Dio HTTP 请求与 WebView 必须共享 Cookie |
| 实现 | `webview_flutter` Cookie 与 Dio CookieJar 互通 |

---

## 四、推荐数据获取方案

| 页面 | 方案 | 接口 |
|---|---|---|
| 首页列表 | HTML 解析 (package:html) | `GET /` 或 `GET /page/{n}/` |
| 首页实时刷新 | JSON API | `GET /plus/json/push.json`（轮询） |
| 文章详情 | HTML 解析 (package:html) | `GET /{category}/{id}.html` |
| 评论列表 | HTML 解析（详情页内） | 同文章详情 |
| 发评论 | 局部 WebView | `POST /zb_system/cmd.php?act=cmt` |
| 搜索 | HTML 解析 | `POST /zb_system/cmd.php?act=search?q={kw}` |
| 登录 | WebView | `/login.html` |
| 用户中心 | WebView + Flutter按钮 | `/login.html`（已登录） |
| 排行榜 | JSON API（可选） | `GET /plus/json/rank/*.json` |

---

## 五、注意事项

1. **Referer 策略**：网站使用 `no-referrer`，图片等资源不会发送 Referer。
2. **域名白名单**：JS 中有域名检测，非白名单域名会强制跳转到 `new.xianbao.fun`。Flutter 的 WebView 中 URL 需保持在白名单域名内。
3. **首页缓存**：首页由服务端缓存生成，约 1 分钟更新一次。`push.json` 为实时增量数据。
4. **验证码**：登录需要图形验证码（计算题），建议用 WebView 处理。
5. **防 CSRF Key**：发评论需要文章详情页中的 `key` 参数，每次请求不同。
6. **密码加密**：前端使用 MD5 加密密码后传输。
7. **搜索结果分页**：搜索结果页的 pagebar 中分页 URL 格式需实际验证。
