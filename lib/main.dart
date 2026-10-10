import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'services/app_state.dart';
import 'services/home_cache_service.dart';
import 'services/http_client.dart';
import 'services/theme_controller.dart';
import 'theme/app_theme.dart';
import 'pages/main_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Set a simple, self-contained error widget BEFORE runApp so that any
  // build-time exception shows a visible message instead of a blank screen.
  // We avoid Theme.of(context) here because the error widget may be built
  // outside a valid widget context during a build failure.
  ErrorWidget.builder = (details) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        color: const Color(0xFFF5F5F5),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 48,
                  color: Color(0xFFD32F2F),
                ),
                const SizedBox(height: 16),
                SelectableText(
                  details.exceptionAsString(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFFD32F2F)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  };

  // Catch framework errors (including build exceptions) so they are
  // visible in release mode instead of silently rendering blank.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
  };
  // Catch async errors outside the widget tree.
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('AsyncError: $error\n$stack');
    return true;
  };
  // 登录态现在是原生 Cookie（不再经过 WebView），把 jar 落到应用目录里，
  // 这样重启后仍然是登录状态。拿不到目录就退回内存 jar，不影响使用。
  try {
    final dir = await getApplicationSupportDirectory();
    await HttpClient().configureCookieStore(dir.path);
  } catch (e) {
    debugPrint('cookie store init failed: $e');
  }
  final initialHomeCache = await HomeCacheService().load();
  final themeController = ThemeController();
  await themeController.load();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AppState(initialHomeCache: initialHomeCache),
        ),
        ChangeNotifierProvider.value(value: themeController),
      ],
      child: const XianbaoApp(),
    ),
  );
}

class XianbaoApp extends StatelessWidget {
  const XianbaoApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeMode = context.watch<ThemeController>().mode;
    return MaterialApp(
      title: '线报酷',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      // Without these, MaterialApp falls back to English-only
      // DefaultMaterialLocalizations and the long-press text selection toolbar
      // (复制 / 全选 / 粘贴 …) renders in English. The app's own strings are all
      // Chinese, so zh_CN is the only supported locale - devices set to any
      // other language fall back to it rather than to English.
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh', 'CN')],
      home: const MainShell(),
    );
  }
}
