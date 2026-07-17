import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/article.dart';
import '../../services/api_service.dart';
import '../../services/app_state.dart';
import '../../utils/html_utils.dart';
import '../../widgets/article_content_view.dart';
import '../../widgets/comment_list.dart';

class ArticleDetailPage extends StatefulWidget {
  final ArticleListItem article;

  const ArticleDetailPage({super.key, required this.article});

  @override
  State<ArticleDetailPage> createState() => _ArticleDetailPageState();
}

class _ArticleDetailPageState extends State<ArticleDetailPage> {
  final ApiService _api = ApiService();
  ArticleDetail? _detail;
  bool _isLoading = true;
  String? _error;

  bool _isCollected = false;
  int _collectSize = 0;
  bool _collectBusy = false;
  bool _refetchBusy = false;

  int? get _articleId =>
      _detail?.articleId ?? widget.article.articleId;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final detail = await _api.fetchArticleDetail(widget.article.path);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _isLoading = false;
      });
      final id = detail.articleId ?? widget.article.articleId;
      if (id != null) {
        unawaited(_refreshCollectState(id));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = '加载失败: $e';
      });
    }
  }

  Future<void> _refreshCollectState(int articleId) async {
    final state = await _api.fetchCollectButtonState(articleId);
    if (!mounted || state == null) return;
    setState(() {
      _isCollected = state.isCollected;
      _collectSize = state.size;
    });
  }

  void _snack(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  bool _ensureLoggedIn() {
    final appState = context.read<AppState>();
    if (appState.isLoggedIn) return true;
    _snack('请先登录后再收藏');
    appState.goToLoginTab();
    Navigator.of(context).popUntil((route) => route.isFirst);
    return false;
  }

  Future<void> _onCollect() async {
    if (_collectBusy) return;
    final id = _articleId;
    if (id == null) {
      _snack('无法识别文章 ID');
      return;
    }
    if (!_ensureLoggedIn()) return;

    setState(() => _collectBusy = true);
    try {
      final result = await _api.toggleCollect(id);
      if (!mounted) return;
      if (result.needLogin) {
        _snack(result.message.isNotEmpty ? result.message : '请先登录后再收藏');
        context.read<AppState>().goToLoginTab();
        Navigator.of(context).popUntil((route) => route.isFirst);
        return;
      }
      setState(() {
        _isCollected = result.isCollected;
        _collectSize = result.size;
      });
      _snack(
        result.message.isNotEmpty
            ? result.message
            : (result.isCollected ? '收藏成功' : '已取消收藏'),
      );
    } catch (e) {
      _snack('收藏失败: $e');
    } finally {
      if (mounted) setState(() => _collectBusy = false);
    }
  }

  Future<void> _onCopy() async {
    final detail = _detail;
    if (detail == null) return;
    final text = HtmlUtils.toPlainText(detail.contentHtml);
    if (text.isEmpty) {
      _snack('正文为空，无法复制');
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    _snack('复制成功');
  }

  Future<void> _onRefetch() async {
    if (_refetchBusy) return;
    final id = _articleId;
    if (id == null) {
      _snack('无法识别文章 ID');
      return;
    }
    setState(() => _refetchBusy = true);
    try {
      final msg = await _api.refetchArticle(id);
      _snack(msg.isEmpty ? '已提交重新抓取' : msg);
    } catch (e) {
      _snack('重新抓取失败: $e');
    } finally {
      if (mounted) setState(() => _refetchBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.article.category,
          style: const TextStyle(fontSize: 16),
        ),
        centerTitle: true,
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loadDetail,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    final detail = _detail;
    if (detail == null) {
      return const Center(child: Text('无内容'));
    }

    return RefreshIndicator(
      onRefresh: _loadDetail,
      child: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              detail.title,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                if (detail.author.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.person_outline,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(detail.author, style: theme.textTheme.bodySmall),
                    ],
                  ),
                if (detail.datetime.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(detail.datetime, style: theme.textTheme.bodySmall),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildActionBar(theme),
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ArticleContentView(contentHtml: detail.contentHtml),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          CommentList(comments: detail.comments),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildActionBar(ThemeData theme) {
    final collectLabel = _isCollected
        ? (_collectSize > 0 ? '已藏 | $_collectSize' : '已藏')
        : '收藏';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _ActionChip(
            icon: _isCollected ? Icons.star : Icons.star_border,
            label: collectLabel,
            busy: _collectBusy,
            selected: _isCollected,
            onPressed: _onCollect,
          ),
          _ActionChip(
            icon: Icons.copy_outlined,
            label: '复制',
            onPressed: _onCopy,
          ),
          _ActionChip(
            icon: Icons.refresh,
            label: '重抓',
            busy: _refetchBusy,
            onPressed: _onRefetch,
          ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final bool selected;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ActionChip(
      avatar: busy
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: selected
                    ? theme.colorScheme.onSecondaryContainer
                    : theme.colorScheme.primary,
              ),
            )
          : Icon(icon, size: 18),
      label: Text(label),
      onPressed: busy ? null : onPressed,
      backgroundColor: selected
          ? theme.colorScheme.secondaryContainer
          : null,
    );
  }
}

// Local unawaited helper (avoid importing dart:async just for this).
void unawaited(Future<void> future) {}