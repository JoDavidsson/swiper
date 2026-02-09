import 'package:flutter/material.dart';

/// Design tokens: warm Scandinavian editorial.
/// Base spacing: 16dp; corner radius: 28 (cards), 24 (sheets), 14 (chips).
class AppTheme {
  static const double spacingUnit = 16.0;
  static const double radiusCard = 28.0;
  static const double radiusSheet = 24.0;
  static const double radiusChip = 14.0;

  static const Color primaryAction = Color(0xFFBF5E30);
  static const Color secondaryAction = Color(0xFF304C46);
  static const Color positiveLike = Color(0xFF4C7A61);
  static const Color negativeDislike = Color(0xFFB55D5D);
  static const Color accentHeart = Color(0xFFE0724D);
  static const Color priceHighlight = Color(0xFFC07A2A);
  static const Color background = Color(0xFFFAF8F4);
  static const Color surface = Color(0xFFFFFDF9);
  static const Color textPrimary = Color(0xFF29241F);
  static const Color textSecondary = Color(0xFF675E54);
  static const Color textCaption = Color(0xFF8D8277);
  static const Color outlineSoft = Color(0xFFE6DFD6);

  // Semantic colors for status indicators
  static const Color success = Color(0xFF4C7A61);
  static const Color warning = Color(0xFFD8A147);
  static const Color error = Color(0xFFB55D5D);
  static const Color surfaceVariant = Color(0xFFF0EBE3);

  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        primary: primaryAction,
        secondary: secondaryAction,
        surface: surface,
        error: negativeDislike,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textPrimary,
        onError: Colors.white,
      ),
      scaffoldBackgroundColor: background,
      fontFamily: 'DM Sans',
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontFamily: 'Playfair Display',
          fontSize: 34,
          fontWeight: FontWeight.w700,
          height: 1.12,
          color: textPrimary,
        ),
        headlineMedium: TextStyle(
          fontFamily: 'Playfair Display',
          fontSize: 30,
          fontWeight: FontWeight.w700,
          height: 1.15,
          color: textPrimary,
        ),
        headlineSmall: TextStyle(
          fontFamily: 'Playfair Display',
          fontSize: 25,
          fontWeight: FontWeight.w700,
          height: 1.18,
          color: textPrimary,
        ),
        titleLarge: TextStyle(
          fontFamily: 'Playfair Display',
          fontSize: 22,
          fontWeight: FontWeight.w600,
          height: 1.2,
          color: textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          height: 1.28,
          color: textPrimary,
        ),
        bodyLarge: TextStyle(fontSize: 16, height: 1.4, color: textPrimary),
        bodyMedium: TextStyle(fontSize: 14, height: 1.4, color: textPrimary),
        bodySmall: TextStyle(fontSize: 12, height: 1.35, color: textCaption),
        labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      cardTheme: CardThemeData(
        elevation: 2.5,
        shadowColor: Colors.black12,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusCard)),
        color: surface,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryAction,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(
              horizontal: spacingUnit * 2, vertical: spacingUnit),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusChip),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusChip),
          borderSide: const BorderSide(color: outlineSoft),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusChip),
          borderSide: const BorderSide(color: outlineSoft),
        ),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: spacingUnit, vertical: spacingUnit),
      ),
    );
  }
}
