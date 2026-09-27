import 'package:flutter/material.dart';

/// Design tokens lifted from the website theme
/// (`zb_users/theme/xianbao_theme/style/style.css`) so the app shares the
/// same color language as new.xianbao.fun.
///
/// Light values come from the default rules, dark values from the site's
/// `.night` block (the website's own 夜间模式).
class AppPalette {
  AppPalette._();

  // ---- shared brand ----
  /// `--c-primary`
  static const Color primary = Color(0xFF0084FF);

  /// `--c-primary-dark`
  static const Color primaryDark = Color(0xFF0D71E3);

  /// Corner radius (`--radius: 2px`).
  static const double radius = 2;

  // ---- light: html{color:#333;background:#f1f1f1} / .sb{background:#fff} ----
  static const Color lightBackground = Color(0xFFF1F1F1);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightHeader = Color(0xFFFFFFFF);
  static const Color lightText = Color(0xFF333333);
  static const Color lightTextSecondary = Color(0xFF737A8A);
  static const Color lightDivider = Color(0xFFE8E8E8);
  static const Color lightHover = Color(0xFFF7F7F7);
  static const Color lightBadge = Color(0xFFF5F5F5);
  static const Color lightSelected = Color(0xFFE8F3FF);

  /// `.article-list .title .red {color:red}`
  static const Color lightTimeText = Color(0xFFFF0000);

  // ---- night: .night{background:#232931;color:#edeef0} ----
  static const Color darkBackground = Color(0xFF232931);
  static const Color darkSurface = Color(0xFF2B333E);
  static const Color darkHeader = Color(0xFF1E232B);
  static const Color darkText = Color(0xFFEDEEF0);
  static const Color darkTextSecondary = Color(0xFFB4C2E1);
  static const Color darkMuted = Color(0xFF737A8A);
  static const Color darkDivider = Color(0xFF39444F);
  static const Color darkHover = Color(0xFF36404D);
  static const Color darkBadge = Color(0xFF565C69);
  static const Color darkSelected = Color(0xFF1C3B57);

  /// `.night .badge {background:#565c69 !important;color:#d6d6d6;}`
  static const Color darkTimeText = Color(0xFFD6D6D6);
}

/// Builds the app [ThemeData] from [AppPalette].
class AppTheme {
  AppTheme._();

  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppPalette.primary,
      onPrimary: Colors.white,
      primaryContainer: AppPalette.lightSelected,
      onPrimaryContainer: AppPalette.primaryDark,
      secondary: AppPalette.primaryDark,
      onSecondary: Colors.white,
      secondaryContainer: AppPalette.lightBadge,
      onSecondaryContainer: AppPalette.lightText,
      error: Color(0xFFD32F2F),
      onError: Colors.white,
      surface: AppPalette.lightSurface,
      onSurface: AppPalette.lightText,
      surfaceContainerLowest: AppPalette.lightSurface,
      surfaceContainerLow: AppPalette.lightSurface,
      surfaceContainer: AppPalette.lightBadge,
      surfaceContainerHigh: AppPalette.lightBadge,
      surfaceContainerHighest: AppPalette.lightBadge,
      onSurfaceVariant: AppPalette.lightTextSecondary,
      outline: Color(0xFFC8C8C8),
      outlineVariant: AppPalette.lightDivider,
      shadow: Color(0x1A1A1A1A),
    );

    return _base(
      scheme,
      background: AppPalette.lightBackground,
      header: AppPalette.lightHeader,
      divider: AppPalette.lightDivider,
      navBackground: AppPalette.lightSurface,
      navUnselected: AppPalette.lightTextSecondary,
    );
  }

  static ThemeData dark() {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: AppPalette.primary,
      onPrimary: Colors.white,
      primaryContainer: AppPalette.darkSelected,
      onPrimaryContainer: AppPalette.darkTextSecondary,
      secondary: AppPalette.primary,
      onSecondary: Colors.white,
      secondaryContainer: AppPalette.darkBadge,
      onSecondaryContainer: AppPalette.darkText,
      error: Color(0xFFFF6B6B),
      onError: Colors.white,
      surface: AppPalette.darkSurface,
      onSurface: AppPalette.darkText,
      surfaceContainerLowest: AppPalette.darkHeader,
      surfaceContainerLow: AppPalette.darkBackground,
      surfaceContainer: AppPalette.darkSurface,
      surfaceContainerHigh: AppPalette.darkHover,
      surfaceContainerHighest: AppPalette.darkHover,
      onSurfaceVariant: AppPalette.darkTextSecondary,
      outline: AppPalette.darkBadge,
      outlineVariant: AppPalette.darkDivider,
      shadow: Color(0x66000000),
    );

    return _base(
      scheme,
      background: AppPalette.darkBackground,
      header: AppPalette.darkHeader,
      divider: AppPalette.darkDivider,
      navBackground: AppPalette.darkHeader,
      navUnselected: AppPalette.darkMuted,
    );
  }

  static ThemeData _base(
    ColorScheme scheme, {
    required Color background,
    required Color header,
    required Color divider,
    required Color navBackground,
    required Color navUnselected,
  }) {
    final isDark = scheme.brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      dividerColor: divider,
      splashFactory: InkRipple.splashFactory,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        toolbarHeight: 44,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: header,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        // 1px hairline like the site's .header border-bottom.
        shape: Border(bottom: BorderSide(color: divider, width: 1)),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppPalette.radius),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: divider,
        thickness: 1,
        space: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 56,
        elevation: 0,
        backgroundColor: navBackground,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: selected ? scheme.primary : navUnselected,
          );
        }),
      ),
      listTileTheme: ListTileThemeData(
        textColor: scheme.onSurface,
        iconColor: scheme.onSurfaceVariant,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? AppPalette.darkBadge : AppPalette.lightText,
        contentTextStyle: TextStyle(
          color: isDark ? AppPalette.darkText : Colors.white,
        ),
      ),
    );
  }
}
