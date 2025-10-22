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
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _companyNameController = TextEditingController();
  final _companyFullNameController = TextEditingController();
  final _companyEmailController = TextEditingController();
  final _companyPasswordController = TextEditingController();
  final _companyConfirmPasswordController = TextEditingController(); // ✅ جديد

  final _seekerNameController = TextEditingController();
  final _seekerEmailController = TextEditingController();
  final _seekerPasswordController = TextEditingController();
  final _seekerConfirmPasswordController = TextEditingController(); // ✅ جديد

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true; // ✅ جديد

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void dispose() {
    _companyNameController.dispose();
    _companyFullNameController.dispose();
    _companyEmailController.dispose();
    _companyPasswordController.dispose();
    _companyConfirmPasswordController.dispose(); // ✅ جديد

    _seekerNameController.dispose();
    _seekerEmailController.dispose();
    _seekerPasswordController.dispose();
    _seekerConfirmPasswordController.dispose(); // ✅ جديد
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

  // ✅ Email validation with proper regex
  bool _isValidEmail(String email) {
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
    return emailRegex.hasMatch(email.trim());
  }

  // ✅ Full name validation
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

  // ✅ Strong password validation
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

  // ✅ فحص مزدوج - Firestore + حماية إضافية
  Future<bool> _isEmailUnique(String email) async {
    try {
      String trimmedEmail = email.trim().toLowerCase();

      print('🔵 Checking email: $trimmedEmail');

      // 1️⃣ فحص في Firestore بطريقتين مختلفتين

      // الطريقة الأولى: where clause
      final querySnapshot1 = await _firestore
          .collection('Users')
          .where('Email', isEqualTo: trimmedEmail)
          .get();

      print('🔵 Method 1 (where): ${querySnapshot1.docs.length} docs');

      // الطريقة الثانية: get all and filter
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
        'email': email.trim(),
        'otp': otp.trim(),
        'userType': userType,
      });

      if (result.data != null && result.data['success'] == true) {
        await _firestore.collection('AdminOTPs').doc(email).set({
          'OTP': otp,
          'Email': email,
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

  Future<void> _handleJobSeekerSignup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // Validate email format
      if (!_isValidEmail(_seekerEmailController.text.trim())) {
        _showErrorDialog('Please enter a valid email address');
        setState(() => _isLoading = false);
        return;
      }

      // Validate full name
      if (!_isValidFullName(_seekerNameController.text.trim())) {
        _showErrorDialog('Name must have at least 2 words with letters only');
        setState(() => _isLoading = false);
        return;
      }

      // Validate password strength
      if (!_isStrongPassword(_seekerPasswordController.text)) {
        _showErrorDialog(
            _getPasswordRequirements(_seekerPasswordController.text));
        setState(() => _isLoading = false);
        return;
      }

      // ✅ التحقق من تطابق كلمات السر
      if (_seekerPasswordController.text !=
          _seekerConfirmPasswordController.text) {
        _showErrorDialog('Passwords do not match');
        setState(() => _isLoading = false);
        return;
      }

      // Check email uniqueness
      bool isUnique = await _isEmailUnique(_seekerEmailController.text.trim());
      if (!isUnique) {
        _showErrorDialog('This email is already registered');
        setState(() => _isLoading = false);
        return;
      }

      // Create user
      UserCredential userCredential =
          await _auth.createUserWithEmailAndPassword(
        email: _seekerEmailController.text.trim(),
        password: _seekerPasswordController.text.trim(),
      );

      String userId = userCredential.user!.uid;

      await _firestore.collection('Users').doc(userId).set({
        'UserID': userId,
        'UserType': 'JobSeeker',
        'Email':
            _seekerEmailController.text.trim().toLowerCase(), // ✅ lowercase
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
        _seekerEmailController.text.trim(),
        otp,
        'JobSeeker',
      );

      if (otpSent) {
        Navigator.pushReplacementNamed(
          context,
          '/otp-verification',
          arguments: {
            'email': _seekerEmailController.text.trim(),
            'userId': userId,
            'userType': 'JobSeeker',
          },
        );
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
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // Validate email format
      if (!_isValidEmail(_companyEmailController.text.trim())) {
        _showErrorDialog('Please enter a valid email address');
        setState(() => _isLoading = false);
        return;
      }

      // Validate full name
      if (!_isValidFullName(_companyFullNameController.text.trim())) {
        _showErrorDialog('Name must have at least 2 words with letters only');
        setState(() => _isLoading = false);
        return;
      }

      // Validate password strength
      if (!_isStrongPassword(_companyPasswordController.text)) {
        _showErrorDialog(
            _getPasswordRequirements(_companyPasswordController.text));
        setState(() => _isLoading = false);
        return;
      }

      // ✅ التحقق من تطابق كلمات السر
      if (_companyPasswordController.text !=
          _companyConfirmPasswordController.text) {
        _showErrorDialog('Passwords do not match');
        setState(() => _isLoading = false);
        return;
      }

      // Check email uniqueness
      bool isUnique = await _isEmailUnique(_companyEmailController.text.trim());
      if (!isUnique) {
        _showErrorDialog('This email is already registered');
        setState(() => _isLoading = false);
        return;
      }

      // Create user
      UserCredential userCredential =
          await _auth.createUserWithEmailAndPassword(
        email: _companyEmailController.text.trim(),
        password: _companyPasswordController.text.trim(),
      );

      String userId = userCredential.user!.uid;

      await _firestore.collection('Users').doc(userId).set({
        'UserID': userId,
        'UserType': 'Company',
        'Email':
            _companyEmailController.text.trim().toLowerCase(), // ✅ lowercase
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
        _companyEmailController.text.trim(),
        otp,
        'Company',
      );

      if (otpSent) {
        // ✅ إشعار الأدمن بالشركة الجديدة
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

        Navigator.pushReplacementNamed(
          context,
          '/otp-verification',
          arguments: {
            'email': _companyEmailController.text.trim(),
            'userId': userId,
            'userType': 'Company',
          },
        );
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

  Widget _buildCompanyForm() {
    return Column(
      children: [
        _buildTextField(
          label: 'Company Name',
          controller: _companyNameController,
          hint: 'Enter company name',
          validator: (v) => v == null || v.isEmpty ? 'Required' : null,
        ),
        SizedBox(height: 24),
        _buildTextField(
          label: 'Full Name',
          controller: _companyFullNameController,
          hint: 'Enter your full name (First Last)',
          validator: (v) {
            if (v == null || v.isEmpty) return 'Required';
            if (!_isValidFullName(v)) return 'At least 2 words (letters only)';
            return null;
          },
        ),
        SizedBox(height: 24),
        _buildTextField(
          label: 'Email',
          controller: _companyEmailController,
          hint: 'Enter your email',
          keyboardType: TextInputType.emailAddress,
          validator: (v) {
            if (v == null || v.isEmpty) return 'Required';
            if (!_isValidEmail(v)) return 'Invalid email address';
            return null;
          },
        ),
        SizedBox(height: 24),
        _buildPasswordField(_companyPasswordController),
        SizedBox(height: 24), // ✅ جديد
        _buildConfirmPasswordField(
          // ✅ جديد
          _companyPasswordController,
          _companyConfirmPasswordController,
        ),
        SizedBox(height: 40),
        _buildSignUpButton(_handleCompanySignup),
      ],
    );
  }

  Widget _buildJobSeekerForm() {
    return Column(
      children: [
        _buildTextField(
          label: 'Full Name',
          controller: _seekerNameController,
          hint: 'Enter your full name (First Last)',
          validator: (v) {
            if (v == null || v.isEmpty) return 'Required';
            if (!_isValidFullName(v)) return 'At least 2 words (letters only)';
            return null;
          },
        ),
        SizedBox(height: 24),
        _buildTextField(
          label: 'Email',
          controller: _seekerEmailController,
          hint: 'Enter your email',
          keyboardType: TextInputType.emailAddress,
          validator: (v) {
            if (v == null || v.isEmpty) return 'Required';
            if (!_isValidEmail(v)) return 'Invalid email address';
            return null;
          },
        ),
        SizedBox(height: 24),
        _buildPasswordField(_seekerPasswordController),
        SizedBox(height: 24), // ✅ جديد
        _buildConfirmPasswordField(
          // ✅ جديد
          _seekerPasswordController,
          _seekerConfirmPasswordController,
        ),
        SizedBox(height: 40),
        _buildSignUpButton(_handleJobSeekerSignup),
      ],
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required String hint,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFFFF7B7B),
          ),
        ),
        SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Color(0xFF4A5FBC), width: 2),
            borderRadius: BorderRadius.circular(16),
          ),
          child: TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey[400]),
              border: InputBorder.none,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            ),
            validator: validator,
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
            color: Color(0xFFFF7B7B),
          ),
        ),
        SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Color(0xFF4A5FBC), width: 2),
            borderRadius: BorderRadius.circular(16),
          ),
          child: TextFormField(
            controller: controller,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              hintText: 'Enter your password',
              hintStyle: TextStyle(color: Colors.grey[400]),
              border: InputBorder.none,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  color: Color(0xFF4A5FBC),
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Required';
              if (v.length < 8) return 'At least 8 characters';
              return null;
            },
          ),
        ),
        SizedBox(height: 12),
        Text(
          'Must include: uppercase, lowercase, number, special character',
          style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontStyle: FontStyle.italic),
        ),
      ],
    );
  }

  // ✅ دالة جديدة لبناء Confirm Password Field
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
            color: Color(0xFFFF7B7B),
          ),
        ),
        SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Color(0xFF4A5FBC), width: 2),
            borderRadius: BorderRadius.circular(16),
          ),
          child: TextFormField(
            controller: confirmPasswordController,
            obscureText: _obscureConfirmPassword,
            decoration: InputDecoration(
              hintText: 'Re-enter your password',
              hintStyle: TextStyle(color: Colors.grey[400]),
              border: InputBorder.none,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirmPassword
                      ? Icons.visibility_off
                      : Icons.visibility,
                  color: Color(0xFF4A5FBC),
                ),
                onPressed: () => setState(
                    () => _obscureConfirmPassword = !_obscureConfirmPassword),
              ),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Required';
              if (v != passwordController.text) return 'Passwords do not match';
              return null;
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSignUpButton(VoidCallback onPressed) {
    return _isLoading
        ? Center(child: CircularProgressIndicator())
        : ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFF4A5FBC),
              minimumSize: Size(double.infinity, 56),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            child: Text(
              'Sign Up',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white),
            ),
          );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Color(0xFF4A5FBC)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                SizedBox(height: 20),
                Image.asset('assets/images/logo.jpg', height: 120, width: 120),
                SizedBox(height: 30),
                Text(
                  'Create Account',
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF4A5FBC)),
                ),
                SizedBox(height: 30),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedTab = 0),
                          child: Container(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            decoration: BoxDecoration(
                              color: _selectedTab == 0
                                  ? Color(0xFF4A5FBC)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              'Company',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: _selectedTab == 0
                                    ? Colors.white
                                    : Colors.grey,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedTab = 1),
                          child: Container(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            decoration: BoxDecoration(
                              color: _selectedTab == 1
                                  ? Color(0xFF4A5FBC)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              'Job Seeker',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: _selectedTab == 1
                                    ? Colors.white
                                    : Colors.grey,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 40),
                _selectedTab == 0 ? _buildCompanyForm() : _buildJobSeekerForm(),
                SizedBox(height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Already have an account? ',
                        style: TextStyle(color: Colors.grey[600])),
                    GestureDetector(
                      onTap: () =>
                          Navigator.pushReplacementNamed(context, '/login'),
                      child: Text(
                        'Login',
                        style: TextStyle(
                            color: Color(0xFF4A5FBC),
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
