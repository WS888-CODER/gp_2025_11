import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'dart:math';
import 'dart:async';

import 'package:gp_2025_11/config/theme.dart';

class OTPVerificationScreen extends StatefulWidget {
  @override
  _OTPVerificationScreenState createState() => _OTPVerificationScreenState();
}

class _OTPVerificationScreenState extends State<OTPVerificationScreen> {
  final _otpController = TextEditingController();
  bool _isLoading = false;
  bool _isResending = false;
  String? _otpError;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'us-central1');

  Timer? _resendTimer;
  int _resendCountdown = 0;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
  }

  @override
  void dispose() {
    _otpController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendTimer() {
    setState(() {
      _resendCountdown = 120;
    });

    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCountdown > 0) {
        setState(() {
          _resendCountdown--;
        });
      } else {
        timer.cancel();
      }
    });
  }

  void _showSuccessSnackBar(String message) {
    SnackHelper.success(context, message);
  }

  String _generateOTP() {
    Random random = Random();
    return (100000 + random.nextInt(900000)).toString();
  }

  Future<void> _resendOTP(String email, String userType) async {
    if (_resendCountdown > 0) {
      setState(() {
        _otpError =
            'The current OTP is still valid. Please wait $_resendCountdown seconds.';
      });
      return;
    }

    setState(() {
      _isResending = true;
      _otpError = null;
    });

    try {
      String newOtp = _generateOTP();

      String functionName =
          userType == 'Admin' ? 'sendAdminOtp' : 'sendSignupOtp';
      final callable = _functions.httpsCallable(functionName);

      final result = await callable.call({
        'email': email,
        'otp': newOtp,
        if (userType != 'Admin') 'userType': userType,
      });

      if (result.data['success'] == true) {
        await _firestore.collection('AdminOTPs').doc(email).set({
          'OTP': newOtp,
          'Email': email,
          'UserType': userType,
          'CreatedAt': FieldValue.serverTimestamp(),
          'ExpiresAt': Timestamp.fromDate(
            DateTime.now().add(const Duration(minutes: 2)),
          ),
          'Used': false,
        });

        _showSuccessSnackBar('A new verification code has been sent.');
        _startResendTimer();
        _otpController.clear();
      } else {
        setState(() {
          _otpError = 'Failed to send new OTP. Please try again.';
        });
      }
    } catch (e) {
      setState(() {
        _otpError = 'Failed to send new OTP: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isResending = false;
      });
    }
  }

  Future<void> _sendCompanyEmails(
      String email, String companyName, String name) async {
    try {
      final docRequestCallable =
          _functions.httpsCallable('sendCompanyDocumentRequest');
      await docRequestCallable.call({
        'email': email,
        'companyName': companyName,
      });

      final adminNotifyCallable =
          _functions.httpsCallable('notifyAdminNewCompany');
      await adminNotifyCallable.call({
        'email': email,
        'companyName': companyName,
        'name': name,
      });
    } catch (e) {}
  }

  Future<void> _verifyOTP(String email, String userId, String userType) async {
    setState(() {
      _otpError = null;
    });

    if (_otpController.text.isEmpty) {
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
      DocumentSnapshot otpDoc =
          await _firestore.collection('AdminOTPs').doc(email).get();

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
        await _firestore.collection('AdminOTPs').doc(email).delete();
        return;
      }

      if (_otpController.text.trim() == savedOTP) {
        await _firestore.collection('AdminOTPs').doc(email).update({
          'Used': true,
        });

        await _firestore.collection('Users').doc(userId).update({
          'IsEmailVerified': true,
          'lastLoginTime': FieldValue.serverTimestamp(),
        });

        if (userType == 'Admin') {
          _showSuccessSnackBar('Verification successful!');
          await Future.delayed(const Duration(milliseconds: 500));
          Navigator.pushReplacementNamed(context, '/admin-dashboard');
        } else if (userType == 'Company') {
          DocumentSnapshot userDoc =
              await _firestore.collection('Users').doc(userId).get();
          Map<String, dynamic> userData =
              userDoc.data() as Map<String, dynamic>;

          await _sendCompanyEmails(
            email,
            userData['CompanyName'] ?? 'N/A',
            userData['Name'] ?? 'N/A',
          );

          final result = await showDialog<String>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => WillPopScope(
              onWillPop: () async => false,
              child: const JadeerDialog<String>(
                title: 'Email Verified',
                content: Text(
                  'Your email has been verified successfully! Please check your email for instructions on submitting company verification documents.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                  ),
                  textAlign: TextAlign.center,
                ),
                primaryLabel: 'OK',
                primaryResult: 'ok',
              ),
            ),
          );

          if (!mounted) return;

          if (result == 'ok') {
            Navigator.pushReplacementNamed(context, '/login');
          }
        } else if (userType == 'JobSeeker') {
          final result = await showDialog<String>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => WillPopScope(
              onWillPop: () async => false,
              child: const JadeerDialog<String>(
                title: 'Email Verified',
                content: Text(
                  'Your email has been verified successfully! You can now login to your account.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                  ),
                  textAlign: TextAlign.center,
                ),
                primaryLabel: 'OK',
                primaryResult: 'ok',
              ),
            ),
          );

          if (!mounted) return;

          if (result == 'ok') {
            Navigator.pushReplacementNamed(context, '/login');
          }
        }

        await _firestore.collection('AdminOTPs').doc(email).delete();
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
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _formatTime(int seconds) {
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final args =
        ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
    final String email = args['email'];
    final String userId = args['userId'];
    final String userType = args['userType'] ?? 'Admin';

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
              top: 50,
              right: 30,
              child: Image.asset(
                'assets/images/j_filled.png',
                width: 60,
                height: 80,
                fit: BoxFit.contain,
              ),
            ),
            Center(
              child: Container(
                width: MediaQuery.of(context).size.width * 0.85,
                padding: const EdgeInsets.all(40),
                decoration: BoxDecoration(
                  color: const Color(0xFF4A5FBC).withOpacity(0.8),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Text(
                        'Enter Verification Code',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 16),

                      Text(
                        'A 6-digit verification code has been sent to your email.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.8),
                        ),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 40),

                      // OTP Input Field
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
                                    : Colors.white.withOpacity(0.5)),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                                color: _otpError != null
                                    ? Colors.red
                                    : Colors.white),
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
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),

                      const SizedBox(height: 16),

                      if (_resendCountdown > 0)
                        Center(
                          child: Text(
                            'You can resend the code in: ${_formatTime(_resendCountdown)}',
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
                            onPressed: (_isResending || _resendCountdown > 0)
                                ? null
                                : () => _resendOTP(email, userType),
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon: _isResending
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Icon(
                                    Icons.refresh,
                                    size: 20,
                                    color: _resendCountdown > 0
                                        ? Colors.white.withOpacity(0.4)
                                        : Colors.white,
                                  ),
                            label: Text(
                              'Resend Code',
                              style: TextStyle(
                                color: _resendCountdown > 0
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
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              onPressed: _isLoading
                                  ? null
                                  : () => _verifyOTP(email, userId, userType),
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
