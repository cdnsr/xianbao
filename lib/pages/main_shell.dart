import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import 'home/home_page.dart';
import 'search/search_page.dart';
import 'login/login_page.dart';
import 'profile/profile_page.dart';
import '../utils/cookie_bridge.dart';
import '../widgets/update_dialog.dart';

/// Main app shell with bottom navigation bar.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  final List<Widget> _pages = [const HomePage(), const SearchPage()];
  bool _startupUpdateChecked = false;

  /// Whether the bottom bar is shown. Only the home article list may hide it;
  /// tapping a tab restores it.
  bool _navVisible = true;

  /// The bar only hides once the list has moved past this, so a barely-there
  /// jitter near the top of the list does not make it flicker.
  static const double _navHideThreshold = 24;

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
    await CookieBridge.syncFromWebView();
    if (!mounted) return;
    final appState = context.read<AppState>();
    appState.markSessionReady();
    unawaited(appState.refreshLoginState(refreshOnLoginChange: false));
  }

  Future<void> _refreshHomeSession(AppState appState) async {
    await CookieBridge.syncFromWebView();
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

    final delta = notification.scrollDelta ?? 0;
    if (delta == 0) return false;

    if (delta < 0 || notification.metrics.pixels <= 0) {
      _setNavVisible(true);
    } else if (notification.metrics.pixels > _navHideThreshold) {
      _setNavVisible(false);
    }
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