import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const Jadeer());
}

class Jadeer extends StatelessWidget {
  const Jadeer({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jadeer',
      theme: AppTheme.lightTheme,
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
        '/profile/jobseeker': (context) => const JobSeekerProfileLite(),
        '/profile/company': (context) => const CompanyProfileLite(),
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
      },
    );
  }
}
