import 'package:flutter/material.dart';

/// Design tokens: Scandinavian minimalism.
/// Base spacing: 16dp; corner radius: 16 (cards), 18 (sheets), 10 (chips).
class AppTheme {
  static const double spacingUnit = 16.0;
  static const double radiusCard = 16.0;
  static const double radiusSheet = 18.0;
  static const double radiusChip = 10.0;

  static const Color primaryAction = Color(0xFF007AFF);
  static const Color positiveLike = Color(0xFF4CAF50);
  static const Color negativeDislike = Color(0xFFFF3B30);
  static const Color accentHeart = Color(0xFFFF4081);
  static const Color background = Color(0xFFF5F5F5);
  static const Color surface = Colors.white;
  static const Color textPrimary = Color(0xFF333333);
  static const Color textSecondary = Color(0xFF666666);
  static const Color textCaption = Color(0xFF888888);
  
  // Semantic colors for status indicators
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFFC107);
  static const Color error = Color(0xFFFF3B30);
  static const Color surfaceVariant = Color(0xFFE0E0E0);

  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.light(
        primary: primaryAction,
        secondary: accentHeart,
        surface: surface,
        error: negativeDislike,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textPrimary,
        onError: Colors.white,
      ),
      scaffoldBackgroundColor: background,
      fontFamily: 'Roboto',
      textTheme: const TextTheme(
        headlineLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: textPrimary),
        headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: textPrimary),
        headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textPrimary),
        titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: textPrimary),
        titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textPrimary),
        bodyLarge: TextStyle(fontSize: 16, color: textPrimary),
        bodyMedium: TextStyle(fontSize: 14, color: textPrimary),
        bodySmall: TextStyle(fontSize: 12, color: textCaption),
        labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shadowColor: Colors.black26,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusCard)),
        color: surface,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryAction,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: spacingUnit * 2, vertical: spacingUnit),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusChip)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(radiusChip)),
        contentPadding: const EdgeInsets.symmetric(horizontal: spacingUnit, vertical: spacingUnit),
      ),
    );
  }
}
