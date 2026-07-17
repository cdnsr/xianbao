import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'dart:convert';
import 'dart:typed_data';
import '../utils/cookie_header_codec.dart';

/// Singleton Dio instance with cookie management, shared across the app.
class HttpClient {
  static const String baseUrl = 'https://new.xianbao.fun';

  static final HttpClient _instance = HttpClient._internal();
  late final Dio dio;
  late final CookieJar cookieJar;
  String? _loginCookieHeader;

  /// Set the login cookie header string directly. This bypasses
  /// the CookieJar domain-matching logic which can fail on some
  /// Android WebView implementations. Called by CookieBridge after
  /// syncing cookies from WebView.
  void setLoginCookieHeader(String? cookieHeader) {
    _loginCookieHeader = CookieHeaderCodec.normalize(cookieHeader);
  }

  /// Get the current login cookie header (for debugging).
  String? get loginCookieHeader => _loginCookieHeader;

  HttpClient._internal() {
    cookieJar = CookieJar();
    dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        followRedirects: true,
        maxRedirects: 5,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
          'Referer': '$baseUrl/',
          'Accept': 'text/html, application/xhtml+xml, */*',
          'Accept-Encoding': 'identity',
        },
      ),
    );
    // Load CookieJar first. The direct WebView header is applied afterwards,
    // so dio_cookie_manager never reparses JavaScript cookie strings.
    dio.interceptors.add(CookieManager(cookieJar, ignoreInvalidCookies: true));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (_loginCookieHeader != null && _loginCookieHeader!.isNotEmpty) {
            final jarHeader = options.headers['Cookie']?.toString();
            options.headers['Cookie'] = CookieHeaderCodec.merge(
              jarHeader,
              _loginCookieHeader!,
            );
          }
          handler.next(options);
        },
      ),
    );
  }

  factory HttpClient() => _instance;

  /// Decode response bytes to UTF-8 string. Bypasses Dio's response
  /// processing entirely, which avoids issues with chunked transfer
  /// encoding and gzip on certain server configurations.
  String _decodeBytes(List<int> bytes) {
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// Fetch a page as HTML text. page=1 is "/", page>=2 is "/page/{n}/".
  Future<String> fetchHomePage({int page = 1}) async {
    final path = page <= 1 ? '/' : '/page/$page/';
    final resp = await dio.get<Uint8List>(
      path,
      options: Options(responseType: ResponseType.bytes),
    );
    return _decodeBytes(resp.data ?? []);
  }

  /// Fetch JavaScript containing the current user's homepage filter rules.
  Future<String> fetchHomeFilterScript() async {
    final resp = await dio.get<Uint8List>(
      '/zb_users/theme/xianbao_theme/script/meta.php',
      queryParameters: {
        'type': 'index',
        'pagination': '1',
        '_': DateTime.now().millisecondsSinceEpoch,
      },
      options: Options(
        responseType: ResponseType.bytes,
        headers: const {
          'Accept': 'application/javascript, text/javascript, */*',
        },
      ),
    );
    return _decodeBytes(resp.data ?? []);
  }

  /// Fetch a category page.
  Future<String> fetchCategoryPage(String slug, {int page = 1}) async {
    if (page <= 1) {
      final resp = await dio.get<Uint8List>(
        '/category-$slug/',
        options: Options(responseType: ResponseType.bytes),
      );
      return _decodeBytes(resp.data ?? []);
    }
    final resp = await dio.get<Uint8List>(
      '/category-$slug/page/$page/',
      options: Options(responseType: ResponseType.bytes),
    );
    return _decodeBytes(resp.data ?? []);
  }

  /// Search articles. The search endpoint returns a 302 redirect to
  /// /search.php?q={encoded_keyword}. We GET the redirect target directly.
  Future<String> search(String keyword) async {
    final encoded = Uri.encodeQueryComponent(keyword);
    final resp = await dio.get<Uint8List>(
      '/search.php?q=$encoded',
      options: Options(responseType: ResponseType.bytes),
    );
    return _decodeBytes(resp.data ?? []);
  }

  /// Fetch article detail page HTML.
  Future<String> fetchArticle(String path) async {
    final resp = await dio.get<Uint8List>(
      path,
      options: Options(responseType: ResponseType.bytes),
    );
    return _decodeBytes(resp.data ?? []);
  }

  /// Fetch push.json for new articles (real-time refresh).
  Future<String> fetchPushJson() async {
    final resp = await dio.get<Uint8List>(
      '/plus/json/push.json',
      options: Options(responseType: ResponseType.bytes),
    );
    return _decodeBytes(resp.data ?? []);
  }

  /// Fetch category-specific push JSON for real-time refresh on
  /// category pages. The website uses push_{cateId}.json for this.
  Future<String> fetchCategoryPushJson(int cateId) async {
    final resp = await dio.get<Uint8List>(
      '/plus/json/push_$cateId.json',
      options: Options(responseType: ResponseType.bytes),
    );
    return _decodeBytes(resp.data ?? []);
  }

  /// Post a comment. Returns response HTML/JSON.
  Future<String> postComment({
    required int postId,
    required String key,
    required String content,
    int replyId = 0,
  }) async {
    final resp = await dio.post<Uint8List>(
      '/zb_system/cmd.php?act=cmt&postid=$postId&key=$key',
      data: {
        'inpId': postId.toString(),
        'inpRevID': replyId.toString(),
        'txaArticle': content,
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.bytes,
        validateStatus: (s) => s != null && s < 400,
      ),
    );
    return _decodeBytes(resp.data ?? []);
  }

  /// Check login state by fetching /login.html.
  /// If the page contains login form (#LAY-user-login), user is not logged in.
  Future<bool> checkLoginState() async {
    try {
      final resp = await dio.get<Uint8List>(
        '/login.html',
        options: Options(responseType: ResponseType.bytes),
      );
      final html = _decodeBytes(resp.data ?? []);
      return !html.contains('LAY-user-login');
    } catch (_) {
      return false;
    }
  }

  /// In-memory image cache to avoid re-fetching on rebuild/scroll.
  static final Map<String, Uint8List> _imageCache = <String, Uint8List>{};
  static final Map<String, Future<Uint8List>> _inflightImages =
      <String, Future<Uint8List>>{};
  static const int _maxImageCacheEntries = 100;

  /// Download image bytes from an external URL.
  /// Uses referer header matching the website to avoid anti-hotlink blocks.
  /// Includes memory cache, in-flight dedupe, and retries for flaky CDN.
  Future<Uint8List> downloadImage(
    String url, {
    int maxRetries = 3,
    bool forceRefresh = false,
  }) async {
    final key = url.trim();
    if (key.isEmpty) return Uint8List(0);

    if (!forceRefresh) {
      final cached = _imageCache[key];
      if (cached != null && cached.isNotEmpty) return cached;
      final inflight = _inflightImages[key];
      if (inflight != null) return inflight;
    } else {
      _imageCache.remove(key);
      _inflightImages.remove(key);
    }

    final future = _downloadImageWithRetry(key, maxRetries: maxRetries);
    _inflightImages[key] = future;
    try {
      final bytes = await future;
      if (bytes.isNotEmpty) {
        _imageCache[key] = bytes;
        while (_imageCache.length > _maxImageCacheEntries) {
          _imageCache.remove(_imageCache.keys.first);
        }
      }
      return bytes;
    } finally {
      _inflightImages.remove(key);
    }
  }

  Future<Uint8List> _downloadImageWithRetry(
    String url, {
    required int maxRetries,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < maxRetries; attempt++) {
      try {
        final resp = await dio.get<List<int>>(
          url,
          options: Options(
            responseType: ResponseType.bytes,
            receiveTimeout: const Duration(seconds: 20),
            sendTimeout: const Duration(seconds: 15),
            validateStatus: (status) =>
                status != null && status >= 200 && status < 400,
            headers: const {
              'Referer': 'https://new.xianbao.fun/',
              'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
            },
          ),
        );
        final bytes = Uint8List.fromList(resp.data ?? const <int>[]);
        if (bytes.isNotEmpty) return bytes;
        lastError = StateError('empty image body');
      } catch (e) {
        lastError = e;
      }
      if (attempt + 1 < maxRetries) {
        await Future<void>.delayed(Duration(milliseconds: 250 * (attempt + 1)));
      }
    }
    if (lastError != null) {
      // Preserve previous throw behavior for callers that expect failures.
      throw lastError;
    }
    return Uint8List(0);
  }

  /// POST form-urlencoded body and return response text.
  Future<String> postForm(
    String path, {
    Map<String, dynamic>? data,
    Map<String, dynamic>? queryParameters,
  }) async {
    final resp = await dio.post<Uint8List>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.bytes,
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    return _decodeBytes(resp.data ?? []);
  }

  /// GET text response (e.g. update.php messages).
  Future<String> getText(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    final resp = await dio.get<Uint8List>(
      path,
      queryParameters: queryParameters,
      options: Options(responseType: ResponseType.bytes),
    );
    return _decodeBytes(resp.data ?? []);
  }

  /// Toggle article collect via mochu_us addshoucang.
  Future<String> toggleCollect(int articleId) {
    return postForm(
      '/zb_users/plugin/mochu_us/function_user.php',
      queryParameters: const {'act': 'addshoucang'},
      data: {'id': articleId.toString()},
    );
  }

  /// Fetch AJAX-injected collect button HTML state.
  Future<String> fetchArticleCacheButs(int articleId) {
    return postForm(
      '/zb_users/plugin/mochu_us/function_user.php',
      queryParameters: const {'act': 'article_cache'},
      data: {
        'id': articleId.toString(),
        'buts': 'true',
      },
    );
  }

  /// Request server re-fetch of article source.
  Future<String> refetchArticle(int articleId) {
    return getText(
      '/plus/api/update.php',
      queryParameters: {
        'act': 'shoudong',
        'wzid': articleId.toString(),
      },
    );
  }

  /// Read CSRF token from user center shell page.
  Future<String?> fetchUserCenterCsrfToken() async {
    final html = await getText('/Ucenter');
    final match = RegExp(
      r"basecrsfcode:'([^']+)'",
    ).firstMatch(html);
    return match?.group(1);
  }

  /// Fetch collect list page from user center List.php.
  Future<String> fetchCollectListJson({
    required String csrfToken,
    int page = 1,
    int limit = 20,
  }) {
    return postForm(
      '/zb_users/plugin/mochu_us/json/List.php',
      data: {
        'csrfToken': csrfToken,
        'act': 'CollList',
        'page': page.toString(),
        'limit': limit.toString(),
      },
    );
  }

  /// Cancel a collect entry by collect-record id.
  Future<String> deleteCollect({
    required String collectId,
    required String csrfToken,
  }) {
    return postForm(
      '/zb_users/plugin/mochu_us/json/Get.php',
      data: {
        'id': collectId,
        'csrfToken': csrfToken,
        'act': 'CollDel',
      },
    );
  }
}
