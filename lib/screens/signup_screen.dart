import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'dart:math';

class SignupScreen extends StatefulWidget {
  @override
  _SignupScreenState createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  int _selectedTab = 0;
  int _currentStep = 0;
  final _formKey = GlobalKey<FormState>();

  final _companyNameController = TextEditingController();
  final _companyFullNameController = TextEditingController();
  final _companyEmailController = TextEditingController();
  final _companyPasswordController = TextEditingController();
  final _companyConfirmPasswordController = TextEditingController();

  final _seekerNameController = TextEditingController();
  final _seekerEmailController = TextEditingController();
  final _seekerPasswordController = TextEditingController();
  final _seekerConfirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  // Error messages for real-time validation
  String? _companyNameError;
  String? _companyFullNameError;
  String? _companyEmailError;
  String? _seekerNameError;
  String? _seekerEmailError;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void dispose() {
    _companyNameController.dispose();
    _companyFullNameController.dispose();
    _companyEmailController.dispose();
    _companyPasswordController.dispose();
    _companyConfirmPasswordController.dispose();
    _seekerNameController.dispose();
    _seekerEmailController.dispose();
    _seekerPasswordController.dispose();
    _seekerConfirmPasswordController.dispose();
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

  String _generateOTP() {
    Random random = Random();
    return (100000 + random.nextInt(900000)).toString();
  }

  bool _isValidEmail(String email) {
    final emailRegex =
        RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    return emailRegex.hasMatch(email.trim());
  }

  bool _isValidFullName(String name) {
    String trimmedName = name.trim();
    final nameRegex = RegExp(r'^[a-zA-Z\s]+$');
    if (!nameRegex.hasMatch(trimmedName)) return false;
    List<String> words = trimmedName.split(RegExp(r'\s+'));
    if (words.length < 2) return false;
    for (String word in words) {
      if (word.isEmpty) return false;
    }
    return true;
  }

  bool _isStrongPassword(String password) {
    if (password.length < 8) return false;
    if (!password.contains(RegExp(r'[A-Z]'))) return false;
    if (!password.contains(RegExp(r'[a-z]'))) return false;
    if (!password.contains(RegExp(r'[0-9]'))) return false;
    if (!password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) return false;
    return true;
  }

  String _getPasswordRequirements(String password) {
    List<String> missing = [];
    if (password.length < 8) missing.add('8 characters');
    if (!password.contains(RegExp(r'[A-Z]'))) missing.add('uppercase letter');
    if (!password.contains(RegExp(r'[a-z]'))) missing.add('lowercase letter');
    if (!password.contains(RegExp(r'[0-9]'))) missing.add('number');
    if (!password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]')))
      missing.add('special character');
    if (missing.isEmpty) return '';
    return 'Password must include: ${missing.join(', ')}';
  }

  Future<bool> _isEmailUnique(String email) async {
    try {
      String trimmedEmail = email.trim().toLowerCase();
      print('🔵 Checking email: $trimmedEmail');
      final querySnapshot1 = await _firestore
          .collection('Users')
          .where('Email', isEqualTo: trimmedEmail)
          .get();
      print('🔵 Method 1 (where): ${querySnapshot1.docs.length} docs');
      final allUsers = await _firestore.collection('Users').get();
      final matchingDocs = allUsers.docs.where((doc) {
        final data = doc.data();
        final docEmail = data['Email']?.toString().toLowerCase() ?? '';
        return docEmail == trimmedEmail;
      }).toList();
      print('🔵 Method 2 (filter): ${matchingDocs.length} docs');
      if (querySnapshot1.docs.isNotEmpty || matchingDocs.isNotEmpty) {
        print('❌ Email EXISTS!');
        return false;
      }
      print('✅ Email is UNIQUE');
      return true;
    } catch (e) {
      print('❌ ERROR: $e');
      return false;
    }
  }

  Future<bool> _sendOTPEmail(String email, String otp, String userType) async {
    try {
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final callable = functions.httpsCallable('sendSignupOtp');
      final result = await callable.call(
          {'email': email.trim(), 'otp': otp.trim(), 'userType': userType});
      if (result.data != null && result.data['success'] == true) {
        await _firestore.collection('AdminOTPs').doc(email).set({
          'OTP': otp,
          'Email': email,
          'UserType': userType,
          'CreatedAt': FieldValue.serverTimestamp(),
          'ExpiresAt':
              Timestamp.fromDate(DateTime.now().add(Duration(minutes: 2))),
          'Used': false,
        });
        return true;
      }
      return false;
    } catch (e) {
      print('❌ Error sending OTP: $e');
      return false;
    }
  }

  Future<bool> _validateCurrentStep() async {
    setState(() {
      _companyNameError = null;
      _companyFullNameError = null;
      _companyEmailError = null;
      _seekerNameError = null;
      _seekerEmailError = null;
    });

    if (_selectedTab == 0) {
      // Company validation
      if (_currentStep == 0) {
        // Step 1: Company Name only
        if (_companyNameController.text.trim().isEmpty) {
          setState(() => _companyNameError = 'Please enter company name');
          return false;
        }
      } else if (_currentStep == 1) {
        // Step 2: Full Name + Email
        if (_companyFullNameController.text.trim().isEmpty) {
          setState(() => _companyFullNameError = 'Please enter your full name');
          return false;
        }
        if (!_isValidFullName(_companyFullNameController.text.trim())) {
          setState(
              () => _companyFullNameError = 'At least 2 words (letters only)');
          return false;
        }
        if (_companyEmailController.text.trim().isEmpty) {
          setState(() => _companyEmailError = 'Please enter your email');
          return false;
        }
        if (!_isValidEmail(_companyEmailController.text.trim())) {
          setState(() => _companyEmailError = 'Invalid email address');
          return false;
        }
        setState(() => _isLoading = true);
        bool isUnique =
            await _isEmailUnique(_companyEmailController.text.trim());
        setState(() => _isLoading = false);
        if (!isUnique) {
          setState(
              () => _companyEmailError = 'This email is already registered');
          return false;
        }
      }
    } else {
      // JobSeeker validation
      if (_currentStep == 0) {
        // Step 1: Full Name + Email
        if (_seekerNameController.text.trim().isEmpty) {
          setState(() => _seekerNameError = 'Please enter your full name');
          return false;
        }
        if (!_isValidFullName(_seekerNameController.text.trim())) {
          setState(() => _seekerNameError = 'At least 2 words (letters only)');
          return false;
        }
        if (_seekerEmailController.text.trim().isEmpty) {
          setState(() => _seekerEmailError = 'Please enter your email');
          return false;
        }
        if (!_isValidEmail(_seekerEmailController.text.trim())) {
          setState(() => _seekerEmailError = 'Invalid email address');
          return false;
        }
        setState(() => _isLoading = true);
        bool isUnique =
            await _isEmailUnique(_seekerEmailController.text.trim());
        setState(() => _isLoading = false);
        if (!isUnique) {
          setState(
              () => _seekerEmailError = 'This email is already registered');
          return false;
        }
      }
    }
    return true;
  }

  Future<void> _handleJobSeekerSignup() async {
    setState(() => _isLoading = true);
    try {
      if (!_isStrongPassword(_seekerPasswordController.text)) {
        _showErrorDialog(
            _getPasswordRequirements(_seekerPasswordController.text));
        setState(() => _isLoading = false);
        return;
      }
      if (_seekerPasswordController.text !=
          _seekerConfirmPasswordController.text) {
        _showErrorDialog('Passwords do not match');
        setState(() => _isLoading = false);
        return;
      }
      UserCredential userCredential =
          await _auth.createUserWithEmailAndPassword(
        email: _seekerEmailController.text.trim(),
        password: _seekerPasswordController.text.trim(),
      );
      String userId = userCredential.user!.uid;
      await _firestore.collection('Users').doc(userId).set({
        'UserID': userId,
        'UserType': 'JobSeeker',
        'Email': _seekerEmailController.text.trim().toLowerCase(),
        'Name': _seekerNameController.text.trim(),
        'DoB': null,
        'Nationality': null,
        'Phone': null,
        'PhotoURL': null,
        'CVURL': null,
        'IsProfileComplete': false,
        'CVKeywords': null,
        'ContactEmail': null,
        'IsEmailVerified': false,
        'PhotoPath': null,
        'CVPath': null,
        'Date': FieldValue.serverTimestamp(),
        'AiUsage': {
          'LastReset': FieldValue.serverTimestamp(),
          'CvEnhancement': 2,
          'MockInterview': 2,
        },
      });
      String otp = _generateOTP();
      bool otpSent = await _sendOTPEmail(
          _seekerEmailController.text.trim(), otp, 'JobSeeker');
      if (otpSent) {
        Navigator.pushReplacementNamed(context, '/otp-verification',
            arguments: {
              'email': _seekerEmailController.text.trim(),
              'userId': userId,
              'userType': 'JobSeeker',
            });
      } else {
        await userCredential.user!.delete();
        await _firestore.collection('Users').doc(userId).delete();
        _showErrorDialog('Failed to send verification code');
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage = 'An error occurred';
      if (e.code == 'email-already-in-use') {
        errorMessage = 'This email is already registered';
      } else if (e.code == 'weak-password') {
        errorMessage = 'Password is too weak';
      }
      _showErrorDialog(errorMessage);
    } catch (e) {
      _showErrorDialog('Unexpected error: ${e.toString()}');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleCompanySignup() async {
    setState(() => _isLoading = true);
    try {
      if (!_isStrongPassword(_companyPasswordController.text)) {
        _showErrorDialog(
            _getPasswordRequirements(_companyPasswordController.text));
        setState(() => _isLoading = false);
        return;
      }
      if (_companyPasswordController.text !=
          _companyConfirmPasswordController.text) {
        _showErrorDialog('Passwords do not match');
        setState(() => _isLoading = false);
        return;
      }
      UserCredential userCredential =
          await _auth.createUserWithEmailAndPassword(
        email: _companyEmailController.text.trim(),
        password: _companyPasswordController.text.trim(),
      );
      String userId = userCredential.user!.uid;
      await _firestore.collection('Users').doc(userId).set({
        'UserID': userId,
        'UserType': 'Company',
        'Email': _companyEmailController.text.trim().toLowerCase(),
        'Name': _companyFullNameController.text.trim(),
        'CompanyName': _companyNameController.text.trim(),
        'Phone': null,
        'PhotoURL': null,
        'IsProfileComplete': false,
        'ContactEmail': null,
        'Location': null,
        'Description': null,
        'AccountStatus': 'Pending',
        'IsEmailVerified': false,
        'PhotoPath': null,
        'Date': FieldValue.serverTimestamp(),
        'AiUsage': {
          'LastReset': FieldValue.serverTimestamp(),
          'JobPosting': 2,
        },
      });
      String otp = _generateOTP();
      bool otpSent = await _sendOTPEmail(
          _companyEmailController.text.trim(), otp, 'Company');
      if (otpSent) {
        try {
          final functions =
              FirebaseFunctions.instanceFor(region: 'us-central1');
          final notifyAdmin = functions.httpsCallable('notifyAdminNewCompany');
          await notifyAdmin.call({
            'companyName': _companyNameController.text.trim(),
            'companyEmail': _companyEmailController.text.trim(),
          });
          print('✅ Admin notified successfully');
        } catch (e) {
          print('⚠️ Failed to notify admin: $e');
        }
        Navigator.pushReplacementNamed(context, '/otp-verification',
            arguments: {
              'email': _companyEmailController.text.trim(),
              'userId': userId,
              'userType': 'Company',
            });
      } else {
        await userCredential.user!.delete();
        await _firestore.collection('Users').doc(userId).delete();
        _showErrorDialog('Failed to send verification code');
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage = 'An error occurred';
      if (e.code == 'email-already-in-use') {
        errorMessage = 'This email is already registered';
      } else if (e.code == 'weak-password') {
        errorMessage = 'Password is too weak';
      }
      _showErrorDialog(errorMessage);
    } catch (e) {
      _showErrorDialog('Unexpected error: ${e.toString()}');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
    String? errorText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white)),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(
                  color: errorText != null
                      ? Colors.red
                      : Colors.white.withOpacity(0.5)),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(
                  color: errorText != null ? Colors.red : Colors.white),
            ),
            errorBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.red)),
            focusedErrorBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.red)),
            errorStyle: const TextStyle(color: Colors.red),
          ),
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(errorText,
                style: const TextStyle(color: Colors.red, fontSize: 12)),
          ),
      ],
    );
  }

  Widget _buildPasswordField(TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Password',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white)),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          obscureText: _obscurePassword,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Enter your password',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white.withOpacity(0.5))),
            focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white)),
            errorBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.red)),
            focusedErrorBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.red)),
            errorStyle: const TextStyle(color: Colors.red),
            suffixIcon: IconButton(
              icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  color: Colors.white),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text('Must include: uppercase, lowercase, number, special character',
            style: TextStyle(
                fontSize: 12,
                color: Colors.white.withOpacity(0.7),
                fontStyle: FontStyle.italic)),
      ],
    );
  }

  Widget _buildConfirmPasswordField(TextEditingController confirmController) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Confirm Password',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white)),
        const SizedBox(height: 8),
        TextFormField(
          controller: confirmController,
          obscureText: _obscureConfirmPassword,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Re-enter your password',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white.withOpacity(0.5))),
            focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white)),
            errorBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.red)),
            focusedErrorBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.red)),
            errorStyle: const TextStyle(color: Colors.red),
            suffixIcon: IconButton(
              icon: Icon(
                  _obscureConfirmPassword
                      ? Icons.visibility_off
                      : Icons.visibility,
                  color: Colors.white),
              onPressed: () => setState(
                  () => _obscureConfirmPassword = !_obscureConfirmPassword),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStepIndicator() {
    int totalSteps = _selectedTab == 0 ? 3 : 2;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(totalSteps, (index) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _currentStep == index
                  ? Colors.white
                  : Colors.white.withOpacity(0.3),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildCompanyStep1() {
    return Column(
      children: [
        _buildTextField(
          label: 'Company Name',
          controller: _companyNameController,
          hint: 'Enter company name',
          errorText: _companyNameError,
        ),
      ],
    );
  }

  Widget _buildCompanyStep2() {
    return Column(
      children: [
        _buildTextField(
          label: 'Full Name',
          controller: _companyFullNameController,
          hint: 'Enter your full name (First Last)',
          errorText: _companyFullNameError,
        ),
        const SizedBox(height: 24),
        _buildTextField(
          label: 'Email',
          controller: _companyEmailController,
          hint: 'Enter your email',
          keyboardType: TextInputType.emailAddress,
          errorText: _companyEmailError,
        ),
      ],
    );
  }

  Widget _buildCompanyStep3() {
    return Column(
      children: [
        _buildPasswordField(_companyPasswordController),
        const SizedBox(height: 24),
        _buildConfirmPasswordField(_companyConfirmPasswordController),
      ],
    );
  }

  Widget _buildJobSeekerStep1() {
    return Column(
      children: [
        _buildTextField(
          label: 'Full Name',
          controller: _seekerNameController,
          hint: 'Enter your full name (First Last)',
          errorText: _seekerNameError,
        ),
        const SizedBox(height: 24),
        _buildTextField(
          label: 'Email',
          controller: _seekerEmailController,
          hint: 'Enter your email',
          keyboardType: TextInputType.emailAddress,
          errorText: _seekerEmailError,
        ),
      ],
    );
  }

  Widget _buildJobSeekerStep2() {
    return Column(
      children: [
        _buildPasswordField(_seekerPasswordController),
        const SizedBox(height: 24),
        _buildConfirmPasswordField(_seekerConfirmPasswordController),
      ],
    );
  }

  void _handleNextButton() async {
    bool isValid = await _validateCurrentStep();
    if (!isValid) return;

    if (_selectedTab == 0) {
      // Company: 3 steps
      if (_currentStep < 2) {
        setState(() => _currentStep++);
      } else {
        await _handleCompanySignup();
      }
    } else {
      // JobSeeker: 2 steps
      if (_currentStep < 1) {
        setState(() => _currentStep++);
      } else {
        await _handleJobSeekerSignup();
      }
    }
  }

  void _handleBackButton() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SizedBox.expand(
        child: Stack(
          children: [
            Positioned.fill(
                child:
                    Image.asset('assets/images/office.png', fit: BoxFit.cover)),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: MediaQuery.of(context).size.height * 0.85,
              child: CustomPaint(painter: WavePainter()),
            ),
            Positioned(
                top: 50,
                right: 30,
                child: Image.asset('assets/images/j_filled.png',
                    width: 60, height: 80, fit: BoxFit.contain)),
            SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 280),
                        const Text('Sign Up',
                            style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                        const SizedBox(height: 30),
                        Container(
                          decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(25)),
                          child: Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => setState(() {
                                    _selectedTab = 0;
                                    _currentStep = 0;
                                  }),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    decoration: BoxDecoration(
                                        color: _selectedTab == 0
                                            ? Colors.white
                                            : Colors.transparent,
                                        borderRadius:
                                            BorderRadius.circular(25)),
                                    child: Text('Company',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: _selectedTab == 0
                                                ? const Color(0xFF4A5FBC)
                                                : Colors.white)),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => setState(() {
                                    _selectedTab = 1;
                                    _currentStep = 0;
                                  }),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    decoration: BoxDecoration(
                                        color: _selectedTab == 1
                                            ? Colors.white
                                            : Colors.transparent,
                                        borderRadius:
                                            BorderRadius.circular(25)),
                                    child: Text('Job Seeker',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: _selectedTab == 1
                                                ? const Color(0xFF4A5FBC)
                                                : Colors.white)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 40),
                        if (_selectedTab == 0)
                          _currentStep == 0
                              ? _buildCompanyStep1()
                              : _currentStep == 1
                                  ? _buildCompanyStep2()
                                  : _buildCompanyStep3()
                        else
                          _currentStep == 0
                              ? _buildJobSeekerStep1()
                              : _buildJobSeekerStep2(),
                        const SizedBox(height: 30),
                        _buildStepIndicator(),
                        const SizedBox(height: 30),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            if (_currentStep > 0)
                              Container(
                                width: 45,
                                height: 45,
                                decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.white, width: 2)),
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  onPressed: _handleBackButton,
                                  icon: const Icon(Icons.arrow_back,
                                      color: Colors.white, size: 20),
                                ),
                              )
                            else
                              const SizedBox(width: 45),
                            Container(
                              width: 45,
                              height: 45,
                              decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: Colors.white, width: 2)),
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                onPressed:
                                    _isLoading ? null : _handleNextButton,
                                icon: _isLoading
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2))
                                    : const Icon(Icons.arrow_forward,
                                        color: Colors.white, size: 20),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
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

class WavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF4A5FBC).withOpacity(0.7)
      ..style = PaintingStyle.fill;
    final path = Path();
    path.moveTo(0, size.height);
    path.lineTo(0, size.height * 0.3);
    path.quadraticBezierTo(size.width * 0.25, size.height * 0.15,
        size.width * 0.5, size.height * 0.2);
    path.quadraticBezierTo(
        size.width * 0.75, size.height * 0.25, size.width, size.height * 0.15);
    path.lineTo(size.width, size.height);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
