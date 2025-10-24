// lib/screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:gp_2025_11/config/app_settings_notifier.dart';
import 'package:gp_2025_11/l10n/app_localizations.dart'; 
import 'package:gp_2025_11/screens/account_details_page.dart'; // الاستيراد النهائي


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
  static final Color _hoverColor = _brandColor.withOpacity(0.08);
  static const Color _lightLavenderColor = Color(0xFFD0D0FF); 


  // 1. منطق تسجيل الخروج
  Future<void> _handleLogout(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;

    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.logoutOption),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.logoutOption, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseAuth.instance.signOut();
      if (context.mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/start',
          (Route<dynamic> route) => false,
        );
      }
    }
  }

  // منطق تغيير الثيم
  void _toggleTheme(AppSettingsNotifier settings, bool value) {
    ThemeMode newMode = value ? ThemeMode.dark : ThemeMode.light;
    settings.toggleTheme(newMode);
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Theme changed to ${newMode == ThemeMode.light ? "Light Mode" : "Dark Mode"}')),
    );
  }
  
  // منطق تغيير اللغة
  void _changeLanguage(AppSettingsNotifier settings, AppLocalizations l10n) async {
    final targetLangName = settings.currentLanguageName == 'English' ? 'Arabic' : 'English';
    
    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.languageOption),
        content: Text('Are you sure you want to switch to $targetLangName?'),
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
    setState(() {
      _isNotificationsEnabled = value;
    });
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Notifications are ${_isNotificationsEnabled ? "ON" : "OFF"}')),
    );
  }

  Future<Map<String, dynamic>?> _fetchUserData() async {
    if (widget.userId.isEmpty) return null;
    final doc =
        await FirebaseFirestore.instance.collection('Users').doc(widget.userId).get();
    return doc.data();
  }
  
  @override
  Widget build(BuildContext context) {
    bool isJobSeeker = widget.userType == 'JobSeeker';
    
    final settings = Provider.of<AppSettingsNotifier>(context);
    final l10n = AppLocalizations.of(context)!; 

    final currentLangIsArabic = settings.currentLanguageName == 'Arabic';
    final targetLang = settings.currentLanguageName == 'English' ? 'Arabic' : 'English';

    return Scaffold(
      backgroundColor: Colors.white, // خلفية الشاشة بيضاء
      appBar: AppBar(
        title: Text(l10n.settingsTitle),
        backgroundColor: _SettingsItem._brandColor,
      ),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _fetchUserData(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          final userData = snapshot.data ?? {};
          
          String accountStatus = userData['AccountStatus'] ?? 'Unknown';
          Color statusColor = Colors.grey;

          if (!isJobSeeker) {
            switch (accountStatus) {
              case 'Verified':
                statusColor = Colors.green;
                break;
              case 'Rejected':
                statusColor = Colors.red;
                break;
              case 'Pending':
                statusColor = Colors.orange;
                break;
            }
          }

          // ⬇️ تعديل الـ Padding ليناسب بداية المربع البيضاوي من منتصف الصفحة
          return Padding( 
            padding: const EdgeInsets.fromLTRB(20.0, 120.0, 20.0, 25.0), 
            child: Container( 
              decoration: BoxDecoration(
                color: _lightLavenderColor, // اللون البنفسجي الجديد
                borderRadius: BorderRadius.circular(20), 
              ),
              child: ListView(
                padding: EdgeInsets.zero, 
                children: [
                  
                  // 1.1 اللغة 
                  _SettingsSwitchItem(
                    icon: Icons.language,
                    iconColor: Colors.blue,
                    title: 'Switch Language to $targetLang',
                    value: currentLangIsArabic,
                    onChanged: (value) => _changeLanguage(settings, l10n),
                    switchColor: _SettingsItem._brandColor,
                    subtitle: Text('Current: ${settings.currentLanguageName}'), 
                    isTitleBold: true, 
                  ),

                  // 1.2 الثيم
                  _SettingsSwitchItem(
                    title: settings.themeMode == ThemeMode.dark ? 'Dark Mode' : 'Light Mode',
                    icon: Icons.light_mode,
                    iconColor: Colors.orange,
                    value: settings.themeMode == ThemeMode.dark,
                    onChanged: (value) => _toggleTheme(settings, value),
                    switchColor: _SettingsItem._brandColor,
                    isTitleBold: true, 
                  ),

                  // 1.3 الإشعارات
                  _SettingsSwitchItem(
                    title: l10n.notificationsOption,
                    icon: Icons.notifications_none,
                    iconColor: Colors.purple,
                    value: _isNotificationsEnabled,
                    onChanged: _toggleNotifications,
                    switchColor: _SettingsItem._brandColor,
                    subtitle: Text(l10n.manageAlertsSubtitle),
                    isTitleBold: true, 
                  ),
                  
                  // 2.1 تغيير كلمة المرور
                  _SettingsItem(
                    title: l10n.changePasswordOption,
                    icon: Icons.lock_outline,
                    iconColor: _SettingsItem._brandColor,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pushNamed(context, '/forgot-password'),
                    subtitle: Text(l10n.resetPasswordSubtitle),
                    isTitleBold: true, 
                  ),

                  // 2.2 الحساب (Account - توجيه لصفحة عادية)
                  _SettingsItem(
                    title: 'Account',
                    icon: Icons.account_circle,
                    iconColor: Colors.teal,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                        Navigator.pushNamed(
                          context, 
                          '/account-details',
                          arguments: {'userId': widget.userId, 'userType': widget.userType}
                        );
                    },
                    subtitle: const Text('View your registered details'),
                    isTitleBold: true, 
                  ),
                
                  // 2.3 حالة توثيق الشركة (للشركات فقط)
                  if (!isJobSeeker)
                    _SettingsItem(
                      title: l10n.accountVerificationStatus,
                      icon: Icons.verified_user_outlined,
                      iconColor: statusColor,
                      trailing: Text(l10n.viewOnlyText, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold)),
                      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Verification status managed by Admin.')),
                      ),
                      isTitleBold: true, 
                    ),
                  
                  // 2.4 حول (About)
                  _SettingsItem(
                    title: 'About',
                    icon: Icons.info_outline,
                    iconColor: Colors.lightGreen,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('App version and information'))),
                    subtitle: const Text('App version and information'),
                    isTitleBold: true, 
                  ),
                  
                  // 3. تسجيل الخروج (Logout) 
                  _SettingsItem(
                    title: l10n.logoutOption,
                    icon: Icons.logout,
                    iconColor: Colors.red,
                    trailing: null,
                    onTap: () => _handleLogout(context),
                    isTitleBold: true, 
                  ),
                  
                  // مسافة سفلية داخل المربع البيضاوي
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

// ⬇️ ويدجت لعرض التفاصيل داخل الحوار
class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

// ⬇️ ويدجت لعنصر إعداد عادي (سهم) - يطبق Hover
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

  static const Color _brandColor = Color(0xFF4A5FBC);
  static final Color _hoverColor = _brandColor.withOpacity(0.08);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      hoverColor: _hoverColor, 
      child: ListTile(
        visualDensity: VisualDensity.compact, 
        contentPadding: const EdgeInsets.symmetric(horizontal: 16), 
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

// ⬇️ ويدجت لعنصر إعداد مع زر تبديل (Switch) - يطبق Hover
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
      hoverColor: _SettingsItem._hoverColor, 
      child: ListTile(
        visualDensity: VisualDensity.compact, 
        contentPadding: const EdgeInsets.symmetric(horizontal: 16), 
        leading: Icon(icon, color: iconColor),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: isTitleBold ? FontWeight.bold : FontWeight.normal, 
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

// ويدجت عنوان القسم (تم إزالته من الاستخدام)
class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink(); 
  }
}