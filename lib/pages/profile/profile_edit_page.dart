import 'package:flutter/material.dart';

import '../../services/ucenter_service.dart';
import '../../utils/error_message.dart';
import '../../widgets/load_error_view.dart';

/// 基本资料（`views/Data.php` 表单 + `Get.php act=postdata`）。
///
/// 字段与标签取自网站表单：个人昵称 `Alias`、个人性别 `Sex`（0 保密 / 1 男 / 2 女）、
/// 出生日期 `Both`、联系QQ `QQnber`、个人网址 `HomePage`、个人介绍 `Intro`；
/// 登录账号是只读展示。
class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({super.key});

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  static const List<String> _fields = [
    'Alias',
    'Sex',
    'Both',
    'QQnber',
    'HomePage',
    'Intro',
  ];

  final UcenterService _service = UcenterService();
  final TextEditingController _alias = TextEditingController();
  final TextEditingController _birthday = TextEditingController();
  final TextEditingController _qq = TextEditingController();
  final TextEditingController _homepage = TextEditingController();
  final TextEditingController _intro = TextEditingController();
  String _sex = '0';

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _alias.dispose();
    _birthday.dispose();
    _qq.dispose();
    _homepage.dispose();
    _intro.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await _service.fetchSettingsValues(
        view: 'Data',
        names: _fields,
      );
      if (!mounted) return;
      setState(() {
        _alias.text = values['Alias'] ?? '';
        _birthday.text = values['Both'] ?? '';
        _qq.text = values['QQnber'] ?? '';
        _homepage.text = values['HomePage'] ?? '';
        _intro.text = values['Intro'] ?? '';
        _sex = values['Sex']?.isNotEmpty == true ? values['Sex']! : '0';
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
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final result = await _service.saveProfile({
        'Alias': _alias.text.trim(),
        'Sex': _sex,
        'Both': _birthday.text.trim(),
        'QQnber': _qq.text.trim(),
        'HomePage': _homepage.text.trim(),
        'Intro': _intro.text.trim(),
      });
      if (!mounted) return;
      setState(() => _saving = false);
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result.message.isNotEmpty
                ? result.message
                : (result.ok ? '资料已保存' : '保存失败'),
          ),
        ),
      );
      if (result.ok) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('基本资料'), centerTitle: true),
      body: _buildBody(context),
      bottomNavigationBar: _loading || _error != null
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

  Widget _buildBody(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return LoadErrorView(message: _error!, onRetry: _load);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        TextField(
          controller: _alias,
          decoration: const InputDecoration(
            labelText: '个人昵称',
            prefixIcon: Icon(Icons.badge_outlined),
          ),
        ),
        const SizedBox(height: 16),
        Text('个人性别', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: '0', label: Text('保密')),
            ButtonSegment(value: '1', label: Text('男')),
            ButtonSegment(value: '2', label: Text('女')),
          ],
          selected: {_sex},
          onSelectionChanged: (selection) =>
              setState(() => _sex = selection.first),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _birthday,
          decoration: const InputDecoration(
            labelText: '出生日期',
            hintText: '如 1995-01-01',
            prefixIcon: Icon(Icons.cake_outlined),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _qq,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '联系QQ',
            prefixIcon: Icon(Icons.chat_outlined),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _homepage,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: '个人网址',
            prefixIcon: Icon(Icons.link),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _intro,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: '个人介绍',
            alignLabelWithHint: true,
          ),
        ),
      ],
    );
  }
}
