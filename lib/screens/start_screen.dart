import 'package:flutter/material.dart';
import 'dart:async';
import 'package:gp_2025_11/screens/welcome_screen.dart';

class StartScreen extends StatefulWidget {
  @override
  _StartScreenState createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen>
    with TickerProviderStateMixin {
  late AnimationController _jController;
  late AnimationController _textController;
  late AnimationController _sloganController;
  late AnimationController _transitionController;

  late Animation<double> _jScaleAnimation;
  late Animation<double> _jFadeAnimation;
  late Animation<double> _jSlideAnimation;
  late Animation<double> _textFadeAnimation;
  late Animation<double> _sloganFadeAnimation;

  bool _showOutline = true;
  bool _showFilled = false;
  bool _showText = false;
  bool _showSlogan = false;

  @override
  void initState() {
    super.initState();

    _jController = AnimationController(
      duration: Duration(milliseconds: 1200),
      vsync: this,
    );

    _textController = AnimationController(
      duration: Duration(milliseconds: 800),
      vsync: this,
    );

    _sloganController = AnimationController(
      duration: Duration(milliseconds: 600),
      vsync: this,
    );

    _transitionController = AnimationController(
      duration: Duration(milliseconds: 500),
      vsync: this,
    );

    _jScaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _jController, curve: Curves.easeOutBack),
    );

    _jFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _jController, curve: Curves.easeIn),
    );

    _jSlideAnimation = Tween<double>(begin: 0.0, end: -40.0).animate(
      CurvedAnimation(parent: _textController, curve: Curves.easeInOut),
    );

    _textFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _textController, curve: Curves.easeIn),
    );

    _sloganFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _sloganController, curve: Curves.easeIn),
    );

    _startAnimation();
  }

  void _startAnimation() async {
    await Future.delayed(Duration(milliseconds: 500));
    _jController.forward();

    await Future.delayed(Duration(milliseconds: 1500));
    setState(() {
      _showOutline = false;
      _showFilled = true;
    });

    await Future.delayed(Duration(milliseconds: 800));
    setState(() {
      _showText = true;
    });
    _textController.forward();

    await Future.delayed(Duration(milliseconds: 1200));
    setState(() {
      _showSlogan = true;
    });
    _sloganController.forward();

    await Future.delayed(
        Duration(milliseconds: 4500)); // زيادة المدة من 1200 إلى 2500
    _navigateToLogin();
  }

  void _navigateToLogin() {
    _transitionController.forward().then((_) {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              WelcomeScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: Duration(milliseconds: 500),
        ),
      );
    });
  }

  @override
  void dispose() {
    _jController.dispose();
    _textController.dispose();
    _sloganController.dispose();
    _transitionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF8785C9), // بنفسجي فاتح
              Color(0xFFFAFAFA), // أبيض (وسط الشاشة)
              Color(0xFFFAFAFA), // أبيض
              Color(0xFF4A5FBC), // بنفسجي غامق
              Color(0xFFFF7B7B), // برتقالي/وردي
            ],
            stops: [0.0, 0.3, 0.7, 0.85, 1.0],
          ),
        ),
        child: AnimatedBuilder(
          animation: Listenable.merge([
            _jController,
            _textController,
            _sloganController,
            _transitionController
          ]),
          builder: (context, child) {
            return Opacity(
              opacity: 1.0 - _transitionController.value,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Transform.translate(
                          offset: Offset(_jSlideAnimation.value, 0),
                          child: Transform.scale(
                            scale: _jScaleAnimation.value,
                            child: Opacity(
                              opacity: _jFadeAnimation.value,
                              child: SizedBox(
                                width: 100,
                                height: 140,
                                child: Stack(
                                  children: [
                                    if (_showOutline)
                                      Image.asset(
                                        'assets/images/j_outline.png',
                                        fit: BoxFit.contain,
                                      ),
                                    if (_showFilled)
                                      AnimatedOpacity(
                                        opacity: _showFilled ? 1.0 : 0.0,
                                        duration: Duration(milliseconds: 600),
                                        child: Image.asset(
                                          'assets/images/j_filled.png',
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (_showText)
                          Opacity(
                            opacity: _textFadeAnimation.value,
                            child: Transform.translate(
                              offset: Offset(
                                  (1 - _textFadeAnimation.value) * 50 -
                                      35, // تعديل هنا: أضفنا -35 لتقريب النص أكثر
                                  0),
                              child: Image.asset(
                                'assets/images/adeer_text.png',
                                width: 180,
                                height: 80,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (_showSlogan)
                      Opacity(
                        opacity: _sloganFadeAnimation.value,
                        child: Padding(
                          padding: EdgeInsets.only(top: 20),
                          child: Text(
                            'منصة التوظيف الذكية',
                            style: TextStyle(
                              fontSize: 18,
                              color: Color(0xFF4A5FBC),
                              fontWeight: FontWeight.w500,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
