import 'package:flutter/material.dart';
import '../../models/article.dart';
import '../../services/api_service.dart';
import '../../widgets/paged_list.dart';
import '../article/article_detail_page.dart';

/// User collect list page (native list of 收藏管理).
class CollectListPage extends StatefulWidget {
  const CollectListPage({super.key});

  @override
  State<CollectListPage> createState() => _CollectListPageState();
}

class _CollectListPageState extends State<CollectListPage> {
  final ApiService _api = ApiService();
  final PagedListController<CollectListItem> _listController =
      PagedListController<CollectListItem>();

  @override
  void dispose() {
    _listController.dispose();
    super.dispose();
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
      _listController.removeWhere((e) => e.collectId == item.collectId);
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
      MaterialPageRoute(builder: (_) => ArticleDetailPage(article: article)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('收藏管理'), centerTitle: true),
      body: PagedList<CollectListItem>(
        controller: _listController,
        emptyText: '暂无收藏',
        loader: (page, limit) => _api.fetchCollectList(page: page, limit: limit),
        itemBuilder: (context, item, index) => ListTile(
          title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: item.postTime.isEmpty
              ? null
              : Text('收藏时间：${item.postTime}'),
          onTap: () => _openArticle(item),
          trailing: TextButton(
            onPressed: () => _uncollect(item),
            child: const Text('取消收藏'),
          ),
        ),
      ),
    );
  }
}
