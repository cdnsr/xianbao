import 'package:flutter/material.dart';
import '../../models/article.dart';
import '../../services/api_service.dart';
import '../article/article_detail_page.dart';

/// User collect list page (native list of 收藏管理).
class CollectListPage extends StatefulWidget {
  const CollectListPage({super.key});

  @override
  State<CollectListPage> createState() => _CollectListPageState();
}

class _CollectListPageState extends State<CollectListPage> {
  final ApiService _api = ApiService();
  final List<CollectListItem> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _page = 1;
  int _total = 0;
  static const int _limit = 20;

  bool get _hasMore => _items.length < _total;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _page = 1;
      });
    } else {
      if (_loadingMore || !_hasMore) return;
      setState(() => _loadingMore = true);
    }

    try {
      final page = reset ? 1 : _page + 1;
      final result = await _api.fetchCollectList(page: page, limit: _limit);
      if (!mounted) return;
      setState(() {
        if (reset) {
          _items
            ..clear()
            ..addAll(result.items);
        } else {
          _items.addAll(result.items);
        }
        _page = page;
        _total = result.total;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _uncollect(CollectListItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('取消收藏'),
        content: Text('确定取消收藏「${item.title}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final result = await _api.deleteCollect(item.collectId);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(result.message),
        duration: const Duration(seconds: 1),
      ),
    );
    if (result.ok) {
      setState(() {
        _items.removeWhere((e) => e.collectId == item.collectId);
        if (_total > 0) _total -= 1;
      });
    }
  }

  void _openArticle(CollectListItem item) {
    final path = item.url.isNotEmpty ? item.url : '';
    if (path.isEmpty) return;
    final article = ArticleListItem(
      url: path,
      title: item.title,
      category: '收藏',
      summary: '',
      commentCount: 0,
      date: '',
      time: item.postTime,
      author: '',
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ArticleDetailPage(article: article),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('收藏管理'),
        centerTitle: true,
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => _load(reset: true),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Text(
          '暂无收藏',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _items.length + (_hasMore || _loadingMore ? 1 : 0),
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          if (index >= _items.length) {
            if (!_loadingMore) {
              // Trigger load more once footer is built.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _load(reset: false);
              });
            }
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          final item = _items[index];
          return ListTile(
            title: Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: item.postTime.isEmpty
                ? null
                : Text('收藏时间：${item.postTime}'),
            onTap: () => _openArticle(item),
            trailing: TextButton(
              onPressed: () => _uncollect(item),
              child: const Text('取消收藏'),
            ),
          );
        },
      ),
    );
  }
}