import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/http_client.dart';
import 'cookie_header_codec.dart';

/// 桥接 Dio 的 Cookie 与 WebView 的 Cookie 存储。
///
/// 登录与用户中心已经是原生页面，会话由 [HttpClient] 的持久化 jar 承载
/// （见 `HttpClient.configureCookieStore`），这个类现在只剩两件事：
///
///  - [migrateFromWebView]：升级后首次启动时，把老版本留在 WebView 里的登录
///    Cookie 搬进 jar，用户不用重新登录（读平台存储一般不需要 WebView 实例，
///    失败也不影响使用）；
///  - [syncToWebView]：App 内的页面查看器（[UcenterViewPage]，目前用于推送设置）
///    加载网站页面之前，把 jar 里的 Cookie 写进 WebView，否则会以未登录打开。
class CookieBridge {
  static final WebViewCookieManager _cookieManager = WebViewCookieManager();

  /// Copies WebView cookies for the site into the Dio jar. Returns how many
  /// cookies were migrated (0 when the store was empty or unreadable).
  static Future<int> migrateFromWebView() async {
    final uri = Uri.parse(HttpClient.baseUrl);
    try {
      final cookies = await _cookieManager.getCookies(domain: uri);
      if (cookies.isNotEmpty) {
        await HttpClient().cookieJar.saveFromResponse(
          uri,
          _toIoCookies(cookies, uri),
        );
        return cookies.length;
      }

      // Cookies may live on the parent domain (.xianbao.fun) instead.
      final parentUri = Uri.parse('https://xianbao.fun');
      final parentCookies = await _cookieManager.getCookies(domain: parentUri);
      if (parentCookies.isNotEmpty) {
        await HttpClient().cookieJar.saveFromResponse(
          uri,
          _toIoCookies(parentCookies, uri, domainOverride: '.xianbao.fun'),
        );
        return parentCookies.length;
      }
    } catch (_) {
      // No platform cookie store (or no permission) — nothing to migrate.
    }
    return 0;
  }

  /// Copies the app's current cookies into the WebView cookie store.
  ///
  /// Only used by the in-app viewer for pages that are still the website's own
  /// (推送设置 lives in the separate xbpush plugin). The session lives in Dio's
  /// jar now, so a WebView would otherwise load logged-out.
  static Future<int> syncToWebView() async {
    try {
      final uri = Uri.parse(HttpClient.baseUrl);
      final cookies = await HttpClient().cookieJar.loadForRequest(uri);
      for (final cookie in cookies) {
        if (!CookieHeaderCodec.isValidPair(cookie.name, cookie.value)) continue;
        await _cookieManager.setCookie(
          WebViewCookie(
            name: cookie.name,
            value: cookie.value,
            domain: cookie.domain ?? uri.host,
            path: cookie.path ?? '/',
          ),
        );
      }
      return cookies.length;
    } catch (e) {
      debugPrint('CookieBridge.syncToWebView failed: $e');
      return 0;
    }
  }

  static List<Cookie> _toIoCookies(
    List<WebViewCookie> cookies,
    Uri requestUri, {
    String? domainOverride,
  }) {    final result = <Cookie>[];
    for (final source in cookies) {
      if (!CookieHeaderCodec.isValidPair(source.name, source.value)) continue;
      final cookie = Cookie(source.name, source.value)
        ..domain = domainOverride ?? _normalizeDomain(source.domain, requestUri)
        ..path = source.path.isEmpty ? '/' : source.path;
      result.add(cookie);
    }
    return result;
  }

  static String _normalizeDomain(String domain, Uri requestUri) {
    final value = domain.trim();
    if (value.isEmpty) return requestUri.host;

    final parsed = Uri.tryParse(value);
    if (parsed != null && parsed.host.isNotEmpty) return parsed.host;
    return value;
  }
}
