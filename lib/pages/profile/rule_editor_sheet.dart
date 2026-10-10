import 'package:flutter/material.dart';

import '../../models/ucenter_form.dart';
import '../../services/ucenter_service.dart';
import '../../utils/error_message.dart';
import '../../widgets/load_error_view.dart';
import '../../widgets/ucenter_form_view.dart';

/// 打开规则行编辑页；返回 true 表示已保存。
Future<bool> showRuleEditor(
  BuildContext context, {
  required String channel,
  required String title,
  String id = '',
}) async {
  final saved = await Navigator.push<bool>(
    context,
    MaterialPageRoute(
      builder: (_) => RuleEditorPage(channel: channel, title: title, id: id),
    ),
  );
  return saved == true;
}

/// 规则行编辑页。
///
/// 表单字段由服务端下发（`userfilter_fun.php act=edit_html`），这里按字段类型原生
/// 渲染、按原名回传，网站加字段/改限额都能跟上；服务端的校验消息原样展示。
class RuleEditorPage extends StatefulWidget {
  final String channel;
  final String title;
  final String id;

  const RuleEditorPage({
    super.key,
    required this.channel,
    required this.title,
    this.id = '',
  });

  @override
  State<RuleEditorPage> createState() => _RuleEditorPageState();
}

class _RuleEditorPageState extends State<RuleEditorPage> {
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
      final form = await _service.loadFilterEditorForm(
        channel: widget.channel,
        id: widget.id,
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
    setState(() => _saving = true);
    try {
      final result = await _service.saveFilterRow(
        channel: widget.channel,
        fields: form.withValues(viewState.values).toFormData(),
      );
      if (!mounted) return;
      setState(() => _saving = false);
      if (result.ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message.isEmpty ? '已保存' : result.message),
          ),
        );
        Navigator.pop(context, true);
        return;
      }
      final message = result.message.isEmpty ? '保存失败' : result.message;
      setState(() => _error = message);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
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
      appBar: AppBar(
        title: Text(
          widget.id.isEmpty ? '新增规则 · ${widget.title}' : '编辑规则 · ${widget.title}',
        ),
        centerTitle: true,
      ),
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
      return LoadErrorView(message: _error ?? '无法加载编辑表单', onRetry: _load);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
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
