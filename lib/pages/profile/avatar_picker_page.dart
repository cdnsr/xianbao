import 'package:flutter/material.dart';

import '../../services/ucenter_service.dart';
import '../../utils/error_message.dart';
import '../../widgets/load_error_view.dart';
import '../../widgets/remote_image.dart';

/// 修改图像：网站给一组预设头像，选一个保存（`Get.php act=UserImgList/UserImgSave`）。
class AvatarPickerPage extends StatefulWidget {
  const AvatarPickerPage({super.key});

  @override
  State<AvatarPickerPage> createState() => _AvatarPickerPageState();
}

class _AvatarPickerPageState extends State<AvatarPickerPage> {
  final UcenterService _service = UcenterService();

  List<UcenterAvatarOption> _options = const [];
  String? _selected;
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
      final options = await _service.fetchAvatarOptions();
      if (!mounted) return;
      setState(() {
        _options = options;
        _selected = options
            .firstWhere(
              (o) => o.selected,
              orElse: () => const UcenterAvatarOption(url: ''),
            )
            .url;
        if (_selected!.isEmpty && options.isNotEmpty) {
          _selected = options.first.url;
        }
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
    final url = _selected;
    if (url == null || url.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      final result = await _service.saveAvatar(url);
      if (!mounted) return;
      setState(() => _saving = false);
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result.message.isEmpty
                ? (result.ok ? '头像已更新' : '头像更新失败')
                : result.message,
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
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('修改图像'), centerTitle: true),
      body: _buildBody(theme),
      bottomNavigationBar: _options.isEmpty
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
    if (_error != null) {
      return LoadErrorView(message: _error!, onRetry: _load);
    }
    if (_options.isEmpty) {
      return Center(
        child: Text(
          '暂无可选头像',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      itemCount: _options.length,
      itemBuilder: (context, index) {
        final option = _options[index];
        final selected = option.url == _selected;
        return InkWell(
          onTap: () => setState(() => _selected = option.url),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
                width: selected ? 2 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: RemoteImage(
              url: option.url,
              width: 64,
              height: 64,
              fit: BoxFit.cover,
              placeholder: const SizedBox.shrink(),
            ),
          ),
        );
      },
    );
  }
}
