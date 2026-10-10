import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/app_state.dart';
import '../../services/ucenter_service.dart';
import '../../utils/error_message.dart';
import '../../utils/external_link.dart';

/// Native login page (账号密码 + 计算题验证码).
///
/// 网站登录本来是 WebView 里的表单，这里按同样的协议原生实现：验证码图
/// `yanzhengcode.php`，提交到 `cmd.php?act=verify`（密码 MD5 后传）。
/// 注册 / 忘记密码这类带第三方流程的页面仍用系统浏览器打开。
class LoginPage extends StatefulWidget {
  final AppState appState;

  const LoginPage({super.key, required this.appState});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final UcenterService _service = UcenterService();
  final TextEditingController _username = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _vercode = TextEditingController();

  Uint8List? _captcha;
  bool _captchaLoading = true;
  bool _submitting = false;
  bool _keepLoggedIn = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCaptcha();
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _vercode.dispose();
    super.dispose();
  }

  Future<void> _loadCaptcha() async {
    setState(() {
      _captchaLoading = true;
      _captcha = null;
    });
    try {
      final bytes = await _service.fetchCaptcha();
      if (!mounted) return;
      setState(() {
        _captcha = bytes;
        _captchaLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _captchaLoading = false);
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final username = _username.text.trim();
    final password = _password.text;
    final vercode = _vercode.text.trim();

    if (username.isEmpty) {
      setState(() => _error = '用户名不能为空');
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = '密码不能为空');
      return;
    }
    if (vercode.isEmpty) {
      setState(() => _error = '验证码不能为空');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final result = await _service.login(
        username: username,
        password: password,
        vercode: vercode,
        keepLoggedIn: _keepLoggedIn,
      );
      if (!mounted) return;

      if (result.ok) {
        // 新会话：丢掉上一个账号留下的用户中心令牌。
        UcenterService.resetSession();
        // 告诉系统「这次自动填充到此结束」：Bitwarden 这类管理器据此弹出
        // 「保存 / 更新密码」。失败分支不调用，填充上下文保持可用。
        TextInput.finishAutofillContext();
        // 跟服务端核一次会话是否真的生效：Cookie 没落上的话，用户会在别的页面
        // 莫名被判「未登录」，这里直接告诉他重试，而不是假装登录成功。
        final sessionOk = await widget.appState.verifySessionAfterLogin();
        if (!mounted) return;
        if (!sessionOk) {
          setState(() {
            _submitting = false;
            _error = '登录成功但会话未生效，请重试';
          });
          await _loadCaptcha();
          return;
        }
        await widget.appState.onLoginSuccess();
        return;
      }

      setState(() {
        _submitting = false;
        _error = result.message.isEmpty ? '登录失败，请重试' : result.message;
      });
      _password.clear();
      _vercode.clear();
      await _loadCaptcha();

      // code == 2：服务端要求去某个地址继续（如邮箱验证）。
      final redirect = result.redirectUrl;
      if (redirect != null && redirect.isNotEmpty) {
        await openExternalUrl(redirect);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = friendlyErrorMessage(e);
      });
      await _loadCaptcha();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('登录'),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          children: [
            Center(
              child: Image.asset(
                'assets/app_icon.png',
                width: 72,
                height: 72,
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                '线报酷',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                '登录后可同步你的筛选规则与收藏',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 28),
            // AutofillGroup + autofillHints：让系统的自动填充（Bitwarden 等密码
            // 管理器）把这两个框识别成一次登录，提供填充；登录成功后再
            // TextInput.finishAutofillContext() 触发「保存 / 更新密码」。
            AutofillGroup(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _username,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    enableSuggestions: false,
                    autofillHints: const [AutofillHints.username],
                    decoration: const InputDecoration(
                      labelText: '用户名',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.password],
                    decoration: const InputDecoration(
                      labelText: '密码',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _vercode,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(
                      labelText: '验证码',
                      hintText: '计算结果',
                      prefixIcon: Icon(Icons.calculate_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _buildCaptcha(theme),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _keepLoggedIn = !_keepLoggedIn),
                    child: Row(
                      children: [
                        Checkbox(
                          value: _keepLoggedIn,
                          onChanged: (v) =>
                              setState(() => _keepLoggedIn = v ?? false),
                        ),
                        const Text('保持登录'),
                      ],
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      openExternalUrl('https://new.xianbao.fun/Retpass.html'),
                  child: const Text('忘记密码?'),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('登 录'),
            ),
            const SizedBox(height: 16),
            Center(
              child: TextButton(
                onPressed: () =>
                    openExternalUrl('https://new.xianbao.fun/register.html'),
                child: const Text('注册帐号'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCaptcha(ThemeData theme) {
    return InkWell(
      onTap: _loadCaptcha,
      child: Container(
        width: 120,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(4),
          color: theme.colorScheme.surface,
        ),
        child: _captchaLoading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : (_captcha == null || _captcha!.isEmpty)
            ? Text(
                '点击刷新',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              )
            : Image.memory(_captcha!, gaplessPlayback: true),
      ),
    );
  }
}
