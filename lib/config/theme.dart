import 'package:flutter/material.dart';

class AppTheme {
  static const Color primaryPurple = Color(0xFF4A5FBC);
  static const Color accentCoral = Color(0xFFFD6C67);

  static final SwitchThemeData baseSwitchTheme = SwitchThemeData(
    thumbColor: MaterialStateProperty.resolveWith((states) {
      return Colors.white;
    }),
    trackColor: MaterialStateProperty.resolveWith((states) {
      if (states.contains(MaterialState.selected)) {
        return primaryPurple;
      }
      return Colors.grey;
    }),
    trackOutlineColor: MaterialStateProperty.all(Colors.transparent),
  );

  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      useMaterial3: true,
      primaryColor: primaryPurple,
      scaffoldBackgroundColor: Colors.white,
      colorScheme: const ColorScheme.light(
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

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      primaryColor: primaryPurple,
      scaffoldBackgroundColor: const Color(0xFF121212),
      colorScheme: const ColorScheme.dark(
        primary: primaryPurple,
        secondary: accentCoral,
        background: Color(0xFF121212),
        surface: Color(0xFF1E1E1E),
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

/// A reusable, styled dialog used across the app.
/// Keeps consistent colors, shapes, and button styles.
class JadeerDialog<T> extends StatelessWidget {
  final String title; // Dialog title
  final Widget? content; // Dialog body content (Text, Column, etc.)
  final String primaryLabel; // Main action button text
  final T? primaryResult; // Value returned when primary button is pressed
  final String? secondaryLabel; // Optional secondary button text
  final T? secondaryResult; // Value returned when secondary button is pressed
  final double width;

  const JadeerDialog({
    super.key,
    required this.title,
    this.content,
    required this.primaryLabel,
    this.primaryResult,
    this.secondaryLabel,
    this.secondaryResult,
    this.width = 420,
  });

  @override
  Widget build(BuildContext context) {
    const Color brandColor = Color(0xFF4A5FBC);
    const Color dangerColor = Color(0xFFFC686A);

    return AlertDialog(
      backgroundColor: brandColor.withOpacity(0.7),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(30),
      ),

      // Title section
      title: Text(
        title,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),

      // Dialog content section
      content: content == null
          ? null
          : ConstrainedBox(
              constraints: BoxConstraints(
                // dialog body width is controlled here for all usages
                minWidth: width,
                maxWidth: width,
              ),
              child: SingleChildScrollView(
                child: content!,
              ),
            ),

      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      actionsAlignment: MainAxisAlignment.center,

      // Action buttons (Cancel / Confirm)
      actions: [
        if (secondaryLabel != null)
          TextButton(
            onPressed: () => Navigator.pop<T>(context, secondaryResult),
            style: TextButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.9),
              foregroundColor: brandColor,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: Text(
              secondaryLabel!,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        if (secondaryLabel != null) const SizedBox(width: 12),
        TextButton(
          onPressed: () => Navigator.pop<T>(context, primaryResult),
          style: TextButton.styleFrom(
            backgroundColor: dangerColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          child: Text(
            primaryLabel,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
