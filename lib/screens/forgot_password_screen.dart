import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'dart:math';
import 'dart:async';

import 'package:gp_2025_11/config/theme.dart';

class ForgotPasswordScreen extends StatefulWidget {
  @override
  _ForgotPasswordScreenState createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _firestore = FirebaseFirestore.instance;

  bool _isLoading = false;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  bool _canResend = false;
  int _resendTimer = 120;
  Timer? _timer;

  int _currentStep = 1;
  String _userEmail = '';

  String? _emailError;
  String? _otpError;
  String? _passwordError;

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  bool _isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }

  bool _isStrongPassword(String password) {
    return password.length >= 8 &&
        RegExp(r'[A-Z]').hasMatch(password) &&
        RegExp(r'[a-z]').hasMatch(password) &&
        RegExp(r'[0-9]').hasMatch(password) &&
        RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password);
  }

  String _generateOTP() {
    Random random = Random();
    return (100000 + random.nextInt(900000)).toString();
  }

  void _startResendTimer() {
    _canResend = false;
    _resendTimer = 120;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_resendTimer > 0) {
          _resendTimer--;
        } else {
          _canResend = true;
          timer.cancel();
        }
      });
    });
  }

  Future<bool> _sendOTPEmail(String email, String otp) async {
    try {
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final callable = functions.httpsCallable('sendPasswordResetOtp');

      final result = await callable.call({
        'email': email.trim().toLowerCase(),
        'otp': otp.trim(),
      });

      if (result.data != null && result.data['success'] == true) {
        await _firestore
            .collection('PasswordResetOTPs')
            .doc(email.toLowerCase())
            .set({
          'OTP': otp,
          'Email': email.toLowerCase(),
          'CreatedAt': FieldValue.serverTimestamp(),
          'ExpiresAt': Timestamp.fromDate(
            DateTime.now().add(const Duration(minutes: 2)),
          ),
          'Used': false,
        });
        return true;
      }
      return false;
    } catch (e) {
      print('âŒ Error sending OTP: $e');
      return false;
    }
  }

  Future<void> _handleSendOTP() async {
    setState(() {
      _emailError = null;
    });

    if (_emailController.text.isEmpty) {
      setState(() {
        _emailError = 'Please enter your email.';
      });
      return;
    }

    if (!_isValidEmail(_emailController.text)) {
      setState(() {
        _emailError = 'Please enter a valid email address.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      String email = _emailController.text.trim().toLowerCase();

      QuerySnapshot userSnapshot = await _firestore
          .collection('Users')
          .where('Email', isEqualTo: email)
          .limit(1)
          .get();

      if (userSnapshot.docs.isEmpty) {
        setState(() {
          _emailError = 'Email not found. Please check and try again.';
          _isLoading = false;
        });
        return;
      }

      // 🔒 Check if user is Admin - they cannot reset password themselves
      Map<String, dynamic> userData =
          userSnapshot.docs.first.data() as Map<String, dynamic>;
      String userType = userData['UserType'] ?? userData['userType'] ?? '';

      if (userType == 'Admin') {
        setState(() {
          _emailError =
              'Cannot reset password. Please contact system administrator.';
          _isLoading = false;
        });
        return;
      }

      String otp = _generateOTP();
      bool otpSent = await _sendOTPEmail(email, otp);

      if (otpSent) {
        SnackHelper.success(context, 'Verification code sent to your email');
        _startResendTimer();

        setState(() {
          _userEmail = email;
          _currentStep = 2;
        });
      } else {
        setState(() {
          _emailError = 'Failed to send verification code. Please try again.';
        });
      }
    } catch (e) {
      setState(() {
        _emailError = 'An error occurred: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _handleVerifyOTP() async {
    setState(() {
      _otpError = null;
    });

    if (_otpController.text.trim().isEmpty) {
      setState(() {
        _otpError = 'Please enter the verification code.';
      });
      return;
    }

    if (_otpController.text.length != 6) {
      setState(() {
        _otpError = 'The verification code must be 6 digits.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      DocumentSnapshot otpDoc = await _firestore
          .collection('PasswordResetOTPs')
          .doc(_userEmail)
          .get();

      if (!otpDoc.exists) {
        setState(() {
          _otpError = 'Verification code not found. Please try again.';
          _isLoading = false;
        });
        return;
      }

      Map<String, dynamic> otpData = otpDoc.data() as Map<String, dynamic>;
      String savedOTP = otpData['OTP'];
      Timestamp expiresAt = otpData['ExpiresAt'];
      bool used = otpData['Used'] ?? false;

      if (used) {
        setState(() {
          _otpError = 'This code has already been used. Request a new one.';
          _isLoading = false;
        });
        return;
      }

      if (DateTime.now().isAfter(expiresAt.toDate())) {
        setState(() {
          _otpError = 'The code has expired. Please click "Resend Code".';
          _isLoading = false;
        });
        await _firestore
            .collection('PasswordResetOTPs')
            .doc(_userEmail)
            .delete();
        return;
      }

      if (_otpController.text.trim() == savedOTP) {
        await _firestore
            .collection('PasswordResetOTPs')
            .doc(_userEmail)
            .update({
          'Used': true,
        });

        SnackHelper.success(context, 'Code verified successfully!');

        setState(() {
          _currentStep = 3;
        });
      } else {
        setState(() {
          _otpError = 'Incorrect verification code. Please try again.';
        });
      }
    } catch (e) {
      setState(() {
        _otpError = 'An error occurred: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _handleResetPassword() async {
    setState(() {
      _passwordError = null;
    });

    if (_newPasswordController.text.trim().isEmpty ||
        _confirmPasswordController.text.trim().isEmpty) {
      setState(() {
        _passwordError = 'Please fill all password fields.';
      });
      return;
    }

    if (_newPasswordController.text != _confirmPasswordController.text) {
      setState(() {
        _passwordError = 'Passwords do not match.';
      });
      return;
    }

    if (!_isStrongPassword(_newPasswordController.text)) {
      setState(() {
        _passwordError =
            'Password must be at least 8 characters with uppercase, lowercase, number, and special character.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final callable = functions.httpsCallable('resetUserPassword');

      final result = await callable.call({
        'email': _userEmail,
        'newPassword': _newPasswordController.text.trim(),
      });

      if (result.data != null && result.data['success'] == true) {
        // ✅ Delete OTP document
        await _firestore
            .collection('PasswordResetOTPs')
            .doc(_userEmail)
            .delete();

        _showSuccessDialog(
          'Password reset successfully!\n\nYour account has been unlocked and you can now login with your new password.',
        );
      } else {
        setState(() {
          _passwordError = 'Failed to reset password. Please try again.';
        });
      }
    } catch (e) {
      print('❌ Error: $e');
      setState(() {
        _passwordError = 'An error occurred: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showSuccessDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF4A5FBC).withOpacity(0.7),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        title: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, color: Colors.white, size: 28),
            SizedBox(width: 10),
            Text('Success',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(color: Colors.white),
          textAlign: TextAlign.center,
        ),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        actionsPadding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            style: TextButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.9),
              foregroundColor: const Color(0xFF4A5FBC),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String _formatTime(int seconds) {
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SizedBox.expand(
        child: Stack(
          children: [
            // Ø®Ù„ÙÙŠØ© office.png
            Positioned.fill(
              child: Image.asset(
                'assets/images/office.png',
                fit: BoxFit.cover,
              ),
            ),

            // Ù„ÙˆØ¬Ùˆ j_filled ÙÙŠ Ø£Ø¹Ù„Ù‰ Ø§Ù„ÙŠÙ…ÙŠÙ†
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

            // Ø§Ù„Ù…Ø±Ø¨Ø¹ Ø§Ù„Ø¨Ù†ÙØ³Ø¬ÙŠ ÙÙŠ Ù…Ù†ØªØµÙ Ø§Ù„Ø´Ø§Ø´Ø©
            Center(
              child: Container(
                width: MediaQuery.of(context).size.width * 0.85,
                padding: const EdgeInsets.all(40),
                decoration: BoxDecoration(
                  color: const Color(0xFF4A5FBC).withOpacity(0.7),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: SingleChildScrollView(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Ø§Ù„Ø¹Ù†ÙˆØ§Ù† Ø§Ù„Ø±Ø¦ÙŠØ³ÙŠ
                        Text(
                          _currentStep == 1
                              ? 'Forgot Password?'
                              : _currentStep == 2
                                  ? 'Enter Verification Code'
                                  : 'Create New Password',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        ),

                        const SizedBox(height: 16),

                        // Ø§Ù„Ù†Øµ Ø§Ù„ØªÙˆØ¶ÙŠØ­ÙŠ
                        Text(
                          _currentStep == 1
                              ? 'Enter your email address and we\'ll send you a verification code.'
                              : _currentStep == 2
                                  ? 'A 6-digit verification code has been sent to your email.'
                                  : 'Enter your new password twice to confirm.',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withOpacity(0.8),
                          ),
                          textAlign: TextAlign.center,
                        ),

                        const SizedBox(height: 40),

                        // ========== Ø§Ù„Ù…Ø±Ø­Ù„Ø© 1: Ø¥Ø¯Ø®Ø§Ù„ Ø§Ù„Ø¥ÙŠÙ…ÙŠÙ„ ==========
                        if (_currentStep == 1) ...[
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.white,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Enter your email',
                              hintStyle: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                              ),
                              prefixIcon: const Icon(
                                Icons.email_outlined,
                                color: Colors.white,
                              ),
                              enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                  color: _emailError != null
                                      ? Colors.red
                                      : Colors.white.withOpacity(0.5),
                                ),
                              ),
                              focusedBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                  color: _emailError != null
                                      ? Colors.red
                                      : Colors.white,
                                ),
                              ),
                              errorBorder: const UnderlineInputBorder(
                                borderSide: BorderSide(color: Colors.red),
                              ),
                              focusedErrorBorder: const UnderlineInputBorder(
                                borderSide: BorderSide(color: Colors.red),
                              ),
                            ),
                            onChanged: (value) {
                              if (_emailError != null) {
                                setState(() {
                                  _emailError = null;
                                });
                              }
                            },
                          ),
                          if (_emailError != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                _emailError!,
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 12,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          const SizedBox(height: 40),
                          Container(
                            width: 45,
                            height: 45,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              onPressed: _isLoading ? null : _handleSendOTP,
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
                        ],

                        // ========== Ø§Ù„Ù…Ø±Ø­Ù„Ø© 2: Ø¥Ø¯Ø®Ø§Ù„ OTP ==========
                        if (_currentStep == 2) ...[
                          TextFormField(
                            controller: _otpController,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            maxLength: 6,
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 12,
                              color: Colors.white,
                            ),
                            decoration: InputDecoration(
                              hintText: '000000',
                              hintStyle: TextStyle(
                                color: Colors.white.withOpacity(0.3),
                                letterSpacing: 12,
                              ),
                              enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                  color: _otpError != null
                                      ? Colors.red
                                      : Colors.white.withOpacity(0.5),
                                ),
                              ),
                              focusedBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                  color: _otpError != null
                                      ? Colors.red
                                      : Colors.white,
                                ),
                              ),
                              errorBorder: const UnderlineInputBorder(
                                borderSide: BorderSide(color: Colors.red),
                              ),
                              focusedErrorBorder: const UnderlineInputBorder(
                                borderSide: BorderSide(color: Colors.red),
                              ),
                              counterText: '',
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 20),
                            ),
                            onChanged: (value) {
                              if (_otpError != null) {
                                setState(() {
                                  _otpError = null;
                                });
                              }
                            },
                          ),
                          if (_otpError != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                _otpError!,
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 12,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          const SizedBox(height: 16),
                          if (!_canResend)
                            Center(
                              child: Text(
                                'You can resend the code in: ${_formatTime(_resendTimer)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withOpacity(0.7),
                                ),
                              ),
                            ),
                          const SizedBox(height: 40),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              TextButton.icon(
                                onPressed: !_canResend
                                    ? null
                                    : () async {
                                        String otp = _generateOTP();
                                        bool otpSent = await _sendOTPEmail(
                                            _userEmail, otp);
                                        if (otpSent) {
                                          SnackHelper.success(context,
                                              'A new verification code has been sent.');
                                          _startResendTimer();
                                          _otpController.clear();
                                        } else {
                                          setState(() {
                                            _otpError =
                                                'Failed to resend code. Please try again.';
                                          });
                                        }
                                      },
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                icon: Icon(
                                  Icons.refresh,
                                  size: 20,
                                  color: !_canResend
                                      ? Colors.white.withOpacity(0.4)
                                      : Colors.white,
                                ),
                                label: Text(
                                  'Resend Code',
                                  style: TextStyle(
                                    color: !_canResend
                                        ? Colors.white.withOpacity(0.4)
                                        : Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              Container(
                                width: 45,
                                height: 45,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border:
                                      Border.all(color: Colors.white, width: 2),
                                ),
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  onPressed:
                                      _isLoading ? null : _handleVerifyOTP,
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
                            ],
                          ),
                        ],

                        // ========== Ø§Ù„Ù…Ø±Ø­Ù„Ø© 3: Ø¥Ø¯Ø®Ø§Ù„ ÙƒÙ„Ù…Ø© Ø§Ù„Ø³Ø± Ø§Ù„Ø¬Ø¯ÙŠØ¯Ø© ==========
                        if (_currentStep == 3) ...[
                          TextFormField(
                            controller: _newPasswordController,
                            obscureText: _obscureNewPassword,
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.white,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Enter new password',
                              hintStyle: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                              ),
                              prefixIcon: const Icon(
                                Icons.lock_outline,
                                color: Colors.white,
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureNewPassword
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: Colors.white,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscureNewPassword = !_obscureNewPassword;
                                  });
                                },
                              ),
                              enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                  color: _passwordError != null
                                      ? Colors.red
                                      : Colors.white.withOpacity(0.5),
                                ),
                              ),
                              focusedBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                  color: _passwordError != null
                                      ? Colors.red
                                      : Colors.white,
                                ),
                              ),
                              errorBorder: const UnderlineInputBorder(
                                borderSide: BorderSide(color: Colors.red),
                              ),
                              focusedErrorBorder: const UnderlineInputBorder(
                                borderSide: BorderSide(color: Colors.red),
                              ),
                            ),
                            onChanged: (value) {
                              if (_passwordError != null) {
                                setState(() {
                                  _passwordError = null;
                                });
                              }
                            },
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Must include: uppercase, lowercase, number, special character',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withOpacity(0.7),
                              fontStyle: FontStyle.italic,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          TextFormField(
                            controller: _confirmPasswordController,
                            obscureText: _obscureConfirmPassword,
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.white,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Re-enter new password',
                              hintStyle: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                              ),
                              prefixIcon: const Icon(
                                Icons.lock_outline,
                                color: Colors.white,
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureConfirmPassword
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: Colors.white,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscureConfirmPassword =
                                        !_obscureConfirmPassword;
                                  });
                                },
                              ),
                              enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                  color: _passwordError != null
                                      ? Colors.red
                                      : Colors.white.withOpacity(0.5),
                                ),
                              ),
                              focusedBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                  color: _passwordError != null
                                      ? Colors.red
                                      : Colors.white,
                                ),
                              ),
                              errorBorder: const UnderlineInputBorder(
                                borderSide: BorderSide(color: Colors.red),
                              ),
                              focusedErrorBorder: const UnderlineInputBorder(
                                borderSide: BorderSide(color: Colors.red),
                              ),
                            ),
                            onChanged: (value) {
                              if (_passwordError != null) {
                                setState(() {
                                  _passwordError = null;
                                });
                              }
                            },
                          ),
                          if (_passwordError != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                _passwordError!,
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 12,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          const SizedBox(height: 40),
                          Container(
                            width: 45,
                            height: 45,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              onPressed:
                                  _isLoading ? null : _handleResetPassword,
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
                                      Icons.check,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // ✅ سهم الرجوع في أعلى اليسار
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
