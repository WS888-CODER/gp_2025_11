// lib/config/theme.dart
import 'package:flutter/material.dart';

class AppTheme {
  // Brand Colors
  static const Color primaryPurple = Color(0xFF49469F);
  static const Color accentCoral = Color(0xFFFD6C67);

  // 1. الوضع الفاتح (Light Theme)
  static ThemeData get lightTheme {
    return ThemeData(
      primaryColor: primaryPurple,
      scaffoldBackgroundColor: Colors.white,
      colorScheme: ColorScheme.light(
        primary: primaryPurple,
        secondary: accentCoral,
        surface: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: true,
        backgroundColor: primaryPurple,
        foregroundColor: Colors.white,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryPurple,
          foregroundColor: Colors.white,
        ),
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          color: Colors.black87,
        ),
      ),
      useMaterial3: true,
    );
  }

  // 2. الوضع الداكن (Dark Theme) - NEW
  static ThemeData get darkTheme {
    return ThemeData(
      primaryColor: primaryPurple,
      scaffoldBackgroundColor: const Color(0xFF121212), // خلفية داكنة جداً
      // تحديد السطوع (Brightness) لضمان أن كل الويدجت تعمل بالوضع الداكن
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(
        primary: primaryPurple,
        secondary: accentCoral,
        background: const Color(0xFF121212),
        surface: const Color(0xFF1E1E1E), // لون السطح (surface) للبطاقات
        onSurface: Colors.white70,
      ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: true,
        backgroundColor: Color(0xFF212121), // لون أغمق لشريط التطبيق
        foregroundColor: Colors.white,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryPurple,
          foregroundColor: Colors.white,
        ),
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          color: Colors.white70,
        ),
      ),
      useMaterial3: true,
    );
  }
}
