import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

import 'http_client.dart';

/// Turns a plain JD product URL into the user's **own** JD Union (京东联盟)
/// promotion link, so orders placed from the app earn that account's
/// commission instead of the original poster's.
///
/// This is opt-in and off by default: with no service configured the app
/// behaves exactly as before. Signing a union link needs `appKey`/`appSecret`,
/// which must never ship inside an APK (decompiling would leak them), so the
/// conversion happens on a small server the user runs - see
/// `server/jd-union/`.
class UnionLinkService {
  UnionLinkService._();

  static final UnionLinkService instance = UnionLinkService._();

  static const String _urlKey = 'union_service_url_v1';
  static const String _tokenKey = 'union_service_token_v1';

  String _serviceUrl = '';
  String _token = '';

  /// Only link conversion results are cached, keyed by product URL.
  final Map<String, String?> _cache = <String, String?>{};

  bool get isConfigured => _serviceUrl.isNotEmpty;

  String get serviceUrl => _serviceUrl;

  String get token => _token;

  /// Reads the saved settings. Never throws.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _serviceUrl = (prefs.getString(_urlKey) ?? '').trim();
      _token = (prefs.getString(_tokenKey) ?? '').trim();
    } catch (_) {
      _serviceUrl = '';
      _token = '';
    }
  }

  Future<void> save({required String serviceUrl, required String token}) async {
    _serviceUrl = serviceUrl.trim();
    _token = token.trim();
    // Endpoint or credentials changed, so any earlier result is meaningless.
    _cache.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_urlKey, _serviceUrl);
      await prefs.setString(_tokenKey, _token);
    } catch (_) {
      // Persisting preferences must never break the UI.
    }
  }

  /// Returns the user's promotion link for [productUrl], or null when the
  /// service is not configured or did not answer with one. Callers fall back
  /// to the plain product URL, so a broken service never loses the link.
  Future<String?> promotionUrlFor(String productUrl) async {
    if (!isConfigured || productUrl.isEmpty) return null;

    if (_cache.containsKey(productUrl)) return _cache[productUrl];

    String? result;
    try {
      final response = await HttpClient().dio.get<dynamic>(
        _serviceUrl,
        queryParameters: {
          'url': productUrl,
          if (_token.isNotEmpty) 'token': _token,
        },
        options: Options(
          responseType: ResponseType.plain,
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 10),
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      result = promotionUrlFrom(response.data);
    } catch (_) {
      result = null;
    }

    // Do not cache failures: a link may convert once the network is back.
    if (result != null) _cache[productUrl] = result;
    return result;
  }

  @visibleForTesting
  static String? promotionUrlFrom(Object? body) {
    if (body is! String || body.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final url = decoded['url']?.toString().trim() ?? '';
        if (url.startsWith('http')) return url;
      }
    } catch (_) {
      // Not JSON - treat as unusable rather than guessing.
    }
    return null;
  }
}
