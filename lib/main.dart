import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:gp_2025_11/screens/notifications.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:gp_2025_11/screens/account_details.dart';
import 'package:gp_2025_11/screens/settings.dart';
import 'package:gp_2025_11/screens/company_profile.dart';
import 'package:gp_2025_11/screens/jobseeker_profile.dart';
import 'package:gp_2025_11/screens/about.dart';
import 'firebase_options.dart';
import 'config/theme.dart';
import 'screens/start.dart';
import 'screens/login.dart';
import 'screens/signup.dart';
import 'screens/otp_verification.dart';
import 'screens/forgot_password.dart';
import 'screens/change_password.dart';
import 'screens/admin_dashboard.dart';
import 'screens/job_posting.dart';
import 'screens/questions.dart';
import 'screens/job_post_details.dart';
import 'screens/jobseeker_home.dart';
import 'screens/company_home.dart';
import 'package:gp_2025_11/screens/favorites.dart';
import 'package:gp_2025_11/screens/cv_next_steps.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppSettingsNotifier(),
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
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      debugShowCheckedModeBanner: false,
      home: const AuthGate(),
      routes: {
        '/start': (context) => StartScreen(),
        '/login': (context) => LoginScreen(),
        '/signup': (context) => SignupScreen(),
        '/otp-verification': (context) => OTPVerificationScreen(),
        '/admin-dashboard': (context) => AdminDashboard(),
        '/job-posting': (context) => const JobPostingPage(),
        '/job_posting': (context) => const JobPostingPage(),
        '/questions': (context) => const QuestionsPage(),
        '/job-details-view': (context) => const JobDetailsView(),
        '/forgot-password': (context) => ForgotPasswordScreen(),
        '/change-password': (context) => ChangePasswordScreen(),
        '/profile/jobseeker': (context) => const JobSeekerProfile(),
        '/profile/company': (context) => const CompanyProfile(),
        '/favorites': (context) => const FavoritesPage(),
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
          final args = ModalRoute.of(context)!.settings.arguments
              as Map<String, dynamic>;
          return SettingsScreen(
            userType: args['userType'],
            userId: args['userId'],
          );
        },
        '/account-details': (context) {
          final args = ModalRoute.of(context)!.settings.arguments
              as Map<String, dynamic>;
          return AccountDetailsPage(
            userId: args['userId'],
            userType: args['userType'],
          );
        },
        '/cv-next-steps': (context) {
          final args = ModalRoute.of(context)!.settings.arguments
              as Map<String, dynamic>?;
          return CVNextStepsScreen(
            cvHistoryId: args?['cvHistoryId'],
            jobTitle: args?['jobTitle'],
            hasJobSelection: args?['hasJobSelection'] ?? false,
          );
        },
        '/about': (context) => const AboutPage(),
        '/notifications': (context) {
          return NotificationsPage();
        },
      },
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // ← المفتاح: انتظر Firebase يتحقق من الـ session
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // المستخدم مسجل دخول
        if (snapshot.hasData && snapshot.data != null) {
          return _buildHomeForUser(snapshot.data!);
        }

        // غير مسجل دخول
        return StartScreen();
      },
    );
  }

  Widget _buildHomeForUser(User user) {
    // اجلب نوع المستخدم من Firestore ووجّهه للصفحة الصحيحة
    return FutureBuilder<DocumentSnapshot>(
      future:
          FirebaseFirestore.instance.collection('Users').doc(user.uid).get(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!snap.hasData || !snap.data!.exists) {
          return StartScreen();
        }

        final data = snap.data!.data() as Map<String, dynamic>;
        final userType = (data['UserType'] ?? '').toString().toLowerCase();

        if (userType == 'company') {
          return CompanyHome(companyId: user.uid);
        } else if (userType == 'jobseeker') {
          return JobSeekerHome(userId: user.uid);
        } else if (userType == 'admin') {
          return AdminDashboard();
        }

        return StartScreen();
      },
    );
  }
}
