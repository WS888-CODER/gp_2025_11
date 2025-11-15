import 'package:flutter/material.dart';

class AppTheme {
  // ألوان البراند اللي نبغى نكررها
  static const Color primaryPurple = Color(0xFF4A5FBC); // البنفسجي حقكم
  static const Color accentCoral = Color(0xFFFD6C67); // الكورال حقكم

  // Switch theme الأساسي
  static final SwitchThemeData baseSwitchTheme = SwitchThemeData(
    thumbColor: MaterialStateProperty.resolveWith((states) {
      return Colors.white;
    }),
    trackColor: MaterialStateProperty.resolveWith((states) {
      if (states.contains(MaterialState.selected)) {
        return primaryPurple; // لما يكون ON
      }
      return Colors.grey; // لما يكون OFF
    }),
    trackOutlineColor: MaterialStateProperty.all(Colors.transparent),
  );

  // الوضع الفاتح
  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      useMaterial3: true,
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
      switchTheme: baseSwitchTheme,
    );
  }

  // الوضع الداكن
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      primaryColor: primaryPurple,
      scaffoldBackgroundColor: const Color(0xFF121212),
      colorScheme: ColorScheme.dark(
        primary: primaryPurple,
        secondary: accentCoral,
        background: const Color(0xFF121212),
        surface: const Color(0xFF1E1E1E),
        onSurface: Colors.white70,
      ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: true,
        backgroundColor: Color(0xFF212121),
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
      switchTheme: baseSwitchTheme.copyWith(
        trackColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return primaryPurple;
          }
          return Colors.grey;
        }),
      ),
    );
  }
}

class SnackHelper {
  // ✅ Success message
  static void success(BuildContext context, String message) {
    _show(
      context,
      message,
      const Color(0xFF4CAF50), // Green
    );
  }

  // ✅ Error message
  static void error(BuildContext context, String message) {
    _show(
      context,
      message,
      const Color(0xFFFF7B7B), // Red
    );
  }

  // ✅ Base snack builder
  static void _show(BuildContext context, String message, Color color) {
    if (context.mounted == false) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        backgroundColor: color.withOpacity(0.8),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}
