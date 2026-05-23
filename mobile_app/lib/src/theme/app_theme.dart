import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Brand Colors
  static const Color primary = Color(0xFFFF5200);
  static const Color secondary = Color(0xFF1A237E);
  static const Color tertiary = Color(0xFFA15AB8);
  static const Color neutral = Color(0xFF121212);
  static const Color appBackground = Color(0xFFF3F6F8);
  static const Color surfaceColor = Colors.white;

  static ThemeData get lightTheme {
    final base = ThemeData.light();

    // Typography using Google Fonts
    final manropeTextTheme = GoogleFonts.manropeTextTheme(base.textTheme);
    final interTextTheme = GoogleFonts.interTextTheme(base.textTheme);

    final customTextTheme = base.textTheme.copyWith(
      // Headlines -> Manrope
      displayLarge: manropeTextTheme.displayLarge?.copyWith(color: neutral),
      displayMedium: manropeTextTheme.displayMedium?.copyWith(color: neutral),
      displaySmall: manropeTextTheme.displaySmall?.copyWith(color: neutral),
      headlineLarge: manropeTextTheme.headlineLarge?.copyWith(color: neutral),
      headlineMedium: manropeTextTheme.headlineMedium?.copyWith(color: neutral),
      headlineSmall: manropeTextTheme.headlineSmall?.copyWith(color: neutral),
      titleLarge: manropeTextTheme.titleLarge?.copyWith(color: neutral, fontWeight: FontWeight.bold),
      titleMedium: manropeTextTheme.titleMedium?.copyWith(color: neutral, fontWeight: FontWeight.bold),
      titleSmall: manropeTextTheme.titleSmall?.copyWith(color: neutral, fontWeight: FontWeight.bold),
      
      // Body & Labels -> Inter
      bodyLarge: interTextTheme.bodyLarge?.copyWith(color: neutral),
      bodyMedium: interTextTheme.bodyMedium?.copyWith(color: neutral),
      bodySmall: interTextTheme.bodySmall?.copyWith(color: neutral),
      
      labelLarge: interTextTheme.labelLarge?.copyWith(color: neutral, fontWeight: FontWeight.w600),
      labelMedium: interTextTheme.labelMedium?.copyWith(color: neutral, fontWeight: FontWeight.w600),
      labelSmall: interTextTheme.labelSmall?.copyWith(color: neutral, fontWeight: FontWeight.w600),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: primary,
        secondary: secondary,
        tertiary: tertiary,
        surface: surfaceColor,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onTertiary: Colors.white,
        onSurface: neutral,
      ),
      scaffoldBackgroundColor: appBackground,
      textTheme: customTextTheme,
    );
  }
}
