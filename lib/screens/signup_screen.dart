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
  int _currentStep = 0; // للتنقل بين القسمين
  final _formKey = GlobalKey<FormState>();

  // Controllers
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
          children: [
            Icon(Icons.error_outline, color: Colors.red, size: 28),
            SizedBox(width: 10),
            Text('Error', style: TextStyle(color: Colors.red)),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('OK', style: TextStyle(color: Color(0xFF4A5FBC))),
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
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
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
      String trimmedEmail = email.trim().toLowerCase(); // تحويل لـ lowercase

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
        if (matchingDocs.isNotEmpty) {
          print('❌ Found in doc: ${matchingDocs.first.id}');
          print('❌ Data: ${matchingDocs.first.data()}');
        }
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

      final result = await callable.call({
        'email': email.trim().toLowerCase(), // تحويل لـ lowercase
        'otp': otp.trim(),
        'userType': userType,
      });

      if (result.data != null && result.data['success'] == true) {
        await _firestore.collection('AdminOTPs').doc(email.toLowerCase()).set({
          'OTP': otp,
          'Email': email.toLowerCase(),
          'UserType': userType,
          'CreatedAt': FieldValue.serverTimestamp(),
          'ExpiresAt': Timestamp.fromDate(
            DateTime.now().add(Duration(minutes: 2)),
          ),
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

  // Validation للقسم الأول قبل الانتقال للقسم الثاني
  bool _validateFirstStep() {
    if (_selectedTab == 0) {
      // Company
      if (_companyNameController.text.trim().isEmpty) {
        _showErrorDialog('Please enter company name');
        return false;
      }
      if (!_isValidFullName(_companyFullNameController.text.trim())) {
        _showErrorDialog(
            'Full name must have at least 2 words with letters only');
        return false;
      }
      if (!_isValidEmail(_companyEmailController.text.trim())) {
        _showErrorDialog('Please enter a valid email address');
        return false;
      }
    } else {
      // Job Seeker
      if (!_isValidFullName(_seekerNameController.text.trim())) {
        _showErrorDialog('Name must have at least 2 words with letters only');
        return false;
      }
      if (!_isValidEmail(_seekerEmailController.text.trim())) {
        _showErrorDialog('Please enter a valid email address');
        return false;
      }
    }
    return true;
  }

  Future<void> _handleJobSeekerSignup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // تحويل الإيميل لـ lowercase
      final email = _seekerEmailController.text.trim().toLowerCase();

      if (!_isValidEmail(email)) {
        _showErrorDialog('Please enter a valid email address');
        setState(() => _isLoading = false);
        return;
      }

      if (!_isValidFullName(_seekerNameController.text.trim())) {
        _showErrorDialog('Name must have at least 2 words with letters only');
        setState(() => _isLoading = false);
        return;
      }

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

      final isUnique = await _isEmailUnique(email);
      if (!isUnique) {
        _showErrorDialog('This email is already registered');
        setState(() => _isLoading = false);
        return;
      }

      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: _seekerPasswordController.text,
      );

      await userCredential.user!.sendEmailVerification();

      await _firestore.collection('Users').doc(userCredential.user!.uid).set({
        'UserType': 'JobSeeker',
        'FullName': _seekerNameController.text.trim(),
        'Email': email,
        'IsEmailVerified': false,
        'CreatedAt': FieldValue.serverTimestamp(),
      });

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 28),
              SizedBox(width: 10),
              Text('Success', style: TextStyle(color: Colors.green)),
            ],
          ),
          content: Text(
              'Account created! Please check your email to verify your account before logging in.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.pushReplacementNamed(context, '/login');
              },
              child: Text('OK', style: TextStyle(color: Color(0xFF4A5FBC))),
            ),
          ],
        ),
      );
    } on FirebaseAuthException catch (e) {
      String message = 'An error occurred during signup';
      if (e.code == 'email-already-in-use') {
        message = 'This email is already registered';
      } else if (e.code == 'weak-password') {
        message = 'Password is too weak';
      } else if (e.code == 'invalid-email') {
        message = 'Invalid email format';
      }
      _showErrorDialog(message);
    } catch (e) {
      _showErrorDialog('Unexpected error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleCompanySignup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // تحويل الإيميل لـ lowercase
      final email = _companyEmailController.text.trim().toLowerCase();

      if (_companyNameController.text.trim().isEmpty) {
        _showErrorDialog('Please enter company name');
        setState(() => _isLoading = false);
        return;
      }

      if (!_isValidFullName(_companyFullNameController.text.trim())) {
        _showErrorDialog(
            'Full name must have at least 2 words with letters only');
        setState(() => _isLoading = false);
        return;
      }

      if (!_isValidEmail(email)) {
        _showErrorDialog('Please enter a valid email address');
        setState(() => _isLoading = false);
        return;
      }

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

      final isUnique = await _isEmailUnique(email);
      if (!isUnique) {
        _showErrorDialog('This email is already registered');
        setState(() => _isLoading = false);
        return;
      }

      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: _companyPasswordController.text,
      );

      await userCredential.user!.sendEmailVerification();

      await _firestore.collection('Users').doc(userCredential.user!.uid).set({
        'UserType': 'Company',
        'CompanyName': _companyNameController.text.trim(),
        'FullName': _companyFullNameController.text.trim(),
        'Email': email,
        'IsEmailVerified': false,
        'AccountStatus': 'Pending',
        'CreatedAt': FieldValue.serverTimestamp(),
      });

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 28),
              SizedBox(width: 10),
              Text('Success', style: TextStyle(color: Colors.green)),
            ],
          ),
          content: Text(
              'Account created! Please check your email to verify your account. Admin will review your request.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.pushReplacementNamed(context, '/login');
              },
              child: Text('OK', style: TextStyle(color: Color(0xFF4A5FBC))),
            ),
          ],
        ),
      );
    } on FirebaseAuthException catch (e) {
      String message = 'An error occurred during signup';
      if (e.code == 'email-already-in-use') {
        message = 'This email is already registered';
      } else if (e.code == 'weak-password') {
        message = 'Password is too weak';
      } else if (e.code == 'invalid-email') {
        message = 'Invalid email format';
      }
      _showErrorDialog(message);
    } catch (e) {
      _showErrorDialog('Unexpected error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _buildCompanyForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_currentStep == 0) ...[
          // القسم الأول: Company Name, Full Name, Email
          _buildTextField('Company Name', _companyNameController, false),
          SizedBox(height: 24),
          _buildTextField('Full Name', _companyFullNameController, false),
          SizedBox(height: 24),
          _buildTextField('Email', _companyEmailController, false,
              keyboardType: TextInputType.emailAddress),
        ] else ...[
          // القسم الثاني: Password, Confirm Password
          _buildPasswordField(_companyPasswordController),
          SizedBox(height: 24),
          _buildConfirmPasswordField(
              _companyPasswordController, _companyConfirmPasswordController),
        ],
        SizedBox(height: 40),

        // النقاط
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildDot(0),
            SizedBox(width: 8),
            _buildDot(1),
          ],
        ),

        SizedBox(height: 40),

        // الزر
        _buildNavigationButton(),
      ],
    );
  }

  Widget _buildJobSeekerForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_currentStep == 0) ...[
          // القسم الأول: Full Name, Email
          _buildTextField('Full Name', _seekerNameController, false),
          SizedBox(height: 24),
          _buildTextField('Email', _seekerEmailController, false,
              keyboardType: TextInputType.emailAddress),
        ] else ...[
          // القسم الثاني: Password, Confirm Password
          _buildPasswordField(_seekerPasswordController),
          SizedBox(height: 24),
          _buildConfirmPasswordField(
              _seekerPasswordController, _seekerConfirmPasswordController),
        ],
        SizedBox(height: 40),

        // النقاط
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildDot(0),
            SizedBox(width: 8),
            _buildDot(1),
          ],
        ),

        SizedBox(height: 40),

        // الزر
        _buildNavigationButton(),
      ],
    );
  }

  Widget _buildDot(int index) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _currentStep == index ? Color(0xFF4A5FBC) : Colors.grey[300],
      ),
    );
  }

  Widget _buildNavigationButton() {
    return Align(
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
          onPressed: _isLoading
              ? null
              : () {
                  if (_currentStep == 0) {
                    // التحقق من القسم الأول
                    if (_validateFirstStep()) {
                      setState(() => _currentStep = 1);
                    }
                  } else {
                    // Submit
                    if (_selectedTab == 0) {
                      _handleCompanySignup();
                    } else {
                      _handleJobSeekerSignup();
                    }
                  }
                },
          icon: _isLoading
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : Icon(
                  Icons.arrow_forward,
                  color: Colors.white,
                  size: 20,
                ),
        ),
      ),
    );
  }

  Widget _buildTextField(
      String label, TextEditingController controller, bool obscure,
      {TextInputType keyboardType = TextInputType.text}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        SizedBox(height: 8),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          style: TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Enter your $label',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white.withOpacity(0.5)),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white),
            ),
            errorBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.red),
            ),
            focusedErrorBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.red),
            ),
            errorStyle: TextStyle(color: Colors.red),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordField(TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Password',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        SizedBox(height: 8),
        TextFormField(
          controller: controller,
          obscureText: _obscurePassword,
          style: TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Enter your password',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white.withOpacity(0.5)),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white),
            ),
            errorBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.red),
            ),
            focusedErrorBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.red),
            ),
            errorStyle: TextStyle(color: Colors.red),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                color: Colors.white,
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildConfirmPasswordField(TextEditingController passwordController,
      TextEditingController confirmPasswordController) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Confirm Password',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        SizedBox(height: 8),
        TextFormField(
          controller: confirmPasswordController,
          obscureText: _obscureConfirmPassword,
          style: TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Re-enter your password',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white.withOpacity(0.5)),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white),
            ),
            errorBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.red),
            ),
            focusedErrorBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.red),
            ),
            errorStyle: TextStyle(color: Colors.red),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureConfirmPassword
                    ? Icons.visibility_off
                    : Icons.visibility,
                color: Colors.white,
              ),
              onPressed: () => setState(
                  () => _obscureConfirmPassword = !_obscureConfirmPassword),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
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

            // الموجة البنفسجية
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: MediaQuery.of(context).size.height * 0.75,
              child: CustomPaint(
                painter: WavePainter(),
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

            // المحتوى
            SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 200),

                        // Tabs
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(25),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => setState(() {
                                    _selectedTab = 0;
                                    _currentStep = 0;
                                  }),
                                  child: Container(
                                    padding: EdgeInsets.symmetric(vertical: 12),
                                    decoration: BoxDecoration(
                                      color: _selectedTab == 0
                                          ? Colors.white
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(25),
                                    ),
                                    child: Text(
                                      'Company',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: _selectedTab == 0
                                            ? Color(0xFF4A5FBC)
                                            : Colors.white,
                                      ),
                                    ),
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
                                    padding: EdgeInsets.symmetric(vertical: 12),
                                    decoration: BoxDecoration(
                                      color: _selectedTab == 1
                                          ? Colors.white
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(25),
                                    ),
                                    child: Text(
                                      'Job Seeker',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: _selectedTab == 1
                                            ? Color(0xFF4A5FBC)
                                            : Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 40),

                        _selectedTab == 0
                            ? _buildCompanyForm()
                            : _buildJobSeekerForm(),

                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // زر الرجوع
            if (_currentStep == 1)
              Positioned(
                top: 50,
                left: 30,
                child: IconButton(
                  icon: Icon(Icons.arrow_back, color: Colors.white, size: 28),
                  onPressed: () => setState(() => _currentStep = 0),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// رسم الموجة البنفسجية
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
