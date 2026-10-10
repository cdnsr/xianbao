import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// 用系统浏览器打开一个地址。
///
/// 需要第三方流程的页面（注册、忘记密码、支付、微信/QQ 绑定）交给浏览器，
/// App 内不重做支付与 OAuth。
Future<void> openExternalUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || url.isEmpty) return;
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (e) {
    debugPrint('open external url failed: $e');
  }
}

/// 打开网站用户中心的某个子页（哈希路由，如 `Pay`、`Shezhi_tuisong`）。
Future<void> openUcenterPage(String route) =>
    openExternalUrl('https://new.xianbao.fun/Ucenter#/$route');
