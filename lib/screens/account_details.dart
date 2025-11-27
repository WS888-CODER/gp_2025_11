// lib/screens/account_details_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gp_2025_11/config/theme.dart';
import 'package:gp_2025_11/config/themed_scaffold.dart';

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

  bool _isEditing = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // Same validation logic as signup (Full Name):
  // - Letters and spaces only
  // - At least two words
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

  Future<void> _saveChanges(String currentName) async {
    final newName = _nameController.text.trim();

    if (newName.isEmpty) {
      SnackHelper.error(context, 'Name cannot be empty');
      return;
    }

    if (!_isValidFullName(newName)) {
      SnackHelper.error(
          context, 'Full name must be at least 2 words (letters only)');
      return;
    }

    if (newName == currentName) {
      SnackHelper.error(context, 'No changes to save');
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
      SnackHelper.success(context, 'Name updated successfully');

      setState(() {
        _isEditing = false;
      });
    } catch (e) {
      SnackHelper.error(context, 'Failed to update name: $e');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isJobSeeker = widget.userType == 'JobSeeker';
    const brandColor = AppTheme.primaryPurple;

    return ThemedScaffold(
      appBar: CustomHeader(
        title: 'My Account Details',
        actions: [
          if (!_isEditing)
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.white),
              tooltip: 'Edit Account Details',
              onPressed: () {
                setState(() => _isEditing = true);
              },
            )
          else
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              tooltip: 'Cancel',
              onPressed: () {
                setState(() {
                  _isEditing = false;
                  _nameController.clear();
                });
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
          final photoUrl = (userData['PhotoURL'] ?? '') as String;

          // When entering edit mode for the first time, prefill controller
          if (_isEditing && _nameController.text.isEmpty) {
            _nameController.text = registeredFullName;
          }

          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _AccountHeader(
                        fullName: registeredFullName,
                        email: registeredEmail,
                        userType: widget.userType,
                        photoUrl: photoUrl,
                      ),
                      const SizedBox(height: 20),

                      // Name section (editable)
                      _AccountSectionCard(
                        child: _isEditing
                            ? _EditableNameField(
                                controller: _nameController,
                                label: 'Full Name',
                              )
                            : _DetailTile(
                                icon: Icons.person,
                                label: 'Full Name',
                                value: registeredFullName,
                              ),
                      ),

                      const SizedBox(height: 12),

                      // Company name (read-only â€“ for companies only)
                      if (!isJobSeeker)
                        _AccountSectionCard(
                          child: _DetailTile(
                            icon: Icons.business,
                            label: 'Company Name',
                            value: companyName,
                          ),
                        ),

                      if (!isJobSeeker) const SizedBox(height: 12),

                      // Email (read-only)
                      _AccountSectionCard(
                        child: _DetailTile(
                          icon: Icons.email_outlined,
                          label: 'Registered Email',
                          value: registeredEmail,
                          subtitle: 'Email address cannot be changed.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Fixed Save Changes button at the bottom
              if (_isEditing)
                Container(
                  padding: const EdgeInsets.all(20),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      onPressed: _isSaving
                          ? null
                          : () => _saveChanges(registeredFullName),
                      style: FilledButton.styleFrom(
                        backgroundColor: brandColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                        elevation: 2,
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
                          : const Text(
                              'Save Changes',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/* ------------------ Header with avatar & basic info ------------------ */

class _AccountHeader extends StatelessWidget {
  final String fullName;
  final String email;
  final String userType;
  final String photoUrl;

  const _AccountHeader({
    required this.fullName,
    required this.email,
    required this.userType,
    required this.photoUrl,
  });

  @override
  Widget build(BuildContext context) {
    final initial =
        fullName.trim().isNotEmpty ? fullName.trim()[0].toUpperCase() : '?';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF4A5FBC),
            Color(0xFF6B7EF3),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4A5FBC).withOpacity(0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.white.withOpacity(0.15),
            backgroundImage:
                photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
            child: photoUrl.isEmpty
                ? Text(
                    initial,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withOpacity(0.85),
                      ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    userType == 'JobSeeker' ? 'Job Seeker' : 'Company',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/* ---------------------- Card wrapper for sections -------------------- */

class _AccountSectionCard extends StatelessWidget {
  final Widget child;

  const _AccountSectionCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF4A5FBC).withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

/* -------------------------- Detail display row ----------------------- */

class _DetailTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? subtitle;

  const _DetailTile({
    required this.icon,
    required this.label,
    required this.value,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      leading: Icon(icon, color: const Color(0xFF4A5FBC)),
      title: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          color: Colors.grey,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.grey,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/* --------------------- Editable name text field ---------------------- */

class _EditableNameField extends StatelessWidget {
  final TextEditingController controller;
  final String label;

  const _EditableNameField({
    required this.controller,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    const brandColor = AppTheme.primaryPurple;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.person, color: brandColor),
              hintText: 'Enter your full name',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: brandColor, width: 1.6),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }
}
