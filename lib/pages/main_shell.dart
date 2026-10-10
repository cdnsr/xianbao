import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../services/check_in_service.dart';
import '../services/session_store.dart';
import 'home/home_page.dart';
import 'search/search_page.dart';
import 'login/login_page.dart';
import 'profile/profile_page.dart';
import '../widgets/center_tip.dart';
import '../widgets/update_dialog.dart';

/// Main app shell with bottom navigation bar.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

/// Decides the bottom bar's visibility after one scroll update.
///
/// [pixels] is the list's current scroll offset and [delta] how much it moved
/// since the previous update. Flutter computes `delta` as
/// `pixels - oldPixels`, so a **positive delta means the list advanced**, i.e.
/// the user swiped upwards.
///
/// Returns the new visibility, or null to leave it unchanged. Any reverse
/// movement - or being back at the top - always restores the bar, so it can
/// never get stuck hidden.
bool? navBarVisibleAfterScroll({
  required double pixels,
  required double delta,
  double hideThreshold = _navHideThreshold,
}) {
  if (delta == 0) return null;
  if (delta < 0 || pixels <= 0) return true;
  if (pixels > hideThreshold) return false;
  return null;
}

/// The bar only hides once the list has moved past this, so a barely-there
/// jitter near the top of the list does not make it flicker.
const double _navHideThreshold = 24;

class _MainShellState extends State<MainShell> {
  final List<Widget> _pages = [const HomePage(), const SearchPage()];
  bool _startupUpdateChecked = false;

  /// Whether the bottom bar is shown. Only the home article list may hide it;
  /// tapping a tab restores it.
  bool _navVisible = true;

  /// 上一次看到的登录态，用来捕捉「未登录 → 已登录」这个跳变（补当天签到）。
  bool _wasLoggedIn = false;

  @override
  void initState() {
    super.initState();
    // Check login state on startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeSession();
      _scheduleStartupUpdateCheck();
    });
  }

  void _scheduleStartupUpdateCheck() {
    if (_startupUpdateChecked) return;
    _startupUpdateChecked = true;
    // Delay slightly so first frame / session init can settle.
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      unawaited(UpdateCoordinator.checkOnStartup(context));
    });
  }

  Future<void> _initializeSession() async {
    await SessionStore.restore();
    if (!mounted) return;
    final appState = context.read<AppState>();
    appState.markSessionReady();
    // 登录态判定；一旦判定为「已登录」，下面的监听会顺带补当天那一次签到。
    unawaited(appState.refreshLoginState(refreshOnLoginChange: false));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final appState = context.watch<AppState>();
    final loggedIn = appState.isLoggedIn;
    if (loggedIn && !_wasLoggedIn) {
      // 两个入口都会走到这里：启动时就已经是登录态、以及刚在登录页登录成功。
      // 未登录不会触发（未登录跳过签到）。
      _wasLoggedIn = true;
      unawaited(_runSilentCheckIn());
    } else if (!loggedIn) {
      _wasLoggedIn = false;
    }
  }

  /// 静默签到：成功不提示，只有真的失败（且当天还没提示过）才在屏幕中间弹一条 tip。
  Future<void> _runSilentCheckIn() async {
    final tip = await CheckInCoordinator.attempt();
    if (!mounted || tip == null) return;
    showCenterTip(context, tip);
  }

  Future<void> _refreshHomeSession(AppState appState) async {
    appState.refreshHomeContent();
    unawaited(appState.refreshLoginState(refreshOnLoginChange: false));
  }

  /// Hides the bottom bar while the home list is swiped upwards (the list
  /// advances), and brings it back on any upward swipe or at the top of the
  /// list - the usual "more room to read" behaviour.
  bool _onScrollNotification(ScrollNotification notification) {
    if (!mounted) return false;
    // Only the home article list drives this; the other tabs keep the bar.
    if (context.read<AppState>().currentIndex != 0) return false;
    if (notification.metrics.axis != Axis.vertical) return false;
    if (notification is! ScrollUpdateNotification) return false;

    final visible = navBarVisibleAfterScroll(
      pixels: notification.metrics.pixels,
      delta: notification.scrollDelta ?? 0,
    );
    if (visible != null) _setNavVisible(visible);
    // Never swallow the notification; other listeners still need it.
    return false;
  }

  void _setNavVisible(bool visible) {
    if (!mounted || _navVisible == visible) return;
    setState(() => _navVisible = visible);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final isLoggedIn = appState.isLoggedIn;
    final currentIndex = appState.currentIndex;

    // Build the third tab dynamically based on login state
    final pages = List<Widget>.from(_pages);
    if (isLoggedIn) {
      pages.add(ProfilePage(appState: appState));
    } else {
      pages.add(LoginPage(appState: appState));
    }

    final index = currentIndex.clamp(0, pages.length - 1);

    // _navVisible only governs the home tab; other tabs always show the bar.
    final showNav = index == 0 ? _navVisible : true;

    return Scaffold(
      body: NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: IndexedStack(index: index, children: pages),
      ),
      bottomNavigationBar: AnimatedSize(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        alignment: Alignment.bottomCenter,
        child: showNav
            ? NavigationBar(
                selectedIndex: index,
                labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
                height: 56,
                onDestinationSelected: (i) {
                  // Re-entering the home tab starts with the bar visible.
                  _setNavVisible(true);
                  appState.currentIndex = i;
                  if (i == 0) _refreshHomeSession(appState);
                },
                destinations: [
                  const NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home),
                    label: '首页',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.search_outlined),
                    selectedIcon: Icon(Icons.search),
                    label: '搜索',
                  ),
                  NavigationDestination(
                    icon: Icon(
                      isLoggedIn ? Icons.person_outline : Icons.login_outlined,
                    ),
                    selectedIcon: Icon(isLoggedIn ? Icons.person : Icons.login),
                    label: isLoggedIn ? '用户中心' : '登录',
                  ),
                ],
              )
            : const SizedBox(width: double.infinity),
      ),
    );
  }
}