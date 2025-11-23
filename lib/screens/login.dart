import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:gp_2025_11/config/theme.dart';
import 'package:gp_2025_11/screens/welcome.dart';

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;

  // Ã°Å¸â€â€™ Error message variable
  String? _loginError;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ðŸ”’ Dialog for locked accounts using JadeerDialog
  Future<void> _showPasswordResetRequiredDialog(String userType) async {
    final bool isAdmin = userType == 'Admin';

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => WillPopScope(
        onWillPop: () async => false,
        child: JadeerDialog<String>(
          title: 'Account Locked',
          content: Text(
            isAdmin
                ? 'You have entered an incorrect password 5 times today.\n\n'
                    'For security reasons, please contact the system administrator to unlock your account.'
                : 'You have entered an incorrect password 5 times today.\n\n'
                    'For security reasons, you must reset your password before you can access your account again.',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
            ),
            textAlign: TextAlign.center,
          ),
          // Ø§Ù„Ø£Ø²Ø±Ø§Ø±:
          primaryLabel: isAdmin ? 'OK' : 'Reset Password',
          primaryResult: isAdmin ? 'ok' : 'reset',
          // Ù…Ø§ Ù†Ø­ØªØ§Ø¬ Ø²Ø± Ø«Ø§Ù†ÙŠ Ù‡Ù†Ø§ (Ù†ÙØ³ Ø§Ù„Ø³Ù„ÙˆÙƒ Ø§Ù„Ù‚Ø¯ÙŠÙ…)
          secondaryLabel: null,
          secondaryResult: null,
        ),
      ),
    );

    if (!mounted) return;

    if (isAdmin) {
      // ÙƒØ§Ù† Ø²Ù…Ø§Ù† Ø²Ø± OK ÙŠÙ‚ÙÙ„ Ø§Ù„Ø¯ÙŠØ§Ù„ÙˆØº ÙˆÙŠØ±Ø¬Ø¹ Ù„Ù„ØµÙØ­Ø© Ø§Ù„Ù„ÙŠ Ù‚Ø¨Ù„
      if (result == 'ok') {
        Navigator.of(context).pop();
      }
    } else {
      // ÙƒØ§Ù† Ø²Ù…Ø§Ù† Ø²Ø± Reset Password ÙŠÙˆØ¯Ù‘ÙŠ Ù„ØµÙØ­Ø© Ù†Ø³ÙŠØ§Ù† ÙƒÙ„Ù…Ø© Ø§Ù„Ø³Ø±
      if (result == 'reset') {
        Navigator.pushReplacementNamed(
          context,
          '/forgot-password',
          arguments: {'email': _emailController.text.trim()},
        );
      }
    }
  }

  String _generateOTP() {
    final random = Random();
    return (100000 + random.nextInt(900000)).toString();
  }

  Future<bool> _sendOTPEmail(String email, String otp) async {
    try {
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final callable = functions.httpsCallable('sendAdminOtp');

      final result = await callable.call({
        'email': email.trim(),
        'otp': otp.trim(),
      });

      if (result.data != null && result.data['success'] == true) {
        await _firestore.collection('AdminOTPs').doc(email).set({
          'OTP': otp,
          'Email': email,
          'CreatedAt': FieldValue.serverTimestamp(),
          'ExpiresAt': Timestamp.fromDate(
            DateTime.now().add(const Duration(minutes: 2)),
          ),
          'Used': false,
        });
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  // Ã°Å¸â€â€™ Check account lock status
  Future<Map<String, dynamic>?> _checkAccountLockStatus(String email) async {
    try {
      final querySnapshot = await _firestore
          .collection('Users')
          .where('Email', isEqualTo: email.trim().toLowerCase())
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) return null;

      final userId = querySnapshot.docs.first.id;
      final data = querySnapshot.docs.first.data();

      final mustResetPassword = data['mustResetPassword'] ?? false;
      final accountLocked = data['accountLocked'] ?? false;

      if (mustResetPassword || accountLocked) {
        return {
          'locked': true,
          'userId': userId,
          'userType': data['UserType'] ?? data['userType'] ?? '',
        };
      }

      final failedAttempts = data['failedLoginAttempts'] ?? 0;
      final lastFailedLoginDate = data['lastFailedLoginDate'] as Timestamp?;

      if (failedAttempts >= 5 && lastFailedLoginDate != null) {
        final lastFailedDate = lastFailedLoginDate.toDate();
        final now = DateTime.now();
        final isToday = lastFailedDate.year == now.year &&
            lastFailedDate.month == now.month &&
            lastFailedDate.day == now.day;

        if (isToday) {
          await _firestore.collection('Users').doc(userId).update({
            'accountLocked': true,
            'mustResetPassword': true,
          });
          return {
            'locked': true,
            'userId': userId,
            'userType': data['UserType'] ?? data['userType'] ?? '',
          };
        } else {
          await _firestore.collection('Users').doc(userId).update({
            'failedLoginAttempts': 0,
            'lastFailedLoginDate': null,
            'accountLocked': false,
            'mustResetPassword': false,
          });
        }
      }

      return {
        'locked': false,
        'userId': userId,
        'userType': data['UserType'] ?? data['userType'] ?? '',
        'failedAttempts': failedAttempts,
      };
    } catch (e) {
      print('Ã¢ÂÅ’ Error checking account lock status: $e');
      return null;
    }
  }

  // Ã°Å¸â€â€™ Record failed login attempt
  Future<void> _recordFailedLoginAttempt(String email) async {
    try {
      final querySnapshot = await _firestore
          .collection('Users')
          .where('Email', isEqualTo: email.trim().toLowerCase())
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        // Ã¢Å“â€¦ Ã˜Â§Ã™â€žÃ˜Â¥Ã™Å Ã™â€¦Ã™Å Ã™â€ž Ã™â€¦Ã™Ë† Ã™â€¦Ã™Ë†Ã˜Â¬Ã™Ë†Ã˜Â¯Ã˜Å’ Ã˜Â¨Ã˜Â³ Ã™â€ Ã˜Â¹Ã˜Â±Ã˜Â¶ Ã˜Â±Ã˜Â³Ã˜Â§Ã™â€žÃ˜Â© Ã˜Â¹Ã˜Â§Ã™â€¦Ã˜Â©
        if (mounted) {
          setState(() {
            _loginError = 'Invalid credentials. Please try again.';
          });
        }
        return;
      }

      final userId = querySnapshot.docs.first.id;
      final data = querySnapshot.docs.first.data();

      final failedAttempts = data['failedLoginAttempts'] ?? 0;
      final lastFailedLoginDate = data['lastFailedLoginDate'] as Timestamp?;

      final now = DateTime.now();
      bool resetCounter = false;

      if (lastFailedLoginDate != null) {
        final lastDate = lastFailedLoginDate.toDate();
        if (lastDate.year != now.year ||
            lastDate.month != now.month ||
            lastDate.day != now.day) {
          resetCounter = true;
        }
      }

      final newFailedAttempts = resetCounter ? 1 : failedAttempts + 1;

      // Ã¢Å“â€¦ Update Firestore Ã˜Â£Ã™Ë†Ã™â€žÃ˜Â§Ã™â€¹
      await _firestore.collection('Users').doc(userId).update({
        'failedLoginAttempts': newFailedAttempts,
        'lastFailedLoginDate': FieldValue.serverTimestamp(),
        'accountLocked': newFailedAttempts >= 5,
        'mustResetPassword': newFailedAttempts >= 5,
      });

      print(
          'Ã¢Å“â€¦ Updated failedLoginAttempts to: $newFailedAttempts for user: $userId');

      // Ã¢Å“â€¦ Update UI Ã˜Â¨Ã˜Â¹Ã˜Â¯Ã™Å Ã™â€
      if (mounted) {
        if (newFailedAttempts == 3 || newFailedAttempts == 4) {
          final remaining = 5 - newFailedAttempts;
          setState(() {
            _loginError =
                'Invalid credentials. You have $remaining attempt${remaining > 1 ? 's' : ''} remaining before your account is locked.';
          });
        } else if (newFailedAttempts >= 5) {
          setState(() {
            _loginError = 'Account locked due to multiple failed attempts.';
          });

          // Ã¢Å“â€¦ Show dialog for locked account
          final userType = data['UserType'] ?? data['userType'] ?? '';
          Future.delayed(Duration(milliseconds: 100), () {
            if (mounted) {
              _showPasswordResetRequiredDialog(userType);
            }
          });
        } else {
          setState(() {
            _loginError = 'Invalid credentials. Please try again.';
          });
        }
      }
    } catch (e) {
      print('Ã¢ÂÅ’ Error recording failed login: $e');
      if (mounted) {
        setState(() {
          _loginError = 'An error occurred. Please try again.';
        });
      }
    }
  }

  // Ã°Å¸â€â€™ Reset failed login attempts
  Future<void> _resetFailedLoginAttempts(String userId) async {
    try {
      await _firestore.collection('Users').doc(userId).update({
        'failedLoginAttempts': 0,
        'lastFailedLoginDate': null,
        'accountLocked': false,
        'mustResetPassword': false,
      });
    } catch (e) {
      print('Ã¢ÂÅ’ Error resetting failed attempts: $e');
    }
  }

  Future<void> _handleLogin() async {
    // Ã°Å¸â€â€™ Clear previous error
    setState(() {
      _loginError = null;
    });

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // Ã°Å¸â€â€™ STEP 1: Check if account is locked
      final lockStatus =
          await _checkAccountLockStatus(_emailController.text.trim());

      if (lockStatus != null && lockStatus['locked'] == true) {
        setState(() => _isLoading = false);
        _showPasswordResetRequiredDialog(lockStatus['userType'] ?? '');
        return;
      }

      // ðŸ”’ STEP 2: Check if user exists and if Company, check status BEFORE password verification
      final userQuery = await _firestore
          .collection('Users')
          .where('Email', isEqualTo: _emailController.text.trim().toLowerCase())
          .limit(1)
          .get();

      if (userQuery.docs.isNotEmpty) {
        final userData = userQuery.docs.first.data();
        final userType = userData['UserType'] ?? userData['userType'] ?? '';

        // If Company, check status before attempting password verification
        if (userType == 'Company') {
          final accountStatus = userData['AccountStatus'] ??
              userData['accountStatus'] ??
              'Pending';

          if (accountStatus == 'Pending') {
            setState(() {
              _loginError =
                  'Your account is pending approval from admin. Please wait.';
              _isLoading = false;
            });
            return;
          } else if (accountStatus == 'Rejected') {
            setState(() {
              _loginError = 'Your account has been rejected. Contact support.';
              _isLoading = false;
            });
            return;
          }
        }
      }

      // ðŸ”’ STEP 3: Now attempt password verification
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final userId = userCredential.user!.uid;

      // Ã°Å¸â€â€™ Reset failed attempts on successful login
      await _resetFailedLoginAttempts(userId);

      final userDoc = await _firestore.collection('Users').doc(userId).get();
      if (!userDoc.exists) {
        await _auth.signOut();
        setState(() {
          _loginError = 'User data not found';
        });
        setState(() => _isLoading = false);
        return;
      }

      final data = userDoc.data() as Map<String, dynamic>;
      final userType = data['UserType'] ?? data['userType'] ?? '';

      final isEmailVerified =
          data['IsEmailVerified'] ?? data['isEmailVerified'] ?? false;
      final accountStatus =
          data['AccountStatus'] ?? data['accountStatus'] ?? 'Pending';

      if (userType == 'Admin') {
        final otp = _generateOTP();
        final ok = await _sendOTPEmail(_emailController.text.trim(), otp);
        if (ok) {
          SnackHelper.success(context, 'Verification code sent to your email');
          Navigator.pushReplacementNamed(
            context,
            '/otp-verification',
            arguments: {
              'email': _emailController.text.trim(),
              'userId': userId
            },
          );
        } else {
          await _auth.signOut();
          setState(() {
            _loginError =
                'Failed to send verification code. Please try again later.';
          });
        }
        setState(() => _isLoading = false);
        return;
      }

      if (userType == 'JobSeeker') {
        if (isEmailVerified) {
          Navigator.pushReplacementNamed(
            context,
            '/jobseeker-home',
            arguments: {'userId': userId},
          );
        } else {
          await _auth.signOut();
          setState(() {
            _loginError = 'Please verify your email first. Check your inbox.';
          });
        }
        setState(() => _isLoading = false);
        return;
      }

      if (userType == 'Company') {
        if (!isEmailVerified) {
          await _auth.signOut();
          setState(() {
            _loginError = 'Please verify your email first. Check your inbox.';
          });
        } else if (accountStatus == 'Verified') {
          Navigator.pushReplacementNamed(
            context,
            '/company-home',
            arguments: {'companyId': userId},
          );
        }
        // Note: pending/rejected cases are now checked BEFORE password verification
        setState(() => _isLoading = false);
        return;
      }

      await _auth.signOut();
      setState(() {
        _loginError = 'Unknown user type: "$userType"';
      });
    } on FirebaseAuthException catch (e) {
      print('Ã°Å¸â€Â´ FirebaseAuthException: ${e.code} - ${e.message}');

      // Ã°Å¸â€â€™ Handle different error types
      if (e.code == 'user-not-found') {
        // Email doesn't exist - show error but DON'T record attempt
        if (mounted) {
          setState(() {
            _loginError = 'Invalid credentials. Please try again.';
          });
        }
      } else if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        // Wrong password - record the failed attempt
        print('Ã°Å¸â€Â´ Wrong password detected, recording attempt...');
        await _recordFailedLoginAttempt(_emailController.text.trim());
      } else {
        if (mounted) {
          setState(() {
            if (e.code == 'invalid-email') {
              _loginError = 'Invalid email format';
            } else if (e.code == 'user-disabled') {
              _loginError = 'This account has been disabled';
            } else {
              _loginError = 'An error occurred during login';
            }
          });
        }
      }
    } catch (e) {
      print('Ã¢ÂÅ’ Unexpected error: $e');
      if (mounted) {
        setState(() {
          _loginError = 'Unexpected error. Please try again.';
        });
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SizedBox.expand(
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/images/office.png',
                fit: BoxFit.cover,
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: MediaQuery.of(context).size.height * 0.75,
              child: CustomPaint(
                painter: WavePainter(),
              ),
            ),
            Positioned(
              top: 50,
              right: 30,
              child: Image.asset(
                'assets/images/j_filled.png',
                width: 60,
                height: 80,
                fit: BoxFit.contain,
              ),
            ),
            SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 360),
                        const Text(
                          'Log In',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 40),
                        const Text(
                          'Email',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Enter your email',
                            hintStyle:
                                TextStyle(color: Colors.white.withOpacity(0.6)),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                  color: Colors.white.withOpacity(0.5)),
                            ),
                            focusedBorder: const UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.white),
                            ),
                            errorBorder: const UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.red),
                            ),
                            focusedErrorBorder: const UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.red),
                            ),
                            errorStyle: const TextStyle(
                                color: Colors.red, fontWeight: FontWeight.bold),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty)
                              return 'Please enter your email';
                            if (!v.contains('@'))
                              return 'Please enter a valid email';
                            return null;
                          },
                          onChanged: (_) {
                            if (_loginError != null) {
                              setState(() => _loginError = null);
                            }
                          },
                        ),
                        const SizedBox(height: 30),
                        const Text(
                          'Password',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Enter your password',
                            hintStyle:
                                TextStyle(color: Colors.white.withOpacity(0.6)),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                  color: _loginError != null
                                      ? Colors.red
                                      : Colors.white.withOpacity(0.5)),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                  color: _loginError != null
                                      ? Colors.red
                                      : Colors.white),
                            ),
                            errorBorder: const UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.red),
                            ),
                            focusedErrorBorder: const UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.red),
                            ),
                            errorStyle: const TextStyle(
                                color: Colors.red, fontWeight: FontWeight.bold),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: Colors.white,
                              ),
                              onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return 'Please enter your password';
                            }
                            return null;
                          },
                          onChanged: (_) {
                            if (_loginError != null) {
                              setState(() => _loginError = null);
                            }
                          },
                        ),
                        // Ã°Å¸â€â€™ Show error under password field
                        if (_loginError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              _loginError!,
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.centerRight,
                          child: GestureDetector(
                            onTap: () => Navigator.pushNamed(
                                context, '/forgot-password'),
                            child: const Text(
                              'Forgot Password?',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 60),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Container(
                            width: 45,
                            height: 45,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              onPressed: _isLoading ? null : _handleLogin,
                              icon: _isLoading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.arrow_forward,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 50,
              left: 30,
              child: IconButton(
                padding: EdgeInsets.zero,
                onPressed: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  } else {
                    // If no previous route (e.g., after logout), go to welcome
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (context) => WelcomeScreen()),
                    );
                  }
                },
                icon: const Icon(
                  Icons.arrow_back,
                  color: Color(0xFFFF7B7B),
                  size: 32,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF4A5FBC).withOpacity(0.7)
      ..style = PaintingStyle.fill;

    final path = Path();

    path.moveTo(0, size.height);
    path.lineTo(0, size.height * 0.3);

    path.quadraticBezierTo(
      size.width * 0.25,
      size.height * 0.15,
      size.width * 0.5,
      size.height * 0.2,
    );

    path.quadraticBezierTo(
      size.width * 0.75,
      size.height * 0.25,
      size.width,
      size.height * 0.15,
    );

    path.lineTo(size.width, size.height);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
