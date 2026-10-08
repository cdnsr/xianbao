import 'package:flutter_test/flutter_test.dart';
import 'package:xianbao/models/page_meta.dart';
import 'package:xianbao/models/site_filter.dart';
import 'package:xianbao/services/http_client.dart';

/// 网站 2026-10 改版后的筛选引擎移植测试。
///
/// 夹具全部取自线上真实响应（2026-10-08 抓取）：
///
/// - [_guanzhuMeta]：登录账号的「我的关注」分类 meta.php（`cookie.txt` 账号）；
/// - [_guestMeta]：未登录时的同一页 meta.php（`xb_config` 是空对象）；
/// - [_weiboMeta] / [_zhidemaiMeta]：微博线报、值得买的 meta.php；
/// - [_indexMeta]：首页 meta.php（`?type=index&pagination=1&zdmserver=1`，
///   就是首页 HTML 里那个 `<script src>` 的地址）；
/// - [_indexMetaNoZdmServer]：同一地址去掉 `zdmserver=1` 的变体——服务端会把
///   主列表的规则行内联成 DOM 块，并且把同一个词下发在另一个字段上；
/// - [_haodanJdMeta]：`/category-haodan-jd/`（子频道，cateId 与父频道相同）；
/// - [_realCatenames]：当时 `/plus/json/push.json` 全部 20 条的 `catename`。
const String _guanzhuMeta =
    r'''$(function () {window.xb_global_filter={"status":0,"bankuai":[],"louzhuregtime":"","rows":[],"legacy":{"kw":0,"keywords":[],"fanwei":[]}};window.xb_guanzhu_poll_on=1;window.xb_page_flag='guanzhu';window.xb_page_sub='1';window.xb_config=[{"Status":1,"fanwei":"","title_gjc":"","title_pbc":"","brand_gjc":"","brand_pbc":"","category_gjc":"赚客吧#新赚吧#微博线报#豆瓣线报#小嘀咕","category_pbc":"","mall_gjc":"","mall_pbc":"","louzhu_gjc":"","louzhu_pbc":"","Miprice":"","Mxprice":""}];xb_liebiaoshaixuan(xb_config);''';

/// 未登录时的同一页：轮询开关是 0，`xb_config` 是空对象 —— 等于不筛选。
const String _guestMeta =
    r'''window.xb_guanzhu_poll_on=0;window.xb_page_flag='guanzhu';window.xb_page_sub='1';window.xb_guanzhu_recall={"keywords":["线报活动","赚客吧","新赚吧","小嘀咕","豆瓣线报"],"authors":[],"excludes":[],"operator":"OR"};window.xb_config={};xb_liebiaoshaixuan(xb_config);''';

/// `赚客吧` 等转义解出来就是这条规则的关键词。
const String _guanzhuKeywords = '赚客吧#新赚吧#微博线报#豆瓣线报#小嘀咕';

/// 未登录时同一页下发的召回条件（登录账号那一份是空的）。
const String _guestRecallMeta =
    r'''window.xb_guanzhu_recall={"keywords":["线报活动","赚客吧","新赚吧","小嘀咕","豆瓣线报"],"authors":[],"excludes":[],"operator":"OR"};''';

/// 微博线报/好单线报这类频道页：一行全空规则，等于不筛选；另带频道守卫。
const String _weiboMeta =
    r'''window.xb_page_flag='index';window.xb_page_sub='';window.xb_channel_guard={"channel":"weibo","cateId":10,"cateName":"","platformNames":[]};window.xb_config={"zdmdefault":{"Status":1,"fanwei":"","mall_name":"","title_gjc":"","title_pbc":"","brand_gjc":"","brand_pbc":"","category_gjc":"","category_pbc":"","mall_gjc":"","mall_pbc":"","Miprice":"","Mxprice":""}};xb_liebiaoshaixuan(xb_config);''';

/// 父频道「好单线报」：守卫只认 cateId，不限制平台。
const String _haodanMeta =
    r'''window.xb_page_flag='index';window.xb_page_sub='';window.xb_channel_guard={"channel":"haodan","cateId":30,"cateName":"","platformNames":[]};window.xb_config={"zdmdefault":{"Status":1,"fanwei":"","mall_name":"","title_gjc":"","title_pbc":"","brand_gjc":"","brand_pbc":"","category_gjc":"","category_pbc":"","mall_gjc":"","mall_pbc":"","Miprice":"","Mxprice":""}};xb_liebiaoshaixuan(xb_config);''';

/// 2026-10-08 抓取的 `/plus/json/push_30.json` 全部 20 条 catename
/// （好单线报频道的推送源，页面 slug `/category-haodan/` 与 `/category-haodan-jd/` 共用）。
const List<String> _haodanFeedCatenames = <String>[
  '好单线报-日用-京东',
  '好单线报-美妆-淘宝',
  '好单线报-宠物-淘宝',
  '好单线报-宠物-淘宝|猫超',
  '好单线报-家用-京东',
  '好单线报-宠物-淘宝',
  '好单线报-宠物-淘宝',
  '好单线报-数码-京东',
  '好单线报-数码-京东',
  '好单线报-食品-京东',
  '好单线报-服饰-淘宝',
  '好单线报-服饰-其他活动',
  '好单线报-食品-淘宝',
  '好单线报-日用-京东',
  '好单线报-服饰-淘宝',
  '好单线报-饮料-淘宝',
  '好单线报-母婴-淘宝',
  '好单线报-母婴-淘宝',
  '好单线报-家用-淘宝',
  '好单线报-母婴-淘宝',
];

/// 值得买页的规则：只有 Mxprice，而且没有 `type`。
const String _zhidemaiMeta =
    r'''window.xb_page_flag='index';window.xb_page_sub='';window.xb_config={"midoYbvHwPt":{"Status":1,"mall_name":"","title_gjc":"","title_pbc":"","category_gjc":"","category_pbc":"","Miprice":"","Mxprice":"1000000"}};xb_liebiaoshaixuan(xb_config);''';

/// 首页（`zdmserver=1`，与首页 HTML 里那个 `<script src>` 一致）：全局筛选没启用，
/// 但 `xb_config` 有一行屏蔽词，只作用于推送（`xb_json_guard`）。
const String _indexMeta =
    r'''$(function () {window.xb_global_filter={"status":0,"bankuai":[],"louzhuregtime":"","rows":[],"legacy":{"kw":0,"keywords":[],"fanwei":[]}};window.xb_texts={};window.xb_config=[{"Status":1,"fanwei":"","title_gjc":"","title_pbc":"好单线报","brand_gjc":"","brand_pbc":"","category_gjc":"","category_pbc":"","mall_gjc":"","mall_pbc":"","louzhu_gjc":"","louzhu_pbc":"","Miprice":"","Mxprice":""}];window.xb_json_fanwei=[];window.xb_json_guard = function (d) { return true; };if (window.xb_json_guard && window.xb_json_guard(xindata) == false) { return; }if (typeof xb_global_jsonfilter === "function") { xindata = xb_global_jsonfilter(xindata, ["推送","主列表","首页"]); if (!xindata) { return; } }''';

/// 同一个首页、去掉 `zdmserver=1`：服务端把主列表的规则行内联成 DOM 块，并把
/// 同一个屏蔽词下发在 `category_pbc` 上（字段位置随参数变，所以 App 必须照抄地址）。
const String _indexMetaNoZdmServer =
    r'''$(function () {window.xb_global_filter={"status":0,"bankuai":[],"louzhuregtime":"","rows":[],"legacy":{"kw":0,"keywords":[],"fanwei":[]}};window.xb_config=[{"Status":1,"fanwei":"","title_gjc":"","title_pbc":"","brand_gjc":"","brand_pbc":"","category_gjc":"","category_pbc":"好单线报","mall_gjc":"","mall_pbc":"","louzhu_gjc":"","louzhu_pbc":"","Miprice":"","Mxprice":""}];(function(){var items=document.querySelectorAll("#mainbox .new-post .article-list .title a");var re=/(?:[¥￥]\s*(\d+(?:\.\d+)?)|(\d+(?:\.\d+)?)\s*元)/;for(var i=0;i<items.length;i++){var a=items[i],p=a.getAttribute("data-price");if(p!==null&&p!==""){continue;}var m=re.exec(a.textContent||"");if(m){a.setAttribute("data-price",m[1]!==undefined?m[1]:m[2]);}}})();(function(){var items=document.querySelectorAll("#mainbox .new-post .article-list:not(.top) .title a");for(var i=0;i<items.length;i++){var a=items[i],cn=a.getAttribute("data-catename")||"",keep=window.xb_rows_pass(rows,a.getAttribute("title")||a.textContent||"",a.getAttribute("data-content")||"",cn,a.getAttribute("data-louzhu")||"",a.getAttribute("data-price")||"");if(!keep){a.parentNode.removeChild(a);}}})();''';

/// 子频道页 `/category-haodan-jd/`：cateId 与父频道一样是 30，靠 platformNames
/// 把推送再筛一层。
const String _haodanJdMeta =
    r'''window.xb_page_flag='index';window.xb_page_sub='';window.xb_channel_guard={"channel":"haodan","cateId":30,"cateName":"","platformNames":["京东","淘宝京东"]};window.xb_config={"zdmdefault":{"Status":1,"fanwei":"","mall_name":"","title_gjc":"","title_pbc":"","brand_gjc":"","brand_pbc":"","category_gjc":"","category_pbc":"","mall_gjc":"","mall_pbc":"","Miprice":"","Mxprice":""}};xb_liebiaoshaixuan(xb_config);if (typeof xb_global_jsonfilter === "function") { xindata = xb_global_jsonfilter(xindata, ); if (!xindata) { return; } }''';

/// 普通分类页（赚客吧）：既没有 `xb_page_flag` 也没有 `xb_config`，只有全局筛选；
/// 推送范围 token 是服务端占位没替换留下的空串。
const String _zuankebaMeta =
    r'''$(function () {window.xb_global_filter={"status":0,"bankuai":[],"louzhuregtime":"","rows":[],"legacy":{"kw":0,"keywords":[],"fanwei":[]}};window.xb_texts={};if (typeof xb_global_jsonfilter === "function") { xindata = xb_global_jsonfilter(xindata, ); if (!xindata) { return; } }''';

/// 首页 HTML 里的 meta 地址（带 HTML 转义的 `&amp;`）。
const String _homeHtmlScriptTag =
    r'''<script defer src="/zb_users/theme/xianbao_theme/script/meta.php?type=index&amp;pagination=1&amp;zdmserver=1"></script>''';

/// 分类页 HTML 里的 meta 地址：`cate-name` 是中文且带序号，App 拼不出来，只能抄。
const String _categoryHtmlScriptTag =
    r'''<script defer src="/zb_users/theme/xianbao_theme/script/meta.php?type=category&cateid=5&catename=guanzhu1&cate-name=我的关注①&pagination=1"></script>''';

/// 快捷筛选行：字段是裸 JS 变量，只有 URL 带 `?k=` 时才会顶替服务端配置，
/// 所以解析时必须跳过（App 从不带这些参数）。
const String _quickFilterMeta =
    r'''window.xb_page_flag='index';window.xb_config={xbquick:{Status:1,fanwei:"",mall_name:"",title_gjc:k,title_pbc:kp,brand_gjc:"",brand_pbc:"",category_gjc:cate,category_pbc:"",mall_gjc:mall,mall_pbc:"",Miprice:mip,Mxprice:mxp}};''';

/// 抓取时刻 `/plus/json/push.json` 里全部 20 条的分类名（站级推送源）。
const List<String> _realCatenames = <String>[
  '好单线报-饮料-京东',
  '好单线报-日用-淘宝',
  '微博线报-线报活动-外卖团购|整点',
  '好单线报-数码-京东',
  '好单线报-服饰-京东',
  '好单线报-母婴-淘宝',
  '好单线报-日用-京东',
  '好单线报-服饰-京东',
  '好单线报-服饰-京东',
  '好单线报-日用-京东',
  '赚客吧',
  '好单线报-美妆-京东',
  '好单线报-服饰-京东',
  '微博线报-线报活动-外卖团购|整点',
  '好单线报-服饰-京东',
  '好单线报-服饰-淘宝',
  '微博线报-线报活动-外卖团购',
  '好单线报-服饰-淘宝',
  '好单线报-服饰-京东',
  '微博线报-家用-京东',
];

/// 全局筛选：一行标题关键词 + 一行分类屏蔽词，分别声明范围。
const String _globalMeta =
    r'''window.xb_global_filter={"status":1,"bankuai":[],"louzhuregtime":"30","rows":[{"fanwei":"首页","title_gjc":"秒杀|整点","title_pbc":"","category_gjc":"","category_pbc":"","louzhu_gjc":"","louzhu_pbc":"","Miprice":"","Mxprice":""},{"fanwei":"分类页:赚客吧","title_gjc":"","title_pbc":"广告","category_gjc":"","category_pbc":"","louzhu_gjc":"","louzhu_pbc":"","Miprice":"","Mxprice":"100"}],"legacy":{"kw":0,"keywords":[],"fanwei":[]}};''';

void main() {
  group('kwHit / splitWords', () {
    test('按 # | <br> 和换行拆词，字面量包含匹配', () {
      expect(kwHit('线报活动|赚客吧', '这条来自赚客吧'), isTrue);
      expect(kwHit('线报活动#赚客吧', '这条来自赚客吧'), isTrue);
      expect(kwHit('线报活动<br>赚客吧', '这条来自赚客吧'), isTrue);
      expect(kwHit('线报活动\n赚客吧', '这条来自赚客吧'), isTrue);
      expect(kwHit('线报活动\r\n赚客吧', '这条来自赚客吧'), isTrue);
      expect(kwHit('线报活动|赚客吧', '这条来自好单线报'), isFalse);
    });

    test('大小写敏感，且词内符号按普通字符处理', () {
      // 网站改成字面量匹配后保留了旧的"大小写敏感"行为。
      expect(kwHit('ABC', 'abc'), isFalse);
      expect(kwHit('abc', 'abc'), isTrue);
      // 正则年代 `3.5` 会匹配 `3x5`，现在不会。
      expect(kwHit('3.5元', '3x5元'), isFalse);
      expect(kwHit('3.5元', '只要3.5元'), isTrue);
    });

    test('空词丢弃，不会造成空串恒命中', () {
      expect(splitWords('赚客吧##'), <String>['赚客吧']);
      expect(kwHit('|#', '随便什么'), isFalse);
    });
  });

  group('GlobalFilter', () {
    test('status 0 = 未启用，列表与推送都直通', () {
      final filter = GlobalFilter.fromMetaScript(_guanzhuMeta);
      expect(filter.status, 0);
      final item = const FilterItem(title: '随便', category: '赚客吧');
      expect(filter.keepsListItem(item, kHomeScopes), isTrue);
      expect(filter.keepsPushItem(item, kHomePushScopes), isTrue);
    });

    test('解析真实 meta 里的 xb_global_filter', () {
      final filter = GlobalFilter.fromMetaScript(_globalMeta);
      expect(filter.status, 1);
      expect(filter.rows.length, 2);
      expect(filter.authorRegDays, '30');
      expect(filter.rows.first.scope, '首页');
    });

    test('status 走数值转换（Number），规则行的 Status 走严格比较', () {
      // 网站对 status 用 Number()，对行上的 Status 用 !== 1。
      expect(
        GlobalFilter.fromMetaScript(
          'window.xb_global_filter={"status":"1","rows":[{"Status":1,"title_pbc":"广告"}]};',
        ).status,
        1,
      );
      expect(
        GlobalFilter.fromMetaScript(
          'window.xb_global_filter={"status":"abc","rows":[]};',
        ).status,
        0,
      );
      expect(
        GlobalFilter.fromMetaScript(
          r'window.xb_global_filter={"status":1,"rows":[{"Status":"1","title_pbc":"广告"}]};',
        ).rows.single.enabled,
        isFalse,
      );
    });

    test('行按 fanwei 分板块生效：不命中当前板块的行不参与', () {
      final filter = GlobalFilter.fromMetaScript(_globalMeta);
      // 首页行要求标题含「秒杀|整点」。
      expect(
        filter.keepsListItem(
          const FilterItem(title: '整点抢券', category: '好单线报-日用-京东'),
          kHomeScopes,
        ),
        isTrue,
      );
      expect(
        filter.keepsListItem(
          const FilterItem(title: '普通商品', category: '好单线报-日用-京东'),
          kHomeScopes,
        ),
        isFalse,
      );
      // 分类页里只有「分类页:赚客吧」那一行生效，标题规则不该再拦人。
      final scopes = categoryScopes('赚客吧-线报酷');
      expect(
        filter.keepsListItem(
          const FilterItem(title: '普通商品', category: '赚客吧'),
          scopes,
        ),
        isTrue,
      );
      expect(
        filter.keepsListItem(
          const FilterItem(title: '普通商品广告', category: '赚客吧'),
          scopes,
        ),
        isFalse,
      );
    });

    test('分类页: 范围支持前缀宽松命中（赚客吧 命中 分类页:赚客吧）', () {
      final scopes = categoryScopes('赚客吧-线报酷');
      expect(scopes, contains('分类页:赚客吧'));
      expect(scopes, contains('分类页:线报酷'));
    });

    test('行间 OR：任一行通过即保留', () {
      final filter = GlobalFilter.fromMetaScript(_globalMeta);
      // 被第一行拦下（标题不含关键词），但第二行只在分类页生效 —— 首页只有
      // 第一行适用，所以这里应当被屏蔽。
      expect(
        filter.keepsListItem(const FilterItem(title: '商品'), kHomeScopes),
        isFalse,
      );
    });

    test('价格区间两条路径都校验（20261001 起网站不再有不对称）', () {
      final filter = GlobalFilter.fromMetaScript(_globalMeta);
      final scopes = categoryScopes('赚客吧-线报酷');
      const expensive = FilterItem(
        title: '商品',
        category: '赚客吧',
        price: '888',
      );
      // 第二行（分类页:赚客吧，Mxprice=100）超价 → 列表与推送都拦。
      expect(filter.keepsListItem(expensive, scopes), isFalse);
      expect(filter.keepsPushItem(expensive, scopes), isFalse);
      expect(
        filter.keepsPushItem(
          const FilterItem(title: '商品', category: '赚客吧', price: '50'),
          scopes,
        ),
        isTrue,
      );
      // 无价条目在价格行放行（频道线报大量无价，网站改过两次才定成放行）。
      expect(
        filter.keepsListItem(
          const FilterItem(title: '商品', category: '赚客吧'),
          scopes,
        ),
        isTrue,
      );
    });

    test('louzhuregtime：注册天数小于阈值即屏蔽', () {
      final filter = GlobalFilter.fromMetaScript(_globalMeta);
      // 阈值 30 天：昨天注册的会被屏蔽，十年前注册的放行。
      final yesterday = DateTime.now()
          .subtract(const Duration(days: 1))
          .toIso8601String()
          .split(' ')
          .first;
      expect(
        filter.keepsListItem(
          FilterItem(
            title: '商品',
            category: '赚客吧',
            authorRegistrationTime: yesterday,
          ),
          categoryScopes('赚客吧-线报酷'),
        ),
        isFalse,
      );
      expect(
        filter.keepsListItem(
          const FilterItem(
            title: '商品',
            category: '赚客吧',
            authorRegistrationTime: '2014-2-11',
          ),
          categoryScopes('赚客吧-线报酷'),
        ),
        isTrue,
      );
    });

    test('legacy 旧键：分类范围前缀命中后按关键词屏蔽', () {
      const script =
          r'''window.xb_global_filter={"status":1,"bankuai":[],"louzhuregtime":"","rows":[],"legacy":{"kw":1,"keywords":["广告","薅羊毛"],"fanwei":["豆瓣线报"]}};''';
      final filter = GlobalFilter.fromMetaScript(script);
      const inScope = FilterItem(title: '这是一条广告', category: '豆瓣线报');
      const outOfScope = FilterItem(title: '这是一条广告', category: '赚客吧');
      // 范围外直通（不筛选）。
      expect(filter.keepsListItem(outOfScope, kHomeScopes), isTrue);
      // 范围内命中屏蔽词 → 移除。
      expect(filter.keepsListItem(inScope, kHomeScopes), isFalse);
      expect(
        filter.keepsListItem(
          const FilterItem(title: '正常内容', category: '豆瓣线报'),
          kHomeScopes,
        ),
        isTrue,
      );
      // 范围词是整词前缀匹配，不是「同一大类」匹配：网站注释里写的
      // 「'豆瓣线报' 命中所有豆瓣子组」和代码（`indexOf(word) === 0`）不一致，
      // 实际以代码为准 —— 豆瓣买组 不在范围内。
      expect(
        filter.keepsListItem(
          const FilterItem(title: '这是一条广告', category: '豆瓣买组'),
          kHomeScopes,
        ),
        isTrue,
      );
    });
  });

  group('PageFilterRules.fromCategoryMetaScript', () {
    test('解析真实「我的关注」脚本', () {
      final page = PageFilterRules.fromCategoryMetaScript(_guanzhuMeta);
      expect(page.pageFlag, 'guanzhu');
      expect(page.hasPageRules, isTrue);
      expect(page.rows.length, 1);
      expect(page.rows.single.enabled, isTrue);
      expect(page.rows.single.categoryGjc, _guanzhuKeywords);
      // 登录账号那份召回条件是空的（服务端已按同一条件召回 SSR 列表）。
      expect(page.recall.keywords, isEmpty);
    });

    test('关注页规则只放行分类名命中关键词的条目（真实 push.json 20 条）', () {
      final page = PageFilterRules.fromCategoryMetaScript(_guanzhuMeta);
      final kept = _realCatenames
          .map((name) => FilterItem(category: name))
          .where(page.keeps)
          .length;
      // 网站只插入 5 条，App 之前 20 条全插。
      expect(kept, 5);
    });

    test('分类名命中关键词的条目逐条确认', () {
      final page = PageFilterRules.fromCategoryMetaScript(_guanzhuMeta);
      for (final name in <String>[
        '微博线报-线报活动-外卖团购|整点',
        '微博线报-家用-京东',
        '赚客吧',
        '新赚吧',
        '小嘀咕',
        '豆瓣线报',
      ]) {
        expect(page.keeps(FilterItem(category: name)), isTrue, reason: name);
      }
      for (final name in <String>[
        '好单线报-服饰-京东',
        '值得买',
        '爱Q生活网',
        '酷安',
      ]) {
        expect(page.keeps(FilterItem(category: name)), isFalse, reason: name);
      }
    });

    test('未登录（空 xb_config）→ 不筛选', () {
      final page = PageFilterRules.fromCategoryMetaScript(
        'window.xb_config={};xb_liebiaoshaixuan(xb_config);',
      );
      expect(page.rows, isEmpty);
      for (final name in _realCatenames) {
        expect(page.keeps(FilterItem(category: name)), isTrue, reason: name);
      }
    });

    test('频道页的全空规则（zdmdefault）等于不筛选', () {
      final page = PageFilterRules.fromCategoryMetaScript(_weiboMeta);
      expect(page.pageFlag, 'index');
      expect(page.rows.length, 1);
      expect(page.rows.single.enabled, isTrue);
      expect(page.keeps(const FilterItem(category: '微博线报-线报活动-京东')), isTrue);
      expect(page.keeps(const FilterItem(category: '好单线报-服饰-京东')), isTrue);
    });

    test('值得买规则（无 type、只有 Mxprice）不会误伤条目', () {
      final page = PageFilterRules.fromCategoryMetaScript(_zhidemaiMeta);
      const zdm = FilterItem(
        type: 'smzdm',
        title: '温诗欧 实木柄16骨大号商务直柄伞 49.45元',
        price: '49.45',
        mallName: '京东',
        categoryName: '日用百货/生活用品/生活杂货',
      );
      expect(page.keeps(zdm), isTrue);
    });

    test('值得买商城名沿用网站的实参方向（拿条目名拆词查规则名）', () {
      // 网站写的是 `xb_kwHit(item.mall_name, group.mall_name)`：先用**条目**的商城名
      // 拆词，再看**规则**里的商城名是否包含其中某个词。方向与直觉相反（看着像网站
      // 写反了），但线上就是这个结果，照搬。
      final page = PageFilterRules.fromCategoryMetaScript(
        r'''window.xb_page_flag='index';window.xb_config={"r":{"Status":1,"mall_name":"京东自营|天猫精选"}};''',
      );
      FilterItem zdm(String mall) =>
          FilterItem(type: 'smzdm', title: '某商品', mallName: mall);
      expect(page.keeps(zdm('京东')), isTrue);
      expect(page.keeps(zdm('天猫精选')), isTrue);
      // 条目名比规则名更具体 → 用它拆出来的词在规则名里找不到 → 该行不通过。
      expect(page.keeps(zdm('京东自营旗舰店')), isFalse);
      expect(page.keeps(zdm('拼多多')), isFalse);
    });

    test('跳到裸变量的快捷筛选行，不把配置当规则', () {
      final page = PageFilterRules.fromCategoryMetaScript(_quickFilterMeta);
      expect(page.rows, isEmpty);
      expect(page.keeps(const FilterItem(category: '好单线报-服饰-京东')), isTrue);
    });

    test('对象形式与数组形式都能解析', () {
      expect(
        PageFilterRules.fromCategoryMetaScript(_weiboMeta).rows.length,
        1,
      );
      expect(
        PageFilterRules.fromCategoryMetaScript(_guanzhuMeta).rows.length,
        1,
      );
    });

    test('Status 不是数字 1 的行不生效（网站用的是严格比较）', () {
      const script =
          r'''window.xb_config=[{"Status":"1","category_gjc":"赚客吧"}];''';
      final page = PageFilterRules.fromCategoryMetaScript(script);
      expect(page.rows.single.enabled, isFalse);
      expect(page.keeps(const FilterItem(category: '好单线报-服饰-京东')), isTrue);
    });
  });

  group('GuanzhuRecall（召回守卫）', () {
    test('无召回条件 → 放行', () {
      final recall = PageFilterRules.fromCategoryMetaScript(_guanzhuMeta).recall;
      expect(recall.passes(const FilterItem(title: '任何东西')), isTrue);
    });

    test('真实未登录配置：OR 语义只看标题+分类+正文', () {
      final recall = PageFilterRules.fromCategoryMetaScript(
        _guestRecallMeta,
      ).recall;
      expect(recall.keywords, contains('赚客吧'));
      // 命中的是正文里的关键词。
      expect(
        recall.passes(
          const FilterItem(title: '无标题', content: '转自小嘀咕的一条线报'),
        ),
        isTrue,
      );
      expect(recall.passes(const FilterItem(title: '完全无关的内容')), isFalse);
    });

    test('excludes 任一命中即丢弃，且先于关键词判定', () {
      const script =
          r'''window.xb_guanzhu_recall={"keywords":["线报"],"authors":[],"excludes":["广告"],"operator":"OR"};''';
      final recall = PageFilterRules.fromCategoryMetaScript(script).recall;
      expect(recall.passes(const FilterItem(title: '一条线报')), isTrue);
      expect(recall.passes(const FilterItem(title: '一条线报（广告）')), isFalse);
    });

    test('AND 要求全部关键词命中', () {
      const script =
          r'''window.xb_guanzhu_recall={"keywords":["线报","活动"],"authors":[],"excludes":[],"operator":"AND"};''';
      final recall = PageFilterRules.fromCategoryMetaScript(script).recall;
      expect(recall.passes(const FilterItem(title: '线报活动来了')), isTrue);
      expect(recall.passes(const FilterItem(title: '线报来了')), isFalse);
    });

    test('仅作者条件时匹配楼主', () {
      const script =
          r'''window.xb_guanzhu_recall={"keywords":[],"authors":["佩奇线报"],"excludes":[],"operator":"OR"};''';
      final recall = PageFilterRules.fromCategoryMetaScript(script).recall;
      expect(
        recall.passes(const FilterItem(title: '无关标题', author: '佩奇线报')),
        isTrue,
      );
      expect(
        recall.passes(const FilterItem(title: '无关标题', author: '别人')),
        isFalse,
      );
    });
  });

  group('主列表入口与 keepPushItem', () {
    test('置顶条目豁免筛选', () {
      final meta = MetaFilterConfig.fromScript(_guanzhuMeta);
      const pinned = FilterItem(category: '好单线报-服饰-京东', isTop: true);
      expect(meta.keepsListItem(pinned, kHomeScopes), isTrue);
      // 非置顶的同一条会被页面规则拦掉。
      expect(
        meta.keepsListItem(
          const FilterItem(category: '好单线报-服饰-京东'),
          kHomeScopes,
        ),
        isFalse,
      );
    });

    test('关注页推送：召回守卫 + 页面规则后只剩 5 条', () {
      final page = PageFilterRules.fromCategoryMetaScript(_guanzhuMeta);
      final global = GlobalFilter.fromMetaScript(_guanzhuMeta);
      final kept = _realCatenames
          .map((name) => FilterItem(category: name))
          .where((item) => keepPushItem(item, global: global, page: page))
          .length;
      expect(kept, 5);
    });

    test('普通分类页/首页不做页面级筛选，只有全局筛选把关', () {
      final meta = MetaFilterConfig.fromScript(_globalMeta);
      // 首页：标题规则生效。
      expect(
        meta.keepsListItem(
          const FilterItem(title: '普通商品', category: '好单线报-日用-京东'),
          kHomeScopes,
        ),
        isFalse,
      );
      expect(
        meta.keepsListItem(
          const FilterItem(title: '整点秒杀', category: '好单线报-日用-京东'),
          kHomeScopes,
        ),
        isTrue,
      );
    });

    test('关注页推送不再需要页面对象时只走全局筛选', () {
      final global = GlobalFilter.fromMetaScript(_guanzhuMeta);
      expect(
        keepPushItem(
          const FilterItem(title: '随便一条', category: '酷安'),
          global: global,
        ),
        isTrue,
      );
    });
  });

  group('范围与路径', () {
    test('categoryScopes 取标题各段', () {
      expect(categoryScopes('赚客吧-线报酷'), <String>[
        '主列表',
        '分类页',
        '分类页:赚客吧',
        '分类页:线报酷',
      ]);
      expect(categoryScopes(''), <String>['主列表', '分类页']);
    });

    test('分类分页路径跟着网站改版走', () {
      // 网站已从 /category-x/page/2/ 改成 /category-x/2/。
      expect(categoryPagePath('haodan', 1), '/category-haodan/');
      expect(categoryPagePath('haodan', 2), '/category-haodan/2/');
      expect(categoryPagePath('guanzhu1', 3), '/category-guanzhu1/3/');
    });
  });

  group('metaScriptPath（照抄页面的 meta 地址）', () {
    test('取出 script src 并还原 &amp;', () {
      expect(
        metaScriptPath(_homeHtmlScriptTag),
        '/zb_users/theme/xianbao_theme/script/meta.php'
        '?type=index&pagination=1&zdmserver=1',
      );
    });

    test('中文 + 序号的 cate-name 原样带出来（App 自己拼不出来）', () {
      expect(
        metaScriptPath(_categoryHtmlScriptTag),
        '/zb_users/theme/xianbao_theme/script/meta.php?type=category&cateid=5'
        '&catename=guanzhu1&cate-name=我的关注①&pagination=1',
      );
    });

    test('页面里没有 meta script → null', () {
      expect(metaScriptPath('<html><body>hi</body></html>'), isNull);
      expect(metaScriptPath(''), isNull);
    });
  });

  group('MetaFilterConfig（该页自己的判定方式）', () {
    test('首页：推送守卫 xb_json_guard + 三个 token 的全局范围', () {
      final meta = MetaFilterConfig.fromScript(_indexMeta);
      expect(meta.usesJsonGuard, isTrue);
      expect(meta.pushScopes, kHomePushScopes);
      expect(meta.listUsesConfigRules, isFalse);
      expect(meta.listUsesGuardRows, isFalse);
      expect(meta.extractPriceFromTitle, isFalse);
    });

    test('去掉 zdmserver 的首页：主列表改由内联 DOM 块筛，价格从标题补', () {
      final meta = MetaFilterConfig.fromScript(_indexMetaNoZdmServer);
      expect(meta.listUsesGuardRows, isTrue);
      expect(meta.extractPriceFromTitle, isTrue);
      // 同一个屏蔽词这次落在 category_pbc 上 —— 参数不同，配置就不同。
      expect(
        meta.keepsListItem(
          const FilterItem(title: '贝贝南瓜5斤 7.99元', category: '好单线报-果蔬-京东'),
          kHomeScopes,
        ),
        isFalse,
      );
      expect(
        meta.keepsListItem(
          const FilterItem(title: '贝贝南瓜5斤 7.99元', category: '酷安'),
          kHomeScopes,
        ),
        isTrue,
      );
    });

    test('分类页：主列表走 xb_config，推送范围是空 token', () {
      final meta = MetaFilterConfig.fromScript(_haodanJdMeta);
      expect(meta.listUsesConfigRules, isTrue);
      expect(meta.pushScopes, <String>['']);
      expect(meta.page.channelGuard?.platformNames, <String>['京东', '淘宝京东']);
    });

    test('值得买页的推送压根不走全局 JSON 筛选', () {
      expect(MetaFilterConfig.fromScript(_zhidemaiMeta).pushScopes, isNull);
    });

    test('关注页解析出轮询开关与召回条件', () {
      final meta = MetaFilterConfig.fromScript(_guanzhuMeta);
      expect(meta.page.pollOn, 1);
      expect(meta.page.pageFlag, 'guanzhu');
      expect(meta.page.pageSub, '1');
    });

    test('普通分类页：没有页面规则，推送只过全局筛选', () {
      final meta = MetaFilterConfig.fromScript(_zuankebaMeta);
      expect(meta.page.hasPageRules, isFalse);
      expect(meta.page.rows, isEmpty);
      expect(meta.pushScopes, <String>['']);
      expect(meta.usesJsonGuard, isFalse);
      expect(
        meta.keepsPush(const FilterItem(title: '随便一条', category: '赚客吧')),
        isTrue,
      );
    });
  });

  group('首页推送守卫（xb_json_guard / xb_rows_pass）', () {
    test('规则行的屏蔽词命中标题 → 该条推送不插', () {
      final meta = MetaFilterConfig.fromScript(_indexMeta);
      expect(
        meta.keepsPush(
          const FilterItem(title: '好单线报 今日好单汇总', category: '酷安'),
        ),
        isFalse,
      );
      // title_pbc 只看标题+正文：分类名里带「好单线报」不触发（网站这次把词下发在
      // 标题字段上，屏蔽的是标题里提到该词的条目）。
      expect(
        meta.keepsPush(
          const FilterItem(title: '贝贝南瓜5斤 7.99元', category: '好单线报-果蔬-京东'),
        ),
        isTrue,
      );
    });

    test('xb_rows_pass：正向行之间 OR', () {
      final page = PageFilterRules.fromCategoryMetaScript(
        r'''window.xb_config=[{"Status":1,"title_gjc":"秒杀|整点"},{"Status":1,"title_gjc":"买一送一"}];''',
      );
      final rows = page.rows;
      expect(pageRowsPass(rows, const FilterItem(title: '整点抢券')), isTrue);
      expect(pageRowsPass(rows, const FilterItem(title: '买一送一活动')), isTrue);
      expect(pageRowsPass(rows, const FilterItem(title: '普通商品')), isFalse);
    });

    test('xb_rows_pass：屏蔽词是全局否决，压过其它行的正向命中', () {
      final page = PageFilterRules.fromCategoryMetaScript(
        r'''window.xb_config=[{"Status":1,"title_pbc":"广告"},{"Status":1,"title_gjc":"秒杀"}];''',
      );
      final rows = page.rows;
      expect(pageRowsPass(rows, const FilterItem(title: '秒杀来了')), isTrue);
      expect(pageRowsPass(rows, const FilterItem(title: '秒杀广告贴')), isFalse);
      expect(pageRowsPass(rows, const FilterItem(title: '普通广告贴')), isFalse);
    });

    test('xb_rows_pass：只有屏蔽词没有正向条件时，未命中就保留', () {
      final page = PageFilterRules.fromCategoryMetaScript(
        r'''window.xb_config=[{"Status":1,"title_pbc":"广告"}];''',
      );
      final rows = page.rows;
      expect(pageRowsPass(rows, const FilterItem(title: '正常内容')), isTrue);
      expect(pageRowsPass(rows, const FilterItem(title: '广告内容')), isFalse);
    });

    test('xb_rows_pass：行的 fanwei 不覆盖分类名就不参与；都不覆盖则整条丢', () {
      final page = PageFilterRules.fromCategoryMetaScript(
        r'''window.xb_config=[{"Status":1,"fanwei":"豆瓣线报","title_gjc":"秒杀"}];''',
      );
      final rows = page.rows;
      expect(
        pageRowsPass(rows, const FilterItem(title: '秒杀', category: '豆瓣线报')),
        isTrue,
      );
      expect(
        pageRowsPass(rows, const FilterItem(title: '秒杀', category: '赚客吧')),
        isFalse,
      );
    });

    test('空规则表 → 整条丢（网站 if (!rows.length) return false）', () {
      expect(pageRowsPass(const [], const FilterItem(title: '随便')), isFalse);
    });
  });

  group('频道守卫与页面细分', () {
    test('子频道按尾段平台过滤推送（cateid 与父频道相同）', () {
      final guard = MetaFilterConfig.fromScript(
        _haodanJdMeta,
      ).page.channelGuard!;
      expect(
        channelGuardPass(
          guard,
          const FilterItem(category: '好单线报-食品-京东', cateId: 30),
        ),
        isTrue,
      );
      expect(
        channelGuardPass(
          guard,
          const FilterItem(category: '好单线报-日用-淘宝', cateId: 30),
        ),
        isFalse,
      );
      expect(
        channelGuardPass(
          guard,
          const FilterItem(category: '好单线报-日用-京东', cateId: 10),
        ),
        isFalse,
      );
    });

    test('子频道页推送端到端：平台不符的好单推送不再插进京东页', () {
      final meta = MetaFilterConfig.fromScript(_haodanJdMeta);
      expect(
        meta.keepsPush(
          const FilterItem(title: '某商品', category: '好单线报-食品-京东', cateId: 30),
        ),
        isTrue,
      );
      expect(
        meta.keepsPush(
          const FilterItem(title: '某商品', category: '好单线报-日用-淘宝', cateId: 30),
        ),
        isFalse,
      );
    });

    test('真实好单推送（20 条）：父频道不受平台限制，子频道只留京东 6 条', () {
      final parent = MetaFilterConfig.fromScript(_haodanMeta);
      final child = MetaFilterConfig.fromScript(_haodanJdMeta);
      FilterItem item(String catename) =>
          FilterItem(category: catename, cateId: 30);

      expect(
        _haodanFeedCatenames.where((c) => parent.keepsPush(item(c))).length,
        20,
      );
      // 尾段是「京东」的 6 条；淘宝/其他活动/猫超那些不再混进京东子频道。
      expect(
        _haodanFeedCatenames.where((c) => child.keepsPush(item(c))).length,
        6,
      );
    });
  });

  group('关注页与推送范围', () {
    test('轮询开关没开时关注页推送一条都不插', () {
      final meta = MetaFilterConfig.fromScript(_guestMeta);
      expect(
        meta.keepsPush(const FilterItem(title: '赚客吧线报', category: '赚客吧')),
        isFalse,
      );
      // 主列表不受影响：游客那份 xb_config 是空对象。
      expect(
        meta.keepsListItem(
          const FilterItem(title: '赚客吧线报', category: '赚客吧'),
          kHomeScopes,
        ),
        isTrue,
      );
    });

    test('分类页的空 token 范围只让 fanwei 留空的行生效', () {
      const script =
          r'''window.xb_global_filter={"status":1,"bankuai":[],"louzhuregtime":"","rows":[{"fanwei":"推送","title_gjc":"甲"},{"fanwei":"","title_gjc":"乙"}],"legacy":{"kw":0,"keywords":[],"fanwei":[]}};if (typeof xb_global_jsonfilter === "function") { xindata = xb_global_jsonfilter(xindata, ); }''';
      final meta = MetaFilterConfig.fromScript(script);
      expect(meta.pushScopes, <String>['']);
      final titled = GlobalFilter.fromMetaScript(script);
      // 空 token：只有 fanwei 留空的那一行参与 → 只有「乙」能过。
      expect(
        titled.keepsPushItem(const FilterItem(title: '含甲'), <String>['']),
        isFalse,
      );
      expect(
        titled.keepsPushItem(const FilterItem(title: '含乙'), <String>['']),
        isTrue,
      );
      // 首页那份范围里带「推送」，两行都参与，行间 OR → 两条都过。
      expect(
        titled.keepsPushItem(const FilterItem(title: '含甲'), kHomePushScopes),
        isTrue,
      );
    });
  });

  group('标题价格提取', () {
    test('与 meta.php 的 IIFE 正则一致', () {
      expect(priceFromTitle('乐百氏天然矿泉水360ml*24瓶 23.9元'), '23.9');
      expect(priceFromTitle('到手价 ¥15 包邮'), '15');
      expect(priceFromTitle('64 猫超 OffRelax蓬松洗发水660ml'), '');
    });

    test('只补空缺：data-price 已有就原样用', () {
      const withPrice = FilterItem(title: '某商品 99元', price: '49');
      expect(withPrice.withPriceFromTitle().price, '49');
      const noPrice = FilterItem(title: '某商品 99元');
      expect(noPrice.withPriceFromTitle().price, '99');
    });

    test('补出来的价格会被价格行用上（网站首页就是这么补的）', () {
      const script =
          r'''window.xb_global_filter={"status":1,"bankuai":[],"louzhuregtime":"","rows":[{"fanwei":"","Mxprice":"50"}],"legacy":{"kw":0,"keywords":[],"fanwei":[]}};''';
      final meta = MetaFilterConfig.fromScript(script);
      // meta 没有价格提取 IIFE → 不补价：无价条目放行（与网站 zdmserver 模式一致）。
      expect(
        meta.keepsListItem(const FilterItem(title: '某商品 99元'), kHomeScopes),
        isTrue,
      );
      // 带上提取 IIFE 的页面才会补价，补完就被 Mxprice 拦掉。
      final withExtraction = MetaFilterConfig.fromScript(
        '${script}setAttribute("data-price", x);',
      );
      expect(
        withExtraction.keepsListItem(
          const FilterItem(title: '某商品 99元'),
          kHomeScopes,
        ),
        isFalse,
      );
      expect(
        withExtraction.keepsListItem(
          const FilterItem(title: '某商品 30元'),
          kHomeScopes,
        ),
        isTrue,
      );
    });
  });
}
