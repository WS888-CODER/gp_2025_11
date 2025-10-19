import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

const kUsersCollection = 'Users';

class UserFields {
  static const cvUrl = 'CVURL';
  static const photoUrl = 'PhotoURL';
  static const dob = 'DoB';
  static const nationality = 'Nationality';
  static const phone = 'Phone';
  static const phoneVerified = 'PhoneVerified';
  static const isProfileComplete = 'IsProfileComplete';
}

final _e164 = RegExp(r'^\+[1-9]\d{7,14}$');
const _countries = <String>[
  'Saudi Arabia',
  'United Arab Emirates',
  'Kuwait',
  'Qatar',
  'Bahrain',
  'Oman',
  'Jordan',
  'Egypt',
  'Morocco',
  'Tunisia',
  'Turkey',
  'United States',
  'United Kingdom',
  'Germany',
  'France',
  'India',
  'Pakistan',
  'Philippines',
];

class JobSeekerProfile extends StatefulWidget {
  const JobSeekerProfile({super.key});

  @override
  State<JobSeekerProfile> createState() => _JobSeekerProfileState();
}

class _JobSeekerProfileState extends State<JobSeekerProfile> {
  final _form = GlobalKey<FormState>();
  final _phone = TextEditingController();
  String? _cvUrl, _photoUrl, _nationality;
  DateTime? _dob;
  bool _saving = false;
  bool _phoneVerified = false;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<String> _upload(String pathPrefix, File file,
      {required List<String> exts, int maxBytes = 5 * 1024 * 1024}) async {
    final len = await file.length();
    if (len > maxBytes) {
      throw Exception('File too large');
    }
    final ext = file.path.split('.').last.toLowerCase();
    if (!exts.contains(ext)) {
      throw Exception('Unsupported file type');
    }
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final name = file.path.split('/').last;
    final ref = FirebaseStorage.instance
        .ref('$pathPrefix/$uid/${DateTime.now().millisecondsSinceEpoch}_$name');
    final snap = await ref.putFile(file);
    return await snap.ref.getDownloadURL();
  }

  Future<void> _pickCV() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx'],
    );
    if (res == null || res.files.single.path == null) return;
    try {
      final url = await _upload('cv', File(res.files.single.path!),
          exts: ['pdf', 'docx'], maxBytes: 10 * 1024 * 1024);
      setState(() => _cvUrl = url);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('CV uploaded')));
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('CV upload failed')));
    }
  }

  Future<void> _pickPhoto() async {
    final img = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 92);
    if (img == null) return;
    try {
      final url = await _upload('photos', File(img.path),
          exts: ['jpg', 'jpeg', 'png'], maxBytes: 5 * 1024 * 1024);
      setState(() => _photoUrl = url);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Photo uploaded')));
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Photo upload failed')));
    }
  }

  bool _isAdult(DateTime d) {
    final now = DateTime.now();
    final min = DateTime(d.year + 18, d.month, d.day);
    return !min.isAfter(now);
  }

  Future<void> _save(Map<String, dynamic> current) async {
    if (!_form.currentState!.validate()) return;
    if (_dob == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Select date of birth')));
      return;
    }
    if (!_isAdult(_dob!)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Must be at least 18')));
      return;
    }
    if (_nationality == null || _nationality!.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Select nationality')));
      return;
    }
    if (!_e164.hasMatch(_phone.text.trim())) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Invalid phone format')));
      return;
    }
    if (!_phoneVerified) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Verify phone')));
      return;
    }

    final uid = FirebaseAuth.instance.currentUser!.uid;
    final data = {
      UserFields.cvUrl: _cvUrl ?? current[UserFields.cvUrl],
      UserFields.photoUrl: _photoUrl ?? current[UserFields.photoUrl],
      UserFields.dob: Timestamp.fromDate(_dob!),
      UserFields.nationality: _nationality,
      UserFields.phone: _phone.text.trim(),
      UserFields.phoneVerified: true,
    };

    final complete = (data[UserFields.cvUrl] ?? '').toString().isNotEmpty &&
        (data[UserFields.photoUrl] ?? '').toString().isNotEmpty &&
        data[UserFields.dob] != null &&
        (data[UserFields.nationality] ?? '').toString().isNotEmpty &&
        (data[UserFields.phone] ?? '').toString().isNotEmpty;

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
        _phoneVerified = data[UserFields.phoneVerified] == true;

        final dobCurrent = data[UserFields.dob] is Timestamp
            ? (data[UserFields.dob] as Timestamp).toDate()
            : null;
        final dobText = (_dob ?? dobCurrent) == null
            ? 'Select date'
            : DateFormat('yyyy/MM/dd').format(_dob ?? dobCurrent!);

        return Scaffold(
          appBar: AppBar(title: const Text('Profile')),
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
                          (_photoUrl ?? data[UserFields.photoUrl]) != null &&
                                  (_photoUrl ?? data[UserFields.photoUrl])
                                      .toString()
                                      .isNotEmpty
                              ? NetworkImage(
                                  (_photoUrl ?? data[UserFields.photoUrl])
                                      .toString())
                              : null,
                      child:
                          ((_photoUrl ?? data[UserFields.photoUrl]) == null ||
                                  (_photoUrl ?? data[UserFields.photoUrl])
                                      .toString()
                                      .isEmpty)
                              ? const Icon(Icons.person)
                              : null,
                    ),
                    const SizedBox(width: 12),
                    FilledButton.tonal(
                        onPressed: _pickPhoto,
                        child: const Text('Upload Photo')),
                  ],
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Curriculum Vitae'),
                  subtitle: Text(
                      (_cvUrl ?? data[UserFields.cvUrl])?.toString() ??
                          'No file'),
                  trailing: FilledButton.tonal(
                      onPressed: _pickCV, child: const Text('Upload CV')),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Date of Birth'),
                  subtitle: Text(dobText),
                  trailing: FilledButton.tonal(
                    onPressed: () async {
                      final now = DateTime.now();
                      final initial = _dob ??
                          dobCurrent ??
                          DateTime(now.year - 20, now.month, now.day);
                      final first = DateTime(now.year - 80, 1, 1);
                      final last = DateTime(now.year - 18, now.month, now.day);
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: initial,
                        firstDate: first,
                        lastDate: last,
                      );
                      if (picked != null) setState(() => _dob = picked);
                    },
                    child: const Text('Pick'),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _countries.contains(
                          _nationality ?? data[UserFields.nationality])
                      ? (_nationality ?? data[UserFields.nationality])
                      : null,
                  items: _countries
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => setState(() => _nationality = v),
                  decoration: const InputDecoration(
                      labelText: 'Nationality', border: OutlineInputBorder()),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Select nationality' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phone
                    ..text = _phone.text.isNotEmpty
                        ? _phone.text
                        : (data[UserFields.phone] ?? ''),
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Phone (+E.164)',
                    border: const OutlineInputBorder(),
                    suffixIcon: TextButton(
                      onPressed: () =>
                          Navigator.pushNamed(context, '/otp-verification'),
                      child: Text(_phoneVerified ? 'Verified' : 'Verify'),
                    ),
                  ),
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    if (t.isEmpty) return 'Enter phone';
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
