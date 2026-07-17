import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import 'home/home_page.dart';
import 'search/search_page.dart';
import 'login/login_page.dart';
import 'profile/profile_page.dart';
import '../utils/cookie_bridge.dart';

/// Main app shell with bottom navigation bar.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  final List<Widget> _pages = [const HomePage(), const SearchPage()];

  @override
  void initState() {
    super.initState();
    // Check login state on startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeSession();
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

    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        height: 56,
        onDestinationSelected: (i) {
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
      ),
    );
  }
}
