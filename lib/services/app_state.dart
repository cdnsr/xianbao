import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import 'home_cache_service.dart';
import 'session_store.dart';

/// Global app state: login status, current page index.
class AppState extends ChangeNotifier {
  final HomeCacheData? initialHomeCache;

  /// 探测登录态的方式，默认打服务端的 /login.html；测试里可以换成假的。
  final Future<bool?> Function()? loginProbe;

  AppState({this.initialHomeCache, this.loginProbe});

  bool _isLoggedIn = false;
  int _currentIndex = 0;
  int _loginVersion = 0;
  bool _sessionReady = false;

  /// 会话纪元：每次「登录成功 / 注销」都 +1。
  ///
  /// 用来丢弃过期的登录态探测结果：探测是网络请求，可能**在登录之前发出、登录之后
  /// 才回来**（比如首页 Tab 那次刷新），这种结果必须作废，否则会把刚登录好的状态
  /// 又改回「未登录」——表现就是登录成功后点收藏提示「请先登录」。
  int _sessionEpoch = 0;

  bool get isLoggedIn => _isLoggedIn;
  int get currentIndex => _currentIndex;
  int get loginVersion => _loginVersion;
  bool get sessionReady => _sessionReady;

  set currentIndex(int index) {
    _currentIndex = index;
    notifyListeners();
  }

  /// Switch bottom navigation to the login / profile tab (index 2).
  void goToLoginTab() {
    currentIndex = 2;
  }

  /// Cookies are ready, so homepage requests can start without waiting for
  /// the separate login-state request.
  void markSessionReady({bool refreshHome = true}) {
    final wasReady = _sessionReady;
    _sessionReady = true;
    if (refreshHome) _loginVersion++;
    if (!wasReady || refreshHome) notifyListeners();
  }

  /// Check and update login state.
  ///
  /// A network failure leaves the state untouched ([ApiService.isLoggedIn]
  /// reports "unknown"): the session now lives in a file-backed cookie jar, so
  /// treating an offline cold start as "logged out" would silently drop it.
  ///
  /// 结果只在「期间没有发生登录/注销」时才采纳，见 [_sessionEpoch]。
  Future<void> refreshLoginState({
    bool refreshHome = false,
    bool refreshOnLoginChange = true,
  }) async {
    final epoch = _sessionEpoch;
    final loggedIn = await (loginProbe ?? ApiService().isLoggedIn)();
    if (epoch != _sessionEpoch) {
      // 探测期间登录或注销过：这个结果已经过期，丢掉。
      debugPrint('refreshLoginState: stale probe discarded');
      return;
    }
    _sessionReady = true;
    if (loggedIn == null) return;
    final loginChanged = loggedIn != _isLoggedIn;
    if (loginChanged) {
      _isLoggedIn = loggedIn;
    }
    if ((loginChanged && refreshOnLoginChange) || refreshHome) {
      _loginVersion++;
    }
    if (loginChanged || refreshHome) {
      notifyListeners();
    }
  }

  void refreshHomeContent() {
    _loginVersion++;
    notifyListeners();
  }

  /// 登录成功后跟服务端核一次会话是否真的生效。
  ///
  /// 原生登录靠 Set-Cookie 落进 Cookie 罐，万一没落上（Cookie 被拒、域不匹配），
  /// App 会一直以为自己已登录，用户则在别的页面莫名被判「未登录」。这里核一次：
  /// 服务端明确说未登录 → 返回 false（由登录页提示重试）；网络异常（未知）→ 按
  /// 成功处理，不因为一次抖动把人挡在登录页。
  Future<bool> verifySessionAfterLogin() async {
    try {
      final loggedIn = await (loginProbe ?? ApiService().isLoggedIn)();
      return loggedIn ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Called after a successful native login. Increments loginVersion so
  /// listeners (e.g. HomePage) re-fetch with the new cookies that carry
  /// category filter preferences.
  Future<void> onLoginSuccess() async {
    _sessionEpoch++;
    _isLoggedIn = true;
    _loginVersion++;
    notifyListeners();
  }

  /// Called after logout: drops the server session and every stored cookie.
  Future<void> onLogout() async {
    _sessionEpoch++;
    _isLoggedIn = false;
    _loginVersion++;
    notifyListeners();
    await SessionStore.logout();
  }
}
