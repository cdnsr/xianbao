import 'dart:io';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/http_client.dart';
import 'cookie_header_codec.dart';

/// Utility for synchronizing cookies between Dio CookieJar and
/// WebView CookieManager, ensuring unified login state.
///
/// The website (Z-BlogPHP) may set cookies on either the exact domain
/// (new.xianbao.fun) or the parent domain (.xianbao.fun). Dio's CookieJar
/// matches cookies by domain, so we must preserve the original domain
/// attribute from WebView cookies to ensure they are sent on subsequent
/// requests to new.xianbao.fun.
class CookieBridge {
  static final WebViewCookieManager _cookieManager = WebViewCookieManager();

  /// Copy cookies from Dio CookieJar into WebView.
  /// Call this before loading any WebView page that needs login state.
  static Future<void> syncToWebView() async {
    final uri = Uri.parse(HttpClient.baseUrl);
    final cookies = await HttpClient().cookieJar.loadForRequest(uri);
    for (final cookie in cookies) {
      await _cookieManager.setCookie(
        WebViewCookie(
          name: cookie.name,
          value: cookie.value,
          domain: cookie.domain ?? uri.host,
          path: cookie.path ?? '/',
        ),
      );
    }
  }

  /// Copy cookies from WebView back into Dio CookieJar.
  /// Call this after login completes in WebView.
  /// This ensures all cookies (including category filter preferences
  /// and login session tokens) are shared with Dio for native HTTP requests.
  static Future<void> syncFromWebView() async {
    final uri = Uri.parse(HttpClient.baseUrl);
    final cookies = await _cookieManager.getCookies(domain: uri);
    if (cookies.isEmpty) {
      // Retry with parent domain in case cookies were set on .xianbao.fun
      final parentUri = Uri.parse('https://xianbao.fun');
      final parentCookies = await _cookieManager.getCookies(domain: parentUri);
      if (parentCookies.isNotEmpty) {
        final cookieList = _toIoCookies(
          parentCookies,
          uri,
          domainOverride: '.xianbao.fun',
        );
        await HttpClient().cookieJar.saveFromResponse(uri, cookieList);
        _setLoginHeaderFromCookies(parentCookies);
      }
      return;
    }
    // Preserve original domain attribute so that CookieJar matches correctly.
    // If the cookie domain is exactly the host, set it as-is.
    // If it's a parent domain (starts with dot), keep the dot prefix.
    final cookieList = _toIoCookies(cookies, uri);
    await HttpClient().cookieJar.saveFromResponse(uri, cookieList);
    _setLoginHeaderFromCookies(cookies);

    // Also try fetching with the bare host (without scheme) to catch
    // any cookies that WebView associates differently.
    try {
      final bareCookies = await _cookieManager.getCookies(
        domain: Uri(host: uri.host),
      );
      if (bareCookies.isNotEmpty) {
        final bareList = _toIoCookies(bareCookies, uri);
        await HttpClient().cookieJar.saveFromResponse(uri, bareList);
        _setLoginHeaderFromCookies(bareCookies);
      }
    } catch (_) {
      // Some WebView implementations don't support host-only URIs
    }
  }

  /// Force a fresh sync of all cookies from WebView.
  /// Clears existing Dio cookies first, then copies all WebView cookies.
  /// Use this after login to ensure clean cookie state.
  static Future<void> fullSyncFromWebView() async {
    final uri = Uri.parse(HttpClient.baseUrl);
    // Delete existing cookies for this domain (including domain-shared)
    await HttpClient().cookieJar.delete(uri, true);
    await syncFromWebView();
  }

  /// Clear the session from both networking stacks after server logout.
  static Future<void> clearAll() async {
    await _cookieManager.clearCookies();
    await HttpClient().cookieJar.deleteAll();
    HttpClient().setLoginCookieHeader(null);
  }

  /// Set the login cookie header from a raw cookie string (e.g. from
  /// document.cookie in WebView). Merges with any existing cookies
  /// from WebViewCookieManager, preserving HttpOnly cookies that
  /// document.cookie cannot access.
  static void setLoginCookieString(String cookieString) {
    final existing = HttpClient().loginCookieHeader ?? '';
    // document.cookie is fresher after login, so new values must win.
    HttpClient().setLoginCookieHeader(
      CookieHeaderCodec.merge(existing, cookieString),
    );
  }

  /// Accepts the platform-specific result returned by evaluateJavascript.
  static void setLoginCookieResult(Object? result) {
    final cookieString = CookieHeaderCodec.decodeJavaScriptResult(result);
    if (cookieString.isNotEmpty) {
      setLoginCookieString(cookieString);
    }
  }

  /// Build a Cookie header string from WebViewCookie list and set it
  /// directly on HttpClient, bypassing CookieJar domain matching.
  static void _setLoginHeaderFromCookies(List<WebViewCookie> cookies) {
    if (cookies.isEmpty) return;
    final pairs = <String, String>{};
    for (final cookie in cookies) {
      if (CookieHeaderCodec.isValidPair(cookie.name, cookie.value)) {
        pairs[cookie.name] = cookie.value;
      }
    }
    final header = pairs.isEmpty ? null : CookieHeaderCodec.build(pairs);
    HttpClient().setLoginCookieHeader(header);
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
