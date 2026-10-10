import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../services/http_client.dart';
import '../../utils/cookie_bridge.dart';
import '../../utils/error_message.dart';
import '../../utils/external_link.dart';
import '../../widgets/load_error_view.dart';

/// 站内页面的内嵌查看器（不跳浏览器）。
///
/// 用于网站上还没原生化、但用户需要在 App 内看/改的页面：目前是「推送设置」这一套
/// （独立插件 xbpush，渠道/规则/日志）。加载前会把 App 的登录 Cookie 同步进
/// WebView，所以打开就是登录态；右上角仍保留「在浏览器打开」作为兜底。
///
/// 登录与用户中心本身已经是原生页面，这里是唯一还在用 WebView 的地方。
class UcenterViewPage extends StatefulWidget {
  /// 用户中心里的哈希路由，如 `Shezhi_tuisong`。
  final String route;
  final String title;

  const UcenterViewPage({super.key, required this.route, required this.title});

  @override
  State<UcenterViewPage> createState() => _UcenterViewPageState();
}

class _UcenterViewPageState extends State<UcenterViewPage> {
  late final WebViewController _controller;
  late final String _url = '${HttpClient.baseUrl}/Ucenter#/${widget.route}';

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            if (!mounted) return;
            // 只有主文档失败才替换整页，子资源（图片/脚本）失败不管。
            if (error.isForMainFrame != true) return;
            setState(() => _error = friendlyWebViewErrorMessage(error));
          },
        ),
      );

    // 登录态在 Dio 的持久化 jar 里，先同步进 WebView 再加载。
    await CookieBridge.syncToWebView();
    if (!mounted) return;
    await _controller.loadRequest(Uri.parse(_url));
  }

  Future<void> _retry() async {
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      await _controller.loadRequest(Uri.parse(_url));
    } catch (e) {
      debugPrint('ucenter view retry failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'browser') openExternalUrl(_url);
              if (value == 'reload') _retry();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'reload', child: Text('重新加载')),
              PopupMenuItem(value: 'browser', child: Text('在浏览器打开')),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_error == null) WebViewWidget(controller: _controller),
          if (_loading && _error == null)
            const Center(child: CircularProgressIndicator()),
          if (_error != null)
            Positioned.fill(
              child: ColoredBox(
                color: theme.scaffoldBackgroundColor,
                child: LoadErrorView(message: _error!, onRetry: _retry),
              ),
            ),
        ],
      ),
    );
  }
}
