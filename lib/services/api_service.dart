import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/article.dart';
import '../models/category.dart';
import '../models/page_meta.dart';
import '../models/site_filter.dart';
import 'http_client.dart';

/// 一个分类页的 meta 配置：推送源 + 该页自己的筛选全家桶。
class CategoryMeta {
  /// 该分类自动刷新用的推送源（`postjson.url`）；网站不给的分类为 null，
  /// 此时 App 也不刷新（与网站一致）。
  final String? feedUrl;

  /// `xb_global_filter` / `xb_config` / `xb_page_flag` / 频道守卫 / 推送范围 …
  final MetaFilterConfig filter;

  const CategoryMeta({required this.feedUrl, required this.filter});
}

/// High-level API service for fetching article data.
class ApiService {
  final HttpClient _client = HttpClient();

  int lastHtmlLength = 0;
  String? lastError;
  String lastHtmlPreview = '';

  List<CategoryItem>? _cachedCategories;

  MetaFilterConfig _homeFilter = MetaFilterConfig.empty;
  bool _homeFilterLoaded = false;
  int _filterRequestId = 0;

  /// 首页 meta.php 的地址：正常从首页 HTML 里那个 `<script src>` 抄，抄不到时
  /// 退回线上首页用的那一份（`zdmserver=1` 是网站自己带的参数）。
  static const String _homeMetaPath =
      '/zb_users/theme/xianbao_theme/script/meta.php'
      '?type=index&pagination=1&zdmserver=1';

  /// 分类页 meta（推送源 + 筛选配置），按 slug 缓存。
  ///
  /// 只能按 slug 缓存：子频道（如 `/category-haodan-jd/`）与父频道共用 cateId，
  /// 但 `cate-name` 不同、频道守卫不同。
  final Map<String, CategoryMeta> _categoryMeta = <String, CategoryMeta>{};

  /// 已经解析出来的分类页 meta 地址（与账号无关，会话切换不必丢）。
  ///
  /// 单独缓存是为了失败重试时不必再拉一遍 200KB 的分类页 HTML。
  final Map<String, String> _categoryMetaPath = <String, String>{};

  /// 登录态变化后必须丢弃：筛选规则和推送源都是按账号下发的。
  void resetForSessionChange() {
    _homeFilter = MetaFilterConfig.empty;
    _homeFilterLoaded = false;
    _categoryMeta.clear();
  }

  /// Fetches the homepage filter config (`meta.php?type=index…`).
  ///
  /// [pageHtml] 用于抄下首页真正请求的那个 meta 地址；不给就用线上首页那份。
  Future<MetaFilterConfig> refreshHomeFilterRules({String? pageHtml}) async {
    final requestId = ++_filterRequestId;
    final path = metaScriptPath(pageHtml ?? '') ?? _homeMetaPath;
    final script = await _client.fetchMetaScript(path);
    final rules = MetaFilterConfig.fromScript(script);
    if (requestId == _filterRequestId) {
      _homeFilter = rules;
      _homeFilterLoaded = true;
    }
    return rules;
  }

  Future<MetaFilterConfig> _ensureHomeFilter() async {
    if (!_homeFilterLoaded) await refreshHomeFilterRules();
    return _homeFilter;
  }

  /// Fetches filter rules and homepage HTML.
  ///
  /// 两者现在是先后关系：必须先从首页 HTML 里拿到它自己的 meta.php 地址，才能
  /// 请求到与浏览器一模一样的筛选配置。
  Future<
    ({
      List<ArticleListItem> items,
      List<CategoryItem> categories,
      int totalPages,
    })
  >
  fetchHomeData() async {
    try {
      final html = await _client.fetchHomePage(page: 1);
      lastHtmlLength = html.length;
      lastHtmlPreview = html.length > 300 ? html.substring(0, 300) : html;
      final rules = await refreshHomeFilterRules(pageHtml: html);
      lastError = null;

      final categories = CategoryItem.parseCategories(html);
      _cachedCategories = categories;
      return (
        items: _filterList(
          ArticleListItem.parseList(html),
          rules,
          kHomeScopes,
        ),
        categories: categories,
        totalPages: ArticleListItem.parsePageCount(html),
      );
    } catch (e) {
      lastError = e.toString();
      rethrow;
    }
  }

  /// Fetch article list for a given page.
  /// Returns the list items and total page count.
  Future<({List<ArticleListItem> items, int totalPages, int? cateId})>
  fetchArticleList({int page = 1}) async {
    try {
      final rules = await _ensureHomeFilter();
      final html = await _client.fetchHomePage(page: page);
      lastHtmlLength = html.length;
      lastHtmlPreview = html.length > 300 ? html.substring(0, 300) : html;
      lastError = null;
      final items = _filterList(
        ArticleListItem.parseList(html),
        rules,
        kHomeScopes,
      );
      final totalPages = ArticleListItem.parsePageCount(html);
      return (items: items, totalPages: totalPages, cateId: null);
    } catch (e) {
      lastError = e.toString();
      rethrow;
    }
  }

  /// Fetch categories from the website navigation.
  Future<List<CategoryItem>> fetchCategoryList({
    bool forceRefresh = false,
  }) async {
    if (_cachedCategories != null && !forceRefresh) {
      return _cachedCategories!;
    }
    final html = await _client.fetchHomePage(page: 1);
    _cachedCategories = CategoryItem.parseCategories(html);
    return _cachedCategories!;
  }

  /// Fetch article list for a specific category page.
  Future<({List<ArticleListItem> items, int totalPages, int? cateId})>
  fetchCategoryArticleList({required String slug, int page = 1}) async {
    try {
      final html = await _client.fetchCategoryPage(slug, page: page);
      lastHtmlLength = html.length;
      lastHtmlPreview = html.length > 300 ? html.substring(0, 300) : html;
      lastError = null;

      final items = ArticleListItem.parseList(html);
      final cateId = ArticleListItem.parseCateId(html);
      final pageTitle = CategoryItem.parsePageTitle(html);
      return (
        items: await _filterCategoryList(
          items,
          cateId: cateId,
          slug: slug,
          pageTitle: pageTitle,
          pageHtml: html,
        ),
        totalPages: ArticleListItem.parsePageCount(html),
        cateId: cateId,
      );
    } catch (e) {
      lastError = e.toString();
      rethrow;
    }
  }

  /// 分类页列表筛选。
  ///
  /// 判定口径全部来自该页自己的 meta.php：带 `xb_page_flag` 的页面（我的关注、
  /// 微博/好单/值得买等）走页面规则（网站此时跳过全局筛选），普通分类页落到全局
  /// 筛选，范围 token 取页面标题切段（`分类页:赚客吧`）。
  Future<List<ArticleListItem>> _filterCategoryList(
    List<ArticleListItem> items, {
    required int? cateId,
    required String slug,
    required String pageTitle,
    required String pageHtml,
  }) async {
    try {
      final meta = await _categoryMetaFor(
        cateId: cateId,
        slug: slug,
        pageHtml: pageHtml,
      );
      if (meta == null) {
        // 这页没有 meta.php（既没有 cateid 也抄不到地址）→ 只走全局筛选。
        final home = await _ensureHomeFilter();
        return _filterList(
          items,
          MetaFilterConfig(global: home.global),
          categoryScopes(pageTitle),
        );
      }
      return _filterList(items, meta.filter, categoryScopes(pageTitle));
    } catch (e) {
      // 规则拉不到时按"未启用筛选"处理——网站那边脚本没加载出来也是这个效果。
      // 一次 meta 抖动不该把整个分类页变成错误页；列表本身已经拿到了。
      debugPrint('Category filter rules unavailable, showing unfiltered: $e');
      return items;
    }
  }

  /// Fetch search results as article list.
  ///
  /// The site's search page ships no meta script and excludes it from the list
  /// filters (`xb_global_page_excluded`), so results are not filtered here
  /// either.
  Future<List<ArticleListItem>> searchArticles(String keyword) async {
    final html = await _client.search(keyword);
    return ArticleListItem.parseList(html);
  }

  /// Fetch article detail with comments.
  Future<ArticleDetail> fetchArticleDetail(String path) async {
    final html = await _client.fetchArticle(path);
    return ArticleDetail.parse(html);
  }

  /// Fetch new pushed articles for the home feed.
  Future<List<ArticleListItem>> fetchNewArticles() async {
    final rules = await _ensureHomeFilter();
    final items = await fetchArticlesFromFeed('/plus/json/push.json');
    return _filterPush(items, rules);
  }

  /// Fetch new pushed articles for a category view.
  ///
  /// 我的关注页拉的是站级 `push.json`，网站靠 «召回守卫 + 页面规则» 逐条过滤后
  /// 才插入列表；频道页还要过 `xb_channel_guard`；值得买页走自己的平台细分。
  Future<List<ArticleListItem>> fetchCategoryNewArticles({
    required int cateId,
    required String slug,
  }) async {
    final meta = await _categoryMetaFor(cateId: cateId, slug: slug);
    final feedUrl = meta?.feedUrl;
    if (meta == null || feedUrl == null) return const <ArticleListItem>[];
    final items = await fetchArticlesFromFeed(feedUrl, fallbackCateId: cateId);
    return _filterPush(items, meta.filter);
  }

  /// Fetch articles from a feed path, unfiltered.
  Future<List<ArticleListItem>> fetchArticlesFromFeed(
    String path, {
    int? fallbackCateId,
  }) async {
    final json = await _client.fetchPushFeed(path);
    final list = jsonDecode(json) as List;
    return list
        .whereType<Map<String, dynamic>>()
        .map(
          (m) => ArticleListItem.fromPushMap(m, fallbackCateId: fallbackCateId),
        )
        .toList();
  }

  List<ArticleListItem> _filterList(
    List<ArticleListItem> items,
    MetaFilterConfig rules,
    List<String> scopes,
  ) {
    return items
        .where(
          (a) => rules.keepsListItem(FilterItem.fromArticle(a), scopes),
        )
        .toList();
  }

  List<ArticleListItem> _filterPush(
    List<ArticleListItem> items,
    MetaFilterConfig rules,
  ) {
    return items
        .where((a) => rules.keepsPush(FilterItem.fromArticle(a)))
        .toList();
  }

  /// Resolves a category's meta once (feed source + page filter rules).
  ///
  /// 请求地址优先抄页面 HTML 里那个 `<script src>`（带上 `cate-name`），抄不到
  /// 才退回自己拼的一份——`cate-name` 会影响服务端下发的推送范围与规则行字段。
  /// 连页面 HTML 都拿不到（只有 slug）时返回 null，调用方按「这页没有 meta」
  /// 处理。
  Future<CategoryMeta?> _categoryMetaFor({
    required int? cateId,
    required String slug,
    String? pageHtml,
  }) async {
    final cached = _categoryMeta[slug];
    if (cached != null) return cached;

    var path = _categoryMetaPath[slug];
    if (path == null) {
      var html = pageHtml;
      if (html == null) {
        // 推送轮询可能先于列表加载发生（冷启动），此时只有 slug 可用。
        try {
          html = await _client.fetchCategoryPage(slug, page: 1);
        } catch (_) {
          html = null;
        }
      }
      path = metaScriptPath(html ?? '');
      if (path == null) {
        if (cateId == null) return null;
        path = _fallbackCategoryMetaPath(cateId, slug);
      }
      _categoryMetaPath[slug] = path;
    }

    final script = await _client.fetchMetaScript(path);
    final match = RegExp(r'postjson\.url\s*=\s*"([^"]*)"').firstMatch(script);
    final url = match?.group(1)?.trim() ?? '';
    final meta = CategoryMeta(
      feedUrl: url.isEmpty ? null : url,
      filter: MetaFilterConfig.fromScript(script),
    );
    // Failures above are deliberately not cached, so the next refresh retries.
    _categoryMeta[slug] = meta;
    return meta;
  }

  /// 页面里抄不到 meta 地址时的兜底（不含 `cate-name`，配置形状可能与浏览器略有
  /// 出入，仅用于极端情况：页面 HTML 拉不到）。
  String _fallbackCategoryMetaPath(int cateId, String slug) {
    final params = <String, String>{
      'type': 'category',
      'cateid': '$cateId',
      'catename': slug,
      'pagination': '1',
    };
    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return '/zb_users/theme/xianbao_theme/script/meta.php?$query';
  }

  /// Check whether the user is logged in.
  Future<bool> isLoggedIn() => _client.checkLoginState();

  /// Toggle collect for an article. code==1 means login required.
  Future<CollectToggleResult> toggleCollect(int articleId) async {
    final raw = await _client.toggleCollect(articleId);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return CollectToggleResult.fromJson(json);
  }

  /// Load collect button state (collected or not) for an article.
  Future<CollectButtonState?> fetchCollectButtonState(int articleId) async {
    try {
      final raw = await _client.fetchArticleCacheButs(articleId);
      if (raw.trim().isEmpty) return null;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final buts = json['buts']?.toString() ?? '';
      if (buts.isEmpty) return null;
      return CollectButtonState.fromButsHtml(buts);
    } catch (_) {
      return null;
    }
  }

  /// Ask server to re-crawl article content.
  Future<String> refetchArticle(int articleId) async {
    final text = await _client.refetchArticle(articleId);
    return text.trim();
  }

  /// Fetch one page of the user's collect list.
  Future<({List<CollectListItem> items, int total})> fetchCollectList({
    int page = 1,
    int limit = 20,
  }) async {
    final csrf = await _client.fetchUserCenterCsrfToken();
    if (csrf == null || csrf.isEmpty) {
      throw Exception('无法获取用户中心令牌，请重新登录');
    }
    final raw = await _client.fetchCollectListJson(
      csrfToken: csrf,
      page: page,
      limit: limit,
    );
    if (raw.trim().isEmpty) {
      return (items: <CollectListItem>[], total: 0);
    }
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final code = json['code'];
    if (code == 1001 || code == '1001') {
      throw Exception(json['msg']?.toString() ?? '请先登录');
    }
    final list = (json['data'] as List?) ?? const [];
    final items = list
        .whereType<Map>()
        .map((e) => CollectListItem.fromApiMap(Map<String, dynamic>.from(e)))
        .where((e) => e.collectId.isNotEmpty)
        .toList();
    final total = (json['count'] as num?)?.toInt() ?? items.length;
    return (items: items, total: total);
  }

  /// Cancel collect by collect-record id.
  Future<({bool ok, String message})> deleteCollect(String collectId) async {
    final csrf = await _client.fetchUserCenterCsrfToken();
    if (csrf == null || csrf.isEmpty) {
      return (ok: false, message: '无法获取用户中心令牌，请重新登录');
    }
    final raw = await _client.deleteCollect(
      collectId: collectId,
      csrfToken: csrf,
    );
    if (raw.trim().isEmpty) {
      return (ok: false, message: '取消收藏失败');
    }
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final code = json['code'];
    final msg = json['msg']?.toString() ?? '';
    final ok = code == 0 || code == '0';
    return (ok: ok, message: msg.isEmpty ? (ok ? '已取消收藏' : '取消收藏失败') : msg);
  }
}
