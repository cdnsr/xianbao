import 'package:flutter/material.dart';

import '../../models/ucenter_form.dart';
import '../../services/ucenter_service.dart';
import '../../utils/error_message.dart';
import '../../widgets/load_error_view.dart';
import '../../widgets/ucenter_form_view.dart';

/// 一个基本设置页的描述：视图片段、保存用的 `type`、展示文案。
class UcenterSettingsSpec {
  /// `views/<view>.php`。
  final String view;

  /// `shezhi_fun.php?type=<type>`。
  final String type;

  final String title;
  final String hint;

  const UcenterSettingsSpec({
    required this.view,
    required this.type,
    required this.title,
    this.hint = '',
  });
}

/// 基本设置六页（浏览 / 实时线报 / 顶部导航 / 摸鱼 / 自定义 CSS / 自定义 JS）。
///
/// 表单字段与当前值都来自对应的服务端视图片段，保存走
/// `shezhi_fun.php?type=<type>`；非会员被服务端禁用的字段按只读展示。
const Map<String, UcenterSettingsSpec> ucenterSettingsSpecs = {
  'jiben': UcenterSettingsSpec(
    view: 'Shezhi_jiben',
    type: 'jiben_liulan',
    title: '优化浏览设置',
    hint: '标题标红、分页方式、新标签页行为。',
  ),
  'shishi': UcenterSettingsSpec(
    view: 'Shezhi_shishi',
    type: 'shishi',
    title: '实时线报设置',
    hint: '列表自动刷新的请求开关与间隔（单位秒，3-3600）。',
  ),
  'daohang': UcenterSettingsSpec(
    view: 'Shezhi_daohang',
    type: 'jiben_daohang',
    title: '顶部导航设置',
    hint: '系统默认 / 自定义 / 关闭，电脑端与手机端可分别设置。',
  ),
  'moyu': UcenterSettingsSpec(
    view: 'Shezhi_moyu',
    type: 'jiben_moyu',
    title: '优化摸鱼设置',
    hint: '伪装标题、图标与轮换间隔，生效设备可分别选择。',
  ),
  'css': UcenterSettingsSpec(
    view: 'Shezhi_css',
    type: 'jiben_css',
    title: '自定义 CSS 样式',
    hint: '只对你自己的浏览器生效。',
  ),
  'js': UcenterSettingsSpec(
    view: 'Shezhi_js',
    type: 'jiben_js',
    title: '自定义 JS 脚本',
    hint: '只对你自己的浏览器生效，请谨慎填写。',
  ),
};

/// 基本设置表单页。
class SettingsFormPage extends StatefulWidget {
  final UcenterSettingsSpec spec;

  const SettingsFormPage({super.key, required this.spec});

  @override
  State<SettingsFormPage> createState() => _SettingsFormPageState();
}

class _SettingsFormPageState extends State<SettingsFormPage> {
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
      final form = await _service.fetchSettingsForm(widget.spec.view);
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
      final result = await _service.saveSettings(
        type: widget.spec.type,
        fields: form.withValues(viewState.values).toFormData(),
      );
      if (!mounted) return;
      setState(() => _saving = false);
      final message = result.message.isNotEmpty
          ? result.message
          : (result.ok ? '已保存' : '保存失败');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      if (!result.ok) setState(() => _error = message);
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
      appBar: AppBar(title: Text(widget.spec.title), centerTitle: true),
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
    if (form.visibleFields.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '这一页当前没有可修改的项（可能是会员功能，或网站改版了字段）。',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        if (widget.spec.hint.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              widget.spec.hint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
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
