import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

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

  // 🔒 ONLY ADDITION 1: Error message variable
  String? _loginError;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.error_outline, color: Colors.red, size: 28),
            SizedBox(width: 10),
            Text('Error', style: TextStyle(color: Colors.red)),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK', style: TextStyle(color: Color(0xFF4A5FBC))),
          ),
        ],
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        backgroundColor: Color(0xFFFF7B7B).withOpacity(0.8),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  // 🔒 ONLY ADDITION 2: Dialog for locked accounts
  void _showPasswordResetRequiredDialog(String userType) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: const [
              Icon(Icons.lock_outline, color: Color(0xFFFF7B7B), size: 28),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Account Locked',
                  style: TextStyle(
                    color: Color(0xFFFF7B7B),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            userType == 'Admin'
                ? 'You have entered an incorrect password 5 times today. '
                    'For security reasons, please contact the system administrator to unlock your account.'
                : 'You have entered an incorrect password 5 times today. '
                    'For security reasons, you must reset your password before you can access your account again.',
            style: TextStyle(fontSize: 15),
          ),
          actions: [
            if (userType == 'Admin')
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).pop();
                },
                child: const Text(
                  'OK',
                  style: TextStyle(
                    color: Color(0xFF4A5FBC),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            else
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.pushReplacementNamed(
                    context,
                    '/forgot-password',
                    arguments: {'email': _emailController.text.trim()},
                  );
                },
                child: const Text(
                  'Reset Password',
                  style: TextStyle(
                    color: Color(0xFF4A5FBC),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
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

  // 🔒 ONLY ADDITION 3: Check account lock status
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
      print('Error checking account lock status: $e');
      return null;
    }
  }

  // 🔒 ONLY ADDITION 4: Record failed login attempt
  Future<void> _recordFailedLoginAttempt(String email) async {
    try {
      final querySnapshot = await _firestore
          .collection('Users')
          .where('Email', isEqualTo: email.trim().toLowerCase())
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) return;

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

      await _firestore.collection('Users').doc(userId).update({
        'failedLoginAttempts': newFailedAttempts,
        'lastFailedLoginDate': FieldValue.serverTimestamp(),
        'accountLocked': newFailedAttempts >= 5,
        'mustResetPassword': newFailedAttempts >= 5,
      });

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
      } else {
        setState(() {
          _loginError = 'Invalid credentials. Please try again.';
        });
      }
    } catch (e) {
      print('Error recording failed login: $e');
    }
  }

  // 🔒 ONLY ADDITION 5: Reset failed login attempts
  Future<void> _resetFailedLoginAttempts(String userId) async {
    try {
      await _firestore.collection('Users').doc(userId).update({
        'failedLoginAttempts': 0,
        'lastFailedLoginDate': null,
        'accountLocked': false,
        'mustResetPassword': false,
      });
    } catch (e) {
      print('Error resetting failed attempts: $e');
    }
  }

  Future<void> _handleLogin() async {
    // 🔒 Clear previous error
    setState(() {
      _loginError = null;
    });

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // 🔒 STEP 1: Check if account is locked
      final lockStatus =
          await _checkAccountLockStatus(_emailController.text.trim());

      if (lockStatus != null && lockStatus['locked'] == true) {
        setState(() => _isLoading = false);
        _showPasswordResetRequiredDialog(lockStatus['userType'] ?? '');
        return;
      }

      final userCredential = await _auth.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final userId = userCredential.user!.uid;

      // 🔒 Reset failed attempts on successful login
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
          _showSuccessSnackBar('Verification code sent to your email');
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
        } else if (accountStatus == 'Pending') {
          await _auth.signOut();
          setState(() {
            _loginError =
                'Your account is pending approval from admin. Please wait.';
          });
        } else if (accountStatus == 'Rejected') {
          await _auth.signOut();
          setState(() {
            _loginError = 'Your account has been rejected. Contact support.';
          });
        }
        setState(() => _isLoading = false);
        return;
      }

      await _auth.signOut();
      setState(() {
        _loginError = 'Unknown user type: "$userType"';
      });
    } on FirebaseAuthException catch (e) {
      // 🔒 Handle different error types
      if (e.code == 'user-not-found') {
        // Email doesn't exist - show error but DON'T record attempt
        setState(() {
          _loginError = 'Invalid credentials. Please try again.';
        });
      } else if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        // Wrong password - record the failed attempt
        await _recordFailedLoginAttempt(_emailController.text.trim());
      } else {
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
    } catch (e) {
      setState(() {
        _loginError = 'Unexpected error: $e';
      });
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
                            errorStyle: const TextStyle(color: Colors.red),
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
                            errorStyle: const TextStyle(color: Colors.red),
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
                        // 🔒 ONLY ADDITION 6: Show error under password field
                        if (_loginError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              _loginError!,
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 12,
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
                  Navigator.of(context).pop();
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
