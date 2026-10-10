import 'package:flutter/foundation.dart';
import '../utils/cookie_bridge.dart';
import 'http_client.dart';
import 'ucenter_service.dart';

/// Session lifecycle for the app's cookie-backed login.
///
/// The session itself lives in [HttpClient]'s cookie jar (file-backed after
/// `HttpClient.configureCookieStore`), so this class only has to
/// cover the two transitions: bringing an upgrade-era session across on
/// startup, and tearing the session down on logout.
class SessionStore {
  /// Startup: pull over a session left by old WebView-based versions.
  ///
  /// Only runs when the jar is empty — otherwise it would resurrect cookies a
  /// previous logout already dropped. Failures are swallowed: worst case the
  /// user logs in again.
  static Future<void> restore() async {
    try {
      final jar = HttpClient().cookieJar;
      final existing = await jar.loadForRequest(
        Uri.parse(HttpClient.baseUrl),
      );
      if (existing.isNotEmpty) return;
      final migrated = await CookieBridge.migrateFromWebView();
      if (migrated > 0) {
        debugPrint('SessionStore: migrated $migrated legacy cookies');
      }
    } catch (e) {
      debugPrint('SessionStore.restore failed: $e');
    }
  }

  /// Logout: tell the server, then drop every local cookie.
  ///
  /// Local cookies are cleared even if the server call fails — keeping the user
  /// "logged in" locally after they asked to log out would be worse.
  static Future<void> logout() async {
    try {
      await HttpClient().logout();
    } catch (e) {
      debugPrint('SessionStore.logout server call failed: $e');
    }
    await HttpClient().clearCookies();
    // 用户中心的 csrf 令牌是按会话下发的，换账号必须丢弃。
    UcenterService.resetSession();
  }
}
