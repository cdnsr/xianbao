import 'package:flutter/foundation.dart';
import '../services/http_client.dart';
import '../services/api_service.dart';
import 'home_cache_service.dart';

/// Global app state: login status, current page index.
class AppState extends ChangeNotifier {
  final HomeCacheData? initialHomeCache;

  AppState({this.initialHomeCache});

  bool _isLoggedIn = false;
  int _currentIndex = 0;
  int _loginVersion = 0;
  bool _sessionReady = false;

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
  Future<void> refreshLoginState({
    bool refreshHome = false,
    bool refreshOnLoginChange = true,
  }) async {
    final api = ApiService();
    final loggedIn = await api.isLoggedIn();
    _sessionReady = true;
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

  /// Called after successful login in WebView.
  /// Increments loginVersion so listeners (e.g. HomePage) can re-fetch
  /// with the new cookies that carry category filter preferences.
  Future<void> onLoginSuccess() async {
    _isLoggedIn = true;
    _loginVersion++;
    notifyListeners();
  }

  /// Called after logout.
  void onLogout() {
    _isLoggedIn = false;
    // Clear the direct login cookie header so subsequent requests
    // are unauthenticated.
    HttpClient().setLoginCookieHeader(null);
    _loginVersion++;
    notifyListeners();
  }
}
