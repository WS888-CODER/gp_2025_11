import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gp_2025_11/screens/jobseeker_profile.dart';

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

class JobSeekerAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget title;

  const JobSeekerAppBar({
    super.key,
    required this.title,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  Stream<Map<String, dynamic>> _userMiniStream(String userId) {
    if (userId.isEmpty) {
      return Stream.value({
        'name': 'User',
        'email': '',
        'photo': '',
        'complete': false,
      });
    }
    return FirebaseFirestore.instance
        .collection('Users')
        .doc(userId)
        .snapshots()
        .map((snap) {
      final d = snap.data() ?? {};
      return {
        'name': (d['Name'] ?? '').toString().trim(),
        'email': (d['Email'] ?? '').toString().trim(),
        'photo': (d['PhotoURL'] ?? '').toString().trim(),
        'complete': d['IsProfileComplete'] == true,
      };
    });
  }

  String _initials(String nameOrEmail) {
    final s = nameOrEmail.trim();
    if (s.isEmpty) return 'U';
    final parts = s.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
    final base = s.contains('@') ? s.split('@').first : s;
    return base.isNotEmpty
        ? base.substring(0, base.length > 1 ? 2 : 1).toUpperCase()
        : 'U';
  }

  @override
  Widget build(BuildContext context) {
    const brand = AppTheme.primaryPurple;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return AppBar(
      backgroundColor: brand,
      elevation: 0,
      leadingWidth: 56,
      leading: uid.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.only(left: 8),
              child: StreamBuilder<Map<String, dynamic>>(
                stream: _userMiniStream(uid),
                builder: (context, snap) {
                  final name = (snap.data?['name'] ?? '').toString();
                  final email = (snap.data?['email'] ?? '').toString();
                  final photo = (snap.data?['photo'] ?? '').toString();
                  final complete = (snap.data?['complete'] == true);
                  final placeholder = _initials(name.isNotEmpty ? name : email);

                  final avatar = Hero(
                    tag: 'profileAvatar',
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundImage:
                              photo.isNotEmpty ? NetworkImage(photo) : null,
                          backgroundColor: const Color(0xFFFF7B7B),
                          foregroundColor: Colors.white,
                          child: photo.isEmpty
                              ? Text(
                                  placeholder,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    fontSize: 16,
                                  ),
                                )
                              : null,
                        ),
                      ],
                    ),
                  );

                  return Tooltip(
                    message:
                        complete ? 'Profile complete' : 'Profile incomplete',
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const JobSeekerProfile(),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: avatar,
                      ),
                    ),
                  );
                },
              ),
            ),
      title: title,
      actions: [
        IconButton(
          tooltip: 'Notifications',
          icon: const Icon(Icons.notifications_none, color: Colors.white),
          onPressed: () => SnackHelper.error(
              context, 'Notifications will be available soon'),
        ),
        IconButton(
          tooltip: 'Settings',
          icon: const Icon(Icons.settings_outlined, color: Colors.white),
          onPressed: () {
            if (uid.isEmpty) return;
            Navigator.pushNamed(
              context,
              '/settings',
              arguments: {'userType': 'JobSeeker', 'userId': uid},
            );
          },
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
