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
  // Success message
  static void success(BuildContext context, String message) {
    _show(
      context,
      message,
      const Color(0xFF4CAF50),
    );
  }

  // Error message
  static void error(BuildContext context, String message) {
    _show(
      context,
      message,
      const Color(0xFFFF7B7B),
    );
  }

  // Base snack builder
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
                minWidth: width,
                maxWidth: width,
              ),
              child: SingleChildScrollView(
                child: Center(
                  child: DefaultTextStyle(
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                    ),
                    child: content!,
                  ),
                ),
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

class AppSettingsNotifier extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;

  ThemeMode get themeMode => _themeMode;

  void toggleTheme(ThemeMode mode) {
    if (_themeMode != mode) {
      _themeMode = mode;
      notifyListeners();
    }
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 90, color: scheme.outline.withOpacity(0.4)),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 14,
              color: scheme.onSurfaceVariant.withOpacity(0.6),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class CustomHeader extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool showBack;
  final List<Widget>? actions;
  final Widget? leading;

  const CustomHeader({
    super.key,
    required this.title,
    this.showBack = true,
    this.actions,
    this.leading,
  });

  @override
  Size get preferredSize => const Size.fromHeight(120);

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final Color primaryTop = scheme.primary;
    final Color primaryBottom =
        isDark ? scheme.primary.withOpacity(0.95) : scheme.primary;

    final Color bubbleColor = Colors.white.withOpacity(isDark ? 0.04 : 0.06);
    final Color shadowColor = scheme.primary.withOpacity(isDark ? 0.55 : 0.4);

    return Container(
      height: preferredSize.height,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primaryTop, primaryBottom],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(40),
          bottomRight: Radius.circular(40),
        ),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          // decorations
          Positioned(
            top: -60,
            right: -40,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: bubbleColor,
              ),
            ),
          ),
          Positioned(
            bottom: -20,
            left: -30,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: bubbleColor,
              ),
            ),
          ),

          SafeArea(
            child: Stack(
              children: [
                // -------- leading logic ---------
                if (leading != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: leading!,
                  )
                else if (showBack && canPop)
                  Padding(
                    padding: const EdgeInsets.only(
                      left: 8,
                      right: 8,
                      bottom: 16,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    ),
                  ),

                if (actions != null && actions!.isNotEmpty)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: actions!,
                    ),
                  ),

                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ThemedScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget? body;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final Widget? drawer;
  final Widget? endDrawer;
  final bool? resizeToAvoidBottomInset;
  final Color? overridePageBgColor;

  const ThemedScaffold({
    super.key,
    this.appBar,
    this.body,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.drawer,
    this.endDrawer,
    this.resizeToAvoidBottomInset,
    this.overridePageBgColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color pageBgColor = overridePageBgColor ??
        (isDark ? const Color(0xFF0F0F12) : const Color(0xFFF7F6FC));

    return Scaffold(
      backgroundColor: pageBgColor,
      appBar: appBar,
      body: body,
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
      drawer: drawer,
      endDrawer: endDrawer,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
    );
  }
}
