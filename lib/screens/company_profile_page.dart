import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

const kUsersCollection = 'Users';

class UserFields {
  static const companyName = 'CompanyName';
  static const photoUrl = 'PhotoURL';
  static const description = 'Description';
  static const location = 'Location';
  static const contactEmail = 'ContactEmail';
  static const phone = 'Phone';
  static const isProfileComplete = 'IsProfileComplete';
}

final _email =
    RegExp(r"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$", caseSensitive: false);
final _e164 = RegExp(r'^\+[1-9]\d{7,14}$');

class CompanyProfile extends StatefulWidget {
  const CompanyProfile({super.key});

  @override
  State<CompanyProfile> createState() => _CompanyProfileState();
}

class _CompanyProfileState extends State<CompanyProfile> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _loc = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phone = TextEditingController();

  String? _logoUrl;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _loc.dispose();
    _emailCtrl.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<String> _uploadLogo(File file) async {
    final len = await file.length();
    if (len > 5 * 1024 * 1024) throw Exception('Image too large');
    final ext = file.path.split('.').last.toLowerCase();
    if (!['jpg', 'jpeg', 'png'].contains(ext))
      throw Exception('Unsupported image');
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final name = file.path.split('/').last;
    final ref = FirebaseStorage.instance
        .ref('logos/$uid/${DateTime.now().millisecondsSinceEpoch}_$name');
    final snap = await ref.putFile(file);
    return await snap.ref.getDownloadURL();
  }

  Future<void> _pickLogo() async {
    final img = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 92);
    if (img == null) return;
    try {
      final url = await _uploadLogo(File(img.path));
      setState(() => _logoUrl = url);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Logo uploaded')));
    } catch (_) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Logo upload failed')));
    }
  }

  Future<void> _save(Map<String, dynamic> current) async {
    if (!_form.currentState!.validate()) return;

    final email = _emailCtrl.text.trim();
    if (!_email.hasMatch(email)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Invalid email')));
      return;
    }
    final phone = _phone.text.trim();
    if (phone.isNotEmpty && !_e164.hasMatch(phone)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Invalid phone')));
      return;
    }

    final uid = FirebaseAuth.instance.currentUser!.uid;
    final data = {
      UserFields.companyName: _name.text.trim(),
      UserFields.photoUrl: _logoUrl ?? current[UserFields.photoUrl],
      UserFields.description: _desc.text.trim(),
      UserFields.location: _loc.text.trim(),
      UserFields.contactEmail: email,
      UserFields.phone: phone,
    };

    final complete = data[UserFields.description].toString().length >= 100 &&
        data[UserFields.location].toString().isNotEmpty &&
        data[UserFields.contactEmail].toString().isNotEmpty;

    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection(kUsersCollection)
          .doc(uid)
          .set({...data, UserFields.isProfileComplete: complete},
              SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Saved')));
      Navigator.pop(context);
    } catch (_) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Save failed')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Not signed in')));
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection(kUsersCollection)
          .doc(user.uid)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        final data = snap.data?.data() ?? {};

        _name.text = _name.text.isNotEmpty
            ? _name.text
            : (data[UserFields.companyName] ?? '');
        _desc.text = _desc.text.isNotEmpty
            ? _desc.text
            : (data[UserFields.description] ?? '');
        _loc.text = _loc.text.isNotEmpty
            ? _loc.text
            : (data[UserFields.location] ?? '');
        _emailCtrl.text = _emailCtrl.text.isNotEmpty
            ? _emailCtrl.text
            : (data[UserFields.contactEmail] ?? '');
        _phone.text = _phone.text.isNotEmpty
            ? _phone.text
            : (data[UserFields.phone] ?? '');

        return Scaffold(
          appBar: AppBar(title: const Text('Company Profile')),
          bottomNavigationBar: SafeArea(
            minimum: const EdgeInsets.all(12),
            child: FilledButton(
              onPressed: _saving ? null : () => _save(data),
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save'),
            ),
          ),
          body: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundImage:
                          (_logoUrl ?? data[UserFields.photoUrl]) != null &&
                                  (_logoUrl ?? data[UserFields.photoUrl])
                                      .toString()
                                      .isNotEmpty
                              ? NetworkImage(
                                  (_logoUrl ?? data[UserFields.photoUrl])
                                      .toString())
                              : null,
                      child: ((_logoUrl ?? data[UserFields.photoUrl]) == null ||
                              (_logoUrl ?? data[UserFields.photoUrl])
                                  .toString()
                                  .isEmpty)
                          ? const Icon(Icons.business)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    FilledButton.tonal(
                        onPressed: _pickLogo, child: const Text('Upload Logo')),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(
                      labelText: 'Company Name', border: OutlineInputBorder()),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Enter company name'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _desc,
                  maxLines: 4,
                  decoration: const InputDecoration(
                      labelText: 'Description (min 100 chars)',
                      border: OutlineInputBorder()),
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    if (t.isEmpty) return 'Enter description';
                    if (t.length < 100) return 'Too short';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _loc,
                  decoration: const InputDecoration(
                      labelText: 'Location', border: OutlineInputBorder()),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Enter location' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                      labelText: 'Contact Email', border: OutlineInputBorder()),
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    if (t.isEmpty) return 'Enter email';
                    if (!_email.hasMatch(t)) return 'Invalid email';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                      labelText: 'Contact Phone (+E.164)',
                      border: OutlineInputBorder()),
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    if (t.isEmpty) return null;
                    if (!_e164.hasMatch(t)) return 'Invalid phone';
                    return null;
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
