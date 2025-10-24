// lib/screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:gp_2025_11/config/app_settings_notifier.dart';
// ⬇️ استيراد مكتبة الترجمة التي سيتم إنشاؤها
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
  
  Future<void> _handleLogout(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!; // استيراد الترجمة

    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          l10n.logoutOption,
          textAlign: TextAlign.center,
        ),
        content: const Text(
          'Are you sure you want to log out?',
          textAlign: TextAlign.center,
        ),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xFFF6F5FB),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xFFFC686A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: Text(l10n.logoutOption),
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

  // منطق تغيير اللغة والثيم
  void _toggleTheme(AppSettingsNotifier settings) {
    ThemeMode newMode = settings.themeMode == ThemeMode.light 
        ? ThemeMode.dark 
        : ThemeMode.light;
    settings.toggleTheme(newMode);
    ScaffoldMessenger.of(context).showSnackBar(
       SnackBar(content: Text('Theme changed to ${newMode == ThemeMode.light ? "Light" : "Dark"}')),
    );
  }
  
  void _changeLanguage(AppSettingsNotifier settings) async {
    final l10n = AppLocalizations.of(context)!;
    final newLang = settings.currentLanguageName == 'English' ? 'Arabic' : 'English';
    
    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          l10n.languageOption,
          textAlign: TextAlign.center,
        ),
        content: Text(
          'Are you sure you want to switch to $newLang?',
          textAlign: TextAlign.center,
        ),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xFFF6F5FB),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xFF4A5FBC),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      settings.toggleLanguage(); // سيؤدي إلى إعادة بناء MaterialApp
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Language switched to ${settings.currentLanguageName}')),
      );
    }
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
    Color brandColor = const Color(0xFF4A5FBC);
    
    // ⬇️ قراءة حالة الإعدادات والترجمة
    final settings = Provider.of<AppSettingsNotifier>(context);
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F6FC),
      appBar: AppBar(
        title: Text(l10n.settingsTitle), // استخدام الترجمة
        backgroundColor: brandColor,
      ),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _fetchUserData(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          final userData = snapshot.data ?? {};
          
          final mainName = isJobSeeker
              ? (userData['Name'] ?? l10n.fullNameLabel)
              : (userData['CompanyName'] ?? l10n.companyNameLabel);
          final email = userData['Email'] ?? 'N/A';
          final phone = userData['Phone'] ?? 'N/A';
          
          String displayPhone = phone.startsWith('+966') ? '0${phone.substring(4)}' : phone;
          
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

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 1. قسم الإعدادات العامة
              _SectionTitle(l10n.generalSettingsSection),
              
              // 1.1 اللغة 
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.language, color: Colors.blue),
                  title: Text(l10n.languageOption),
                  subtitle: Text(settings.currentLanguageName),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _changeLanguage(settings),
                ),
              ),

              // 1.2 الثيم 
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.light_mode_outlined, color: Colors.orange),
                  title: Text(l10n.themeOption),
                  subtitle: Text(settings.themeMode == ThemeMode.light ? 'Light Mode' : 'Dark Mode'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _toggleTheme(settings),
                ),
              ),

              // 1.3 الإشعارات
              Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: ListTile(
                  leading: const Icon(Icons.notifications_outlined, color: Colors.purple),
                  title: Text(l10n.notificationsOption),
                  subtitle: Text(l10n.manageAlertsSubtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                     ScaffoldMessenger.of(context).showSnackBar(
                       const SnackBar(content: Text('Notification settings: Future feature.')),
                     );
                  },
                ),
              ),
              


              // 2. قسم الحساب والأمان
              _SectionTitle(l10n.accountSecuritySection),
              
              // 2.1 تغيير كلمة المرور
              Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: ListTile(
                  leading: const Icon(Icons.lock_outline, color: Color(0xFF4A5FBC)),
                  title: Text(l10n.changePasswordOption),
                  subtitle: Text(l10n.resetPasswordSubtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pushNamed(context, '/forgot-password');
                  },
                ),
              ),

              // 2.2 حالة توثيق الشركة
              if (!isJobSeeker)
                Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: ListTile(
                    leading: Icon(Icons.verified_user_outlined, color: statusColor),
                    title: Text(l10n.accountVerificationStatus),
                    subtitle: Text(accountStatus),
                    trailing: Text(
                      l10n.viewOnlyText,
                      style: TextStyle(
                          color: statusColor, fontWeight: FontWeight.bold),
                    ),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content:
                                Text('Verification status managed by Admin.')),
                      );
                    },
                  ),
                ),
              
              // 2.3 معلومات الحساب (Account Details)
              _SectionTitle(l10n.myAccountDetailsSection),
              
              Card(
                margin: const EdgeInsets.only(bottom: 30),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.account_circle, color: Colors.teal),
                      title: Text(isJobSeeker ? l10n.fullNameLabel : l10n.companyNameLabel),
                      subtitle: Text(mainName, style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    ListTile(
                      leading: const Icon(Icons.email_outlined, color: Colors.teal),
                      title: Text(l10n.registeredEmailLabel),
                      subtitle: Text(email),
                    ),
                    ListTile(
                      leading: const Icon(Icons.phone_outlined, color: Colors.teal),
                      title: Text(l10n.contactPhoneLabel),
                      subtitle: Text(displayPhone),
                    ),
                  ],
                ),
              ),

              // 3. تسجيل الخروج
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: Text(l10n.logoutOption, style: TextStyle(color: Colors.red)),
                onTap: () => _handleLogout(context),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ويدجت عنوان القسم
class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.grey[700],
        ),
      ),
    );
  }
}