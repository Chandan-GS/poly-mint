import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_type.dart';

/// Instrument/Technical theme: flat surfaces, hairline borders, sharp 4px radii,
/// IBM Plex type, one green accent. No elevation, no gradients, no tint.
abstract class AppTheme {
  static const double radius = 4;
  static const double radiusLg = 6;

  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final bg = isDark ? AppColors.paperDark : AppColors.paper;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surface;
    final ink = isDark ? AppColors.inkDark : AppColors.ink;
    final muted = isDark ? AppColors.mutedDark : AppColors.muted;
    final hairline = isDark ? AppColors.hairlineDark : AppColors.hairline;
    final accent = isDark ? AppColors.accentDark : AppColors.accent;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: isDark ? const Color(0xFF06231A) : Colors.white,
      secondary: accent,
      onSecondary: Colors.white,
      surface: surface,
      onSurface: ink,
      onSurfaceVariant: muted,
      surfaceContainerLowest: bg,
      surfaceContainerLow: bg,
      surfaceContainer: isDark ? const Color(0xFF1B1E22) : const Color(0xFFEFEEE8),
      surfaceContainerHigh: isDark ? const Color(0xFF202327) : const Color(0xFFEAE9E2),
      surfaceContainerHighest:
          isDark ? const Color(0xFF24272C) : const Color(0xFFE6E4DC),
      outline: hairline,
      outlineVariant: hairline,
      error: AppColors.rejected,
      onError: Colors.white,
    );

    final textTheme = _textTheme(ink, muted);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      fontFamily: AppType.sans,
      textTheme: textTheme,
      dividerTheme: DividerThemeData(
        color: hairline,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: ink,
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        titleTextStyle: AppType.screenTitle.copyWith(color: ink),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: hairline),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: ink,
          foregroundColor: bg,
          disabledBackgroundColor: hairline,
          minimumSize: const Size.fromHeight(52),
          elevation: 0,
          textStyle: AppType.bodyStrong,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: isDark ? const Color(0xFF06231A) : Colors.white,
          minimumSize: const Size.fromHeight(52),
          textStyle: AppType.bodyStrong,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          foregroundColor: ink,
          side: BorderSide(color: hairline),
          textStyle: AppType.bodyStrong,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          textStyle: AppType.bodyStrong,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        hintStyle: AppType.body.copyWith(color: AppColors.faint),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.transparent,
        side: BorderSide(color: hairline),
        labelStyle: AppType.monoSmall.copyWith(color: ink),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
        contentTextStyle: AppType.body.copyWith(color: bg),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        linearMinHeight: 2,
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        height: 60,
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.all(AppType.monoSmall),
      ),
    );
  }

  static TextTheme _textTheme(Color ink, Color muted) {
    TextStyle c(TextStyle s) => s.copyWith(color: ink);
    return TextTheme(
      headlineSmall: c(AppType.screenTitle),
      titleLarge: c(AppType.screenTitle),
      titleMedium: c(AppType.heading),
      bodyLarge: c(AppType.body),
      bodyMedium: c(AppType.body),
      bodySmall: AppType.caption.copyWith(color: muted),
      labelLarge: c(AppType.bodyStrong),
      labelSmall: AppType.label.copyWith(color: muted),
    );
  }
}
