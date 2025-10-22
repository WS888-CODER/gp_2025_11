import 'package:flutter/material.dart';
import 'package:gp_2025_11/screens/login_screen.dart';
import 'package:gp_2025_11/screens/signup_screen.dart';
import 'dart:math';

class WelcomeScreen extends StatefulWidget {
  @override
  _WelcomeScreenState createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with TickerProviderStateMixin {
  List<AnimationController> _controllers = [];
  List<Animation<double>> _animations = [];
  List<Offset> _positions = [];
  List<int> _lastZones = []; // نحفظ آخر منطقة لكل أيقونة
  final Random _random = Random();
  final double _minDistance = 0.15;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
  }

  void _initializeAnimations() {
    for (int i = 0; i < 10; i++) {
      final controller = AnimationController(
        duration: Duration(
          milliseconds: 5000 + _random.nextInt(3000),
        ),
        vsync: this,
      );

      final animation = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: controller, curve: Curves.easeInOut),
      );

      _controllers.add(controller);
      _animations.add(animation);

      int initialZone = _random.nextInt(6);
      _lastZones.add(initialZone);
      _positions.add(_getRandomPositionInZone(initialZone));

      Future.delayed(Duration(milliseconds: i * 600), () {
        if (mounted) {
          _startAnimation(i);
        }
      });
    }
  }

  double _distance(Offset a, Offset b) {
    return sqrt(pow(a.dx - b.dx, 2) + pow(a.dy - b.dy, 2));
  }

  bool _isFarEnough(Offset newPosition, int currentIndex) {
    for (int i = 0; i < _positions.length; i++) {
      if (i != currentIndex && _animations[i].value > 0.3) {
        double dist = _distance(newPosition, _positions[i]);
        if (dist < _minDistance) {
          return false;
        }
      }
    }
    return true;
  }

  // دالة تختار منطقة جديدة مختلفة عن المنطقة السابقة
  int _getNewDifferentZone(int lastZone) {
    int newZone;
    do {
      newZone = _random.nextInt(6);
    } while (newZone == lastZone); // نتأكد إنها مختلفة عن السابقة
    return newZone;
  }

  Offset _getRandomPositionInZone(int zone) {
    double x, y;

    switch (zone) {
      case 0: // فوق يسار
        x = _random.nextDouble() * 0.25;
        y = _random.nextDouble() * 0.2;
        break;
      case 1: // فوق وسط
        x = 0.35 + _random.nextDouble() * 0.3;
        y = _random.nextDouble() * 0.15;
        break;
      case 2: // فوق يمين
        x = 0.75 + _random.nextDouble() * 0.2;
        y = _random.nextDouble() * 0.2;
        break;
      case 3: // تحت يسار
        x = _random.nextDouble() * 0.25;
        y = 0.8 + _random.nextDouble() * 0.15;
        break;
      case 4: // تحت وسط
        x = 0.35 + _random.nextDouble() * 0.3;
        y = 0.85 + _random.nextDouble() * 0.1;
        break;
      case 5: // تحت يمين
        x = 0.75 + _random.nextDouble() * 0.2;
        y = 0.8 + _random.nextDouble() * 0.15;
        break;
      default:
        x = _random.nextDouble() * 0.2;
        y = _random.nextDouble() * 0.2;
    }

    return Offset(x, y);
  }

  Offset _getRandomPositionWithoutOverlap(int index) {
    Offset position;
    int attempts = 0;
    int maxAttempts = 50;

    // نختار منطقة جديدة مختلفة تماماً عن المنطقة السابقة
    int newZone = _getNewDifferentZone(_lastZones[index]);
    _lastZones[index] = newZone; // نحدث آخر منطقة

    do {
      position = _getRandomPositionInZone(newZone);
      attempts++;
      if (attempts >= maxAttempts) break;
    } while (!_isFarEnough(position, index));

    return position;
  }

  void _startAnimation(int index) {
    _controllers[index].forward().then((_) {
      if (mounted) {
        Future.delayed(Duration(milliseconds: 2000 + _random.nextInt(1000)),
            () {
          if (mounted) {
            _controllers[index].reverse().then((_) {
              if (mounted) {
                setState(() {
                  // الموقع الجديد راح يكون في منطقة مختلفة تماماً
                  _positions[index] = _getRandomPositionWithoutOverlap(index);
                });
                Future.delayed(Duration(milliseconds: 500), () {
                  if (mounted) {
                    _startAnimation(index);
                  }
                });
              }
            });
          }
        });
      }
    });
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Color(0xFFF6F5FB),
      body: Stack(
        children: [
          ...List.generate(10, (index) {
            return AnimatedBuilder(
              animation: _animations[index],
              builder: (context, child) {
                return Positioned(
                  left: _positions[index].dx * screenWidth,
                  top: _positions[index].dy * screenHeight,
                  child: Opacity(
                    opacity: _animations[index].value,
                    child: Image.asset(
                      'assets/images/icon${index + 1}.png',
                      width: 80,
                      height: 80,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return SizedBox.shrink();
                      },
                    ),
                  ),
                );
              },
            );
          }),
          SafeArea(
            child: Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 32, vertical: 50),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 20,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.asset(
                            'assets/images/j_filled.png',
                            width: 70,
                            height: 100,
                            fit: BoxFit.contain,
                          ),
                          SizedBox(width: 8),
                          Image.asset(
                            'assets/images/adeer_text.png',
                            width: 150,
                            height: 70,
                            fit: BoxFit.contain,
                          ),
                        ],
                      ),
                      SizedBox(height: 40),
                      Text(
                        'Welcome',
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF4A5FBC),
                          letterSpacing: 1.2,
                        ),
                      ),
                      SizedBox(height: 50),
                      Container(
                        width: double.infinity,
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFFFF7B7B), Color(0xFFFF9A6B)],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: Color(0xFFFF7B7B).withOpacity(0.3),
                              blurRadius: 12,
                              offset: Offset(0, 6),
                            ),
                          ],
                        ),
                        child: TextButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => SignupScreen()),
                            );
                          },
                          style: TextButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28),
                            ),
                          ),
                          child: Text(
                            'Create Account',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFFFF7B7B), Color(0xFFFF9A6B)],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: Color(0xFFFF7B7B).withOpacity(0.3),
                              blurRadius: 12,
                              offset: Offset(0, 6),
                            ),
                          ],
                        ),
                        child: TextButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => LoginScreen()),
                            );
                          },
                          style: TextButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28),
                            ),
                          ),
                          child: Text(
                            'Log In',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
