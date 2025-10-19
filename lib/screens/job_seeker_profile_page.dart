import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // kDebugMode
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

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

// DEV shortcut: set to false before release
const bool kDevSkipOtp = true;

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
  String? _serverPhone;
  DateTime? _dob;
  bool _saving = false;
  bool _phoneVerified = false;
  double? _progress; // 0..1 while uploading

  @override
  void initState() {
    super.initState();
    _phone.addListener(() {
      final t = _phone.text.trim();
      if (_serverPhone == null) return;
      if (t != _serverPhone && _phoneVerified) {
        setState(() => _phoneVerified = false);
      }
    });
  }

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  bool _isAdult(DateTime dob) {
    final now = DateTime.now();
    int years = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      years--;
    }
    return years >= 18;
  }

  Future<String> _uploadWithProgress({
    required String pathPrefix,
    required File file,
    required List<String> exts,
    required int maxBytes,
  }) async {
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

    setState(() => _progress = 0);
    final task = ref.putFile(file);
    task.snapshotEvents.listen((snap) {
      if (snap.totalBytes > 0) {
        setState(() => _progress = snap.bytesTransferred / snap.totalBytes);
      }
    });
    final snap = await task;
    final url = await snap.ref.getDownloadURL();
    setState(() => _progress = null);
    return url;
  }

  Future<void> _pickCV() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx'],
    );
    if (res == null || res.files.single.path == null) return;
    try {
      final url = await _uploadWithProgress(
        pathPrefix: 'cv',
        file: File(res.files.single.path!),
        exts: ['pdf', 'docx'],
        maxBytes: 10 * 1024 * 1024,
      );
      setState(() => _cvUrl = url);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('CV uploaded')));
    } catch (_) {
      setState(() => _progress = null);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('CV upload failed')));
    }
  }

  Future<void> _openCV(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Cannot open CV')));
    }
  }

  Future<void> _pickPhoto() async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (src == null) return;

    final img = await ImagePicker().pickImage(source: src, imageQuality: 92);
    if (img == null) return;
    try {
      final url = await _uploadWithProgress(
        pathPrefix: 'photos',
        file: File(img.path),
        exts: ['jpg', 'jpeg', 'png'],
        maxBytes: 5 * 1024 * 1024,
      );
      setState(() => _photoUrl = url);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Photo uploaded')));
    } catch (_) {
      setState(() => _progress = null);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Photo upload failed')));
    }
  }

  // DEV shortcut: instantly mark phone verified and save it to Firestore.
  Future<void> _devInstantVerifyPhone() async {
    if (!kDebugMode || !kDevSkipOtp) return;
    final phone = _phone.text.trim();
    if (!_e164.hasMatch(phone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid phone format (+E.164)')),
      );
      return;
    }
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      await FirebaseFirestore.instance
          .collection(kUsersCollection)
          .doc(uid)
          .set({
        UserFields.phone: phone,
        UserFields.phoneVerified: true,
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() {
        _serverPhone = phone;
        _phoneVerified = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phone marked as verified (DEV)')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to mark verified: $e')),
      );
    }
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
    if (_progress != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please wait for uploads to finish')),
      );
      return;
    }

    final uid = FirebaseAuth.instance.currentUser!.uid;
    final data = <String, dynamic>{
      UserFields.cvUrl: (_cvUrl == '')
          ? FieldValue.delete()
          : (_cvUrl ?? current[UserFields.cvUrl]),
      UserFields.photoUrl: (_photoUrl == '')
          ? FieldValue.delete()
          : (_photoUrl ?? current[UserFields.photoUrl]),
      UserFields.dob: Timestamp.fromDate(_dob!),
      UserFields.nationality: _nationality,
      UserFields.phone: _phone.text.trim(),
      UserFields.phoneVerified: true,
    };

    final cvOk = (data[UserFields.cvUrl] ?? '').toString().isNotEmpty;
    final photoOk = (data[UserFields.photoUrl] ?? '').toString().isNotEmpty;
    final dobOk = data[UserFields.dob] != null;
    final natOk = (data[UserFields.nationality] ?? '').toString().isNotEmpty;
    final phoneOk = (data[UserFields.phone] ?? '').toString().isNotEmpty;
    final complete = cvOk && photoOk && dobOk && natOk && phoneOk;

    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection(kUsersCollection)
          .doc(uid)
          .set(
        {...data, UserFields.isProfileComplete: complete},
        SetOptions(merge: true),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Saved')));
      Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
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
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final data = snap.data?.data() ?? {};
        final serverPhoneVal = (data[UserFields.phone] ?? '').toString();
        _serverPhone ??= serverPhoneVal;
        _phoneVerified =
            _phoneVerified || (data[UserFields.phoneVerified] == true);

        final dobCurrent = data[UserFields.dob] is Timestamp
            ? (data[UserFields.dob] as Timestamp).toDate()
            : null;

        final dobText = (_dob ?? dobCurrent) == null
            ? 'Select date'
            : DateFormat('yyyy/MM/dd').format(_dob ?? dobCurrent!);

        if (_phone.text.isEmpty && serverPhoneVal.isNotEmpty) {
          _phone.text = serverPhoneVal;
        }

        final hasCV =
            (_cvUrl ?? data[UserFields.cvUrl])?.toString().isNotEmpty == true;
        final hasPhoto =
            (_photoUrl ?? data[UserFields.photoUrl])?.toString().isNotEmpty ==
                true;
        final profileComplete = (data[UserFields.isProfileComplete] == true) ||
            (hasCV &&
                hasPhoto &&
                ((_dob ?? dobCurrent) != null) &&
                ((_nationality ?? data[UserFields.nationality])
                        ?.toString()
                        .isNotEmpty ==
                    true) &&
                (_phone.text.trim().isNotEmpty) &&
                _phoneVerified);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Profile'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12, top: 12, bottom: 12),
                child: Tooltip(
                  message: profileComplete
                      ? 'Profile complete'
                      : 'Profile incomplete',
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: profileComplete
                          ? Colors.green.withOpacity(.15)
                          : Colors.orange.withOpacity(.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          profileComplete
                              ? Icons.check_circle
                              : Icons.error_outline,
                          size: 16,
                          color: profileComplete ? Colors.green : Colors.orange,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          profileComplete ? 'Complete' : 'Incomplete',
                          style: TextStyle(
                            color:
                                profileComplete ? Colors.green : Colors.orange,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            minimum: const EdgeInsets.all(12),
            child: FilledButton(
              onPressed:
                  (_saving || _progress != null) ? null : () => _save(data),
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
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_progress != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: LinearProgressIndicator(value: _progress),
                  ),
                Row(
                  children: [
                    Hero(
                      tag: 'profileAvatar',
                      child: CircleAvatar(
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
                    ),
                    const SizedBox(width: 12),
                    FilledButton.tonal(
                      onPressed:
                          (_saving || _progress != null) ? null : _pickPhoto,
                      child: const Text('Upload Photo'),
                    ),
                    const SizedBox(width: 8),
                    if (hasPhoto)
                      TextButton(
                        onPressed: (_saving || _progress != null)
                            ? null
                            : () => setState(() => _photoUrl = ''),
                        child: const Text('Remove'),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('CV File'),
                  subtitle: Text(
                    (_cvUrl ?? data[UserFields.cvUrl])?.toString() ?? 'No file',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Wrap(
                    spacing: 8,
                    children: [
                      FilledButton.tonal(
                        onPressed:
                            (_saving || _progress != null) ? null : _pickCV,
                        child: const Text('Upload CV'),
                      ),
                      if (hasCV)
                        TextButton(
                          onPressed: () => _openCV(
                              (_cvUrl ?? data[UserFields.cvUrl]).toString()),
                          child: const Text('Open'),
                        ),
                      if (hasCV)
                        TextButton(
                          onPressed: (_saving || _progress != null)
                              ? null
                              : () => setState(() => _cvUrl = ''),
                          child: const Text('Remove'),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Date of Birth'),
                  subtitle: Text(dobText),
                  trailing: FilledButton.tonal(
                    onPressed: (_saving || _progress != null)
                        ? null
                        : () async {
                            final now = DateTime.now();
                            final initial = _dob ??
                                dobCurrent ??
                                DateTime(now.year - 20, now.month, now.day);
                            final first = DateTime(now.year - 80, 1, 1);
                            final last =
                                DateTime(now.year - 18, now.month, now.day);
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
                  onChanged: (_saving || _progress != null)
                      ? null
                      : (v) => setState(() => _nationality = v),
                  decoration: const InputDecoration(
                      labelText: 'Nationality', border: OutlineInputBorder()),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Select nationality' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Phone (+E.164)',
                    border: const OutlineInputBorder(),
                    suffixIcon: TextButton(
                      onPressed: (_saving || _progress != null)
                          ? null
                          : () {
                              if (kDebugMode && kDevSkipOtp) {
                                _devInstantVerifyPhone(); // DEV shortcut
                              } else {
                                Navigator.pushNamed(
                                  context,
                                  '/otp-verification',
                                  arguments: {
                                    'email': FirebaseAuth
                                        .instance.currentUser!.email,
                                    'userId':
                                        FirebaseAuth.instance.currentUser!.uid,
                                    'userType': 'JobSeeker',
                                  },
                                );
                              }
                            },
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
