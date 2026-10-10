import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/ucenter_service.dart';
import '../../utils/error_message.dart';
import '../../utils/external_link.dart';

/// 认证绑定：邮箱绑定/解绑（短信式 6 位验证码）与 QQ 绑定入口。
///
/// 网站的接口是两步式（`bangemail_isemail` 发码 → `bangemail_vfcode` 校验；
/// 解绑是 `Jieemail_isemail` → `Jieemail_vfcode`），这里照搬。
class BindingPage extends StatefulWidget {
  const BindingPage({super.key});

  @override
  State<BindingPage> createState() => _BindingPageState();
}

class _BindingPageState extends State<BindingPage> {
  final UcenterService _service = UcenterService();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _code = TextEditingController();

  String _boundEmail = '';
  bool _loading = true;
  bool _busy = false;
  bool _codeSent = false;
  bool _unbinding = false;
  String? _error;

  Timer? _cooldownTimer;
  int _cooldown = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final email = await _service.fetchBoundEmail();
      if (!mounted) return;
      setState(() {
        _boundEmail = email;
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

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _cooldown = 60);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _cooldown -= 1);
      if (_cooldown <= 0) timer.cancel();
    });
  }

  Future<void> _sendCode() async {
    if (_busy || _cooldown > 0) return;
    setState(() => _busy = true);
    try {
      final result = _unbinding
          ? await _service.requestUnbindEmail()
          : await _service.requestBindEmail(_email.text.trim());
      if (!mounted) return;
      setState(() {
        _busy = false;
        _codeSent = result.ok;
      });
      _showMessage(
        result.message.isNotEmpty
            ? result.message
            : (result.ok ? '验证码已发送' : '发送失败'),
      );
      if (result.ok) _startCooldown();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showMessage(friendlyErrorMessage(e));
    }
  }

  Future<void> _submitCode() async {
    if (_busy) return;
    final code = _code.text.trim();
    if (code.length != 6) {
      _showMessage('请输入 6 位验证码');
      return;
    }
    setState(() => _busy = true);
    try {
      final result = _unbinding
          ? await _service.confirmUnbindEmail(code)
          : await _service.confirmBindEmail(code);
      if (!mounted) return;
      setState(() => _busy = false);
      _showMessage(
        result.message.isNotEmpty
            ? result.message
            : (result.ok ? '操作成功' : '操作失败'),
      );
      if (result.ok) {
        setState(() {
          _codeSent = false;
          _unbinding = false;
          _code.clear();
        });
        await _load();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showMessage(friendlyErrorMessage(e));
    }
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
      appBar: AppBar(title: const Text('认证绑定'), centerTitle: true),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        if (_error != null) ...[
          Text(
            _error!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: 12),
        ],
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Row(
            children: [
              Icon(
                Icons.mark_email_read_outlined,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('邮箱绑定', style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 4),
                    Text(
                      _boundEmail.isEmpty ? '未绑定' : _boundEmail,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (!_unbinding)
                TextButton(
                  onPressed: () {
                    setState(() {
                      _unbinding = _boundEmail.isNotEmpty;
                      _codeSent = false;
                      _code.clear();
                    });
                  },
                  child: Text(_boundEmail.isEmpty ? '绑定' : '解绑'),
                ),
            ],
          ),
        ),
        if (_unbinding || _boundEmail.isEmpty) ...[
          const SizedBox(height: 16),
          if (!_unbinding)
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: '邮箱地址',
                prefixIcon: Icon(Icons.alternate_email),
              ),
            ),
          if (!_unbinding) const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    labelText: '6 位验证码',
                    counterText: '',
                    prefixIcon: Icon(Icons.password_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: _busy || _cooldown > 0 ? null : _sendCode,
                child: Text(
                  _cooldown > 0
                      ? '${_cooldown}s'
                      : (_codeSent ? '重新发送' : '获取验证码'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy || !_codeSent ? null : _submitCode,
            child: Text(_unbinding ? '提交解绑' : '提交绑定'),
          ),
          if (_unbinding)
            TextButton(
              onPressed: () =>
                  setState(() => _unbinding = false),
              child: const Text('取消解绑'),
            ),
        ],
        const SizedBox(height: 8),
        const Divider(height: 1),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.chat_bubble_outline, color: theme.colorScheme.primary),
          title: const Text('QQ 绑定'),
          subtitle: const Text('在网站页面完成授权'),
          trailing: const Icon(Icons.open_in_new, size: 18),
          onTap: () => openExternalUrl(
            'https://new.xianbao.fun/zb_users/plugin/mochu_us/cmd.php?act=qqbangding',
          ),
        ),
      ],
    );
  }
}
