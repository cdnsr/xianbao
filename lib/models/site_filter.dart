import 'dart:convert';

import 'article.dart';

/// 网站（new.xianbao.fun）列表筛选引擎的 Dart 移植。
///
/// 网站 2026-09 把筛选重做成三层，全部在浏览器里跑（旧协议是
/// `listfilter(xindata, 11个字符串)`，已随改版下线）：
///
/// 1. **全局筛选** `window.xb_global_filter`（Ucenter「全局筛选」），按行上的
///    `fanwei` 范围 token 分板块生效，主列表与推送共用；
/// 2. **页面级筛选** `window.xb_config`（各分类页/频道页/关注页自己的规则行）。
///    页面一旦带 `xb_page_flag`，网站就**跳过**全局筛选，只走这一层；
/// 3. **召回守卫** `window.xb_guanzhu_recall`，只有「我的关注」页的推送条目要用。
///
/// 判定语义逐条对齐线上 `theme/xianbao_theme/script/app/list.js` 与
/// `script/meta.php`：
///
/// - 关键词按 `#` / `|` / `<br>` / 换行拆成词后做**字面量**包含匹配
///   （`indexOf`，大小写敏感，空词丢弃）——改版后正则已下线，词内的 `.` `?`
///   等符号一律按普通字符处理；
/// - 规则行内每组字段是「关键词(gjc) 空或命中 **且** 屏蔽词(pbc) 空或不命中」；
/// - 行与行之间 **OR**：任一行通过即保留，全空行直通；
/// - `li.article-list.top` 置顶条目豁免主列表的两种筛选（网站两个入口都跳过）。

/// 换行/分隔符拆词用的分割符，与网站的 `xb_kwHit` 拆分规则一致。
final RegExp _wordSplitter = RegExp(r'\||#|<br>|\r\n|\r|\n');

/// `xb_config` 的 JS 对象字面量字段（值可能是引号串、数字或裸变量）。
final RegExp _configField = RegExp(
  r'''([A-Za-z_$][A-Za-z0-9_$]*)\s*:\s*(?:"((?:\\.|[^"\\])*)"|'((?:\\.|[^'\\])*)'|([^,}]*))''',
);

final RegExp _statusField = RegExp(r'(^|[,{[])\s*"?Status"?\s*:');

/// 拆词结果缓存（网站同样缓存，避免逐条重复 split）。
final Map<String, List<String>> _wordCache = <String, List<String>>{};
const int _wordCacheLimit = 256;

/// `xb_kwHit`：把 [pattern] 拆成词，任一词被 [text] 字面量包含即命中。
bool kwHit(String pattern, String text) {
  if (pattern.isEmpty || text.isEmpty) return false;
  for (final word in splitWords(pattern)) {
    if (text.contains(word)) return true;
  }
  return false;
}

/// 按 `#` / `|` / `<br>` / 换行拆词，去空白、丢空词。结果按原文缓存。
List<String> splitWords(String pattern) {
  if (pattern.isEmpty) return const <String>[];
  final cached = _wordCache[pattern];
  if (cached != null) return cached;
  final words = <String>[];
  for (final part in pattern.split(_wordSplitter)) {
    final word = part.trim();
    if (word.isNotEmpty) words.add(word);
  }
  if (_wordCache.length >= _wordCacheLimit) _wordCache.clear();
  _wordCache[pattern] = words;
  return words;
}

/// 按 `-` 取尾段（关注页/频道页的商城名回退口径）。无分隔符 → 空串。
String _trailingSegment(String text) {
  final index = text.lastIndexOf('-');
  return index < 0 ? '' : text.substring(index + 1);
}

/// 严格数值：空串或非有限数 → null（对应 `raw !== "" && isFinite(Number(raw))`）。
double? _asNumber(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final value = double.tryParse(text);
  if (value == null || !value.isFinite) return null;
  return value;
}

/// 宽松数值：只有空串才回 null，非数值 → NaN（网站频道分支就是直接 `Number()`，
/// NaN 参与比较恒为 false，等价于「该行价格约束不生效」）。
double? _looseNumber(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  return double.tryParse(text) ?? double.nan;
}

/// 注册天数。网站的 `daysComputed` 用 `new Date(s.replace(/-/g,'/'))`；这里额外
/// 兼容 10 位秒级时间戳（网站只有推送分支认它，DOM 分支会让它退化成 0 天而误杀
/// 条目——那种情况线上不会出现，没必要把这个坑一起搬过来）。
int? registrationAgeDays(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  if (text.isEmpty) return null;

  DateTime? registeredAt;
  final seconds = RegExp(r'^\d{10}$');
  if (seconds.hasMatch(text)) {
    registeredAt = DateTime.fromMillisecondsSinceEpoch(int.parse(text) * 1000);
  } else {
    final epoch = int.tryParse(text);
    if (epoch != null) {
      registeredAt = DateTime.fromMillisecondsSinceEpoch(
        epoch < 1000000000000 ? epoch * 1000 : epoch,
      );
    } else {
      // 站上形如 "2014-2-11"（月/日不补零），Dart 的 DateTime.parse 不一定吃。
      final match = RegExp(
        r'(\d{4})[-/](\d{1,2})[-/](\d{1,2})',
      ).firstMatch(text);
      if (match != null) {
        registeredAt = DateTime(
          int.parse(match.group(1)!),
          int.parse(match.group(2)!),
          int.parse(match.group(3)!),
        );
      }
    }
  }
  if (registeredAt == null) return null;

  final age = DateTime.now().difference(registeredAt);
  return age.isNegative ? 0 : age.inDays;
}

/// 归一化后的待筛选条目：DOM 列表项与推送项都映射成这一种输入。
class FilterItem {
  /// 标题。
  final String title;

  /// 正文/摘要（DOM `data-content`、推送 `content`）。
  final String content;

  /// 分类名（DOM `data-catename`、推送 `catename`）。
  final String category;

  /// 楼主（DOM `data-louzhu`、推送 `louzhu`）。
  final String author;

  /// 原始价格串，空串表示无价（网站区分「无价」与「0」）。
  final String price;

  /// 推送字段 `platforms`，关注页商城名优先取它。
  final String platforms;

  /// DOM `data-type`，值得买条目为 `smzdm`。
  final String type;

  /// DOM `data-brand`。
  final String brand;

  /// DOM `data-mall_name`。
  final String mallName;

  /// DOM `data-category_name`。
  final String categoryName;

  /// 分类 id：推送取 `cateid`，DOM 由 `figure.cgN` 推断。
  final int? cateId;

  /// 楼主注册时间（`data-louzhuregtime` / `louzhuregtime`）。
  final Object? authorRegistrationTime;

  /// `li.article-list.top`，置顶豁免；
  final bool isTop;

  const FilterItem({
    this.title = '',
    this.content = '',
    this.category = '',
    this.author = '',
    this.price = '',
    this.platforms = '',
    this.type = '',
    this.brand = '',
    this.mallName = '',
    this.categoryName = '',
    this.cateId,
    this.authorRegistrationTime,
    this.isTop = false,
  });

  factory FilterItem.fromArticle(ArticleListItem article) => FilterItem(
    title: article.title,
    content: article.summary,
    category: article.category,
    author: article.author,
    price: article.price,
    platforms: article.platforms,
    type: article.type,
    brand: article.brand,
    mallName: article.mallName,
    categoryName: article.categoryName,
    cateId: article.cateId,
    authorRegistrationTime: article.authorRegistrationTime,
    isTop: article.isTop,
  );

  /// 关注页/频道页里的「分类名」：`catename || category_name`。
  String get effectiveCategory => category.isNotEmpty ? category : categoryName;
}

/// 一行筛选规则（`xb_global_filter.rows[i]` / `xb_config` 的值）。
class FilterRule {
  /// `Status === 1` 才生效（网站用的是严格不等，字符串 `"1"` 不算启用）。
  final bool enabled;

  /// `fanwei` 生效范围，空 = 全板块。
  final String scope;

  final String titleGjc;
  final String titlePbc;
  final String categoryGjc;
  final String categoryPbc;

  /// 网站目前没有任何分支读 `brand_*`，解析保留以便对齐结构。
  final String brandGjc;
  final String brandPbc;

  final String mallGjc;
  final String mallPbc;
  final String authorGjc;
  final String authorPbc;

  /// 值得买行的 type（只有 `smzdm` 分支会用到）。
  final String type;

  /// 值得买行的商城名。
  final String mallName;

  final String minPrice;
  final String maxPrice;

  const FilterRule({
    this.enabled = false,
    this.scope = '',
    this.titleGjc = '',
    this.titlePbc = '',
    this.categoryGjc = '',
    this.categoryPbc = '',
    this.brandGjc = '',
    this.brandPbc = '',
    this.mallGjc = '',
    this.mallPbc = '',
    this.authorGjc = '',
    this.authorPbc = '',
    this.type = '',
    this.mallName = '',
    this.minPrice = '',
    this.maxPrice = '',
  });

  factory FilterRule.fromJson(Map<String, dynamic> json) {
    String text(String key) {
      final value = json[key];
      return value == null ? '' : value.toString();
    }

    return FilterRule(
      enabled: json['Status'] is num && json['Status'] == 1,
      scope: text('fanwei'),
      titleGjc: text('title_gjc'),
      titlePbc: text('title_pbc'),
      categoryGjc: text('category_gjc'),
      categoryPbc: text('category_pbc'),
      brandGjc: text('brand_gjc'),
      brandPbc: text('brand_pbc'),
      mallGjc: text('mall_gjc'),
      mallPbc: text('mall_pbc'),
      authorGjc: text('louzhu_gjc'),
      authorPbc: text('louzhu_pbc'),
      type: text('type'),
      mallName: text('mall_name'),
      minPrice: text('Miprice'),
      maxPrice: text('Mxprice'),
    );
  }

  /// 从 JS 对象字面量解析一行；行内出现裸变量（`title_gjc:k` 这种 `xbquick`
  /// 快捷筛选行，只有 URL 带 `?k=` 时才会顶替服务端配置）→ 返回 null 跳过。
  static FilterRule? fromJsObjectLiteral(String body) {
    final fields = <String, dynamic>{};
    for (final match in _configField.allMatches(body)) {
      final key = match.group(1)!;
      final quoted = match.group(2) ?? match.group(3);
      if (quoted != null) {
        fields[key] = quoted
            .replaceAll(r'\"', '"')
            .replaceAll(r"\'", "'")
            .replaceAll(r'\\', r'\');
        continue;
      }
      final bare = (match.group(4) ?? '').trim();
      final number = num.tryParse(bare);
      if (number != null) {
        fields[key] = number;
        continue;
      }
      return null; // 裸 JS 变量，整行不可用
    }
    if (fields.isEmpty) return null;
    return FilterRule.fromJson(fields);
  }

  bool get hasPriceBound =>
      _asNumber(minPrice) != null || _asNumber(maxPrice) != null;
}

/// 「我的关注」召回条件 `window.xb_guanzhu_recall`。
///
/// 只作用于推送条目（SSR 列表已由服务端按同一条件召回，网站不会二次过滤）。
class GuanzhuRecall {
  final List<String> keywords;
  final List<String> authors;
  final List<String> excludes;
  final String operator;

  const GuanzhuRecall({
    this.keywords = const [],
    this.authors = const [],
    this.excludes = const [],
    this.operator = '',
  });

  static const GuanzhuRecall empty = GuanzhuRecall();

  factory GuanzhuRecall.fromJson(Object? json) {
    if (json is! Map) return GuanzhuRecall.empty;
    List<String> list(Object? value) => value is List
        ? value.map((e) => e?.toString() ?? '').toList()
        : const <String>[];
    return GuanzhuRecall(
      keywords: list(json['keywords']),
      authors: list(json['authors']),
      excludes: list(json['excludes']),
      operator: json['operator']?.toString() ?? '',
    );
  }

  /// `guanzhu_push_guard`：true = 放行。
  bool passes(FilterItem item) {
    // 匹配文本是「标题 + 分类名」直接拼接，再接换行 + 正文（网站原样如此）。
    // 这里用的是推送字段 `catename`，不带 `category_name` 回退（那是
    // `xb_listfilter` 的口径）。
    final text = '${item.title}${item.category}\n${item.content}';

    for (final word in excludes) {
      if (word.isNotEmpty && kwHit(word, text)) return false;
    }

    var keywordHit = false;
    var keywordValid = 0;
    var keywordAll = true;
    for (final word in keywords) {
      if (word.isEmpty) continue;
      keywordValid++;
      if (kwHit(word, text)) {
        keywordHit = true;
      } else {
        keywordAll = false;
      }
    }

    var authorHit = false;
    var authorValid = 0;
    for (final word in authors) {
      if (word.isEmpty) continue;
      authorValid++;
      if (kwHit(word, item.author)) authorHit = true;
    }

    if (keywordValid == 0 && authorValid == 0) return true;
    if (keywordValid > 0 && authorValid > 0) {
      if (operator == 'AND') return keywordAll && authorHit;
      return keywordHit || authorHit;
    }
    if (keywordValid > 0) return operator == 'AND' ? keywordAll : keywordHit;
    return authorHit;
  }
}

/// 全局筛选 `window.xb_global_filter`。
class GlobalFilter {
  /// 网站的 `Number(cfg.status) !== 1` 会做数值转换，所以字符串 `"1"` 也算启用。
  final int status;
  final List<String> bankuai;
  final String authorRegDays;
  final List<FilterRule> rows;

  /// `legacy` 旧键兜底：只有在没有 `rows` 且 `kw == 1` 时才走屏蔽语义。
  final bool legacyKeywordEnabled;
  final List<String> legacyKeywords;
  final List<String> legacyScopes;

  const GlobalFilter({
    this.status = 0,
    this.bankuai = const [],
    this.authorRegDays = '',
    this.rows = const [],
    this.legacyKeywordEnabled = false,
    this.legacyKeywords = const [],
    this.legacyScopes = const [],
  });

  static const GlobalFilter empty = GlobalFilter();

  /// 解析 meta.php 里的 `window.xb_global_filter={...}`；缺失/坏 JSON → 空规则。
  factory GlobalFilter.fromMetaScript(String script) {
    final raw = _rawAssignment(script, 'window.xb_global_filter');
    if (raw == null) return GlobalFilter.empty;
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return GlobalFilter.empty;
    }
    if (decoded is! Map) return GlobalFilter.empty;

    final statusRaw = decoded['status'];
    final legacy = decoded['legacy'] is Map
        ? Map<String, dynamic>.from(decoded['legacy'] as Map)
        : const <String, dynamic>{};

    return GlobalFilter(
      status: _numericFlag(statusRaw),
      bankuai: _stringList(decoded['bankuai']),
      authorRegDays: decoded['louzhuregtime']?.toString() ?? '',
      rows: _ruleList(decoded['rows']),
      legacyKeywordEnabled: _numericFlag(legacy['kw']) == 1,
      legacyKeywords: _stringList(legacy['keywords']),
      legacyScopes: _stringList(legacy['fanwei']),
    );
  }

  /// 主列表（DOM）：网站这条路径**不校验价格**。
  bool keepsListItem(FilterItem item, List<String> scopes) {
    final gate = _gate(scopes);
    if (gate == null) return true;
    return _keeps(item, gate, withPrice: false);
  }

  /// 推送（JSON）：网站这条路径校验 `Miprice`/`Mxprice` 与条目 `price`。
  bool keepsPushItem(FilterItem item, List<String> scopes) {
    final gate = _gate(scopes);
    if (gate == null) return true;
    return _keeps(item, gate, withPrice: true);
  }

  /// `xb_global_gate`：当前板块适用的规则；null = 本板块不做全局筛选。
  _GlobalGate? _gate(List<String> scopes) {
    if (status != 1) return null;

    if (bankuai.isNotEmpty && !bankuai.any(scopes.contains)) return null;

    final hasRows = rows.isNotEmpty;
    final applicable = <FilterRule>[];
    if (hasRows) {
      for (final row in rows) {
        if (_scopeMatches(row.scope, scopes)) applicable.add(row);
      }
      // 没有任何行声明本板块 → 本板块直通，避免板块间规则互相清空。
      if (applicable.isEmpty) return null;
    }

    final legacyOn = !hasRows && legacyKeywordEnabled;
    final keywords = legacyOn && legacyKeywords.isNotEmpty
        ? legacyKeywords
        : null;
    final inScopeWords = legacyOn && legacyScopes.isNotEmpty
        ? legacyScopes
        : null;
    final regDays = _asNumber(authorRegDays)?.toInt();

    if (!hasRows && keywords == null && inScopeWords == null && regDays == null) {
      return null;
    }
    return _GlobalGate(
      rows: hasRows ? applicable : null,
      keywords: keywords,
      legacyScopes: inScopeWords,
      authorRegDays: regDays,
    );
  }

  bool _keeps(FilterItem item, _GlobalGate gate, {required bool withPrice}) {
    final rows = gate.rows;
    if (rows != null) {
      var kept = false;
      for (final row in rows) {
        if (_rowPass(row, item, withPrice: withPrice)) {
          kept = true;
          break;
        }
      }
      if (!kept) return false;
    } else {
      final legacyScopes = gate.legacyScopes;
      if (legacyScopes != null) {
        var inScope = false;
        for (final word in legacyScopes) {
          // 全局筛选（含 legacy 兜底）一律只看 data-catename，不回退
          // data-category_name——网站这两条路径就是取 catename。
          if (item.category.startsWith(word)) {
            inScope = true;
            break;
          }
        }
        if (!inScope) return true; // 不在范围内 → 直通
      }
      final keywords = gate.keywords;
      if (keywords != null) {
        final haystack = '${item.title}\n${item.content}\n${item.author}';
        for (final word in keywords) {
          if (word.isNotEmpty && haystack.contains(word)) return false;
        }
      }
    }

    final regDays = gate.authorRegDays;
    if (regDays != null && item.authorRegistrationTime != null) {
      final age = registrationAgeDays(item.authorRegistrationTime);
      if (age != null && age < regDays) return false;
    }
    return true;
  }

  /// 行通过条件：标题/分类/楼主三组各自「关键词空或命中 且 屏蔽词空或不命中」。
  bool _rowPass(FilterRule row, FilterItem item, {required bool withPrice}) {
    final titleGjc = row.titleGjc.trim();
    final titlePbc = row.titlePbc.trim();
    final categoryGjc = row.categoryGjc.trim();
    final categoryPbc = row.categoryPbc.trim();
    final authorGjc = row.authorGjc.trim();
    final authorPbc = row.authorPbc.trim();

    final fieldsEmpty =
        titleGjc.isEmpty &&
        titlePbc.isEmpty &&
        categoryGjc.isEmpty &&
        categoryPbc.isEmpty &&
        authorGjc.isEmpty &&
        authorPbc.isEmpty;
    final priceChecked = withPrice && row.hasPriceBound;
    // 全空行直通（只有价格另有约束时才不算"全空"）。
    if (fieldsEmpty && !priceChecked) return true;

    if (priceChecked) {
      final price = _asNumber(item.price);
      final minPrice = _asNumber(row.minPrice);
      final maxPrice = _asNumber(row.maxPrice);
      if (price != null &&
          ((minPrice != null && price < minPrice) ||
              (maxPrice != null && price > maxPrice))) {
        return false;
      }
    }

    if (_fieldFails(titleGjc, titlePbc, '${item.title}\n${item.content}')) {
      return false;
    }
    if (_fieldFails(categoryGjc, categoryPbc, item.category)) return false;
    if (authorGjc.isNotEmpty || authorPbc.isNotEmpty) {
      if (item.author.isEmpty || _fieldFails(authorGjc, authorPbc, item.author)) {
        return false;
      }
    }
    return true;
  }
}

class _GlobalGate {
  final List<FilterRule>? rows;
  final List<String>? keywords;
  final List<String>? legacyScopes;
  final int? authorRegDays;

  const _GlobalGate({
    this.rows,
    this.keywords,
    this.legacyScopes,
    this.authorRegDays,
  });
}

/// 页面级筛选 `window.xb_config` + 召回守卫 `window.xb_guanzhu_recall`。
///
/// 站点结构（真实样本）：`xb_config` 既可能是数组 `[{...}]`，也可能是对象
/// `{"zdmdefault":{...}}` —— 网站用 `Object.values()` 遍历，两种都能吃。
class PageFilterRules {
  /// `window.xb_page_flag`：`guanzhu`（我的关注）/ `index`（微博、好单、值得买
  /// 等频道页）/ 空（普通分类页，此时才由全局筛选兜底）。
  final String pageFlag;

  /// 页面自己的规则行（已跳过裸变量行）。
  final List<FilterRule> rows;

  /// 我的关注召回条件。
  final GuanzhuRecall recall;

  const PageFilterRules({
    this.pageFlag = '',
    this.rows = const [],
    this.recall = GuanzhuRecall.empty,
  });

  static const PageFilterRules empty = PageFilterRules();

  factory PageFilterRules.fromCategoryMetaScript(String script) {
    return PageFilterRules(
      pageFlag: _rawAssignment(script, 'window.xb_page_flag') ?? '',
      rows: _parseConfig(_rawAssignment(script, 'window.xb_config')),
      recall: GuanzhuRecall.fromJson(
        _decodeAssignment(script, 'window.xb_guanzhu_recall'),
      ),
    );
  }

  /// 页面是否声明了自己的规则（此时网站会跳过全局筛选）。
  bool get hasPageRules => pageFlag.isNotEmpty;

  /// `xb_listfilter`：true = 保留。行间 OR，全空行直通。
  bool keeps(FilterItem item) {
    final enabled = rows.where((row) => row.enabled).toList();
    // 无启用规则 → 不筛选展示全部（网站与"未设置规则走默认配置"语义一致）。
    if (enabled.isEmpty) return true;

    final channel = _channelOf(item);
    for (final row in enabled) {
      // 关注页分支必须排在频道分支之前：关注页混有微博/好单条目，
      // 落入频道分支会按"中段/尾段"语义错配。
      if (pageFlag == 'guanzhu') {
        if (_guanzhuRowPass(row, item)) return true;
        continue;
      }
      if (channel.isNotEmpty) {
        if (_channelRowPass(row, item, channel)) return true;
        continue;
      }
      if (item.type != 'smzdm') continue;
      if (_zdmRowPass(row, item)) return true;
    }
    return false;
  }

  /// 关注页分支：价格 → 标题 → 分类 → 商城 → 楼主。
  bool _guanzhuRowPass(FilterRule row, FilterItem item) {
    final category = item.effectiveCategory;
    final mall = item.platforms.isNotEmpty
        ? item.platforms
        : _trailingSegment(category);
    final minPrice = _asNumber(row.minPrice);
    final maxPrice = _asNumber(row.maxPrice);

    final allEmpty =
        minPrice == null &&
        maxPrice == null &&
        row.titleGjc.trim().isEmpty &&
        row.titlePbc.trim().isEmpty &&
        row.categoryGjc.trim().isEmpty &&
        row.categoryPbc.trim().isEmpty &&
        row.mallGjc.trim().isEmpty &&
        row.mallPbc.trim().isEmpty &&
        row.authorGjc.trim().isEmpty &&
        row.authorPbc.trim().isEmpty;
    if (allEmpty) return true;

    if (minPrice != null || maxPrice != null) {
      final price = _asNumber(item.price);
      if (price == null) return false; // 行带价格约束时无价条目该行不通过
      if (minPrice != null && price < minPrice) return false;
      if (maxPrice != null && price > maxPrice) return false;
    }

    if (item.title.isNotEmpty &&
        _fieldFails(row.titleGjc, row.titlePbc, item.title)) {
      return false;
    }
    if (category.isNotEmpty &&
        _fieldFails(row.categoryGjc, row.categoryPbc, category)) {
      return false;
    }
    if (mall.isEmpty) {
      if (row.mallGjc.trim().isNotEmpty) return false;
    } else if (_fieldFails(row.mallGjc, row.mallPbc, mall)) {
      return false;
    }
    if (item.author.isEmpty) {
      if (row.authorGjc.trim().isNotEmpty) return false;
    } else if (_fieldFails(row.authorGjc, row.authorPbc, item.author)) {
      return false;
    }
    return true;
  }

  /// 频道页分支（微博线报/好单线报）：分类取 catename 中段、商城取尾段。
  bool _channelRowPass(FilterRule row, FilterItem item, String channel) {
    final segments = _channelSplit(item.effectiveCategory, channel);

    final minPrice = _looseNumber(row.minPrice);
    final maxPrice = _looseNumber(row.maxPrice);
    if (minPrice != null || maxPrice != null) {
      // 频道线报大量无价格，网站对无价条目放行（与值得买分支相反）。
      final price = _asNumber(item.price);
      if (price != null) {
        if (minPrice != null && price < minPrice) return false;
        if (maxPrice != null && price > maxPrice) return false;
      }
    }

    if (item.title.isNotEmpty || item.content.isNotEmpty) {
      if (_fieldFails(row.titleGjc, row.titlePbc, '${item.title}\n${item.content}')) {
        return false;
      }
    }
    if (segments.category.isNotEmpty &&
        _fieldFails(row.categoryGjc, row.categoryPbc, segments.category)) {
      return false;
    }
    if (segments.mall.isNotEmpty &&
        _fieldFails(row.mallGjc, row.mallPbc, segments.mall)) {
      return false;
    }
    if (row.authorGjc.trim().isNotEmpty || row.authorPbc.trim().isNotEmpty) {
      if (item.author.isEmpty ||
          _fieldFails(row.authorGjc, row.authorPbc, item.author)) {
        return false;
      }
    }
    return true;
  }

  /// 值得买分支。
  bool _zdmRowPass(FilterRule row, FilterItem item) {
    if (row.mallName.isNotEmpty &&
        item.mallName.isNotEmpty &&
        !kwHit(row.mallName, item.mallName)) {
      return false;
    }

    final minPrice = _asNumber(row.minPrice);
    final maxPrice = _asNumber(row.maxPrice);
    // 网站这条分支只对"有价的条目"校验区间：`group.price === ""` 时两个条件都
    // 不成立，无价条目照常放行（注释里说的"无价排除"并没有落到代码上）。
    if (minPrice != null || maxPrice != null) {
      final price = _asNumber(item.price);
      if (price != null) {
        if (minPrice != null && price < minPrice) return false;
        if (maxPrice != null && price > maxPrice) return false;
      }
    }

    if (item.title.isNotEmpty || item.content.isNotEmpty) {
      if (_fieldFails(row.titleGjc, row.titlePbc, '${item.title}\n${item.content}')) {
        return false;
      }
    }
    if (item.categoryName.isNotEmpty &&
        _fieldFails(row.categoryGjc, row.categoryPbc, item.categoryName)) {
      return false;
    }
    return true;
  }
}

/// 全站筛选入口：主列表（首页/普通分类页）——置顶豁免 → 全局筛选。
bool keepMainListItem(
  FilterItem item,
  GlobalFilter global,
  List<String> scopes,
) {
  if (item.isTop) return true;
  return global.keepsListItem(item, scopes);
}

/// 有页面级规则的主列表（频道页/我的关注）——置顶豁免 → 页面规则。
///
/// 网站此时会跳过全局筛选（`xb_global_mainfilter` 见到 `xb_page_flag` 直接
/// return），所以这里不传全局规则。
bool keepPageListItem(FilterItem item, PageFilterRules page) {
  if (item.isTop) return true;
  return page.keeps(item);
}

/// 推送条目：关注页先过召回守卫，再走页面规则，最后才是全局筛选。
///
/// 对应网站 worker 里的顺序：
/// `guanzhu_push_guard` → `xb_listfilter(item, xb_config)` → `["推送"]` 全局筛选。
bool keepPushItem(
  FilterItem item, {
  GlobalFilter? global,
  PageFilterRules? page,
}) {
  if (page != null && page.hasPageRules) {
    if (page.pageFlag == 'guanzhu' && !page.recall.passes(item)) return false;
    if (!page.keeps(item)) return false;
  }
  if (global != null && !global.keepsPushItem(item, kPushScopes)) return false;
  return true;
}

/// 首页/推送的板块 token。
const List<String> kHomeScopes = <String>['主列表', '首页'];
const List<String> kPushScopes = <String>['推送'];

/// 分类页范围 token：网站取 `document.title` 按 `-` 切段
/// （如「赚客吧-线报酷」→ `分类页:赚客吧`、`分类页:线报酷`）。
List<String> categoryScopes(String pageTitle) {
  final scopes = <String>['主列表', '分类页'];
  for (final segment in pageTitle.split('-')) {
    final name = segment.trim();
    if (name.isEmpty) continue;
    final token = '分类页:$name';
    if (!scopes.contains(token)) scopes.add(token);
  }
  return scopes;
}

/// `fanwei` 是否命中当前板块 token（含「分类页:」的宽松前缀命中）。
bool _scopeMatches(String scopeField, List<String> scopes) {
  final trimmed = scopeField.trim();
  if (trimmed.isEmpty) return true; // 空 = 全板块
  for (final word in splitWords(trimmed)) {
    for (final token in scopes) {
      if (word == token) return true;
      if (!token.startsWith('分类页:')) continue;
      final pageName = token.substring(4);
      if (word.startsWith('分类页:')) {
        final name = word.substring(4);
        if (name.isNotEmpty && pageName.startsWith(name)) return true;
      } else if (pageName.startsWith(word)) {
        return true;
      }
    }
  }
  return false;
}

/// 字段组判定：true = 该组不通过（关键词未命中，或屏蔽词命中）。
bool _fieldFails(String gjc, String pbc, String value) {
  final keywords = gjc.trim();
  final blocked = pbc.trim();
  final keywordHit = keywords.isNotEmpty && kwHit(keywords, value);
  final blockedHit = blocked.isNotEmpty && kwHit(blocked, value);
  if (keywordHit && blockedHit) return true;
  if (keywords.isNotEmpty && !keywordHit) return true;
  if (blocked.isNotEmpty && blockedHit) return true;
  return false;
}

/// 频道判定：优先按 `cateid`（10 = 微博线报，30 = 好单线报），
/// 回退按 catename 前缀。
String _channelOf(FilterItem item) {
  switch (item.cateId) {
    case 10:
      return 'weibo';
    case 30:
      return 'haodan';
  }
  final name = item.effectiveCategory;
  if (name.startsWith('微博线报')) return 'weibo';
  if (name.startsWith('好单线报')) return 'haodan';
  return '';
}

/// `xbh_channel_split`：「微博线报-标签-平台」→ 中段标签 + 尾段平台。
({String category, String mall}) _channelSplit(String catename, String channel) {
  final prefix = channel == 'weibo'
      ? '微博线报-'
      : (channel == 'haodan' ? '好单线报-' : '');
  if (prefix.isEmpty || !catename.startsWith(prefix)) {
    return (category: '', mall: '');
  }
  final rest = catename.substring(prefix.length);
  final index = rest.lastIndexOf('-');
  if (index < 0) return (category: rest, mall: '');
  return (
    category: rest.substring(0, index),
    mall: rest.substring(index + 1),
  );
}

/// `xb_config` 解析：先按严格 JSON 试（服务端下发的两种形态都是合法 JSON），
/// 失败再退回对象字面量解析（用于跳过 `xbquick` 这类裸变量行）。
List<FilterRule> _parseConfig(String? raw) {
  if (raw == null || raw.isEmpty) return const <FilterRule>[];

  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    decoded = null;
  }
  if (decoded is List) return _ruleList(decoded);
  if (decoded is Map) return _ruleList(decoded.values.toList());

  return _parseConfigLiteral(raw);
}

List<FilterRule> _parseConfigLiteral(String body) {
  final rules = <FilterRule>[];
  void visit(String text) {
    var index = 0;
    while (true) {
      final open = text.indexOf('{', index);
      if (open < 0) break;
      final end = _balancedEnd(text, open, '{', '}');
      if (end < 0) break;
      final inner = text.substring(open + 1, end);
      if (_statusField.hasMatch(inner)) {
        final rule = FilterRule.fromJsObjectLiteral(inner);
        if (rule != null) rules.add(rule);
      } else {
        visit(inner); // 外层包裹对象（如 {"zdmdefault":{...}}）
      }
      index = end + 1;
    }
  }

  visit(body);
  return rules;
}

List<FilterRule> _ruleList(Object? source) {
  if (source is! List) return const <FilterRule>[];
  final rules = <FilterRule>[];
  for (final entry in source) {
    if (entry is Map) rules.add(FilterRule.fromJson(Map<String, dynamic>.from(entry)));
  }
  return rules;
}

List<String> _stringList(Object? source) {
  if (source is! List) return const <String>[];
  return source.map((e) => e?.toString() ?? '').toList();
}

/// 网站的 `Number(cfg.status)` / `Number(leg.kw)` 口径（会做数值转换，
/// 和规则行的 `Status !== 1` 严格比较不一样）。
int _numericFlag(Object? value) {
  if (value is num) return value.toInt();
  if (value == null) return 0;
  return num.tryParse(value.toString())?.toInt() ?? 0;
}

/// 取 `name=` 右侧的原始字面量（引号串或配对的花括号/方括号），找不到 → null。
String? _rawAssignment(String script, String name) {
  final match = RegExp('${RegExp.escape(name)}\\s*=').firstMatch(script);
  if (match == null) return null;
  final start = match.end;
  if (start >= script.length) return null;

  final first = script[start];
  if (first == '"' || first == "'") {
    final buffer = StringBuffer();
    var index = start + 1;
    while (index < script.length) {
      final char = script[index];
      if (char == r'\' && index + 1 < script.length) {
        buffer.write(script[index + 1]);
        index += 2;
        continue;
      }
      if (char == first) return buffer.toString();
      buffer.write(char);
      index++;
    }
    return null;
  }
  if (first == '{' || first == '[') {
    final end = _balancedEnd(script, start, first, first == '{' ? '}' : ']');
    if (end < 0) return null;
    return script.substring(start, end + 1);
  }
  return null;
}

/// 解析 `name=` 右侧的 JSON 字面量（非 JSON → null）。
Object? _decodeAssignment(String script, String name) {
  final raw = _rawAssignment(script, name);
  if (raw == null) return null;
  try {
    return jsonDecode(raw);
  } on FormatException {
    return null;
  }
}

/// 从 [start] 处的 [open] 找到配对的 [close]，考虑引号与转义。
int _balancedEnd(String source, int start, String open, String close) {
  var depth = 0;
  String? quote;
  var escaped = false;
  for (var index = start; index < source.length; index++) {
    final char = source[index];
    if (escaped) {
      escaped = false;
      continue;
    }
    if (char == r'\') {
      escaped = true;
      continue;
    }
    if (quote != null) {
      if (char == quote) quote = null;
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
      continue;
    }
    if (char == open) {
      depth++;
    } else if (char == close) {
      depth--;
      if (depth == 0) return index;
    }
  }
  return -1;
}
