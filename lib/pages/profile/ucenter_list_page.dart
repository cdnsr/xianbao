import 'package:flutter/material.dart';

import '../../models/article.dart';
import '../../models/ucenter_table.dart';
import '../../services/ucenter_service.dart';
import '../../widgets/paged_list.dart';
import '../article/article_detail_page.dart';
import '../../widgets/text_tip.dart';

/// 用户中心的通用列表页：评论管理 / 工单系统 / 已购订单 / 系统通知。
///
/// 这几个页面在网站上是同一套 layui 表格（`json/List.php` 不同 `act`），列定义见
/// [ucenterListSpecs]，所以原生侧也用同一个页面渲染，只有行尾操作不同。
class UcenterListPage extends StatefulWidget {
  /// [ucenterListSpecs] 里的键：comments / tickets / orders / notices。
  final String specKey;

  const UcenterListPage({super.key, required this.specKey});

  @override
  State<UcenterListPage> createState() => _UcenterListPageState();
}

class _UcenterListPageState extends State<UcenterListPage> {
  final UcenterService _service = UcenterService();
  final PagedListController<UcenterTableRow> _listController =
      PagedListController<UcenterTableRow>();
  late final UcenterListSpec _spec = ucenterListSpecs[widget.specKey]!;

  @override
  void dispose() {
    _listController.dispose();
    super.dispose();
  }

  Future<({List<UcenterTableRow> items, int total})> _load(
    int page,
    int limit,
  ) async {
    final result = await _service.fetchTable(
      act: _spec.act,
      page: page,
      limit: limit,
      extra: _spec.extraParams,
    );
    if (result.needLogin) {
      throw Exception(
        result.message.isEmpty ? '登录已失效，请重新登录' : result.message,
      );
    }
    return (items: result.rows, total: result.total);
  }

  Future<void> _runAction(UcenterTableRow row) async {
    final id = row.actionId;
    if (id == null || id.isEmpty) {
      _showMessage('这条记录没有可操作的编号', isError: true);
      return;
    }
    final (title, confirmLabel, action) = switch (_spec.action) {
      UcenterRowAction.deleteComment => ('删除评论', '删除', 'del'),
      UcenterRowAction.closeTicket => ('关闭工单', '关闭', 'close'),
      UcenterRowAction.deleteCollect => ('取消收藏', '取消收藏', 'del'),
      UcenterRowAction.none => ('', '', ''),
    };
    if (action.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text('确定要$confirmLabel这条记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final result = switch (_spec.action) {
        UcenterRowAction.deleteComment => await _service.deleteComment(id),
        UcenterRowAction.closeTicket => await _service.closeTicket(id),
        UcenterRowAction.deleteCollect => UcenterResult.fromText(''),
        UcenterRowAction.none => UcenterResult.fromText(''),
      };
      if (!mounted) return;
      _showMessage(
        result.message.isNotEmpty
            ? result.message
            : (result.ok ? '操作成功' : '操作失败'),
        isError: !result.ok,
      );
      if (result.ok) _listController.reload();
    } catch (e) {
      if (!mounted) return;
      _showMessage('$e', isError: true);
    }
  }

  /// 操作回执用轻量文字提示：成功 1 秒、失败略长（够看清原因）。
  void _showMessage(String message, {bool isError = false}) {
    showTextTip(
      context,
      message,
      duration: isError ? kErrorTipDuration : const Duration(seconds: 1),
    );
  }

  void _openArticle(UcenterTableRow row) {
    final path = row.articleUrl;
    if (path == null || path.isEmpty) return;
    final primary = _spec.columns.firstWhere(
      (c) => c.primary,
      orElse: () => _spec.columns.first,
    );
    final article = ArticleListItem(
      url: path,
      title: row.cell(primary.key),
      category: _spec.title,
      summary: '',
      commentCount: 0,
      date: '',
      time: '',
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
      appBar: AppBar(title: Text(_spec.title), centerTitle: true),
      body: PagedList<UcenterTableRow>(
        controller: _listController,
        emptyText: _spec.emptyText,
        loader: _load,
        itemBuilder: (context, row, index) =>
            _buildRow(context, row),
      ),
    );
  }

  Widget _buildRow(BuildContext context, UcenterTableRow row) {
    final theme = Theme.of(context);
    final primary = _spec.columns.firstWhere(
      (c) => c.primary,
      orElse: () => _spec.columns.first,
    );
    final details = _spec.columns.where((c) => !c.primary).toList();
    final hasAction = _spec.action != UcenterRowAction.none;

    return InkWell(
      onTap: row.articleUrl == null ? null : () => _openArticle(row),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              row.cell(primary.key),
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
            if (details.any((c) => row.cell(c.key).isNotEmpty)) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  for (final column in details)
                    if (row.cell(column.key).isNotEmpty)
                      Text(
                        '${column.label}：${row.cell(column.key)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                ],
              ),
            ],
            if (hasAction) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => _runAction(row),
                  child: Text(
                    _spec.action == UcenterRowAction.closeTicket
                        ? '关闭工单'
                        : '删除',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
