import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../services/app_state.dart';
import '../../utils/cookie_bridge.dart';
import '../../utils/webview_dark_theme.dart';
import '../../widgets/update_dialog.dart';

/// User center page using WebView (after login).
class ProfilePage extends StatefulWidget {
  final AppState appState;

  const ProfilePage({super.key, required this.appState});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final WebViewController _controller;
  bool _loaded = false;
  bool _loggingOut = false;
  bool? _lastDark;
  final List<Timer> _themeRetryTimers = <Timer>[];

  static const Color _darkBg = Color(WebViewDarkTheme.darkBgArgb);
  static const Color _lightBg = Color(WebViewDarkTheme.lightBgArgb);

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  @override
  void dispose() {
    _clearThemeRetries();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_loaded && _lastDark != isDark) {
      unawaited(_applyThemeToWebView(isDark, scheduleRetries: true));
    }
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) async {
            if (_loggingOut) {
              await CookieBridge.clearAll();
              widget.appState.onLogout();
              return;
            }
            await CookieBridge.syncFromWebView();
            try {
              final docCookie = await _controller.runJavaScriptReturningResult(
                'document.cookie',
              );
              CookieBridge.setLoginCookieResult(docCookie);
            } catch (_) {}
            if (mounted) {
              final isDark = Theme.of(context).brightness == Brightness.dark;
              await _applyThemeToWebView(isDark, scheduleRetries: true);
            }
          },
          onUrlChange: (change) {
            if (!mounted || _loggingOut) return;
            final isDark = Theme.of(context).brightness == Brightness.dark;
            if (isDark) {
              unawaited(_applyThemeToWebView(true, scheduleRetries: true));
            }
          },
        ),
      );

    CookieBridge.syncToWebView().then((_) async {
      if (!mounted) return;
      final isDark = Theme.of(context).brightness == Brightness.dark;
      await _controller.setBackgroundColor(isDark ? _darkBg : _lightBg);
      _lastDark = isDark;
      // Prefer Ucenter when already logged in so user center content loads directly.
      final url = widget.appState.isLoggedIn
          ? 'https://new.xianbao.fun/Ucenter'
          : 'https://new.xianbao.fun/login.html';
      await _controller.loadRequest(Uri.parse(url));
      setState(() => _loaded = true);
    });
  }

  void _clearThemeRetries() {
    for (final timer in _themeRetryTimers) {
      timer.cancel();
    }
    _themeRetryTimers.clear();
  }

  Future<void> _applyThemeToWebView(
    bool isDark, {
    bool scheduleRetries = false,
  }) async {
    _lastDark = isDark;
    try {
      await _controller.setBackgroundColor(isDark ? _darkBg : _lightBg);
      final result = await _controller.runJavaScriptReturningResult(
        isDark ? WebViewDarkTheme.injectJs : WebViewDarkTheme.removeJs,
      );
      debugPrint('profile theme inject => $result');
    } catch (e) {
      debugPrint('profile theme inject failed: $e');
    }

    if (!scheduleRetries || !isDark) {
      _clearThemeRetries();
      return;
    }

    _clearThemeRetries();
    for (final delayMs in const [300, 800, 1600, 3000, 5000]) {
      _themeRetryTimers.add(
        Timer(Duration(milliseconds: delayMs), () {
          if (!mounted || _lastDark != true) return;
          unawaited(_applyThemeToWebView(true));
        }),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? _darkBg : null,
      appBar: AppBar(
        title: const Text('用户中心'),
        centerTitle: true,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.system_update_alt),
            tooltip: '检查更新',
            onPressed: () => UpdateCoordinator.checkManual(context),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: '退出登录',
            onPressed: _loggingOut
                ? null
                : () {
                    setState(() => _loggingOut = true);
                    _controller.loadRequest(
                      Uri.parse(
                        'https://new.xianbao.fun/zb_users/plugin/mochu_us/cmd.php?act=logout',
                      ),
                    );
                  },
          ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ColoredBox(
              color: isDark ? _darkBg : _lightBg,
              child: WebViewWidget(controller: _controller),
            ),
    );
  }
}
