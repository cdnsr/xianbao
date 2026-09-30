import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/article.dart';
import '../models/category.dart';
import '../models/site_filter.dart';
import 'http_client.dart';

/// 一个分类页的 meta 配置：推送源 + 该页自己的筛选规则。
class CategoryMeta {
  /// 该分类自动刷新用的推送源（`postjson.url`）；网站不给的分类为 null，
  /// 此时 App 也不刷新（与网站一致）。
  final String? feedUrl;

  /// `xb_page_flag` / `xb_config` / `xb_guanzhu_recall`。
  final PageFilterRules page;

  const CategoryMeta({required this.feedUrl, required this.page});
}

/// High-level API service for fetching article data.
class ApiService {
  final HttpClient _client = HttpClient();

  int lastHtmlLength = 0;
  String? lastError;
  String lastHtmlPreview = '';

  List<CategoryItem>? _cachedCategories;

  GlobalFilter _globalFilter = GlobalFilter.empty;
  bool _globalFilterLoaded = false;
  int _filterRequestId = 0;

  /// 分类页 meta（推送源 + 页面规则），按 cateId 缓存。
  final Map<int, CategoryMeta> _categoryMeta = <int, CategoryMeta>{};

  /// 登录态变化后必须丢弃：筛选规则和推送源都是按账号下发的。
  void resetForSessionChange() {
    _globalFilter = GlobalFilter.empty;
    _globalFilterLoaded = false;
    _categoryMeta.clear();
  }

  /// Fetches the current user's global filter rules (`window.xb_global_filter`).
  Future<GlobalFilter> refreshHomeFilterRules() async {
    final requestId = ++_filterRequestId;
    final script = await _client.fetchHomeFilterScript();
    final rules = GlobalFilter.fromMetaScript(script);
    if (requestId == _filterRequestId) {
      _globalFilter = rules;
      _globalFilterLoaded = true;
    }
    return rules;
  }

  Future<GlobalFilter> _ensureGlobalFilter() async {
    if (!_globalFilterLoaded) await refreshHomeFilterRules();
    return _globalFilter;
  }

  /// Fetches filter rules and homepage HTML concurrently. The same HTML is
  /// used for articles and categories, avoiding the previous duplicate GET.
  Future<
    ({
      List<ArticleListItem> items,
      List<CategoryItem> categories,
      int totalPages,
    })
  >
  fetchHomeData() async {
    try {
      final responses = await Future.wait<Object>([
        refreshHomeFilterRules(),
        _client.fetchHomePage(page: 1),
      ]);
      final rules = responses[0] as GlobalFilter;
      final html = responses[1] as String;
      lastHtmlLength = html.length;
      lastHtmlPreview = html.length > 300 ? html.substring(0, 300) : html;
      lastError = null;

      final categories = CategoryItem.parseCategories(html);
      _cachedCategories = categories;
      return (
        items: _filterMainList(ArticleListItem.parseList(html), rules, kHomeScopes),
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
      final rules = await _ensureGlobalFilter();
      final html = await _client.fetchHomePage(page: page);
      lastHtmlLength = html.length;
      lastHtmlPreview = html.length > 300 ? html.substring(0, 300) : html;
      lastError = null;
      final items = _filterMainList(
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
  /// 带 `xb_page_flag` 的页面（我的关注、微博/好单/值得买等频道页）由页面
  /// 自己的规则过滤，网站此时会跳过全局筛选；普通分类页才落到全局筛选，
  /// 且范围 token 取页面标题切段（`分类页:赚客吧`）。
  Future<List<ArticleListItem>> _filterCategoryList(
    List<ArticleListItem> items, {
    required int? cateId,
    required String slug,
    required String pageTitle,
  }) async {
    try {
      if (cateId != null) {
        final meta = await _categoryMetaFor(cateId: cateId, slug: slug);
        if (meta.page.hasPageRules) {
          return items
              .where(
                (a) => keepPageListItem(FilterItem.fromArticle(a), meta.page),
              )
              .toList();
        }
      }
      final rules = await _ensureGlobalFilter();
      return _filterMainList(items, rules, categoryScopes(pageTitle));
    } catch (e) {
      // 规则拉不到时按"未启用筛选"处理——网站那边脚本没加载出来也是这个效果。
      // 一次 meta 抖动不该把整个分类页变成错误页；列表本身已经拿到了。
      debugPrint('Category filter rules unavailable, showing unfiltered: $e');
      return items;
    }
  }

  /// Fetch search results as article list.
  ///
  /// The site's search page ships no global-filter script, so results are not
  /// filtered there either.
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
    final rules = await _ensureGlobalFilter();
    final items = await fetchArticlesFromFeed('/plus/json/push.json');
    return _filterPush(items, global: rules);
  }

  /// Fetch new pushed articles for a category view.
  ///
  /// 我的关注页拉的是站级 `push.json`，网站靠 «召回守卫 + 页面规则» 逐条过滤后
  /// 才插入列表；频道页同样要过 `xb_config`。
  Future<List<ArticleListItem>> fetchCategoryNewArticles({
    required int cateId,
    required String slug,
  }) async {
    final meta = await _categoryMetaFor(cateId: cateId, slug: slug);
    final feedUrl = meta.feedUrl;
    if (feedUrl == null) return const <ArticleListItem>[];
    final items = await fetchArticlesFromFeed(feedUrl, fallbackCateId: cateId);
    return _filterPush(items, global: await _ensureGlobalFilter(), page: meta.page);
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

  List<ArticleListItem> _filterMainList(
    List<ArticleListItem> items,
    GlobalFilter rules,
    List<String> scopes,
  ) {
    return items
        .where((a) => keepMainListItem(FilterItem.fromArticle(a), rules, scopes))
        .toList();
  }

  List<ArticleListItem> _filterPush(
    List<ArticleListItem> items, {
    GlobalFilter? global,
    PageFilterRules? page,
  }) {
    return items
        .where(
          (a) => keepPushItem(
            FilterItem.fromArticle(a),
            global: global,
            page: page,
          ),
        )
        .toList();
  }

  /// Resolves a category's meta once (feed source + page filter rules).
  Future<CategoryMeta> _categoryMetaFor({
    required int cateId,
    required String slug,
  }) async {
    final cached = _categoryMeta[cateId];
    if (cached != null) return cached;

    final script = await _client.fetchCategoryMetaScript(
      cateId: cateId,
      slug: slug,
    );
    final match = RegExp(r'postjson\.url\s*=\s*"([^"]*)"').firstMatch(script);
    final url = match?.group(1)?.trim() ?? '';
    final meta = CategoryMeta(
      feedUrl: url.isEmpty ? null : url,
      page: PageFilterRules.fromCategoryMetaScript(script),
    );
    // Failures above are deliberately not cached, so the next refresh retries.
    _categoryMeta[cateId] = meta;
    return meta;
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
