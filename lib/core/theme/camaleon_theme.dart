import 'package:flutter/material.dart';

/// Brand tokens from https://www.camaleonpos.com (css + homepage accents).
abstract final class CamaleonColors {
  /// Brand green from Camaleon POS web.
  static const green = Color(0xFF009966);
  static const greenBright = Color(0xFF009966);
  static const greenSoft = Color(0xFF31C299);
  static const blue = Color(0xFF2563EB);
  static const blueSoft = Color(0xFF3B82F6);
  static const purple = Color(0xFF9333EA);
  static const orange = Color(0xFFF9A45B);
  static const ink = Color(0xFF101828);
  static const slate = Color(0xFF4B5563);
  static const mist = Color(0xFFF8F6F3);
  static const line = Color(0xFFE5E7EB);
  static const night = Color(0xFF0B1220);
  static const nightSurface = Color(0xFF151C28);
  static const nightElevated = Color(0xFF1B2433);
  static const nightLine = Color(0xFF2A3544);
  static const nightText = Color(0xFFE8EEF5);
  static const nightMuted = Color(0xFF8B9BB0);
}

abstract final class CamaleonAssets {
  /// Official logo from camaleonpos.com (transparent PNG).
  static const logo = 'assets/brand/camaleon_logo.png';
}

abstract final class CamaleonTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: CamaleonColors.green,
      brightness: Brightness.light,
      primary: CamaleonColors.green,
      secondary: CamaleonColors.blue,
      tertiary: CamaleonColors.purple,
      surface: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: CamaleonColors.mist,
      appBarTheme: const AppBarTheme(
        backgroundColor: CamaleonColors.mist,
        foregroundColor: CamaleonColors.ink,
        elevation: 0,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: CamaleonColors.green,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: CamaleonColors.ink,
          side: const BorderSide(color: CamaleonColors.line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: CamaleonColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: CamaleonColors.green, width: 1.4),
        ),
      ),
      dividerColor: CamaleonColors.line,
    );
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: CamaleonColors.green,
      brightness: Brightness.dark,
      primary: CamaleonColors.green,
      secondary: CamaleonColors.blueSoft,
      tertiary: CamaleonColors.purple,
      surface: CamaleonColors.nightSurface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: CamaleonColors.night,
      appBarTheme: const AppBarTheme(
        backgroundColor: CamaleonColors.night,
        foregroundColor: CamaleonColors.nightText,
        elevation: 0,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: CamaleonColors.green,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: CamaleonColors.nightText,
          side: const BorderSide(color: CamaleonColors.nightLine),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: CamaleonColors.nightElevated,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: CamaleonColors.nightLine),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
            color: CamaleonColors.green,
            width: 1.4,
          ),
        ),
      ),
      dividerColor: CamaleonColors.nightLine,
    );
  }
}
