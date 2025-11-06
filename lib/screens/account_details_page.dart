// lib/screens/account_details_page.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:gp_2025_11/l10n/app_localizations.dart';
import 'dart:math';

class AccountDetailsPage extends StatefulWidget {
  final String userId;
  final String userType;

  const AccountDetailsPage({
    super.key,
    required this.userId,
    required this.userType,
  });

  @override
  State<AccountDetailsPage> createState() => _AccountDetailsPageState();
}

class _AccountDetailsPageState extends State<AccountDetailsPage> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  bool _isEditing = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _showSnackSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showSnackError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ========== OTP GENERATION ==========
  String _generateOTP() {
    Random random = Random();
    return (100000 + random.nextInt(900000)).toString();
  }

  // ========== SEND OTP EMAIL ==========
  Future<bool> _sendOTPEmail(String email, String otp, String userType) async {
    try {
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final callable = userType == 'Admin'
          ? functions.httpsCallable('sendAdminOtp')
          : functions.httpsCallable('sendSignupOtp');

      final Map<String, dynamic> params = {
        'email': email.trim(),
        'otp': otp.trim(),
      };

      if (userType != 'Admin') {
        params['userType'] = userType;
      }

      final result = await callable.call(params);

      if (result.data != null && result.data['success'] == true) {
        await FirebaseFirestore.instance
            .collection('AdminOTPs')
            .doc(email)
            .set({
          'OTP': otp,
          'Email': email,
          'UserType': userType,
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
      print('Error sending OTP: $e');
      return false;
    }
  }

  // ========== EMAIL CHANGE WARNING DIALOG (FOR COMPANIES) ==========
  Future<bool> _showEmailChangeWarningForCompany(
      String oldEmail, String newEmail) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            SizedBox(width: 10),
            Expanded(child: Text('Email Change Warning')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Important Information:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),
              const Text('• Your account status will change to "Pending"'),
              const SizedBox(height: 8),
              const Text(
                  '• Admin approval will be required after verification'),
              const SizedBox(height: 8),
              const Text('• An OTP will be sent to your new email'),
              const SizedBox(height: 8),
              const Text('• You must verify the OTP to complete the change'),
              const SizedBox(height: 8),
              const Text('• You will be logged out after verification'),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Old email: $oldEmail',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'New email: $newEmail',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    return confirmed ?? false;
  }

  // ========== SIMPLE EMAIL CHANGE CONFIRMATION (FOR JOB SEEKERS) ==========
  Future<bool> _showEmailChangeConfirmation(
      String oldEmail, String newEmail) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.info_outline, color: Color(0xFF4A5FBC), size: 28),
            SizedBox(width: 10),
            Text('Confirm Email Change'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'An OTP will be sent to your new email for verification.'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Old email: $oldEmail',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'New email: $newEmail',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF4A5FBC)),
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    return confirmed ?? false;
  }

  // ========== SAVE CHANGES ==========
  Future<void> _saveChanges(String currentEmail, String currentName) async {
    final newName = _nameController.text.trim();
    final newEmail = _emailController.text.trim();

    if (newName.isEmpty) {
      _showSnackError('Name cannot be empty');
      return;
    }

    if (newEmail.isEmpty ||
        !RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(newEmail)) {
      _showSnackError('Please enter a valid email');
      return;
    }

    // Check if email changed
    final emailChanged = newEmail != currentEmail;

    if (emailChanged) {
      // Show appropriate warning based on user type
      bool confirmed;
      if (widget.userType == 'Company') {
        confirmed =
            await _showEmailChangeWarningForCompany(currentEmail, newEmail);
      } else {
        confirmed = await _showEmailChangeConfirmation(currentEmail, newEmail);
      }

      if (!confirmed) {
        return; // User cancelled
      }

      // Send OTP
      setState(() => _isSaving = true);
      try {
        final otp = _generateOTP();
        final success = await _sendOTPEmail(newEmail, otp, widget.userType);

        if (!success) {
          _showSnackError('Failed to send OTP. Please try again.');
          setState(() => _isSaving = false);
          return;
        }

        // Update database
        final updates = <String, dynamic>{
          'Email': newEmail,
          'IsEmailVerified': false,
        };

        // Update name if changed
        if (newName != currentName) {
          updates['Name'] = newName;
        }

        // For companies, set account status to pending
        if (widget.userType == 'Company') {
          updates['AccountStatus'] = 'Pending';
        }

        await FirebaseFirestore.instance
            .collection('Users')
            .doc(widget.userId)
            .update(updates);

        if (!mounted) return;

        // Navigate to OTP verification
        Navigator.pushReplacementNamed(
          context,
          '/otp-verification',
          arguments: {
            'email': newEmail,
            'userId': widget.userId,
            'userType': widget.userType,
          },
        );
      } catch (e) {
        _showSnackError('Failed to update email: $e');
        setState(() => _isSaving = false);
      }
    } else {
      // Only name changed (no email change)
      if (newName == currentName) {
        _showSnackError('No changes to save');
        setState(() {
          _isEditing = false;
        });
        return;
      }

      setState(() => _isSaving = true);
      try {
        await FirebaseFirestore.instance
            .collection('Users')
            .doc(widget.userId)
            .update({'Name': newName});

        if (!mounted) return;
        _showSnackSuccess('Name updated successfully');
        setState(() {
          _isEditing = false;
          _isSaving = false;
        });
      } catch (e) {
        _showSnackError('Failed to update name: $e');
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isJobSeeker = widget.userType == 'JobSeeker';
    final brandColor = const Color(0xFF4A5FBC);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Account Details'),
        backgroundColor: brandColor,
        actions: [
          if (!_isEditing)
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.white),
              tooltip: 'Edit Account Details',
              onPressed: () {
                setState(() => _isEditing = true);
              },
            ),
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              tooltip: 'Cancel',
              onPressed: () {
                setState(() => _isEditing = false);
              },
            ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('Users')
            .doc(widget.userId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError ||
              !snapshot.hasData ||
              !snapshot.data!.exists) {
            return const Center(child: Text('Failed to load user data.'));
          }

          final userData = snapshot.data!.data()!;

          final registeredFullName = userData['Name'] ?? 'N/A';
          final registeredEmail = userData['Email'] ?? 'N/A';
          final companyName = userData['CompanyName'] ?? 'N/A';

          // Initialize controllers with current values when entering edit mode
          if (_isEditing) {
            if (_nameController.text.isEmpty) {
              _nameController.text = registeredFullName;
            }
            if (_emailController.text.isEmpty) {
              _emailController.text = registeredEmail;
            }
          } else {
            // Clear controllers when not editing
            _nameController.clear();
            _emailController.clear();
          }

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // Name Field
              if (_isEditing)
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: l10n.fullNameLabel,
                    prefixIcon:
                        const Icon(Icons.person, color: Color(0xFF4A5FBC)),
                    border: const OutlineInputBorder(),
                  ),
                )
              else
                _DetailCard(
                  icon: Icons.person,
                  label: l10n.fullNameLabel,
                  value: registeredFullName,
                ),

              const SizedBox(height: 15),

              // Company Name (for companies only, not editable)
              if (!isJobSeeker)
                _DetailCard(
                  icon: Icons.business,
                  label: l10n.companyNameLabel,
                  value: companyName,
                ),

              if (!isJobSeeker) const SizedBox(height: 15),

              // Email Field
              if (_isEditing)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: l10n.registeredEmailLabel,
                        prefixIcon:
                            const Icon(Icons.email, color: Color(0xFF4A5FBC)),
                        border: const OutlineInputBorder(),
                        suffixIcon: _emailController.text.trim() !=
                                registeredEmail
                            ? const Tooltip(
                                message: 'Changing email requires verification',
                                child: Icon(Icons.warning_amber_rounded,
                                    color: Colors.orange),
                              )
                            : null,
                      ),
                    ),
                    if (_emailController.text.trim() != registeredEmail)
                      Padding(
                        padding: const EdgeInsets.only(top: 8, left: 12),
                        child: Text(
                          widget.userType == 'Company'
                              ? '⚠️ Changing email will set your account status to Pending. Admin approval will be required after OTP verification.'
                              : '⚠️ Changing email requires OTP verification.',
                          style: const TextStyle(
                            color: Colors.orange,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                )
              else
                _DetailCard(
                  icon: Icons.email,
                  label: l10n.registeredEmailLabel,
                  value: registeredEmail,
                ),

              if (_isEditing) ...[
                const SizedBox(height: 30),
                FilledButton(
                  onPressed: _isSaving
                      ? null
                      : () => _saveChanges(registeredEmail, registeredFullName),
                  style: FilledButton.styleFrom(
                    backgroundColor: brandColor,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Save Changes'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0.5,
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF4A5FBC)),
        title: Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        subtitle: Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}
