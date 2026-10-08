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

#### 2.1 用户筛选规则（2026-10 现行版）

> **两个已废弃的旧协议**：更早的 `listfilter(xindata, 11个字符串)` 只剩普通分类页的
> 推送 handler 里还在传参（对本账号实参是「显示标题=(.*)」，等于不筛）；2026-09
> 那版「页面级 `xb_config` 三分支 + 全局 `["推送"]`」也已经被 20261001～20261008
> 的几次改动换掉了。**筛选配置现在不在页面 HTML 里**，而是页面用一条 `<script>`
> 单独拉下来的：

```html
<script defer src="/zb_users/theme/xianbao_theme/script/meta.php?type=index&pagination=1&zdmserver=1"></script>
```

`meta.php` 是 `Cache-Control: no-store` 的动态脚本，按账号下发，一次带全该页需要的
全部筛选信息。**同一个页面的查询串会改变响应内容**，App 必须照抄页面里那一份地址
（`lib/models/page_meta.dart` 的 `metaScriptPath()`），自己拼会拿到形状不同的配置：

| 地址差异 | 响应差异（实测） |
|---|---|
| 首页带 `zdmserver=1`（网站自己带的） | 不做主列表的客户端筛选（服务端已筛）、下发同一屏蔽词的 `title_pbc`；条目 `data-price` 由服务端补 |
| 首页不带 `zdmserver=1` | 内联「价格提取 IIFE + `xb_rows_pass` DOM 块」自己筛，同一个词落在 `category_pbc` |
| 分类页不带 `cate-name` | 推送的全局范围下发 `["推送"]`；带上（浏览器就是这么带的）则下发空串 |

**① 全局筛选** `window.xb_global_filter`（Ucenter「全局筛选」，服务端下推的那份）：

```json
{"status":0,"bankuai":[],"louzhuregtime":"","rows":[],"legacy":{"kw":0,"keywords":[],"fanwei":[]}}
```

- `status != 1` → 未启用，直接放行；
- `rows[]`：每行 `{fanwei,title_gjc,title_pbc,category_gjc,category_pbc,louzhu_gjc,louzhu_pbc,Miprice,Mxprice}`，
  `fanwei` 是该行生效的板块范围（空 = 全部）。**行间 OR**：条目被任一行通过才保留，
  全空行直通；预筛后没有任何行声明当前板块 → 本板块直通（避免板块规则互相清空）；
- **价格区间（20261001 新增）**：`Miprice`/`Mxprice` 现在**两条路径都校验**（旧的
  「SSR 列表不校验价格」不对称已取消）。无价条目在价格行放行；主列表条目没有
  `data-price` 时，网站会用 meta.php 内联的价格提取 IIFE 从标题补
  （`[¥￥]\s*(数) | (数)\s*元`，见 `priceFromTitle()`）；
- `legacy`：老键兜底，只在 `rows` 为空且 `kw == 1` 时生效，语义是"屏蔽"——`keywords`
  任一词命中标题/内容/楼主即移除，`fanwei` 非空时仅对 catename 以其为前缀的条目生效；
- `louzhuregtime`：楼主注册天数小于该值（可以是小数）→ 移除。

范围 token（`fanwei` 与当前页面的匹配口径）：

| 页面 | scope |
|---|---|
| 首页 | `主列表` / `首页` |
| 分类页 | `主列表` / `分类页` / `分类页:{标题各段}`（如「赚客吧-线报酷」→ `分类页:赚客吧`、`分类页:线报酷`） |
| 排行榜页 | `排行榜`（旧值 `热榜` 兼容） |
| 推送（首页） | `推送` / `主列表` / `首页`（三个一起递，见下） |
| 推送（分类页/频道页/关注页） | 服务端下发的是**空 token**，只有 `fanwei` 留空的行生效 |

`分类页:` token 支持前缀宽松命中（范围词 `微博` 命中 `分类页:微博线报`）。

**② 用户端全局列表筛选** `window.xb_global_fe_filter`（`20261001` 新增，只有
`status`/`rows`）：服务端零消费、纯浏览器本地过滤，**所有列表页（含频道页）都要过**，
与全局筛选并行生效。本账号没启用（变量不存在），App 按「有就叠加」实现。

**③ 页面级筛选** `window.xb_config`（分类页/频道页/关注页/首页各自的规则行），两条判定口径：

- **`xb_listfilter`（关注页/频道页/值得买三个分支）**：主列表与推送都用它。关注页分支
  按 价格 → 标题 → 分类（完整 catename）→ 商城（`platforms` 优先，回退 catename 尾段）
  → 楼主；频道页分支把 catename 拆「中段=分类 / 尾段=商城」，无价条目放行；值得买分支
  走 `data-type=smzdm`（商城名那一步网站把实参写反了，App 照搬了线上的方向）。
- **`xb_rows_pass`（首页推送守卫 `xb_json_guard`、首页内联 DOM 块）**：先按 `fanwei`
  是否覆盖 catename 挑行（一条都不覆盖 → 整条丢），**屏蔽词是全局否决**（任一行命中
  标题/分类/楼主的屏蔽词即丢），正向条件行之间 OR（至少一行完整通过）。与
  `xb_listfilter` 的"行间 OR"不是一回事。
- 形态既可能是数组 `[{...}]`，也可能是对象 `{"zdmdefault":{...}}`，两种都能吃；
- URL 带 `?k=&kp=&cate=&mall=&mip=&mxp=` 时脚本会**整份覆盖**成一行 `xbquick`
  （字段值是裸 JS 变量）。App 不带这些参数，解析时跳过这类裸变量行；
- 页面一旦带 `window.xb_page_flag`，网站就**跳过全局筛选**（`xb_global_mainfilter`
  见到它直接 return），只走这一层；
- **轮询开关** `window.xb_guanzhu_poll_on`：关注页不为 1 时 `xb_listfilter` 一行都不
  放行（游客那份 `xb_config` 是空对象，所以游客不受影响）；关注页推送也只在它为 1
  时才插。

**④ 频道守卫** `window.xb_channel_guard`（微博/好单频道页）：`{channel, cateId,
cateName, platformNames}`。子频道页（如 `/category-haodan-jd/`）cateId 与父频道相同
（都是 30），靠 `platformNames`（尾段等值命中）与 `cateName`（中段包含）再筛一层——
不加这一层，好单的淘宝/猫超推送会混进「好单线报-京东」页。

**⑤ 关注页召回守卫** `window.xb_guanzhu_recall`（只作用于**推送条目**）：

```json
{"keywords":["线报活动","赚客吧","新赚吧","小嘀咕","豆瓣线报"],"authors":[],"excludes":[],"operator":"OR"}
```

- 只用在推送上；SSR 列表已由服务端按同一条件召回，网站不会二次过滤；
- 匹配文本是「标题 + 分类名」直接拼接，再接换行 + 正文；`authors` 匹配楼主；
  `excludes` 任一命中即丢弃；
- 组合语义：`keywords` 与 `authors` 并存时 `AND` = 全部关键词命中且作者命中、
  `OR`/其他 = 任一命中；只有 `keywords` 时 `AND` = 全部、`OR` = 任一；全空 → 放行。

**⑥ 推送的全局筛选范围**由页面自己声明，写在 worker handler 里：

| 页面 | 调用 | 实际效果 |
|---|---|---|
| 首页 | `xb_global_jsonfilter(xindata, ["推送","主列表","首页"])` | 三个 token 都算 |
| 分类页/频道页/关注页 | `xb_global_jsonfilter(xindata, )` | 空 token（服务端占位没替换）→ 只有 `fanwei` 留空的行 |
| 值得买页 | 该页 handler 不调它 | 推送完全不过全局筛选 |

**关键词匹配方式（全站统一）**：按 `#` / `|` / `<br>` / 换行拆词，逐词做**字面量**
包含匹配（`indexOf`，大小写敏感，空词丢弃）。改版后正则已下线，词内的 `.` `?` `+`
等符号一律按普通字符处理。（旧版是 `RegExp`，大小写也不敏感。）

**页面级排除（20261002）**：站内搜索页（`/search.php` 与首页 quick 搜索 `/?k=`）与
楼主记录页（`/record/…`）不应用列表筛选；首页/分类页带搜索参数时同样跳过用户中心
筛选（`xb_search_mode`）。App 的搜索页本来就不筛，也没做楼主页。

**其他注意**：

- `li.article-list.top`（置顶）豁免主列表的两种筛选；
- 注册天数：网站两条路径口径不同（推送认 10 位秒级时间戳，DOM 只认 `2014-2-11`
  这类日期串）；App 两边都认 10 位时间戳（线上 DOM 不会出现这种值）；
- **已知未实现**：普通分类页推送 handler 里那句带实参的 `listfilter(xindata, …)`
  （老协议的「屏蔽分类/楼主/标题/内容/注册天数」）。本账号的实参是
  「显示标题=(.*)」，等于不筛；要移植得先解析带转义的位置实参，收益极低，暂缓。

Flutter 侧实现：引擎在 `lib/models/site_filter.dart`，meta 解析与判定在
`lib/models/page_meta.dart`，接线在 `lib/services/api_service.dart`。

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
