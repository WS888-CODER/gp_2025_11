// lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:gp_2025_11/config/app_settings_notifier.dart';

// ⬇️ الاستيراد الصحيح للمكتبات القياسية
import 'package:flutter_localizations/flutter_localizations.dart'; 
// ⬇️ استبدال استيراد app_localizations.dart بمسار محلي قسري
import 'package:gp_2025_11/l10n/app_localizations.dart'; 

import 'package:gp_2025_11/screens/company_profile_page.dart';
import 'package:gp_2025_11/screens/job_seeker_profile_page.dart';
import 'firebase_options.dart';
import 'config/theme.dart';
import 'screens/start_screen.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/otp_verification_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'screens/admin_dashboard.dart';
import 'screens/job_posting_page.dart';
import 'screens/jobseeker_home.dart';
import 'screens/company_home.dart';
import 'screens/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(
    ChangeNotifierProvider(
      create: (context) => AppSettingsNotifier(),
      child: const Jadeer(),
    ),
  );
}

class Jadeer extends StatelessWidget {
  const Jadeer({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsNotifier>(context);

    return MaterialApp(
      title: 'Jadeer',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: settings.themeMode,
      
      // تفويضات الترجمة: تتضمن تفويض الترجمة المُخصص
      localizationsDelegates: const [
        AppLocalizations.delegate, // ⬅️ التفويض الذي يترجم النصوص الثابتة
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      
      locale: settings.locale, 
      supportedLocales: AppLocalizations.supportedLocales, 
      
      debugShowCheckedModeBanner: false,
      home: StartScreen(),
      routes: {
        '/start': (context) => StartScreen(),
        '/login': (context) => LoginScreen(),
        '/signup': (context) => SignupScreen(),
        '/otp-verification': (context) => OTPVerificationScreen(),
        '/admin-dashboard': (context) => AdminDashboard(),
        '/job-posting': (context) => const JobPostingPage(),
        '/forgot-password': (context) => ForgotPasswordScreen(),
        '/profile/jobseeker': (context) => const JobSeekerProfile(),
        '/profile/company': (context) => const CompanyProfile(),
        '/jobseeker-home': (context) {
          final args = ModalRoute.of(context)!.settings.arguments
              as Map<String, dynamic>?;
          return JobSeekerHome(userId: args?['userId']);
        },
        '/company-home': (context) {
          final args = ModalRoute.of(context)!.settings.arguments
              as Map<String, dynamic>?;
          return CompanyHome(companyId: args?['companyId']);
        },
        '/settings': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
          return SettingsScreen(
            userType: args['userType'],
            userId: args['userId'],
          );
        },
      },
    );
  }
}