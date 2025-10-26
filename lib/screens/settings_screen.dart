// lib/screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:gp_2025_11/config/app_settings_notifier.dart';
import 'package:gp_2025_11/l10n/app_localizations.dart';

class SettingsScreen extends StatefulWidget {
  final String userType;
  final String userId;

  const SettingsScreen({
    super.key,
    required this.userType,
    required this.userId,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isNotificationsEnabled = false;
  static const Color _brandColor = Color(0xFF4A5FBC);

  Future<void> _handleLogout(BuildContext context) async {
    const Color dialogBaseColor = Color(0xFF4A5FBC);
    const Color cancelBgColor = Color(0xFFE5E7EB);
    const Color cancelTextColor = Color(0xFF4B5563);
    const Color logoutBgColor = Color(0xFFFC686A);

    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: dialogBaseColor.withOpacity(0.7),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        title: const Text(
          'Confirm Logout',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        content: const Text(
          'Are you sure you want to log out?',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70),
        ),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          Expanded(
            child: TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              style: TextButton.styleFrom(
                backgroundColor: cancelBgColor,
                foregroundColor: cancelTextColor,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
              child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: TextButton.styleFrom(
                backgroundColor: logoutBgColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
              child: const Text('Logout', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseAuth.instance.signOut();
      if (context.mounted) {
        // ✅ FIXED: Now redirects to login instead of start screen
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      }
    }
  }

  void _toggleTheme(AppSettingsNotifier settings, bool value) {
    final newMode = value ? ThemeMode.dark : ThemeMode.light;
    settings.toggleTheme(newMode);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Theme changed to ${newMode == ThemeMode.light ? "Light Mode" : "Dark Mode"}'),
      ),
    );
  }

  void _changeLanguage(AppSettingsNotifier settings, AppLocalizations l10n) async {
    final targetLangName =
        settings.currentLanguageName == 'English' ? 'Arabic' : 'English';

    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.languageOption, textAlign: TextAlign.center),
        content: Text(
          'Are you sure you want to switch to $targetLangName?',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      settings.toggleLanguage();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Language switched to ${settings.currentLanguageName}')),
      );
    }
  }

  void _toggleNotifications(bool value) {
    setState(() => _isNotificationsEnabled = value);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Notifications are ${_isNotificationsEnabled ? "ON" : "OFF"}'),
      ),
    );
  }

  Future<Map<String, dynamic>?> _fetchUserData() async {
    if (widget.userId.isEmpty) return null;
    final doc = await FirebaseFirestore.instance
        .collection('Users')
        .doc(widget.userId)
        .get();
    return doc.data();
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsNotifier>(context);
    final l10n = AppLocalizations.of(context)!;
    final currentLangIsArabic = settings.currentLanguageName == 'Arabic';
    final targetLang =
        settings.currentLanguageName == 'English' ? 'Arabic' : 'English';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(l10n.settingsTitle),
        backgroundColor: _brandColor,
      ),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _fetchUserData(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          return Padding(
            padding: const EdgeInsets.fromLTRB(20.0, 120.0, 20.0, 25.0),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
              ),
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _SettingsSwitchItem(
                    icon: Icons.language,
                    iconColor: Colors.blue,
                    title: 'Switch Language to $targetLang',
                    value: currentLangIsArabic,
                    onChanged: (value) => _changeLanguage(settings, l10n),
                    switchColor: _brandColor,
                    subtitle: Text('Current: ${settings.currentLanguageName}'),
                    isTitleBold: true,
                  ),
                  _SettingsSwitchItem(
                    title: settings.themeMode == ThemeMode.dark
                        ? 'Dark Mode'
                        : 'Light Mode',
                    icon: Icons.light_mode,
                    iconColor: Colors.orange,
                    value: settings.themeMode == ThemeMode.dark,
                    onChanged: (value) => _toggleTheme(settings, value),
                    switchColor: _brandColor,
                    isTitleBold: true,
                  ),
                  _SettingsSwitchItem(
                    title: l10n.notificationsOption,
                    icon: Icons.notifications_none,
                    iconColor: Colors.purple,
                    value: _isNotificationsEnabled,
                    onChanged: _toggleNotifications,
                    switchColor: _brandColor,
                    subtitle: Text(l10n.manageAlertsSubtitle),
                    isTitleBold: true,
                  ),
                  _SettingsItem(
                    title: l10n.changePasswordOption,
                    icon: Icons.lock_outline,
                    iconColor: _brandColor,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () =>
                        Navigator.pushNamed(context, '/forgot-password'),
                    subtitle: Text(l10n.resetPasswordSubtitle),
                    isTitleBold: true,
                  ),
                  _SettingsItem(
                    title: 'Account',
                    icon: Icons.account_circle,
                    iconColor: Colors.teal,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.pushNamed(
                        context,
                        '/account-details',
                        arguments: {
                          'userId': widget.userId,
                          'userType': widget.userType
                        },
                      );
                    },
                    subtitle: const Text('View your registered details'),
                    isTitleBold: true,
                  ),
                  _SettingsItem(
                    title: 'About',
                    icon: Icons.info_outline,
                    iconColor: Colors.lightGreen,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pushNamed(context, '/about'),
                    subtitle: const Text('App version and information'),
                    isTitleBold: true,
                  ),
                  _SettingsItem(
                    title: l10n.logoutOption,
                    icon: Icons.logout,
                    iconColor: Colors.red,
                    onTap: () => _handleLogout(context),
                    isTitleBold: true,
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/* -------------------- Helper Widgets -------------------- */

class _SettingsItem extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final Widget? trailing;
  final VoidCallback onTap;
  final Widget? subtitle;
  final bool isTitleBold;

  const _SettingsItem({
    required this.title,
    required this.icon,
    required this.iconColor,
    this.trailing,
    required this.onTap,
    this.subtitle,
    this.isTitleBold = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      hoverColor: _brandColor.withOpacity(0.05),
      child: ListTile(
        visualDensity: VisualDensity.compact,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        leading: Icon(icon, color: iconColor),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: isTitleBold ? FontWeight.bold : FontWeight.normal,
            color: Theme.of(context).textTheme.bodyLarge?.color,
          ),
        ),
        trailing: trailing,
        subtitle: subtitle,
      ),
    );
  }

  static const Color _brandColor = Color(0xFF4A5FBC);
}

class _SettingsSwitchItem extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color switchColor;
  final Widget? subtitle;
  final bool isTitleBold;

  const _SettingsSwitchItem({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.onChanged,
    required this.switchColor,
    this.subtitle,
    this.isTitleBold = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      hoverColor: _SettingsItem._brandColor.withOpacity(0.05),
      child: ListTile(
        visualDensity: VisualDensity.compact,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        leading: Icon(icon, color: iconColor),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: isTitleBold ? FontWeight.bold : FontWeight.normal,
            color: Theme.of(context).textTheme.bodyLarge?.color,
          ),
        ),
        subtitle: subtitle,
        trailing: Switch(
          value: value,
          onChanged: onChanged,
          activeColor: switchColor,
        ),
      ),
    );
  }
}