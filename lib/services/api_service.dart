import 'dart:convert';
import '../models/article.dart';
import '../models/article_filter_rules.dart';
import '../models/category.dart';
import 'http_client.dart';

/// High-level API service for fetching article data.
class ApiService {
  final HttpClient _client = HttpClient();

  int lastHtmlLength = 0;
  String? lastError;
  String lastHtmlPreview = '';

  List<CategoryItem>? _cachedCategories;
  ArticleFilterRules _homeFilterRules = const ArticleFilterRules();
  bool _homeFilterRulesLoaded = false;
  int _filterRequestId = 0;

  Future<ArticleFilterRules> refreshHomeFilterRules() async {
    final requestId = ++_filterRequestId;
    final script = await _client.fetchHomeFilterScript();
    final rules = ArticleFilterRules.fromMetaScript(script);
    if (requestId == _filterRequestId) {
      _homeFilterRules = rules;
      _homeFilterRulesLoaded = true;
    }
    return rules;
  }

  Future<void> _ensureHomeFilterRules() async {
    if (!_homeFilterRulesLoaded) await refreshHomeFilterRules();
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
      final rules = responses[0] as ArticleFilterRules;
      final html = responses[1] as String;
      lastHtmlLength = html.length;
      lastHtmlPreview = html.length > 300 ? html.substring(0, 300) : html;
      lastError = null;

      final categories = CategoryItem.parseCategories(html);
      _cachedCategories = categories;
      return (
        items: ArticleListItem.parseList(html).where(rules.allows).toList(),
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
      await _ensureHomeFilterRules();
      final html = await _client.fetchHomePage(page: page);
      lastHtmlLength = html.length;
      lastHtmlPreview = html.length > 300 ? html.substring(0, 300) : html;
      lastError = null;
      final items = ArticleListItem.parseList(
        html,
      ).where(_homeFilterRules.allows).toList();
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
      final totalPages = ArticleListItem.parsePageCount(html);
      final cateId = ArticleListItem.parseCateId(html);
      return (items: items, totalPages: totalPages, cateId: cateId);
    } catch (e) {
      lastError = e.toString();
      rethrow;
    }
  }

  /// Fetch search results as article list.
  Future<List<ArticleListItem>> searchArticles(String keyword) async {
    final html = await _client.search(keyword);
    return ArticleListItem.parseList(html);
  }

  /// Fetch article detail with comments.
  Future<ArticleDetail> fetchArticleDetail(String path) async {
    final html = await _client.fetchArticle(path);
    return ArticleDetail.parse(html);
  }

  /// Fetch new pushed articles from push.json for real-time refresh.
  Future<List<ArticleListItem>> fetchNewArticles() async {
    await _ensureHomeFilterRules();
    final json = await _client.fetchPushJson();
    final list = jsonDecode(json) as List;
    return list
        .map((e) {
          final m = e as Map<String, dynamic>;
          return ArticleListItem(
            url: m['url'] as String? ?? '',
            title: m['title'] as String? ?? '',
            category: m['catename'] as String? ?? '',
            summary: m['content'] as String? ?? '',
            commentCount: (m['comments'] as num?)?.toInt() ?? 0,
            date: m['datetime'] as String? ?? '',
            time: '${m['datetime'] ?? ''} ${m['shorttime'] ?? ''}',
            author: m['louzhu'] as String? ?? '',
            authorRegistrationTime: m['louzhuregtime'],
          );
        })
        .where(_homeFilterRules.allows)
        .toList();
  }

  /// Fetch new pushed articles for a specific category using
  /// the category-specific push_{cateId}.json endpoint.
  Future<List<ArticleListItem>> fetchCategoryNewArticles(int cateId) async {
    final json = await _client.fetchCategoryPushJson(cateId);
    final list = jsonDecode(json) as List;
    return list.map((e) {
      final m = e as Map<String, dynamic>;
      return ArticleListItem(
        url: m['url'] as String? ?? '',
        title: m['title'] as String? ?? '',
        category: m['catename'] as String? ?? '',
        summary: m['content'] as String? ?? '',
        commentCount: (m['comments'] as num?)?.toInt() ?? 0,
        date: m['datetime'] as String? ?? '',
        time: '${m['datetime'] ?? ''} ${m['shorttime'] ?? ''}',
        author: m['louzhu'] as String? ?? '',
        authorRegistrationTime: m['louzhuregtime'],
      );
    }).toList();
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
