import 'package:flutter/material.dart';
import '../../models/article.dart';
import '../../services/api_service.dart';
import '../../utils/error_message.dart';
import '../../widgets/load_error_view.dart';
import '../../widgets/article_list_tile.dart';
import '../article/article_detail_page.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final ApiService _api = ApiService();
  final TextEditingController _controller = TextEditingController();
  List<ArticleListItem> _results = [];
  bool _isSearching = false;
  bool _hasSearched = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _doSearch() async {
    final keyword = _controller.text.trim();
    if (keyword.isEmpty) return;
    setState(() {
      _isSearching = true;
      _error = null;
      _hasSearched = true;
    });
    try {
      final results = await _api.searchArticles(keyword);
      setState(() {
        _results = results;
        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _isSearching = false;
        _error = friendlyErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _doSearch(),
          decoration: const InputDecoration(
            hintText: '请输入关键词...',
            border: InputBorder.none,
          ),
          style: theme.textTheme.titleMedium,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _doSearch,
            tooltip: '搜索',
          ),
        ],
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return LoadErrorView(message: _error!, onRetry: _doSearch);
    }
    if (!_hasSearched) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search,
                size: 64,
                color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              '输入关键词搜索文章',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(
          '没有找到相关文章',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      );
    }
    return ColoredBox(
      color: theme.colorScheme.surface,
      child: ListView.builder(
        itemCount: _results.length,
        itemBuilder: (context, index) {
          final article = _results[index];
          return ArticleListTile(
            article: article,
            showDivider: index != _results.length - 1,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      ArticleDetailPage(article: article),
                ),
              );
            },
          );
        },
      ),
    );
  }
}