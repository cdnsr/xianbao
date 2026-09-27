import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/article.dart';
import '../../models/category.dart';
import '../../services/api_service.dart';
import '../../services/app_state.dart';
import '../../services/home_cache_service.dart';
import '../../services/theme_controller.dart';
import '../../utils/error_message.dart';
import '../../widgets/article_list_tile.dart';
import '../../widgets/load_error_view.dart';
import '../../widgets/about_dialog.dart';
import '../../widgets/union_settings_dialog.dart';
import '../article/article_detail_page.dart';
import '../collect/collect_list_page.dart';

/// Rows revealed per top-up, and the default page size shown on first load.
const int _itemsPerPage = 30;

/// How many screens of content to keep below the viewport. Topping up this
/// early means the list never dead-ends at the bottom.
const double _preloadScreens = 1.5;

/// What the article list should do after a scroll update.
///
/// [shown] is how many articles are in the list window, [fetched] how many are
/// already in memory; the rest come from [ScrollPosition]. [reveal] is the
/// window size to switch to (unchanged when nothing should happen), and
/// [fetchNextPage] asks for the following page from the server.
///
/// The trigger sits [preloadScreens] viewports *before* the end. Waiting for
/// the exact bottom dead-ends: the position cannot move any further, so no
/// scroll event fires and the user has to reverse and scroll back down before
/// anything more appears.
({int reveal, bool fetchNextPage}) preloadForScroll({
  required int shown,
  required int fetched,
  required double pixels,
  required double maxScrollExtent,
  required double viewportDimension,
  int chunk = _itemsPerPage,
  double preloadScreens = _preloadScreens,
}) {
  final trigger = maxScrollExtent - viewportDimension * preloadScreens;
  if (pixels < trigger) {
    return (reveal: shown, fetchNextPage: false);
  }
  if (shown < fetched) {
    final next = shown + chunk;
    return (reveal: next > fetched ? fetched : next, fetchNextPage: false);
  }
  return (reveal: shown, fetchNextPage: true);
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ApiService _api = ApiService();
  final HomeCacheService _cache = HomeCacheService();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  List<ArticleListItem> _articles = [];
  int _currentPage = 1;
  int _totalPages = 1;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _error;

  int _displayCount = _itemsPerPage;

  CategoryItem? _selectedCategory;
  int? _currentCateId;
  List<CategoryItem> _categories = [];
  bool _categoriesLoaded = false;

  final Set<String> _expandedSlugs = {};

  Timer? _autoRefreshTimer;
  Set<String> _knownUrls = {};

  int _lastLoginVersion = 0;
  int _loadRequestId = 0;
  int _sessionReloadId = 0;
  bool _initialCacheApplied = false;

  /// Resolved push feed path per category, cached for this page's lifetime.
  /// A null value means the category declares no feed (the site does not
  /// refresh it either); failures are not cached, so they retry next tick.
  final Map<int, String?> _categoryFeedUrls = <int, String?>{};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadCategories();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPage(1);
      _startAutoRefresh();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final appState = context.watch<AppState>();
    if (!_initialCacheApplied) {
      _initialCacheApplied = true;
      _applyInitialCache(appState.initialHomeCache);
    }
    if (appState.sessionReady && appState.loginVersion != _lastLoginVersion) {
      _lastLoginVersion = appState.loginVersion;
      _reloadForSessionChange();
    }
  }

  void _applyInitialCache(HomeCacheData? cache) {
    if (cache == null || cache.articles.isEmpty) return;
    _articles = cache.articles;
    _knownUrls = cache.articles.map((article) => article.url).toSet();
    _categories = cache.categories;
    _categoriesLoaded = cache.categories.isNotEmpty;
    _totalPages = cache.totalPages;
    _displayCount = _itemsPerPage;
  }

  Future<void> _reloadForSessionChange() async {
    // Per-category feed config can differ per account (e.g. 我的关注), so it
    // is re-resolved after a login change.
    _categoryFeedUrls.clear();
    if (_selectedCategory != null) {
      await _loadPage(1, force: true);
      return;
    }
    final reloadId = ++_sessionReloadId;
    _loadRequestId++;
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    try {
      final result = await _api.fetchHomeData();
      if (!mounted || reloadId != _sessionReloadId) return;
      setState(() {
        _articles = result.items;
        _knownUrls = result.items.map((article) => article.url).toSet();
        _categories = result.categories;
        _categoriesLoaded = true;
        _currentPage = 1;
        _totalPages = result.totalPages;
        _displayCount = _itemsPerPage;
        _currentCateId = null;
        _isLoading = false;
        _error = null;
      });
      unawaited(
        _cache.save(
          HomeCacheData(
            articles: result.items,
            categories: result.categories,
            totalPages: result.totalPages,
            savedAt: DateTime.now(),
          ),
        ),
      );
    } catch (e) {
      debugPrint('Failed to refresh session data: $e');
      if (mounted && reloadId == _sessionReloadId) {
        setState(() {
          _isLoading = false;
          if (_articles.isEmpty) _error = friendlyErrorMessage(e);
        });
      }
    }
  }

  void _openCollectList() {
    final appState = context.read<AppState>();
    if (!appState.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录后查看收藏')),
      );
      appState.goToLoginTab();
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CollectListPage()),
    );
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _fetchNewArticles();
    });
  }

  Future<void> _loadCategories() async {
    try {
      final cats = await _api.fetchCategoryList();
      if (!mounted) return;
      setState(() {
        _categories = cats;
        _categoriesLoaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _categoriesLoaded = true;
      });
      debugPrint('Failed to load categories: ' + e.toString());
    }
  }

  Future<void> _fetchNewArticles() async {
    if (_isLoading) return;
    try {
      final newArticles = await _fetchCandidateArticles();
      if (!mounted || newArticles.isEmpty) return;

      final fresh = newArticles
          .where((a) => a.url.isNotEmpty && !_knownUrls.contains(a.url))
          .toList();
      if (fresh.isEmpty) return;

      setState(() {
        _articles.insertAll(0, fresh);
        for (final a in fresh) {
          _knownUrls.add(a.url);
        }
        if (_articles.length > 200) {
          _articles = _articles.sublist(0, 200);
        }
        // Deliberately do NOT grow _displayCount here. Pushed articles are
        // inserted at the top, so they are already inside the visible window;
        // growing it instead would make the list creep past its page size
        // (this site pushes ~25 articles/minute) until scrolling re-opens it.
        if (_displayCount > _articles.length) {
          _displayCount = _articles.length;
        }
      });
    } catch (e) {
      // Keep the list usable, but never hide the failure: a swallowed error
      // here silently disables the 5s auto-refresh with no other symptom.
      debugPrint('Home auto refresh failed: $e');
    }
  }

  /// Picks the refresh source for the current view.
  ///
  /// The website auto-refreshes a category only when its own meta script
  /// declares a push feed (`postjson.url`), so we resolve that feed instead of
  /// assuming `push_{cateId}.json`. Categories the site does not refresh - the
  /// drawer has 11 of them, e.g. 我的关注、公告、教程、线报库、归档 - declare no
  /// feed and are left alone, matching the site.
  Future<List<ArticleListItem>> _fetchCandidateArticles() async {
    final category = _selectedCategory;
    if (category == null) return _api.fetchNewArticles();

    // The category id is only known once its page has loaded. Before that
    // there is nothing to poll, and falling back to the site-wide feed would
    // push other categories' articles into this list.
    final cateId = _currentCateId;
    if (cateId == null) return const <ArticleListItem>[];

    final feedUrl = await _resolveCategoryFeedUrl(cateId, category.slug);
    if (feedUrl == null) return const <ArticleListItem>[];

    return _api.fetchArticlesFromFeed(feedUrl, fallbackCateId: cateId);
  }

  Future<String?> _resolveCategoryFeedUrl(int cateId, String slug) async {
    if (_categoryFeedUrls.containsKey(cateId)) return _categoryFeedUrls[cateId];
    final url = await _api.fetchCategoryPushFeedUrl(cateId: cateId, slug: slug);
    _categoryFeedUrls[cateId] = url;
    return url;
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final decision = preloadForScroll(
      shown: _displayCount,
      fetched: _articles.length,
      pixels: pos.pixels,
      maxScrollExtent: pos.maxScrollExtent,
      viewportDimension: pos.viewportDimension,
    );

    // Already-fetched articles are instant to reveal, so show those first.
    if (decision.reveal != _displayCount) {
      setState(() => _displayCount = decision.reveal);
      return;
    }
    if (decision.fetchNextPage &&
        !_isLoadingMore &&
        !_isLoading &&
        _currentPage < _totalPages) {
      _loadMore();
    }
  }

  Future<void> _loadPage(int page, {bool force = false}) async {
    if (_isLoading && !force) return;
    final requestId = ++_loadRequestId;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final result = _selectedCategory != null
          ? await _api.fetchCategoryArticleList(
              slug: _selectedCategory!.slug, page: page)
          : await _api.fetchArticleList(page: page);
      if (!mounted || requestId != _loadRequestId) return;
      setState(() {
        _articles = result.items;
        _knownUrls = result.items.map((a) => a.url).toSet();
        _currentPage = page;
        _totalPages = result.totalPages;
        _displayCount = _itemsPerPage;
        _isLoading = false;
        if (_selectedCategory != null) {
          _currentCateId = result.cateId;
        } else {
          _currentCateId = null;
        }
      });
      if (_selectedCategory == null && page == 1) {
        unawaited(
          _cache.save(
            HomeCacheData(
              articles: result.items,
              categories: _categories,
              totalPages: result.totalPages,
              savedAt: DateTime.now(),
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted || requestId != _loadRequestId) return;
      setState(() {
        _isLoading = false;
        _error = friendlyErrorMessage(e);
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || _currentPage >= _totalPages) return;
    setState(() => _isLoadingMore = true);
    try {
      final nextPage = _currentPage + 1;
      final result = _selectedCategory != null
          ? await _api.fetchCategoryArticleList(
              slug: _selectedCategory!.slug, page: nextPage)
          : await _api.fetchArticleList(page: nextPage);
      if (!mounted) return;
      setState(() {
        _articles.addAll(result.items);
        _knownUrls.addAll(result.items.map((a) => a.url));
        _currentPage = nextPage;
        _totalPages = result.totalPages;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _refresh() async {
    await _loadPage(1);
  }

  void _selectCategory(CategoryItem? category) {
    setState(() {
      _selectedCategory = category;
      _articles = [];
      _knownUrls = {};
      _currentPage = 1;
      _totalPages = 1;
      _displayCount = _itemsPerPage;
      _currentCateId = null;
    });
    Navigator.pop(context);
    _loadPage(1);
  }

  void _toggleExpand(String slug) {
    setState(() {
      if (_expandedSlugs.contains(slug)) {
        _expandedSlugs.remove(slug);
      } else {
        _expandedSlugs.add(slug);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildDrawer(theme),
      appBar: AppBar(
        title: Text(
          _selectedCategory?.name ?? '线报酷',
          style: const TextStyle(fontSize: 16),
        ),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          tooltip: '分类菜单',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.star_border),
            tooltip: '收藏管理',
            onPressed: _openCollectList,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildDrawer(ThemeData theme) {
    final themeController = context.watch<ThemeController>();
    final isDark = theme.brightness == Brightness.dark;

    return SizedBox(
      width: 240,
      child: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                ),
                child: Row(
                  children: [
                    Text(
                      '分类',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    // Day/night toggle, same row as the 分类 title.
                    IconButton(
                      icon: Icon(
                        isDark
                            ? Icons.light_mode_outlined
                            : Icons.dark_mode_outlined,
                      ),
                      color: theme.colorScheme.onPrimaryContainer,
                      tooltip: isDark ? '切换到日间模式' : '切换到夜间模式',
                      onPressed: () => themeController.toggle(
                        theme.brightness,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _categoriesLoaded
                    ? _buildCategoryTree(theme)
                    : const Center(child: CircularProgressIndicator()),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.link),
                title: const Text('京东转链'),
                onTap: () {
                  Navigator.of(context).pop(); // close drawer
                  showUnionSettingsDialog(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('关于'),
                onTap: () {
                  Navigator.of(context).pop(); // close drawer
                  showAboutAppDialog(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryTree(ThemeData theme) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _buildAllItem(theme),
        const Divider(height: 1),
        ..._categories.map((cat) => _buildCategoryNode(cat, theme, 0)),
      ],
    );
  }

  Widget _buildAllItem(ThemeData theme) {
    final isSelected = _selectedCategory == null;
    return InkWell(
      onTap: () => _selectCategory(null),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: isSelected ? theme.colorScheme.primaryContainer : null,
        child: Row(
          children: [
            Icon(Icons.home_outlined,
                size: 20,
                color: isSelected ? theme.colorScheme.primary : null),
            const SizedBox(width: 12),
            Text(
              '全部',
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? theme.colorScheme.primary : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Recursively check if an item has any visible descendants
  /// (children that are category pages or have visible children).
  bool _hasVisibleChildren(CategoryItem item) {
    for (final child in item.children) {
      if (child.isCategoryPage) return true;
      if (_hasVisibleChildren(child)) return true;
    }
    return false;
  }

  Widget _buildCategoryNode(CategoryItem item, ThemeData theme, int level) {
    final isSelected = _selectedCategory?.url == item.url;

    // Leaf node: no visible children.
    if (!_hasVisibleChildren(item)) {
      if (!item.isCategoryPage) return const SizedBox.shrink();
      return InkWell(
        onTap: () => _selectCategory(item),
        child: Container(
          padding: EdgeInsets.only(
              left: 16.0 + level * 16, right: 16, top: 10, bottom: 10),
          color: isSelected ? theme.colorScheme.primaryContainer : null,
          child: Text(
            item.name,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? theme.colorScheme.primary : null,
            ),
          ),
        ),
      );
    }

    // Parent node with visible children: title tap navigates,
    // chevron icon toggles expansion.
    final expanded = _expandedSlugs.contains(item.slug);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => _selectCategory(item),
          child: Container(
            padding: EdgeInsets.only(
                left: 16.0 + level * 16, right: 8, top: 10, bottom: 10),
            color: isSelected ? theme.colorScheme.primaryContainer : null,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    item.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.w600,
                      color: isSelected ? theme.colorScheme.primary : null,
                    ),
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _toggleExpand(item.slug),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    child: Icon(
                      expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 22,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          ...item.children
              .map((child) => _buildCategoryNode(child, theme, level + 1)),
      ],
    );
  }

  Widget _buildBody() {
    final theme = Theme.of(context);

    if (_isLoading && _articles.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return LoadErrorView(
        message: _error!,
        onRetry: () => _loadPage(1),
      );
    }

    if (_articles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.article_outlined, size: 48,
                color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => _loadPage(1),
              child: const Text('加载文章'),
            ),
          ],
        ),
      );
    }

    final displayItems = _articles.take(_displayCount).toList();
    // One trailing slot: a spinner while the next page loads, or the end note.
    // The pagination bar is gone - scrolling is the only way to load more.
    final itemCount = displayItems.length + 1;
    final reachedEnd =
        _displayCount >= _articles.length && _currentPage >= _totalPages;

    return ColoredBox(
      // The list module sits on the page background, like `.sb` on the site.
      color: theme.colorScheme.surface,
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView.builder(
          controller: _scrollController,
          itemCount: itemCount,
          itemBuilder: (context, index) {
            if (index == itemCount - 1) {
              if (_isLoadingMore) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (reachedEnd) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: Text(
                      '没有更多了',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                );
              }
              // Keeps the last row off the bottom edge while the next chunk
              // is on its way.
              return const SizedBox(height: 12);
            }
            final article = displayItems[index];
            return ArticleListTile(
              article: article,
              showDivider: index != displayItems.length - 1,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ArticleDetailPage(article: article),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
