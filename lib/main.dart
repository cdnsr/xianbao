import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/app_state.dart';
import 'services/home_cache_service.dart';
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
  final initialHomeCache = await HomeCacheService().load();
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(initialHomeCache: initialHomeCache),
      child: const XianbaoApp(),
    ),
  );
}

class XianbaoApp extends StatelessWidget {
  const XianbaoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '线报酷',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.red,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(centerTitle: true),
        cardTheme: CardThemeData(elevation: 1, margin: EdgeInsets.zero),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.red,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(centerTitle: true),
        cardTheme: CardThemeData(elevation: 1, margin: EdgeInsets.zero),
      ),
      themeMode: ThemeMode.system,
      home: const MainShell(),
    );
  }
}
