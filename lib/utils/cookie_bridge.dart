import 'dart:io';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/http_client.dart';
import 'cookie_header_codec.dart';

/// One-time migration of the session cookies old app versions left behind in
/// the WebView's cookie store.
///
/// Login and the user center used to run inside a WebView; the session lived in
/// the platform cookie store and was copied into Dio on every page load. Both
/// pages are native now, so [HttpClient]'s jar is the only source of truth and
/// it persists itself (see `HttpClient.configureCookieStore`).
///
/// This class therefore only does the upgrade dance: on first launch after the
/// upgrade, copy whatever WebView still holds into the jar so the user is not
/// forced to log in again. Reading the platform store usually works without a
/// WebView widget, but any failure is non-fatal — the user just logs in again.
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

  static List<Cookie> _toIoCookies(
    List<WebViewCookie> cookies,
    Uri requestUri, {
    String? domainOverride,
  }) {
    final result = <Cookie>[];
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
