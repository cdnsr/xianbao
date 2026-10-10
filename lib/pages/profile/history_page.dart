import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/ucenter_form.dart';
import '../../services/ucenter_service.dart';
import '../../utils/error_message.dart';
import '../../widgets/load_error_view.dart';
import '../../widgets/text_tip.dart';

/// 历史筛选数据（只读）。
///
/// 网站这一页说明得很清楚：历史遗留配置，对应保存表单已下线，仅供查看与一键复制。
/// 所以原生版也只读：把「标签 + 旧键名 + 值」列出来，逐条可复制，方便贴到新版规则行里。
class FilterHistoryPage extends StatefulWidget {
  const FilterHistoryPage({super.key});

  @override
  State<FilterHistoryPage> createState() => _FilterHistoryPageState();
}

class _FilterHistoryPageState extends State<FilterHistoryPage> {
  final UcenterService _service = UcenterService();
  List<UcenterReadonlyField> _fields = const [];
  bool _loading = true;
  String? _error;

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
      final fields = await _service.fetchReadonlyFields('Shaixuan_history');
      if (!mounted) return;
      setState(() {
        _fields = fields.where((f) => !f.isEmpty).toList();
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

  Future<void> _copy(UcenterReadonlyField field) async {
    await Clipboard.setData(ClipboardData(text: field.value));
    if (!mounted) return;
    showTextTip(context, '已复制');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('历史筛选数据'), centerTitle: true),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody(theme)),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
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
    if (_fields.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Center(
            child: Text(
              '暂无历史筛选数据',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Text(
            '历史遗留配置（只读）：对应保存入口已下线，旧数据仍可能在前台兜底生效。'
            '点右侧按钮可复制，粘贴到新版规则行即可继续使用。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.6,
            ),
          ),
        ),
        const Divider(height: 1),
        for (final field in _fields)
          Container(
            color: theme.colorScheme.surface,
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        field.label.isEmpty ? field.key : field.label,
                        style: theme.textTheme.bodyMedium,
                      ),
                      if (field.key.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          field.key,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        field.value,
                        style: theme.textTheme.bodySmall?.copyWith(height: 1.6),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '复制',
                  icon: const Icon(Icons.copy_all_outlined, size: 18),
                  onPressed: () => _copy(field),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }
}
