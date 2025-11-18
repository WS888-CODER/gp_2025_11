import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gp_2025_11/config/theme.dart';
import 'package:gp_2025_11/config/themed_scaffold.dart';
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
  bool _isDeletingAccount = false;

  Future<void> _handleLogout(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final currentLangCode = Localizations.localeOf(context).languageCode;

    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => JadeerDialog<bool>(
        title:
            currentLangCode == 'ar' ? 'تأكيد تسجيل الخروج' : 'Confirm Logout',
        content: Text(
          currentLangCode == 'ar'
              ? 'هل أنت متأكد أنك تريد تسجيل الخروج؟'
              : 'Are you sure you want to log out?',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 15,
          ),
        ),
        secondaryLabel: currentLangCode == 'ar' ? 'إلغاء' : 'Cancel',
        secondaryResult: false,
        primaryLabel: l10n.logoutOption,
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
    final currentLangCode = Localizations.localeOf(context).languageCode;
    final isArabic = currentLangCode == 'ar';
    final isJobSeeker = widget.userType == 'JobSeeker';

    final title = isJobSeeker
        ? (isArabic ? 'حذف الحساب نهائيًا' : 'Delete Account')
        : (isArabic ? 'حذف حساب الشركة' : 'Delete Company Account');

    final description = isJobSeeker
        ? (isArabic
            ? 'سيتم حذف حسابك نهائيًا بما في ذلك بياناتك الشخصية، سيرتك الذاتية، تقاريرك، وبيانات المقابلات. كما سيتم إلغاء جميع طلبات التوظيف النشطة وحذف بياناتها المرتبطة.'
            : 'Your account will be permanently deleted, including your personal data, CVs, reports, and interview data. All active applications will be cancelled and related data removed.')
        : (isArabic
            ? 'سيتم حذف حساب شركتكم نهائيًا بما في ذلك ملف الشركة، إعلانات الوظائف، وبيانات المتقدمين المرتبطة بها. سيتم إغلاق جميع الوظائف النشطة وحذف بيانات المتقدمين، وسيتم إرسال رسالة تأكيد إلى البريد الإلكتروني المسجل.'
            : 'Your company account will be permanently deleted, including the company profile, job postings, and related applicant data. All active postings will be closed, and a confirmation email will be sent to the registered address.');

    final confirmLabel =
        isArabic ? 'تأكيد الحذف' : (isJobSeeker ? 'Delete Account' : 'Delete');

    final cancelLabel = isArabic ? 'إلغاء' : 'Cancel';

    final bool? confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => JadeerDialog<bool>(
        title: title,
        primaryLabel: confirmLabel,
        primaryResult: true,
        secondaryLabel: cancelLabel,
        secondaryResult: false,
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isArabic
                    ? 'هل أنت متأكد أنك تريد المتابعة؟ لا يمكن التراجع عن هذه العملية.'
                    : 'Are you sure you want to proceed? This action cannot be undone.',
                style: const TextStyle(
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

    if (confirm != true) {
      return;
    }

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
          isArabic
              ? 'فشل حذف الحساب. حاول مرة أخرى.'
              : 'Failed to delete account. Please try again.',
        );
        setState(() => _isDeletingAccount = false);
        return;
      }

      final successMessage = isJobSeeker
          ? (isArabic
              ? 'تم حذف حسابك بنجاح.'
              : 'Your account has been deleted successfully.')
          : (isArabic
              ? 'تم حذف حساب الشركة بنجاح. تم إرسال رسالة تأكيد إلى بريدكم الإلكتروني.'
              : 'Your company account has been deleted successfully. A confirmation email has been sent to your registered email.');

      SnackHelper.success(context, successMessage);

      await Future.delayed(const Duration(seconds: 2));

      await FirebaseAuth.instance.signOut();
      if (!context.mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    } catch (e) {
      SnackHelper.error(
        context,
        isArabic
            ? 'حدث خطأ أثناء حذف الحساب. حاول مرة أخرى.'
            : 'An error occurred while deleting your account. Please try again.',
      );
    } finally {
      if (mounted) {
        setState(() => _isDeletingAccount = false);
      }
    }
  }

  void _toggleTheme(AppSettingsNotifier settings, bool value) {
    final newMode = value ? ThemeMode.dark : ThemeMode.light;
    final currentLangCode = Localizations.localeOf(context).languageCode;
    settings.toggleTheme(newMode);

    final themeName = newMode == ThemeMode.light
        ? (currentLangCode == 'ar' ? 'الوضع الفاتح' : 'Light Mode')
        : (currentLangCode == 'ar' ? 'الوضع الداكن' : 'Dark Mode');

    SnackHelper.success(
      context,
      currentLangCode == 'ar'
          ? 'تم تغيير السمة إلى $themeName'
          : 'Theme changed to $themeName',
    );
  }

  void _changeLanguage(AppSettingsNotifier settings, AppLocalizations l10n) {
    final targetLangName =
        settings.currentLanguageName == 'English' ? 'العربية' : 'English';
    final currentLangCode = Localizations.localeOf(context).languageCode;

    settings.toggleLanguage();

    if (context.mounted) {
      Navigator.of(context).pushReplacementNamed(
        '/settings',
        arguments: {
          'userType': widget.userType,
          'userId': widget.userId,
        },
      );
    }

    SnackHelper.success(
      context,
      currentLangCode == 'ar'
          ? 'تم التبديل إلى $targetLangName'
          : 'Language switched to $targetLangName',
    );
  }

  void _toggleNotifications(bool value) {
    setState(() => _isNotificationsEnabled = value);
    final currentLangCode = Localizations.localeOf(context).languageCode;

    final statusText = _isNotificationsEnabled
        ? (currentLangCode == 'ar' ? 'قيد التشغيل' : 'ON')
        : (currentLangCode == 'ar' ? 'متوقفة' : 'OFF');

    SnackHelper.success(
      context,
      currentLangCode == 'ar'
          ? 'الإشعارات الآن $statusText'
          : 'Notifications are $statusText',
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
    final currentLangIsArabic =
        Localizations.localeOf(context).languageCode == 'ar';

    final targetLangName = currentLangIsArabic ? 'English' : 'العربية';
    final currentLangName = currentLangIsArabic ? 'العربية' : 'English';

    return ThemedScaffold(
      appBar: AppBar(
        title: Text(l10n.settingsTitle,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            )),
        backgroundColor: _brandColor,
      ),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _fetchUserData(),
        builder: (context, snapshot) {
          final isLoading = snapshot.connectionState == ConnectionState.waiting;

          if (isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          return Padding(
            padding: const EdgeInsets.fromLTRB(20.0, 40.0, 20.0, 25.0),
            child: ListView(
              children: [
                SettingsSectionCard(
                  child: _SettingsSwitchItem(
                    icon: Icons.language,
                    iconColor: Colors.blue,
                    title: l10n.switchLanguage(targetLangName),
                    value: settings.locale.languageCode == 'ar',
                    onChanged: (value) => _changeLanguage(settings, l10n),
                    switchColor: _brandColor,
                    subtitle: Text(l10n.currentLanguage(currentLangName)),
                    isTitleBold: true,
                  ),
                ),
                SettingsSectionCard(
                  child: _SettingsSwitchItem(
                    title: l10n.themeOption,
                    icon: Icons.light_mode,
                    iconColor: Colors.orange,
                    value: settings.themeMode == ThemeMode.dark,
                    onChanged: (value) => _toggleTheme(settings, value),
                    switchColor: _brandColor,
                    isTitleBold: true,
                    subtitle: Text(
                      settings.themeMode == ThemeMode.dark
                          ? (currentLangIsArabic ? 'الوضع الداكن' : 'Dark Mode')
                          : (currentLangIsArabic
                              ? 'الوضع الفاتح'
                              : 'Light Mode'),
                    ),
                  ),
                ),
                SettingsSectionCard(
                  child: _SettingsSwitchItem(
                    title: l10n.notificationsOption,
                    icon: Icons.notifications_none,
                    iconColor: Colors.purple,
                    value: _isNotificationsEnabled,
                    onChanged: _toggleNotifications,
                    switchColor: _brandColor,
                    subtitle: Text(l10n.manageAlertsSubtitle),
                    isTitleBold: true,
                  ),
                ),
                SettingsSectionCard(
                  child: _SettingsItem(
                    title: l10n.changePasswordOption,
                    icon: Icons.lock_outline,
                    iconColor: _brandColor,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () =>
                        Navigator.pushNamed(context, '/change-password'),
                    subtitle: Text(l10n.resetPasswordSubtitle),
                    isTitleBold: true,
                  ),
                ),
                SettingsSectionCard(
                  child: _SettingsItem(
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
                          'userType': widget.userType,
                        },
                      );
                    },
                    subtitle: Text(l10n.viewOnlyText),
                    isTitleBold: true,
                  ),
                ),
                SettingsSectionCard(
                  child: _SettingsItem(
                    title: currentLangIsArabic ? 'حول التطبيق' : 'About',
                    icon: Icons.info_outline,
                    iconColor: Colors.lightGreen,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pushNamed(
                      context,
                      '/about',
                    ),
                    subtitle: Text(
                      currentLangIsArabic
                          ? 'إصدار التطبيق والمعلومات'
                          : 'App version and information',
                    ),
                    isTitleBold: true,
                  ),
                ),
                SettingsSectionCard(
                  child: _SettingsItem(
                    title: l10n.logoutOption,
                    icon: Icons.logout,
                    iconColor: Colors.red,
                    onTap: () => _handleLogout(context),
                    isTitleBold: true,
                  ),
                ),
                SettingsSectionCard(
                  child: _SettingsItem(
                    title: currentLangIsArabic
                        ? (widget.userType == 'JobSeeker'
                            ? 'حذف الحساب نهائيًا'
                            : 'حذف حساب الشركة نهائيًا')
                        : (widget.userType == 'JobSeeker'
                            ? 'Delete Account'
                            : 'Delete Company Account'),
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
                      currentLangIsArabic
                          ? (widget.userType == 'JobSeeker'
                              ? 'سيتم حذف بياناتك وجميع نشاطاتك نهائيًا'
                              : 'سيتم حذف بيانات الشركة وجميع الوظائف والمتقدمين المرتبطين بها')
                          : (widget.userType == 'JobSeeker'
                              ? 'Permanently delete your account and all related data'
                              : 'Permanently delete your company account and related data'),
                    ),
                    isTitleBold: true,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/* ----------------------------------------------------------------------
   Card wrapper widget to give each setting its own rounded card
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
   Single tap item (no switch)
---------------------------------------------------------------------- */
class _SettingsItem extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final Widget? trailing;
  final VoidCallback onTap;
  final Widget? subtitle;
  final bool isTitleBold;

  static const Color _brandColor = Color(0xFF4A5FBC);

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
      hoverColor: _brandColor.withOpacity(0.05),
      child: ListTile(
        visualDensity: VisualDensity.compact,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
}

/* ----------------------------------------------------------------------
   Switch item (language / theme / notifications)
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
      hoverColor: const Color(0xFF4A5FBC).withOpacity(0.05),
      child: ListTile(
        visualDensity: VisualDensity.compact,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(icon, color: iconColor),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: isTitleBold ? FontWeight.bold : FontWeight.normal,
            color: Theme.of(context).textTheme.bodyLarge?.color,
          ),
        ),
        subtitle: subtitle,
        trailing: Theme(
          data: Theme.of(context).copyWith(
            switchTheme: SwitchThemeData(
              trackColor: MaterialStateProperty.resolveWith((states) {
                if (states.contains(MaterialState.selected)) {
                  return scheme.secondary;
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
                  return scheme.secondary;
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
