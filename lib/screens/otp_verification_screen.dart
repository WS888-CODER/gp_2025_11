import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';
import 'dart:async';

class OTPVerificationScreen extends StatefulWidget {
  @override
  _OTPVerificationScreenState createState() => _OTPVerificationScreenState();
}

class _OTPVerificationScreenState extends State<OTPVerificationScreen> {
  final _otpController = TextEditingController();
  bool _isLoading = false;
  bool _isResending = false;
  String? _otpError; // لحفظ رسالة الخطأ
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

    _resendTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (_resendCountdown > 0) {
        setState(() {
          _resendCountdown--;
        });
      } else {
        timer.cancel();
      }
    });
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
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.white,
          ),
          textAlign: TextAlign.center,
        ),
        backgroundColor: Color(0xFFFF9800), // لون برتقالي
        behavior: SnackBarBehavior.fixed,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
          ),
        ),
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        duration: Duration(seconds: 3),
      ),
    );
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
      _otpError = null; // مسح أي خطأ سابق
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
            DateTime.now().add(Duration(minutes: 2)),
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

      print('Company emails sent successfully');
    } catch (e) {
      print('⚠️ Error sending company emails: $e');
    }
  }

  Future<void> _verifyOTP(String email, String userId, String userType) async {
    // مسح أي خطأ سابق
    setState(() {
      _otpError = null;
    });

    // التحقق من أن الحقل غير فارغ
    if (_otpController.text.isEmpty) {
      setState(() {
        _otpError = 'Please enter the verification code.';
      });
      return;
    }

    // التحقق من أن الكود 6 أرقام
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
          await Future.delayed(Duration(milliseconds: 500));
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

          _showSuccessSnackBar(
              'Your email has been verified successfully! Please check your email for instructions on submitting company verification documents.');
          await Future.delayed(Duration(seconds: 3));
          Navigator.pushReplacementNamed(context, '/login');
        } else if (userType == 'JobSeeker') {
          _showSuccessSnackBar('Verification successful!');
          await Future.delayed(Duration(milliseconds: 500));
          Navigator.pushReplacementNamed(context, '/jobseeker-home');
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
            // خلفية office.png
            Positioned.fill(
              child: Image.asset(
                'assets/images/office.png',
                fit: BoxFit.cover,
              ),
            ),

            // لوجو j_filled في أعلى اليمين
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

            // المربع البنفسجي في منتصف الشاشة
            Center(
              child: Container(
                width: MediaQuery.of(context).size.width * 0.85,
                padding: EdgeInsets.all(40),
                decoration: BoxDecoration(
                  color: const Color(0xFF4A5FBC).withOpacity(0.7),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment:
                        CrossAxisAlignment.center, // تغيير من start إلى center
                    children: [
                      // العنوان الرئيسي
                      const Text(
                        'Enter Verification Code',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center, // إضافة textAlign
                      ),

                      const SizedBox(height: 16),

                      // النص التوضيحي
                      Text(
                        'A 6-digit verification code has been sent to your email.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.8),
                        ),
                        textAlign: TextAlign.center, // إضافة textAlign
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
                          contentPadding: EdgeInsets.symmetric(vertical: 20),
                        ),
                        onChanged: (value) {
                          // مسح الخطأ عند بداية الكتابة
                          if (_otpError != null) {
                            setState(() {
                              _otpError = null;
                            });
                          }
                        },
                      ),

                      // رسالة الخطأ
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

                      // مؤقت إعادة الإرسال
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

                      // الأزرار - Resend Code والسهم
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // زر Resend Code (بدون إطار)
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

                          // زر Verify (السهم)
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
          ],
        ),
      ),
    );
  }
}
