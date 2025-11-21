import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gp_2025_11/config/theme.dart';
import 'package:gp_2025_11/config/themed_scaffold.dart';
import 'package:provider/provider.dart';

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
  bool _isDeletingAccount = false;

  Future<void> _handleLogout(BuildContext context) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => const JadeerDialog<bool>(
        title: 'Confirm Logout',
        content: Text(
          'Are you sure you want to log out?',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white70,
            fontSize: 15,
          ),
        ),
        secondaryLabel: 'Cancel',
        secondaryResult: false,
        primaryLabel: 'Log Out',
        primaryResult: true,
      ),
    );

    if (confirm == true) {
      await FirebaseAuth.instance.signOut();
      if (context.mounted) {
        Navigator.of(context)
            .pushNamedAndRemoveUntil('/login', (route) => false);
      }
    }
  }

  Future<void> _handleDeleteAccount(BuildContext context) async {
    final isJobSeeker = widget.userType == 'JobSeeker';

    final title = isJobSeeker ? 'Delete Account' : 'Delete Company Account';

    final description = isJobSeeker
        ? 'Your account will be permanently deleted, including your personal data, CVs, reports, and interview data. All active applications will be cancelled and related data removed.'
        : 'Your company account will be permanently deleted, including the company profile, job postings, and related applicant data. All active postings will be closed, and a confirmation email will be sent to your registered address.';

    final confirmLabel = isJobSeeker ? 'Delete Account' : 'Delete';

    final bool? confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => JadeerDialog<bool>(
        title: title,
        primaryLabel: confirmLabel,
        primaryResult: true,
        secondaryLabel: 'Cancel',
        secondaryResult: false,
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Are you sure you want to proceed? This action cannot be undone.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                description,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirm != true) return;

    setState(() => _isDeletingAccount = true);

    try {
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final callable = functions.httpsCallable('deleteUserAccount');

      final result = await callable.call(<String, dynamic>{
        'userId': widget.userId,
        'userType': widget.userType,
      });

      final success = (result.data is Map &&
              (result.data['success'] == true ||
                  result.data['status'] == 'ok')) ||
          result.data == true;

      if (!success) {
        SnackHelper.error(
          context,
          'Failed to delete account. Please try again.',
        );
        setState(() => _isDeletingAccount = false);
        return;
      }

      final successMessage = isJobSeeker
          ? 'Your account has been deleted successfully.'
          : 'Your company account has been deleted successfully. A confirmation email has been sent.';

      SnackHelper.success(context, successMessage);

      await FirebaseAuth.instance.signOut();
      if (!context.mounted) return;

      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    } catch (e) {
      SnackHelper.error(
        context,
        'An error occurred while deleting your account. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _isDeletingAccount = false);
    }
  }

  void _toggleTheme(AppSettingsNotifier settings, bool value) {
    final newMode = value ? ThemeMode.dark : ThemeMode.light;
    settings.toggleTheme(newMode);
  }

  void _toggleNotifications(bool value) {
    setState(() => _isNotificationsEnabled = value);
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsNotifier>(context);
    final isAdmin = widget.userType == 'Admin';

    return ThemedScaffold(
        appBar: AppBar(
          title: const Text(
            'Settings',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          backgroundColor: _brandColor,
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(20.0, 40.0, 20.0, 25.0),
          child: ListView(
            children: [
              // ======= Appearance =======
              SettingsSectionCard(
                child: _SettingsSwitchItem(
                  title: 'Appearance',
                  icon: Icons.light_mode,
                  iconColor: Colors.orange,
                  value: settings.themeMode == ThemeMode.dark,
                  onChanged: (value) => _toggleTheme(settings, value),
                  switchColor: _brandColor,
                  isTitleBold: true,
                  subtitle: Text(
                    settings.themeMode == ThemeMode.dark
                        ? 'Dark Mode'
                        : 'Light Mode',
                  ),
                ),
              ),

              if (!isAdmin) ...[
                // Notifications
                SettingsSectionCard(
                  child: _SettingsSwitchItem(
                    title: 'Notifications',
                    icon: Icons.notifications_none,
                    iconColor: Colors.purple,
                    value: _isNotificationsEnabled,
                    onChanged: _toggleNotifications,
                    switchColor: _brandColor,
                    subtitle: const Text('Manage alerts and reminders'),
                    isTitleBold: true,
                  ),
                ),

                // Change password
                SettingsSectionCard(
                  child: _SettingsItem(
                    title: 'Change Password',
                    icon: Icons.lock_outline,
                    iconColor: _brandColor,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () =>
                        Navigator.pushNamed(context, '/change-password'),
                    subtitle: const Text('Reset your password securely'),
                    isTitleBold: true,
                  ),
                ),

                // Account details
                SettingsSectionCard(
                  child: _SettingsItem(
                    title: 'My Account Details',
                    icon: Icons.account_circle,
                    iconColor: Colors.teal,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.pushNamed(
                        context,
                        '/account-details',
                        arguments: {
                          'userId': widget.userId,
                          'userType': widget.userType,
                        },
                      );
                    },
                    subtitle: const Text('Account information overview'),
                    isTitleBold: true,
                  ),
                ),
              ],

              // About
              SettingsSectionCard(
                child: _SettingsItem(
                  title: 'About',
                  icon: Icons.info_outline,
                  iconColor: Colors.lightGreen,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pushNamed(context, '/about'),
                  subtitle: const Text('App version and information'),
                  isTitleBold: true,
                ),
              ),

              // Logout
              SettingsSectionCard(
                child: _SettingsItem(
                  title: 'Log Out',
                  icon: Icons.logout,
                  iconColor: Colors.red,
                  onTap: () => _handleLogout(context),
                  isTitleBold: true,
                ),
              ),

              // Delete account
              if (!isAdmin)
                SettingsSectionCard(
                  child: _SettingsItem(
                    title: widget.userType == 'JobSeeker'
                        ? 'Delete Account'
                        : 'Delete Company Account',
                    icon: Icons.delete_forever_outlined,
                    iconColor: Colors.red,
                    trailing: _isDeletingAccount
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.red,
                            ),
                          )
                        : const Icon(Icons.chevron_right),
                    onTap: () {
                      if (_isDeletingAccount) return;
                      _handleDeleteAccount(context);
                    },
                    subtitle: Text(
                      widget.userType == 'JobSeeker'
                          ? 'Permanently delete your account and all related data'
                          : 'Permanently delete your company account and all related data',
                    ),
                    isTitleBold: true,
                  ),
                ),
            ],
          ),
        ));
  }
}

/* ----------------------------------------------------------------------
   Card wrapper
---------------------------------------------------------------------- */
class SettingsSectionCard extends StatelessWidget {
  final Widget child;

  const SettingsSectionCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final Color bg = Theme.of(context).colorScheme.surface;
    final Color borderColor = const Color(0xFF4A5FBC).withOpacity(0.08);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

/* ----------------------------------------------------------------------
   Basic item
---------------------------------------------------------------------- */
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
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: ListTile(
        visualDensity: VisualDensity.compact,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(icon, color: iconColor),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: isTitleBold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        trailing: trailing,
        subtitle: subtitle,
      ),
    );
  }
}

/* ----------------------------------------------------------------------
   Switch item
---------------------------------------------------------------------- */
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
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => onChanged(!value),
      child: ListTile(
        visualDensity: VisualDensity.compact,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(icon, color: iconColor),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: isTitleBold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        subtitle: subtitle,
        trailing: Theme(
          data: Theme.of(context).copyWith(
            switchTheme: SwitchThemeData(
              trackColor: MaterialStateProperty.resolveWith((states) {
                if (states.contains(MaterialState.selected)) {
                  return switchColor;
                } else {
                  return scheme.surface;
                }
              }),
              thumbColor: MaterialStateProperty.resolveWith((states) {
                if (states.contains(MaterialState.selected)) {
                  return Colors.white;
                } else {
                  return scheme.primary;
                }
              }),
              trackOutlineColor: MaterialStateProperty.resolveWith((states) {
                if (states.contains(MaterialState.selected)) {
                  return switchColor;
                } else {
                  return scheme.primary;
                }
              }),
            ),
          ),
          child: Transform.scale(
            scale: 0.9,
            child: Switch.adaptive(
              value: value,
              onChanged: onChanged,
            ),
          ),
        ),
      ),
    );
  }
}
