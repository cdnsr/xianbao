import 'package:flutter/material.dart';

import '../../services/ucenter_service.dart';
import '../../utils/error_message.dart';
import '../../widgets/load_error_view.dart';
import 'rule_editor_sheet.dart';

/// 一个频道的规则行列表（我的关注三个位、各筛选页共用）。
///
/// 数据来自 `userfilter_fun.php act=list`：开关、范围、八组词与价格区间；开关走
/// `switchs`，删除走 `deldata`，编辑/新增打开服务端下发的表单（[showRuleEditor]）。
class RuleRowsPage extends StatefulWidget {
  final String channel;
  final String title;

  /// 页面顶部的说明（限额、生效范围等），空则不显示。
  final String hint;

  const RuleRowsPage({
    super.key,
    required this.channel,
    required this.title,
    this.hint = '',
  });

  @override
  State<RuleRowsPage> createState() => _RuleRowsPageState();
}

class _RuleRowsPageState extends State<RuleRowsPage> {
  final UcenterService _service = UcenterService();

  List<UcenterRuleRow> _rows = const [];
  bool _loading = true;
  String? _error;
  final Set<String> _busyIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _service.fetchFilterRows(widget.channel);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyErrorMessage(e);
      });
    }
  }

  Future<void> _toggle(UcenterRuleRow row, bool enabled) async {
    setState(() => _busyIds.add(row.id));
    try {
      final result = await _service.setFilterRowStatus(
        channel: widget.channel,
        id: row.id,
        enabled: enabled,
      );
      if (!mounted) return;
      _showMessage(
        result.message.isNotEmpty
            ? result.message
            : (result.ok ? '已更新' : '更新失败'),
      );
      if (result.ok) await _load();
    } catch (e) {
      if (!mounted) return;
      _showMessage(friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busyIds.remove(row.id));
    }
  }

  Future<void> _delete(UcenterRuleRow row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除规则'),
        content: const Text('确定删除这条规则吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final result = await _service.deleteFilterRow(
        channel: widget.channel,
        id: row.id,
      );
      if (!mounted) return;
      _showMessage(
        result.message.isNotEmpty
            ? result.message
            : (result.ok ? '已删除' : '删除失败'),
      );
      if (result.ok) await _load();
    } catch (e) {
      if (!mounted) return;
      _showMessage(friendlyErrorMessage(e));
    }
  }

  Future<void> _edit(UcenterRuleRow? row) async {
    final saved = await showRuleEditor(
      context,
      channel: widget.channel,
      title: widget.title,
      id: row?.id ?? '',
    );
    if (saved && mounted) await _load();
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新增规则',
            onPressed: () => _edit(null),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(theme),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _rows.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: LoadErrorView(message: _error!, onRetry: _load),
          ),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (widget.hint.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              widget.hint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ),
        if (_rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 32),
            child: Column(
              children: [
                Icon(
                  Icons.rule_folder_outlined,
                  size: 40,
                  color: theme.colorScheme.outline,
                ),
                const SizedBox(height: 12),
                Text(
                  '还没有规则，点右上角「+」新增',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          )
        else
          for (final row in _rows)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: _buildRowCard(theme, row),
            ),
      ],
    );
  }

  Widget _buildRowCard(ThemeData theme, UcenterRuleRow row) {
    final rule = row.rule;
    final busy = _busyIds.contains(row.id);
    final details = <String>[
      if (rule.scope.trim().isNotEmpty) '范围：${rule.scope.trim()}',
      if (rule.titleGjc.trim().isNotEmpty) '关键词：${rule.titleGjc.trim()}',
      if (rule.titlePbc.trim().isNotEmpty) '屏蔽词：${rule.titlePbc.trim()}',
      if (rule.categoryGjc.trim().isNotEmpty) '分类词：${rule.categoryGjc.trim()}',
      if (rule.categoryPbc.trim().isNotEmpty)
        '分类屏蔽：${rule.categoryPbc.trim()}',
      if (rule.authorGjc.trim().isNotEmpty) '楼主词：${rule.authorGjc.trim()}',
      if (rule.authorPbc.trim().isNotEmpty) '楼主屏蔽：${rule.authorPbc.trim()}',
      if (rule.minPrice.trim().isNotEmpty || rule.maxPrice.trim().isNotEmpty)
        '价格：${rule.minPrice.trim().isEmpty ? '不限' : rule.minPrice.trim()}'
            ' - ${rule.maxPrice.trim().isEmpty ? '不限' : rule.maxPrice.trim()}',
    ];

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(2),
      ),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  details.isEmpty ? '（空规则，全部放行）' : '规则行',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Switch(
                  value: rule.enabled,
                  onChanged: (v) => _toggle(row, v),
                ),
            ],
          ),
          if (details.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final detail in details)
                    Text(
                      detail,
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                    ),
                ],
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => _edit(row),
                child: const Text('编辑'),
              ),
              TextButton(
                onPressed: () => _delete(row),
                child: const Text('删除'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
