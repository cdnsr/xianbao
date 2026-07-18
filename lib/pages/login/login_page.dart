import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../services/app_state.dart';
import '../../utils/cookie_bridge.dart';
import '../../utils/webview_dark_theme.dart';
import '../../widgets/update_dialog.dart';

/// Login page using WebView, as login requires captcha and JS.
/// After successful login, syncs cookies back to Dio.
class LoginPage extends StatefulWidget {
  final AppState appState;

  const LoginPage({super.key, required this.appState});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late final WebViewController _controller;
  bool _loaded = false;
  bool _loginHandled = false;
  bool? _lastDark;
  final List<Timer> _themeRetryTimers = <Timer>[];
  final List<Timer> _uiTweakRetryTimers = <Timer>[];

  static const Color _darkBg = Color(WebViewDarkTheme.darkBgArgb);
  static const Color _lightBg = Color(WebViewDarkTheme.lightBgArgb);

  /// Login-page-only UI tweaks (ES5 for Android WebView):
  /// 1) default-check "保持登录" (first ~5s only, respects later user uncheck)
  /// 2) hide "返回首页" (app already has bottom nav home)
  static const String _loginUiTweakJs = r'''
(function(){
  try {
    var STYLE_ID = 'xianbao-login-ui-tweak';
    var css = ''
      + '.layui-login-returnindex{display:none !important;visibility:hidden !important;'
      + 'height:0 !important;max-height:0 !important;overflow:hidden !important;'
      + 'margin:0 !important;padding:0 !important;border:0 !important;}'
      + '.layui-login-returnindex a{display:none !important;}';

    function injectStyle() {
      var parent = document.head || document.documentElement;
      var s = document.getElementById(STYLE_ID);
      if (!s) {
        s = document.createElement('style');
        s.id = STYLE_ID;
        s.type = 'text/css';
        parent.appendChild(s);
      }
      if (s.styleSheet) { s.styleSheet.cssText = css; } else { s.innerHTML = css; }
    }

    function hideReturnHome() {
      injectStyle();
      var nodes = document.querySelectorAll('.layui-login-returnindex');
      for (var i = 0; i < nodes.length; i++) {
        try {
          nodes[i].style.setProperty('display', 'none', 'important');
          nodes[i].setAttribute('hidden', 'hidden');
        } catch (e) {}
      }
      var links = document.querySelectorAll('a');
      for (var j = 0; j < links.length; j++) {
        var t = (links[j].textContent || '').replace(/\s+/g, '');
        if (t === '返回首页') {
          var wrap = links[j].closest
            ? links[j].closest('.layui-login-returnindex')
            : null;
          var el = wrap || links[j];
          try {
            el.style.setProperty('display', 'none', 'important');
            el.setAttribute('hidden', 'hidden');
          } catch (e2) {}
        }
      }
    }

    function bindUserTouch(cb) {
      if (window.__xianbaoKeepLoginListen || !cb) return;
      window.__xianbaoKeepLoginListen = true;
      var markTouched = function () {
        window.__xianbaoKeepLoginUserTouched = true;
      };
      try { cb.addEventListener('change', markTouched); } catch (e) {}
      try { cb.addEventListener('click', markTouched); } catch (e2) {}
      var box = cb.nextElementSibling;
      if (box && box.classList && box.classList.contains('layui-form-checkbox')) {
        try { box.addEventListener('click', markTouched); } catch (e3) {}
      }
      if (cb.parentNode) {
        var boxes = cb.parentNode.querySelectorAll('.layui-form-checkbox');
        for (var i = 0; i < boxes.length; i++) {
          try { boxes[i].addEventListener('click', markTouched); } catch (e4) {}
        }
      }
    }

    function markKeepLoginChecked() {
      // Stop forcing after user toggles, or after settle window.
      if (window.__xianbaoKeepLoginUserTouched) return true;
      if (!window.__xianbaoKeepLoginStart) {
        window.__xianbaoKeepLoginStart = Date.now();
      }
      var elapsed = Date.now() - window.__xianbaoKeepLoginStart;
      // After 6s stop re-forcing so user uncheck sticks permanently.
      if (elapsed > 6000 && window.__xianbaoKeepLoginDefaulted) return true;

      var cb = document.querySelector('input[lay-filter="Baochi"]')
        || document.querySelector('#LAY-user-login input[type="checkbox"]')
        || document.querySelector('input[title="保持登录"]');
      if (!cb) return false;

      bindUserTouch(cb);

      if (!cb.checked) {
        cb.checked = true;
        try { cb.setAttribute('checked', 'checked'); } catch (e) {}
        try { cb.defaultChecked = true; } catch (e2) {}
      }

      var box = cb.nextElementSibling;
      if (box && box.classList && box.classList.contains('layui-form-checkbox')) {
        if (!box.classList.contains('layui-form-checked')) {
          box.classList.add('layui-form-checked');
        }
      } else if (cb.parentNode) {
        var boxes = cb.parentNode.querySelectorAll('.layui-form-checkbox');
        for (var i = 0; i < boxes.length; i++) {
          if (!boxes[i].classList.contains('layui-form-checked')) {
            boxes[i].classList.add('layui-form-checked');
          }
        }
      }

      try {
        if (window.layui && layui.form) {
          layui.form.render('checkbox');
          var cb2 = document.querySelector('input[lay-filter="Baochi"]')
            || document.querySelector('#LAY-user-login input[type="checkbox"]');
          if (cb2) {
            bindUserTouch(cb2);
            cb2.checked = true;
            try { cb2.setAttribute('checked', 'checked'); } catch (e3) {}
            var box2 = cb2.nextElementSibling;
            if (box2 && box2.classList && box2.classList.contains('layui-form-checkbox')) {
              box2.classList.add('layui-form-checked');
            }
          }
        }
      } catch (e4) {}

      // Site login uses global `date` as savedate (days). Keep-login => 30.
      try { window.date = 30; } catch (e5) {
        try { date = 30; } catch (e6) {}
      }

      window.__xianbaoKeepLoginDefaulted = true;
      return true;
    }

    hideReturnHome();
    markKeepLoginChecked();

    if (!window.__xianbaoLoginUiObs) {
      var t = null;
      window.__xianbaoLoginUiObs = new MutationObserver(function () {
        if (t) return;
        t = setTimeout(function () {
          t = null;
          hideReturnHome();
          markKeepLoginChecked();
        }, 150);
      });
      try {
        window.__xianbaoLoginUiObs.observe(document.documentElement, {
          childList: true,
          subtree: true
        });
      } catch (e7) {}
    }

    if (!window.__xianbaoLoginUiKeepAlive) {
      window.__xianbaoLoginUiKeepAlive = setInterval(function () {
        hideReturnHome();
        markKeepLoginChecked();
        // Stop interval after settle if default applied (hide still done via style).
        if (window.__xianbaoKeepLoginDefaulted
            && window.__xianbaoKeepLoginStart
            && (Date.now() - window.__xianbaoKeepLoginStart > 8000)) {
          clearInterval(window.__xianbaoLoginUiKeepAlive);
          window.__xianbaoLoginUiKeepAlive = null;
        }
      }, 1200);
    }

    return 'login-ui-ok';
  } catch (err) {
    return 'login-ui-err:' + (err && err.message ? err.message : err);
  }
})();
''';

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  @override
  void dispose() {
    _clearThemeRetries();
    _clearUiTweakRetries();
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
          onPageFinished: (url) async {
            // After any page load, sync cookies from WebView to Dio
            // and check login state.
            await CookieBridge.syncFromWebView();

            if (mounted) {
              final isDark = Theme.of(context).brightness == Brightness.dark;
              await _applyThemeToWebView(isDark, scheduleRetries: true);
              await _applyLoginUiTweaks(scheduleRetries: true);
            }

            final loggedIn = await _controller
                .runJavaScriptReturningResult(
                  '!!document.querySelector("#LAY-user-login") == false',
                )
                .then((r) => r.toString() == 'true')
                .catchError((_) => false);
            if (loggedIn && !_loginHandled) {
              _loginHandled = true;
              // Full sync ensures all cookies including category
              // filter preferences (COWL) are shared with Dio.
              await CookieBridge.fullSyncFromWebView();
              // Also capture cookies via document.cookie to supplement
              // any cookies that WebViewCookieManager might miss.
              try {
                final docCookie = await _controller
                    .runJavaScriptReturningResult('document.cookie');
                CookieBridge.setLoginCookieResult(docCookie);
              } catch (_) {}
              await widget.appState.onLoginSuccess();
            }
          },
          onUrlChange: (change) {
            if (!mounted || _loginHandled) return;
            final isDark = Theme.of(context).brightness == Brightness.dark;
            if (isDark) {
              unawaited(_applyThemeToWebView(true, scheduleRetries: true));
            }
            unawaited(_applyLoginUiTweaks(scheduleRetries: true));
          },
        ),
      );

    // Sync Dio cookies to WebView before loading.
    CookieBridge.syncToWebView().then((_) async {
      if (!mounted) return;
      final isDark = Theme.of(context).brightness == Brightness.dark;
      await _controller.setBackgroundColor(isDark ? _darkBg : _lightBg);
      _lastDark = isDark;
      await _controller.loadRequest(
        Uri.parse('https://new.xianbao.fun/login.html'),
      );
      setState(() => _loaded = true);
    });
  }

  void _clearThemeRetries() {
    for (final timer in _themeRetryTimers) {
      timer.cancel();
    }
    _themeRetryTimers.clear();
  }

  void _clearUiTweakRetries() {
    for (final timer in _uiTweakRetryTimers) {
      timer.cancel();
    }
    _uiTweakRetryTimers.clear();
  }

  Future<void> _applyThemeToWebView(
    bool isDark, {
    bool scheduleRetries = false,
  }) async {
    _lastDark = isDark;
    try {
      await _controller.setBackgroundColor(isDark ? _darkBg : _lightBg);
      await _controller.runJavaScriptReturningResult(
        isDark ? WebViewDarkTheme.injectJs : WebViewDarkTheme.removeJs,
      );
    } catch (_) {
      // Page may be mid-navigation; retries will re-apply.
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

  Future<void> _applyLoginUiTweaks({bool scheduleRetries = false}) async {
    try {
      await _controller.runJavaScriptReturningResult(_loginUiTweakJs);
    } catch (_) {
      // Page may be mid-navigation; retries will re-apply.
    }

    if (!scheduleRetries) {
      _clearUiTweakRetries();
      return;
    }

    _clearUiTweakRetries();
    // Layui form.render runs after page scripts; retry to catch late checkbox DOM.
    for (final delayMs in const [200, 500, 1000, 2000, 4000]) {
      _uiTweakRetryTimers.add(
        Timer(Duration(milliseconds: delayMs), () {
          if (!mounted || _loginHandled) return;
          unawaited(_applyLoginUiTweaks());
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
        title: const Text('登录'),
        centerTitle: true,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.system_update_alt),
            tooltip: '检查更新',
            onPressed: () => UpdateCoordinator.checkManual(context),
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
