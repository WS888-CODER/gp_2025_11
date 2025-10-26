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

  // 💡 تم تعديل وظيفة تسجيل الخروج لاستخدام Localizations.localeOf(context) وتعريب نصوص الحوار
  Future<void> _handleLogout(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final currentLangCode = Localizations.localeOf(context).languageCode;

    const Color dialogBaseColor = Color(0xFF4A5FBC);
    const Color cancelBgColor = Color(0xFFE5E7EB);
    const Color cancelTextColor = Color(0xFF4B5563);
    const Color logoutBgColor = Color(0xFFFC686A);

    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: dialogBaseColor.withOpacity(0.7),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        title: Text(
          // 🟢 تم تعريب العنوان
          currentLangCode == 'ar' ? 'تأكيد تسجيل الخروج' : 'Confirm Logout',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        content: Text(
          // 🟢 تم تعريب محتوى الحوار
          currentLangCode == 'ar' ? 'هل أنت متأكد أنك تريد تسجيل الخروج؟' : 'Are you sure you want to log out?',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70),
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
              // 🟢 تم تعريب الزر
              child: Text(currentLangCode == 'ar' ? 'إلغاء' : 'Cancel', style: const TextStyle(fontWeight: FontWeight.bold)),
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
              // 🟢 تم استخدام مفتاح التعريب
              child: Text(l10n.logoutOption, style: const TextStyle(fontWeight: FontWeight.bold)),
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

  // 💡 تم تعديل وظيفة الثيم لتعريب نصوص الـ SnackBar
  void _toggleTheme(AppSettingsNotifier settings, bool value) {
    final newMode = value ? ThemeMode.dark : ThemeMode.light;
    final currentLangCode = Localizations.localeOf(context).languageCode;
    settings.toggleTheme(newMode);

    final themeName = newMode == ThemeMode.light 
        ? (currentLangCode == 'ar' ? 'الوضع الفاتح' : 'Light Mode')
        : (currentLangCode == 'ar' ? 'الوضع الداكن' : 'Dark Mode');
        
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(currentLangCode == 'ar' ? 'تم تغيير السمة إلى $themeName' : 'Theme changed to $themeName'),
      ),
    );
  }

  // 💡 وظيفة تغيير اللغة - تم تحديث تصميم الحوار ليتطابق مع حوار تسجيل الخروج
  void _changeLanguage(AppSettingsNotifier settings, AppLocalizations l10n) async {
    final targetLangName = settings.currentLanguageName == 'English' ? 'العربية' : 'English';
    final currentLangCode = Localizations.localeOf(context).languageCode;
    
    // الألوان - مطابقة لحوار تسجيل الخروج
    const Color dialogBaseColor = Color(0xFF4A5FBC);
    const Color cancelBgColor = Color(0xFFE5E7EB);
    const Color cancelTextColor = Color(0xFF4B5563);
    const Color confirmBgColor = Color(0xFFFC686A);

    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        // 🟢 تصميم جديد لحوار اللغة
        backgroundColor: dialogBaseColor.withOpacity(0.7),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        title: Text(
          currentLangCode == 'ar' ? 'تأكيد تغيير اللغة' : 'Confirm Language',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        content: Text(
          currentLangCode == 'ar' ? 'هل أنت متأكد من التبديل إلى $targetLangName؟' : 'Are you sure you want to switch to $targetLangName?',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70),
        ),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          Expanded(
            child: TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              style: TextButton.styleFrom(
                backgroundColor: cancelBgColor,
                foregroundColor: cancelTextColor,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
              child: Text(currentLangCode == 'ar' ? 'إلغاء' : 'Cancel', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(
                backgroundColor: confirmBgColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
              child: Text(currentLangCode == 'ar' ? 'تأكيد' : 'Confirm', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      settings.toggleLanguage();
      // 🟢 FIX: هذا السطر يجبر الشاشة على إعادة التحميل بالـ Locale الجديد
      if (context.mounted) {
        Navigator.of(context).pushReplacementNamed('/settings', arguments: {'userType': widget.userType, 'userId': widget.userId});
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(currentLangCode == 'ar' ? 'تم التبديل إلى $targetLangName' : 'Language switched to $targetLangName')),
      );
    }
  }

  // 💡 تم تعديل وظيفة الإشعارات لتعريب نصوص الـ SnackBar
  void _toggleNotifications(bool value) {
    setState(() => _isNotificationsEnabled = value);
    final currentLangCode = Localizations.localeOf(context).languageCode;

    final statusText = _isNotificationsEnabled 
        ? (currentLangCode == 'ar' ? 'قيد التشغيل' : 'ON')
        : (currentLangCode == 'ar' ? 'متوقفة' : 'OFF');
        
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(currentLangCode == 'ar' 
            ? 'الإشعارات الآن $statusText'
            : 'Notifications are $statusText'),
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
    // 🟢 FIX: استخدام السياق للحصول على الـ Locale
    final currentLangIsArabic = Localizations.localeOf(context).languageCode == 'ar';
    
    // 🟢 تم تغيير طريقة حساب targetLang/currentLang لتعرض الأسماء المعربة
    final targetLangName = currentLangIsArabic ? 'English' : 'العربية';
    final currentLangName = currentLangIsArabic ? 'العربية' : 'English';

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
                    // 🟢 FIX 1: استخدام الدالة switchLanguage
                    title: l10n.switchLanguage(targetLangName),
                    value: settings.locale.languageCode == 'ar',
                    onChanged: (value) => _changeLanguage(settings, l10n),
                    switchColor: _brandColor,
                    // 🟢 FIX 2: استخدام الدالة currentLanguage
                    subtitle: Text(l10n.currentLanguage(currentLangName)),
                    isTitleBold: true,
                  ),
                  _SettingsSwitchItem(
                    // 🟢 FIX 3: استخدام مفتاح themeOption
                    title: l10n.themeOption,
                    icon: Icons.light_mode,
                    iconColor: Colors.orange,
                    value: settings.themeMode == ThemeMode.dark,
                    onChanged: (value) => _toggleTheme(settings, value),
                    switchColor: _brandColor,
                    isTitleBold: true,
                    // 🟢 FIX 4: تعريب subtitle الوضع الفاتح/الداكن
                    subtitle: Text(settings.themeMode == ThemeMode.dark
                        ? (currentLangIsArabic ? 'الوضع الداكن' : 'Dark Mode')
                        : (currentLangIsArabic ? 'الوضع الفاتح' : 'Light Mode')),
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
                    // 🟢 FIX 5: استخدام مفتاح myAccountDetailsSection بدلاً من 'Account'
                    title: l10n.myAccountDetailsSection,
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
                    // 🟢 FIX 6: استخدام مفتاح viewOnlyText بدلاً من 'View your registered details'
                    subtitle: Text(l10n.viewOnlyText),
                    isTitleBold: true,
                  ),
                  _SettingsItem(
                    // 🟢 استرجاع الـ About الأصلي
                    title: currentLangIsArabic ? 'حول التطبيق' : 'About',
                    icon: Icons.info_outline,
                    iconColor: Colors.lightGreen,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pushNamed(context, '/about'),
                    // 🟢 استرجاع الوصف الأصلي (مع تعريب يدوي بسيط لعدم وجود المفتاح)
                    subtitle: Text(currentLangIsArabic ? 'إصدار التطبيق والمعلومات' : 'App version and information'),
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
// تم ترك هذه الـ Widgets كما هي في الكود الأصلي
class _SettingsItem extends StatelessWidget {
// ... (بقية الكود) ...
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
// ... (بقية الكود) ...
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
