import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'http_client.dart';

/// Expands JD short / affiliate (返利) links into the real product page.
///
/// A `u.jd.com/xxxx` link is not a plain 3xx redirect: JD answers 200 with a
/// small HTML page carrying the next hop in `var hrl='...'`, so following
/// redirects alone is not enough. JD's risk control also intercepts some hops
/// and returns a `cfe.m.jd.com/.../risk_handler/...` page - even then the real
/// destination leaks through its `returnurl` parameter, which is read here as
/// a fallback.
///
/// Everything is best effort: when a link cannot be resolved the caller keeps
/// the original URL, which is never worse than not trying.
///
/// Coverage is limited by what JD actually serves, so expect gaps:
///
///  * Single-product links resolve to `https://item.jd.com/<sku>.html`. That
///    is roughly a third of `u.jd.com` links picked at random.
///  * Coupon / campaign links do NOT resolve, and there is no plain product
///    URL to recover: `u.jd.com` hops to `jingfen.jd.com/item?q=...` (领券页)
///    or `pro.m.jd.com/mall/active/.../index.html?sku=...&q=...` (活动页),
///    where the target sits inside the encrypted `q`. Those pages are SPA
///    shells that fetch everything over JS, the `q` is not a simple
///    obfuscation (single-byte and repeating-key XOR both fail to yield a
///    URL), and nothing in the response mentions a product. Getting further
///    would need to execute JD's JavaScript in a WebView. Posts that share
///    coupons (新赚吧 / 好单 领券帖) are almost entirely this kind, so
///    coverage on them is near zero rather than a third.
///
/// Taobao's `m.tb.cn` is deliberately NOT handled - it is not a matter of the
/// parsing below being incomplete. Measured over 15 live links:
///
///  * it never redirects; every user agent (desktop, iPhone, Android) gets a
///    200 with the real hop buried in `location.replace(url)`;
///  * that hop is always a 淘宝客 page (`s.click.taobao.com/t` or
///    `uland.taobao.com/coupon/edetail`) whose product id exists only inside
///    the encrypted `e` parameter - no plain product URL is served anywhere;
///  * those pages render the product client-side, so nothing is recoverable
///    over plain HTTP. Expanding them would need a WebView.
class ShortLinkResolver {
  ShortLinkResolver._();

  static final ShortLinkResolver instance = ShortLinkResolver._();

  /// JD shortener / affiliate hosts worth expanding.
  static const Set<String> _shortHosts = {
    'u.jd.com',
    '3.cn',
    'union-click.jd.com',
    'jingfen.jd.com',
  };

  /// How many HTML hops to chase before giving up.
  static const int _maxHops = 3;

  /// Resolved values, including nulls, so a failing link is only tried once.
  final Map<String, String?> _cache = <String, String?>{};

  /// Whether [url] is a link this resolver can expand.
  ///
  /// Cheap and network-free, so callers can skip the whole path for articles
  /// that contain no JD links at all.
  static bool isExpandable(String url) {
    if (canonicalProductUrl(url) != null) return true;
    return _shortHosts.contains(_hostOf(url));
  }

  /// True when [html] contains at least one expandable link.
  static bool hasExpandableLink(String html) =>
      expandableUrlsIn(html).isNotEmpty;

  /// The canonical `https://item.jd.com/<sku>.html` form of a JD product link.
  ///
  /// Handles the mobile form and strips every affiliate query parameter, so
  /// the result is a clean product URL.
  static String? canonicalProductUrl(String url) {
    final mobile = _mobileProductPattern.firstMatch(url);
    if (mobile != null) return 'https://item.jd.com/${mobile.group(1)}.html';
    final desktop = _desktopProductPattern.firstMatch(url);
    if (desktop != null) return 'https://item.jd.com/${desktop.group(1)}.html';
    return null;
  }

  /// Every distinct expandable URL in [html], in document order.
  static List<String> expandableUrlsIn(String html) {
    final seen = <String>{};
    final found = <String>[];
    for (final match in _urlPattern.allMatches(html)) {
      final url = _trimTrailingPunctuation(match.group(0)!);
      if (url.isEmpty || !seen.add(url)) continue;
      if (isExpandable(url)) found.add(url);
    }
    return found;
  }

  /// Resolves [url] to the real page, or null when it cannot be resolved.
  Future<String?> expand(String url) async {
    final key = url.trim();
    if (key.isEmpty) return null;

    final cached = _cache[key];
    if (cached != null || _cache.containsKey(key)) return cached;

    // Already a product link - no network needed.
    final direct = canonicalProductUrl(key);
    if (direct != null) {
      _cache[key] = direct;
      return direct;
    }
    if (!_shortHosts.contains(_hostOf(key))) {
      _cache[key] = null;
      return null;
    }

    String? resolved;
    try {
      resolved = await _follow(key);
    } catch (_) {
      resolved = null;
    }
    // Do not cache failures: a link may resolve next time the network is up.
    if (resolved != null) _cache[key] = resolved;
    return resolved;
  }

  /// Rewrites every expandable link in [html] to its real destination,
  /// including plain-text copies of the same URL. Links that cannot be
  /// resolved are left exactly as they were.
  Future<String> rewriteHtml(String html) async {
    final urls = expandableUrlsIn(html);
    if (urls.isEmpty) return html;

    final resolved = await Future.wait(
      urls.map((url) async => MapEntry(url, await expand(url))),
    );

    // Longest first, so one short link being a prefix of another cannot
    // corrupt it mid-replacement.
    resolved.sort((a, b) => b.key.length.compareTo(a.key.length));

    var result = html;
    for (final entry in resolved) {
      final target = entry.value;
      if (target == null || target == entry.key) continue;
      result = result.replaceAll(entry.key, target);
    }
    return result;
  }

  Future<String?> _follow(String start) async {
    var current = start;
    for (var hop = 0; hop < _maxHops; hop++) {
      final response = await HttpClient().dio.get<String>(
        current,
        options: Options(
          responseType: ResponseType.plain,
          headers: const {
            'Accept':
                'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          },
          validateStatus: (status) => status != null && status < 400,
        ),
      );

      // Where the redirect chain actually landed.
      final landed = response.realUri.toString();
      final fromLanded =
          canonicalProductUrl(landed) ?? productUrlFromReturnUrl(landed);
      if (fromLanded != null) return fromLanded;

      final body = response.data ?? '';
      final fromBody =
          canonicalProductUrl(body) ?? productUrlFromReturnUrl(body);
      if (fromBody != null) return fromBody;

      final next = redirectTargetInHtml(body);
      if (next == null || next == current) return null;
      current = next;
    }
    return null;
  }

  /// JD's risk-control page hides the destination in `returnurl=`, sometimes
  /// percent-encoded more than once.
  @visibleForTesting
  static String? productUrlFromReturnUrl(String text) {
    final match = _returnUrlPattern.firstMatch(text);
    if (match == null) return null;

    var value = match.group(1)!;
    for (var attempt = 0; attempt < 3; attempt++) {
      final product = canonicalProductUrl(value);
      if (product != null) return product;
      final decoded = Uri.decodeComponent(value);
      if (decoded == value) break;
      value = decoded;
    }
    return canonicalProductUrl(value);
  }

  /// The next hop buried in a JS / meta-refresh interstitial, if any.
  @visibleForTesting
  static String? redirectTargetInHtml(String html) {
    final hrl = _hrlPattern.firstMatch(html);
    if (hrl != null) return _unescapeJsUrl(hrl.group(1)!);

    final meta = _metaRefreshPattern.firstMatch(html);
    if (meta != null) return _unescapeJsUrl(meta.group(1)!);

    final location = _locationPattern.firstMatch(html);
    if (location != null) return _unescapeJsUrl(location.group(1)!);

    return null;
  }

  static String _unescapeJsUrl(String value) => value
      .replaceAll('&amp;', '&')
      .replaceAll(r'\/', '/')
      .trim();

  static String? _hostOf(String url) {
    final host = Uri.tryParse(url.trim())?.host;
    if (host == null || host.isEmpty) return null;
    return host.toLowerCase();
  }

  static String _trimTrailingPunctuation(String url) =>
      url.replaceFirst(RegExp(r'''[.,;:!?)\]}']+$'''), '');

  static final RegExp _desktopProductPattern =
      RegExp(r'item\.jd\.com/(\d{6,})\.html');
  static final RegExp _mobileProductPattern =
      RegExp(r'item\.m\.jd\.com/product/(\d{6,})\.html');
  static final RegExp _returnUrlPattern =
      RegExp(r'''returnurl=([^&\s"<>']+)''', caseSensitive: false);
  static final RegExp _hrlPattern =
      RegExp(r'''var\s+hrl\s*=\s*['"]([^'"]+)['"]''');
  static final RegExp _metaRefreshPattern = RegExp(
    r'''http-equiv=["']?refresh["']?[^>]*content=["'][^"']*url=([^"'\s>]+)''',
    caseSensitive: false,
  );
  static final RegExp _locationPattern = RegExp(
    r'''location(?:\.href|\.replace\s*\()\s*=?\s*['"]([^'"]+)['"]''',
    caseSensitive: false,
  );
  static final RegExp _urlPattern =
      RegExp(r'''https?://[^\s"'<>]+''', caseSensitive: false);
}
