import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/ucenter_service.dart';
import '../../utils/error_message.dart';
import '../../widgets/text_tip.dart';

/// 重置密码（`Get.php act=newpassword`）。
class PasswordPage extends StatefulWidget {
  const PasswordPage({super.key});

  @override
  State<PasswordPage> createState() => _PasswordPageState();
}

class _PasswordPageState extends State<PasswordPage> {
  final UcenterService _service = UcenterService();
  final TextEditingController _old = TextEditingController();
  final TextEditingController _new = TextEditingController();
  final TextEditingController _confirm = TextEditingController();

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _old.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    final oldPassword = _old.text;
    final newPassword = _new.text;
    final confirm = _confirm.text;

    if (oldPassword.isEmpty) {
      setState(() => _error = '请输入原有密码');
      return;
    }
    if (newPassword.isEmpty) {
      setState(() => _error = '请输入新密码');
      return;
    }
    if (newPassword != confirm) {
      setState(() => _error = '两次输入的新密码不一致');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await _service.changePassword(
        oldPassword: oldPassword,
        newPassword: newPassword,
        confirmPassword: confirm,
      );
      if (!mounted) return;
      setState(() => _saving = false);
      if (result.ok) {
        // 改密成功：让密码管理器（Bitwarden 等）提示更新保存的密码。
        TextInput.finishAutofillContext();
        showTextTip(
          context,
          result.message.isEmpty ? '密码已修改' : result.message,
        );
        Navigator.pop(context, true);
        return;
      }
      setState(() {
        _error = result.message.isEmpty ? '修改失败' : result.message;
      });
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
      appBar: AppBar(title: const Text('重置密码'), centerTitle: true),
      // AutofillGroup + 提示：密码管理器可以填充原密码，并在改密成功后提示更新。
      body: AutofillGroup(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            TextField(
              controller: _old,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              decoration: const InputDecoration(
                labelText: '原有密码',
                prefixIcon: Icon(Icons.lock_outline),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _new,
            obscureText: true,
            autofillHints: const [AutofillHints.newPassword],
            decoration: const InputDecoration(
              labelText: '新密码',
              prefixIcon: Icon(Icons.lock_reset_outlined),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _confirm,
            obscureText: true,
            autofillHints: const [AutofillHints.newPassword],
            decoration: const InputDecoration(
              labelText: '确认新密码',
              prefixIcon: Icon(Icons.check_circle_outline),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('确认修改'),
          ),
        ],
        ),
      ),
    );
  }
}
