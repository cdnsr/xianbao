import 'package:flutter_test/flutter_test.dart';
import 'package:xianbao/models/site_filter.dart';
import 'package:xianbao/services/http_client.dart';

/// 网站 2026-09 改版后的筛选引擎移植测试。
///
/// 夹具全部取自线上真实响应（2026-09-30 抓取）：
///
/// - [_guanzhuMeta]：登录账号的「我的关注」分类 meta.php（`cookie.txt` 账号）；
/// - [_guestRecallMeta]：未登录时的同一页 meta.php；
/// - [_weiboMeta] / [_zhidemaiMeta]：微博线报、值得买的 meta.php；
/// - [_realCatenames]：当时 `/plus/json/push.json` 全部 20 条的 `catename`。
const String _guanzhuMeta =
    r'''$(function () {window.xb_global_filter={"status":0,"bankuai":[],"louzhuregtime":"","rows":[],"legacy":{"kw":0,"keywords":[],"fanwei":[]}};window.xb_page_flag='guanzhu';window.xb_page_sub='1';window.xb_config=[{"Status":1,"fanwei":"","title_gjc":"","title_pbc":"","brand_gjc":"","brand_pbc":"","category_gjc":"赚客吧#新赚吧#微博线报#豆瓣线报#小嘀咕","category_pbc":"","mall_gjc":"","mall_pbc":"","louzhu_gjc":"","louzhu_pbc":"","Miprice":"","Mxprice":""}];''';

/// `赚客吧` 等转义解出来就是这条规则的关键词。
const String _guanzhuKeywords = '赚客吧#新赚吧#微博线报#豆瓣线报#小嘀咕';

/// 未登录时同一页下发的召回条件（登录账号那一份是空的）。
const String _guestRecallMeta =
    r'''window.xb_guanzhu_recall={"keywords":["线报活动","赚客吧","新赚吧","小嘀咕","豆瓣线报"],"authors":[],"excludes":[],"operator":"OR"};''';

/// 微博线报/好单线报这类频道页：一行全空规则，等于不筛选。
const String _weiboMeta =
    r'''window.xb_page_flag='index';window.xb_config={"zdmdefault":{"Status":1,"fanwei":"","mall_name":"","title_gjc":"","title_pbc":"","brand_gjc":"","brand_pbc":"","category_gjc":"","category_pbc":"","mall_gjc":"","mall_pbc":"","Miprice":"","Mxprice":""}};''';

/// 值得买页的规则：只有 Mxprice，而且没有 `type`。
const String _zhidemaiMeta =
    r'''window.xb_page_flag='index';window.xb_config={"midoYbvHwPt":{"Status":1,"mall_name":"","title_gjc":"","title_pbc":"","category_gjc":"","category_pbc":"","Miprice":"","Mxprice":"1000000"}};''';

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
      expect(filter.keepsPushItem(item, kPushScopes), isTrue);
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

    test('价格约束只在推送路径生效（网站自身的不对称）', () {
      final filter = GlobalFilter.fromMetaScript(_globalMeta);
      final scopes = categoryScopes('赚客吧-线报酷');
      const expensive = FilterItem(
        title: '商品',
        category: '赚客吧',
        price: '888',
      );
      // SSR 列表路径不校验价格。
      expect(filter.keepsListItem(expensive, scopes), isTrue);
      // 推送路径校验 Mxprice。
      expect(filter.keepsPushItem(expensive, scopes), isFalse);
      expect(
        filter.keepsPushItem(
          const FilterItem(title: '商品', category: '赚客吧', price: '50'),
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

  group('keepMainListItem / keepPageListItem / keepPushItem', () {
    test('置顶条目豁免筛选', () {
      final page = PageFilterRules.fromCategoryMetaScript(_guanzhuMeta);
      const pinned = FilterItem(category: '好单线报-服饰-京东', isTop: true);
      expect(keepPageListItem(pinned, page), isTrue);
      // 非置顶的同一条会被页面规则拦掉。
      expect(
        keepPageListItem(
          const FilterItem(category: '好单线报-服饰-京东'),
          page,
        ),
        isFalse,
      );
    });

    test('关注页推送：召回守卫 → 页面规则 → 全局筛选', () {
      final page = PageFilterRules.fromCategoryMetaScript(_guanzhuMeta);
      final global = GlobalFilter.fromMetaScript(_guanzhuMeta);
      final kept = _realCatenames
          .map((name) => FilterItem(category: name))
          .where((item) => keepPushItem(item, global: global, page: page))
          .length;
      expect(kept, 5);
    });

    test('普通分类页/首页不做页面级筛选，只有全局筛选把关', () {
      final global = GlobalFilter.fromMetaScript(_globalMeta);
      // 首页：标题规则生效。
      expect(
        keepMainListItem(
          const FilterItem(title: '普通商品', category: '好单线报-日用-京东'),
          global,
          kHomeScopes,
        ),
        isFalse,
      );
      expect(
        keepMainListItem(
          const FilterItem(title: '整点秒杀', category: '好单线报-日用-京东'),
          global,
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
}
