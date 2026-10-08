import 'dart:convert';

import 'site_filter.dart';

/// 一个页面（或它自己的推送源）的完整筛选配置 —— 由该页 `meta.php` 的响应解析而来。
///
/// 网站 2026100x 把筛选配置从页面 HTML 里搬到了独立请求：
///
/// ```html
/// <script defer src="/zb_users/theme/xianbao_theme/script/meta.php?type=index&pagination=1&zdmserver=1"></script>
/// ```
///
/// 这份响应（`Cache-Control: no-store`，按账号下发）同时带着全局筛选、页面规则、
/// 召回条件、频道守卫和**该页自己的判定方式**。参数会改变响应内容（同一个首页，
/// 带不带 `zdmserver=1` 下发的 `xb_config` 字段位置都不一样），所以 App 必须照抄
/// 页面上那个 `src` 去请求，见 [metaScriptPath]。
///
/// 判定入口：[keepsListItem]（SSR 主列表）与 [keepsPush]（轮询推送）。
class MetaFilterConfig {
  /// `window.xb_global_filter` —— 服务端（ES 下推）那份全局筛选。
  final GlobalFilter global;

  /// `window.xb_global_fe_filter` —— 用户端「全局列表筛选」，只有 status/rows，
  /// 服务端零消费、纯浏览器本地过滤。所有列表页（含频道页）都要过它。
  final GlobalFilter? feFilter;

  /// `window.xb_config` / `xb_page_flag` / `xb_guanzhu_recall` / `xb_guanzhu_poll_on`
  /// / `xb_channel_guard` / `xb_page_sub`。
  final PageFilterRules page;

  /// `window.xb_json_fanwei`（首页推送守卫的召回范围，本站默认空数组）。
  final List<String> jsonFanwei;

  /// 该页的推送 handler 是否调用 `window.xb_json_guard`（只有首页有）。
  final bool usesJsonGuard;

  /// 该页推送路径的全局筛选范围 token（`xb_global_jsonfilter(xindata, …)`）。
  ///
  /// null = 这一页的推送压根不走全局 JSON 筛选（值得买页就是）；空串 token
  /// （服务端占位没替换，分类页/频道页/关注页都是这样）= 只有 `fanwei` 留空的
  /// 规则行生效。
  final List<String>? pushScopes;

  /// meta 里调了 `xb_liebiaoshaixuan(xb_config)`：主列表按 `xb_listfilter` 筛。
  final bool listUsesConfigRules;

  /// meta 里内联了 `xb_rows_pass` 的 DOM 块：主列表按 `xb_rows_pass` 筛。
  final bool listUsesGuardRows;

  /// meta 里内联了价格提取 IIFE：主列表条目缺 `data-price` 时从标题补 [priceFromTitle]。
  final bool extractPriceFromTitle;

  const MetaFilterConfig({
    this.global = GlobalFilter.empty,
    this.feFilter,
    this.page = PageFilterRules.empty,
    this.jsonFanwei = const [],
    this.usesJsonGuard = false,
    this.pushScopes,
    this.listUsesConfigRules = false,
    this.listUsesGuardRows = false,
    this.extractPriceFromTitle = false,
  });

  static const MetaFilterConfig empty = MetaFilterConfig();

  /// 解析一份 meta.php 响应。
  factory MetaFilterConfig.fromScript(String script) {
    return MetaFilterConfig(
      global: GlobalFilter.fromMetaScript(script),
      feFilter: _decodeJsonAssignment(script, 'window.xb_global_fe_filter'),
      page: PageFilterRules.fromCategoryMetaScript(script),
      jsonFanwei: _decodeStringList(script, 'window.xb_json_fanwei'),
      usesJsonGuard: script.contains('xb_json_guard(xindata)'),
      pushScopes: _parseJsonFilterScopes(script),
      listUsesConfigRules: script.contains('xb_liebiaoshaixuan(xb_config)'),
      // 定义体是 `window.xb_rows_pass=function(rows, …`，只有内联块才带 `(rows,` 调用。
      listUsesGuardRows: script.contains('window.xb_rows_pass(rows,'),
      extractPriceFromTitle: script.contains('setAttribute("data-price",'),
    );
  }

  /// `xb_config` 里 Status 严格等于 1 的行（网站用 `!== 1` 判，字符串 `"1"` 不算）。
  List<FilterRule> get enabledConfigRows =>
      page.rows.where((row) => row.enabled).toList();

  /// SSR 主列表条目判定（首页/分类页/频道页/关注页同一入口）。
  ///
  /// 顺序对齐网站：置顶豁免 → 用户端全局筛选 → 页面自己的口径（页面一旦声明了
  /// `xb_page_flag`，`xb_global_mainfilter` 就跳过服务端全局筛选）。
  bool keepsListItem(FilterItem raw, List<String> scopes) {
    if (raw.isTop) return true;
    final item = extractPriceFromTitle ? raw.withPriceFromTitle() : raw;

    final fe = feFilter;
    if (fe != null && !fe.keepsListItem(item, scopes)) return false;

    if (page.hasPageRules) {
      if (listUsesConfigRules) return page.keeps(item);
      if (listUsesGuardRows) return pageRowsPass(enabledConfigRows, item);
      return true;
    }
    if (!global.keepsListItem(item, scopes)) return false;
    if (listUsesGuardRows) return pageRowsPass(enabledConfigRows, item);
    return true;
  }

  /// 轮询推送条目判定。
  ///
  /// 关注页的推送只在轮询开关打开时才插入（网站 `xb_consume_addhtml` 的门控），
  /// 所以关闭时这里直接判 false。
  bool keepsPush(FilterItem raw) {
    if (page.pageFlag == 'guanzhu' && page.pollOn != 1) return false;
    return keepPushItem(
      raw,
      global: global,
      page: page,
      guardRows: enabledConfigRows,
      jsonFanwei: jsonFanwei,
      usesJsonGuard: usesJsonGuard,
      pushScopes: pushScopes,
    );
  }
}

/// 取出页面里 meta.php 的 `<script src>`（相对路径 + query），找不到 → null。
///
/// App 想跟浏览器看到同一份筛选配置，就必须请求同一个地址：同一个首页，带不带
/// `zdmserver=1`，服务端下发的 `xb_config` 字段位置都不一样；分类页带不带
/// `cate-name`，推送的全局筛选范围一个是一个空 token、一个是 `["推送"]`。
String? metaScriptPath(String html) {
  final match = RegExp(
    r'''<script[^>]+src="([^"]*script/meta\.php[^"]*)"''',
  ).firstMatch(html);
  final raw = match?.group(1);
  if (raw == null || raw.isEmpty) return null;
  return raw.replaceAll('&amp;', '&');
}

/// 读 `name=<json 对象>`；不是合法对象 → null。
GlobalFilter? _decodeJsonAssignment(String script, String name) {
  final raw = _rawLiteral(script, name);
  if (raw == null) return null;
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;
  return GlobalFilter.fromJsonValue(decoded);
}

List<String> _decodeStringList(String script, String name) {
  final raw = _rawLiteral(script, name);
  if (raw == null) return const [];
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return const [];
  }
  if (decoded is! List) return const [];
  return decoded.map((e) => e?.toString() ?? '').toList();
}

/// `xb_global_jsonfilter(xindata, <scope>)` 里的 scope。
///
/// 返回值三态：null = 该页推送不调它；`['']` = 调了但 scope 是空（网站模板占位
/// 没替换，分类页系就这样）；否则是服务端写死的 token 数组。
List<String>? _parseJsonFilterScopes(String script) {
  final call = RegExp(
    r'xb_global_jsonfilter\(\s*xindata\s*,\s*([^)]*)\)',
  ).firstMatch(script);
  if (call == null) return null;

  final arg = call.group(1)!.trim();
  if (arg.isEmpty) return const <String>[''];
  try {
    final decoded = jsonDecode(arg);
    if (decoded is List) {
      return decoded.map((e) => e?.toString() ?? '').toList();
    }
  } on FormatException {
    // 落到下面的兜底：按字面量当单个 token 用（与网站 String(scope) 一致）。
  }
  return <String>[arg];
}

/// 取 `name=` 右侧的原始字面量（引号串或配对的花括号/方括号）。
String? _rawLiteral(String script, String name) {
  final match = RegExp('${RegExp.escape(name)}\\s*=').firstMatch(script);
  if (match == null) return null;
  final start = match.end;
  if (start >= script.length) return null;
  final first = script[start];
  if (first == '"' || first == "'") {
    final end = script.indexOf(first, start + 1);
    return end < 0 ? null : script.substring(start, end + 1);
  }
  if (first == '{' || first == '[') {
    final end = _balancedEnd(script, start, first == '{' ? '}' : ']');
    return end < 0 ? null : script.substring(start, end + 1);
  }
  return null;
}

int _balancedEnd(String source, int start, String close) {
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
    if (char == '[' || char == '{') {
      depth++;
    } else if (char == close) {
      depth--;
      if (depth == 0) return index;
    }
  }
  return -1;
}
