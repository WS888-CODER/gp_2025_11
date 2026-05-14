import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gp_2025_11/screens/admin_dashboard.dart';
import 'package:gp_2025_11/screens/company_home.dart';
import 'package:gp_2025_11/screens/jobseeker_home.dart';
import 'package:gp_2025_11/screens/welcome.dart';

class StartScreen extends StatefulWidget {
  @override
  _StartScreenState createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _splitController;
  late Animation<double> _splitAnimation;

  @override
  void initState() {
    super.initState();

    _splitController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _splitAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _splitController, curve: Curves.easeInOut),
    );

    _startAnimation();
  }

  void _startAnimation() async {
    await Future.delayed(const Duration(seconds: 3));
    _splitController.forward();
    await Future.delayed(const Duration(milliseconds: 1000));

    if (!mounted) return;

    // ← تحقق من حالة الـ Auth قبل التوجيه
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      // غير مسجل دخول → WelcomeScreen
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              const WelcomeScreen(),
          transitionDuration: Duration.zero,
        ),
      );
      return;
    }

    // مسجل دخول → اجلب بيانات المستخدم من Firestore
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(user.uid)
          .get();

      if (!mounted) return;

      if (!userDoc.exists) {
        // بيانات غير موجودة → سجّل خروج وارجع للـ Welcome
        await FirebaseAuth.instance.signOut();
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const WelcomeScreen(),
            transitionDuration: Duration.zero,
          ),
        );
        return;
      }

      final data = userDoc.data() as Map<String, dynamic>;
      final userType = (data['UserType'] ?? data['userType'] ?? '').toString();

      if (!mounted) return;

      // وجّه المستخدم حسب نوعه مباشرةً
      if (userType == 'JobSeeker') {
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => JobSeekerHome(userId: user.uid),
            transitionDuration: Duration.zero,
          ),
        );
      } else if (userType == 'Company') {
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => CompanyHome(companyId: user.uid),
            transitionDuration: Duration.zero,
          ),
        );
      } else if (userType == 'Admin') {
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => AdminDashboard(),
            transitionDuration: Duration.zero,
          ),
        );
      } else {
        // نوع غير معروف → WelcomeScreen
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const WelcomeScreen(),
            transitionDuration: Duration.zero,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      // خطأ في الشبكة → WelcomeScreen
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const WelcomeScreen(),
          transitionDuration: Duration.zero,
        ),
      );
    }
  }

  @override
  void dispose() {
    _splitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      body: AnimatedBuilder(
        animation: _splitAnimation,
        builder: (context, child) {
          return Stack(
            children: [
              Positioned(
                left: -_splitAnimation.value * screenWidth,
                top: 0,
                bottom: 0,
                width: screenWidth / 2,
                child: Container(
                  color: const Color(0xFF4A5FBC),
                  child: Stack(
                    children: [
                      Center(
                        child: Transform.translate(
                          offset: Offset(screenWidth / 4, 0),
                          child: Image.asset(
                            'assets/images/whiteLogo.png',
                            width: 400,
                            height: 400,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                right: -_splitAnimation.value * screenWidth,
                top: 0,
                bottom: 0,
                width: screenWidth / 2,
                child: Container(
                  color: const Color(0xFF4A5FBC),
                  child: Stack(
                    children: [
                      Center(
                        child: Transform.translate(
                          offset: Offset(-screenWidth / 4, 0),
                          child: Image.asset(
                            'assets/images/whiteLogo.png',
                            width: 400,
                            height: 400,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
