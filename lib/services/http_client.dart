import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'dart:convert';
import 'dart:typed_data';

/// Path of a category page for a given page number.
///
/// The site moved category pagination from `/category-{slug}/page/{n}/` to
/// `/category-{slug}/{n}/`; the old form now silently serves page 1 (making the
/// list repeat itself) or nothing at all on channel pages.
String categoryPagePath(String slug, int page) =>
    page <= 1 ? '/category-$slug/' : '/category-$slug/$page/';

/// Directory of the user center plugin's server-rendered view fragments.
const String _ucenterViewBase =
    '/zb_users/plugin/mochu_us/src/views/';

/// JSON controllers of the same plugin (paged tables, form writes).
const String _ucenterJsonBase = '/zb_users/plugin/mochu_us/json/';

/// Singleton Dio instance with cookie management, shared across the app.
///
/// Login is native now (email/password + captcha through the site's own
/// `cmd.php?act=verify`), so the cookie jar is the single source of truth for
/// the session and has to survive restarts — [configureCookieStore] swaps the
/// in-memory jar for a file-backed one at startup.
class HttpClient {
  static const String baseUrl = 'https://new.xianbao.fun';

  static final HttpClient _instance = HttpClient._internal();
  late final Dio dio;

  CookieJar? _jar;
  bool _persistentStore = false;

  /// The active cookie jar.
  ///
  /// Falls back to an in-memory jar when [configureCookieStore] was never called
  /// (desktop runs, tests, or path_provider failing) — the [CookieManager]
  /// interceptor is installed together with whichever jar wins, so requests are
  /// never sent without cookies.
  CookieJar get cookieJar {
    final existing = _jar;
    if (existing != null) return existing;
    return _installJar(CookieJar(), persistent: false);
  }

  /// True once cookies are backed by a file and survive app restarts.
  bool get hasPersistentStore => _persistentStore;

  CookieJar _installJar(CookieJar jar, {required bool persistent}) {
    _jar = jar;
    _persistentStore = persistent;
    dio.interceptors.add(CookieManager(jar, ignoreInvalidCookies: true));
    return jar;
  }

  HttpClient._internal() {
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
          // No explicit `Accept-Encoding`: `dart:io` then negotiates gzip and
          // transparently inflates the body. Forcing `identity` (as this used to
          // do) meant every list page came down as ~220KB of HTML instead of
          // ~42KB, which is most of why loading articles felt slow.
        },
      ),
    );
  }

  factory HttpClient() => _instance;

  /// Point the cookie jar at [directory] so the session survives restarts.
  ///
  /// Must run before the first request that needs the session; `main()` awaits
  /// it. Cookies are stored as files by `PersistCookieJar`; if an in-memory jar
  /// was already installed (nothing in `main()` should touch the client first),
  /// the persistent store is skipped rather than silently replaced mid-flight.
  Future<void> configureCookieStore(String directory) async {
    if (_jar != null) {
      if (!_persistentStore) {
        debugPrint(
          'HttpClient: cookie jar already in use, keeping in-memory store',
        );
      }
      return;
    }
    final persistent = PersistCookieJar(
      storage: FileStorage(directory),
      persistSession: true,
    );
    await persistent.forceInit();
    _installJar(persistent, persistent: true);
  }

  /// Drop every stored cookie (logout / session expired).
  Future<void> clearCookies() async {
    await cookieJar.deleteAll();
  }

  /// Decode response bytes to UTF-8 string.
  ///
  /// Requests ask for `ResponseType.bytes` so the body reaches us exactly as
  /// `dart:io` handed it over (already gunzipped when the server compressed it)
  /// instead of going through Dio's string transformer.
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

  /// Fetch the theme's meta script by path (page HTML carries the exact URL).
  ///
  /// It holds the page's whole filter configuration (global filter, page rules,
  /// recall conditions, channel guard) plus the worker / push config the website
  /// uses to refresh that page (`postjson.url`). The response is `no-store` and
  /// account-scoped, and it *does* vary with the query string, so callers pass
  /// the very path the page's `<script src>` uses.
  Future<String> fetchMetaScript(String path) async {
    final resp = await dio.get<Uint8List>(
      path,
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
    final resp = await dio.get<Uint8List>(
      categoryPagePath(slug, page),
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

  /// Fetch the site-wide push feed for new articles (real-time refresh).
  Future<String> fetchPushJson() => fetchPushFeed('/plus/json/push.json');

  /// Fetch a push feed by its path, e.g. `/plus/json/push_30.json`.
  /// Paths come from a category's meta script so we poll exactly the feed the
  /// website itself polls.
  Future<String> fetchPushFeed(String path) async {
    final resp = await dio.get<Uint8List>(
      path,
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
  ///
  /// Returns null when the answer is unknown (network error, timeout): with a
  /// file-backed cookie jar, treating "offline" as "logged out" would silently
  /// drop a valid session, so callers must only act on a definite false.
  Future<bool?> checkLoginState() async {
    try {
      final resp = await dio.get<Uint8List>(
        '/login.html',
        options: Options(responseType: ResponseType.bytes),
      );
      final html = _decodeBytes(resp.data ?? []);
      return !html.contains('LAY-user-login');
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------- 用户中心

  /// Fetch the captcha image bytes for the native login form.
  ///
  /// The site renders an arithmetic question; the answer goes back as `vercode`
  /// on login. `r` busts the server-side cache, exactly like the page does.
  Future<Uint8List> fetchCaptcha() async {
    final resp = await dio.get<List<int>>(
      '/zb_users/plugin/mochu_us/function/yanzhengcode.php',
      queryParameters: {'r': DateTime.now().millisecondsSinceEpoch},
      options: Options(
        responseType: ResponseType.bytes,
        headers: const {'Accept': 'image/*,*/*;q=0.8'},
      ),
    );
    return Uint8List.fromList(resp.data ?? const <int>[]);
  }

  /// Native login (`cmd.php?act=verify`), returns the raw JSON body.
  ///
  /// Redirects are **not** followed: the site answers a successful login with a
  /// 302, and `CookieManager` only stores `Set-Cookie` from 3xx responses when
  /// the request does not follow them — following the redirect throws the
  /// session cookies away.
  Future<String> login({
    required String username,
    required String passwordMd5,
    required String vercode,
    required int savedate,
  }) async {
    final resp = await dio.post<Uint8List>(
      '/zb_users/plugin/mochu_us/cmd.php?act=verify',
      data: {
        'username': username,
        'password': passwordMd5,
        'vercode': vercode,
        'savedate': savedate.toString(),
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.bytes,
        followRedirects: false,
        validateStatus: (s) => s != null && s < 400,
      ),
    );
    return _decodeBytes(resp.data ?? []);
  }

  /// Server-side logout.
  Future<String> logout() async {
    final resp = await dio.get<Uint8List>(
      '/zb_users/plugin/mochu_us/cmd.php?act=logout',
      options: Options(
        responseType: ResponseType.bytes,
        validateStatus: (s) => s != null && s < 400,
      ),
    );
    return _decodeBytes(resp.data ?? []);
  }

  /// 每日签到（`cmd.php?act=qiandao`，网站点「签到」按钮的同一个接口）。
  ///
  /// 回包 JSON：`code == 1` 失败（`msg` 是原因），其余成功并带最新的 `giod` 积分。
  Future<String> checkIn() async {
    final resp = await dio.post<Uint8List>(
      '/zb_users/plugin/mochu_us/cmd.php?act=qiandao',
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.bytes,
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    return _decodeBytes(resp.data ?? []);
  }

  /// POST one of the user center's server-rendered view fragments.
  ///
  /// Views live under `src/views/<name>.php` and are POST-only; they return the
  /// HTML the SPA injects (`index`, `Nav`, `Collectlist`, `Shezhi_jiben`, …).
  Future<String> postUcenterView(String view, {String routs = ''}) async {
    final resp = await dio.post<Uint8List>(
      '$_ucenterViewBase$view.php',
      data: {'v': '3.70', 'routs': routs},
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.bytes,
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    return _decodeBytes(resp.data ?? []);
  }

  /// POST a user center JSON controller (`List.php`, `Get.php`,
  /// `userfilter_fun.php`, `shezhi_fun.php`).
  ///
  /// Callers add the `csrfToken` / `act` fields themselves, mirroring the
  /// website's own AJAX calls.
  Future<String> postUcenterJson(
    String file, {
    Map<String, dynamic>? query,
    required Map<String, dynamic> data,
  }) {
    return postForm('$_ucenterJsonBase$file', data: data, queryParameters: query);
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
}
