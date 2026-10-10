import 'package:flutter/material.dart';

import '../../models/ucenter_form.dart';
import '../../services/ucenter_service.dart';
import '../../utils/error_message.dart';
import '../../widgets/load_error_view.dart';
import '../../widgets/ucenter_form_view.dart';

/// 整表单式筛选页（排行榜单筛选）。
///
/// 这一页在网站上不是规则行表格，而是一张表单：当前这套配置直接铺在表单里，提交时
/// 整表序列化（隐藏字段 `act`/`channel`/`id`/`csrfToken` 都在片段里）。字段与当前值
/// 都从对应视图片段解析，保存走 `userfilter_fun.php`。
///
/// 保存成功后网站会再拉一次 `act=list` 把新行的 id 回写进表单，避免重复提交产生多行；
/// 这里同样照做。
class FilterFormPage extends StatefulWidget {
  final UcenterFilterTarget target;

  /// `views/<view>.php`。
  final String view;

  final String title;
  final String hint;

  const FilterFormPage({
    super.key,
    required this.target,
    required this.view,
    required this.title,
    this.hint = '',
  });

  @override
  State<FilterFormPage> createState() => _FilterFormPageState();
}

class _FilterFormPageState extends State<FilterFormPage> {
  final UcenterService _service = UcenterService();
  final GlobalKey<UcenterFormViewState> _formKey =
      GlobalKey<UcenterFormViewState>();

  UcenterForm? _form;
  bool _loading = true;
  bool _saving = false;
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
      final form = await _service.fetchFilterForm(
        target: widget.target,
        view: widget.view,
      );
      if (!mounted) return;
      setState(() {
        _form = form;
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

  Future<void> _save() async {
    final form = _form;
    final viewState = _formKey.currentState;
    if (form == null || viewState == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await _service.saveFilterForm(
        target: widget.target,
        fields: form.withValues(viewState.values).toFormData(),
      );
      if (!mounted) return;
      setState(() => _saving = false);

      final message = result.message.isNotEmpty
          ? result.message
          : (result.ok ? '已保存' : '保存失败');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      if (!result.ok) {
        setState(() => _error = message);
        return;
      }

      // 新配置首次保存会新建一行，把 id 回写进表单，避免下次保存再多出一行。
      final rowId = await _service.fetchFilterFormRowId(widget.target);
      if (!mounted) return;
      if (rowId != null && rowId.isNotEmpty) {
        setState(() => _form = form.withValues({'id': rowId}));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = friendlyErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), centerTitle: true),
      body: _buildBody(theme),
      bottomNavigationBar: _form == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('保存'),
                ),
              ),
            ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final form = _form;
    if (form == null) {
      return LoadErrorView(message: _error ?? '加载失败', onRetry: _load);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        if (widget.hint.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              widget.hint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ),
        if (form.message.isNotEmpty)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              form.message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.6,
              ),
            ),
          ),
        UcenterFormView(key: _formKey, form: form),
        if (_error != null)
          Text(
            _error!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
      ],
    );
  }
}
