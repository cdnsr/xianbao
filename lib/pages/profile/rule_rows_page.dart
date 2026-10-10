import 'package:flutter/material.dart';

import '../../models/ucenter_form.dart';
import '../../services/ucenter_service.dart';
import '../../utils/error_message.dart';
import '../../widgets/load_error_view.dart';
import 'rule_editor_sheet.dart';

/// 一个筛选页的规则行列表（我的关注三个位、各筛选频道共用）。
///
/// 数据来自该页对应的 `act=list`：开关、范围、八组词与价格区间；开关走 `switchs`，
/// 删除走 `deldata`，编辑/新增用服务端下发的表单（[showRuleEditor]）。
///
/// 响应速度上做了三件事（这些接口都在站内、每次往返几百毫秒起）：
///  - 开关与删除**就地更新**，不再整页重拉；
///  - 进入页面时**预取**新增用的表单，点「+」可以秒开；
///  - 保存返回后先关掉编辑页，再在后台静默刷新列表（不闪整页 loading）。
class RuleRowsPage extends StatefulWidget {
  final UcenterFilterTarget target;
  final String title;

  /// 页面顶部的说明（限额、生效范围等），空则不显示。
  final String hint;

  const RuleRowsPage({
    super.key,
    required this.target,
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

  /// 预取的新增表单（进入页面时后台拉一次）。
  UcenterForm? _newRowForm;
  bool _prefetching = false;

  @override
  void initState() {
    super.initState();
    _load();
    _prefetchEditorForm();
  }

  /// 提前把「新增」用的表单取回来，点 + 时直接打开。
  Future<void> _prefetchEditorForm() async {
    if (_prefetching) return;
    _prefetching = true;
    try {
      final form = await _service.loadFilterEditorForm(widget.target);
      if (!mounted) return;
      setState(() => _newRowForm = form);
    } catch (_) {
      // 预取失败不影响使用：点「+」时会再拉一次并给出提示。
    } finally {
      _prefetching = false;
    }
  }

  /// [silent] 为真时不显示整页 loading（用于操作后的后台刷新）。
  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final rows = await _service.fetchFilterRows(widget.target);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) _error = friendlyErrorMessage(e);
      });
    }
  }

  Future<void> _toggle(UcenterRuleRow row, bool enabled) async {
    setState(() => _busyIds.add(row.id));
    // 先就地翻转开关，请求在后台跑；失败再翻回来。
    _replaceRow(row.id, enabled: enabled);
    try {
      final result = await _service.setFilterRowStatus(
        target: widget.target,
        id: row.id,
        enabled: enabled,
      );
      if (!mounted) return;
      if (!result.ok) {
        _replaceRow(row.id, enabled: row.rule.enabled);
        _showMessage(
          result.message.isEmpty ? '更新失败' : result.message,
        );
      }
    } catch (e) {
      if (!mounted) return;
      _replaceRow(row.id, enabled: row.rule.enabled);
      _showMessage(friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busyIds.remove(row.id));
    }
  }

  /// 就地更新一行的开关状态（不重拉列表）。
  void _replaceRow(String id, {required bool enabled}) {
    if (!mounted) return;
    setState(() {
      _rows = _rows
          .map(
            (row) => row.id == id
                ? UcenterRuleRow(
                    id: row.id,
                    rule: row.rule.copyWithEnabled(enabled),
                  )
                : row,
          )
          .toList();
    });
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

    // 先移除，请求失败再把整表拉回来。
    final backup = _rows;
    setState(() {
      _rows = _rows.where((r) => r.id != row.id).toList();
    });
    try {
      final result = await _service.deleteFilterRow(
        target: widget.target,
        id: row.id,
      );
      if (!mounted) return;
      if (!result.ok) {
        setState(() => _rows = backup);
        _showMessage(result.message.isEmpty ? '删除失败' : result.message);
        return;
      }
      _showMessage(result.message.isEmpty ? '已删除' : result.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _rows = backup);
      _showMessage(friendlyErrorMessage(e));
    }
  }

  Future<void> _edit(UcenterRuleRow? row) async {
    final saved = await showRuleEditor(
      context,
      target: widget.target,
      title: widget.title,
      id: row?.id ?? '',
      // 新增时用预取好的表单（编辑单据的另取，避免拿到旧值）。
      prefetchedForm: row == null ? _newRowForm : null,
    );
    if (!saved || !mounted) return;
    // 新行的表单已经用掉了，重新预取一份；顺带静默刷新列表。
    setState(() => _newRowForm = null);
    await _load(silent: true);
    _prefetchEditorForm();
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
        onRefresh: () => _load(),
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
            child: LoadErrorView(message: _error!, onRetry: () => _load()),
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
      if (rule.mallGjc.trim().isNotEmpty) '商城词：${rule.mallGjc.trim()}',
      if (rule.mallPbc.trim().isNotEmpty) '商城屏蔽：${rule.mallPbc.trim()}',
      if (rule.mallName.trim().isNotEmpty) '商城名：${rule.mallName.trim()}',
      if (rule.brandGjc.trim().isNotEmpty) '品牌词：${rule.brandGjc.trim()}',
      if (rule.brandPbc.trim().isNotEmpty) '品牌屏蔽：${rule.brandPbc.trim()}',
      if (rule.authorGjc.trim().isNotEmpty) '楼主词：${rule.authorGjc.trim()}',
      if (rule.authorPbc.trim().isNotEmpty) '楼主屏蔽：${rule.authorPbc.trim()}',
      if (rule.type.trim().isNotEmpty) '类型：${rule.type.trim()}',
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
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
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
