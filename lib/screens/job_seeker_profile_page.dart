import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // <-- NEW for input formatters
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
  static const isProfileComplete = 'IsProfileComplete';
  static const cvPath = 'CVPath';
  static const photoPath = 'PhotoPath';
}

// صيغة الهاتف المحلية: يبدأ بـ 5 وطوله 9 أرقام (سعودي)
final _localSaPhone = RegExp(r'^5\d{8}$');
const _saPrefix = '+966';

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
  double? _progress;
  File? _pendingPhotoFile; // صورة محليّة قبل الرفع
  File? _pendingCvFile;
  static const int _kMaxImageBytes = 5 * 1024 * 1024; // 5MB
  static const int _kMaxCvBytes = 10 * 1024 * 1024; // 10MB

  String? _validateImageFile(File f) {
    final len = f.lengthSync();
    if (len > _kMaxImageBytes) return 'Image too large (max 5 MB)';
    final ext = f.path.split('.').last.toLowerCase();
    final normalized = (ext == 'jpeg') ? 'jpg' : ext;
    if (!['jpg', 'png'].contains(normalized)) {
      return 'Unsupported image (JPG/PNG only)';
    }
    return null; // valid
  }

  String? _validateCvFile(File f) {
    final len = f.lengthSync();
    if (len > _kMaxCvBytes) return 'File too large (max 10 MB)';
    final ext = f.path.split('.').last.toLowerCase();
    if (!['pdf', 'docx'].contains(ext)) {
      return 'Unsupported file (PDF/DOCX only)';
    }
    return null; // valid
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
  // ======================================================================

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  String _toLocal(String e164) {
    final t = e164.trim();
    if (t.startsWith(_saPrefix)) return t.substring(_saPrefix.length);
    return t;
  }

  Future<Map<String, String>> _uploadPhoto(File file) async {
    final err = _validateImageFile(file);
    if (err != null) throw Exception(err);

    final uid = FirebaseAuth.instance.currentUser!.uid;
    final name = file.path.split('/').last;
    final ref = FirebaseStorage.instance.ref(
      'photos/$uid/${DateTime.now().millisecondsSinceEpoch}_$name',
    );

    setState(() => _progress = 0);
    final task = ref.putFile(file);
    task.snapshotEvents.listen((s) {
      if (!mounted) return;
      final total = s.totalBytes;
      if (total > 0) setState(() => _progress = s.bytesTransferred / total);
    });

    final snap = await task;
    final url = await snap.ref.getDownloadURL();
    final path = snap.ref.fullPath;
    if (mounted) setState(() => _progress = null);
    return {'url': url, 'path': path};
  }

  Future<Map<String, String>> _uploadCv(File file) async {
    final err = _validateCvFile(file);
    if (err != null) throw Exception(err);

    final uid = FirebaseAuth.instance.currentUser!.uid;
    final name = file.path.split('/').last;
    final ref = FirebaseStorage.instance.ref(
      'cv/$uid/${DateTime.now().millisecondsSinceEpoch}_$name',
    );

    setState(() => _progress = 0);
    final task = ref.putFile(file);
    task.snapshotEvents.listen((s) {
      if (!mounted) return;
      final total = s.totalBytes;
      if (total > 0) setState(() => _progress = s.bytesTransferred / total);
    });

    final snap = await task;
    final url = await snap.ref.getDownloadURL();
    final path = snap.ref.fullPath;
    if (mounted) setState(() => _progress = null);
    return {'url': url, 'path': path};
  }

  Future<void> _deleteStorageFile(String? pathOrUrl) async {
    if (pathOrUrl == null || pathOrUrl.isEmpty) return;
    try {
      final isUrl =
          pathOrUrl.startsWith('http') || pathOrUrl.startsWith('gs://');
      final ref = isUrl
          ? FirebaseStorage.instance.refFromURL(pathOrUrl)
          : FirebaseStorage.instance.ref(pathOrUrl);
      await ref.delete();
    } catch (_) {/* ignore */}
  }

  Future<void> _pickCV() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx'],
    );
    if (res == null || res.files.single.path == null) return;

    final file = File(res.files.single.path!);

    // ✅ لا نرفع الآن — بس نخزن محلي
    setState(() {
      _pendingCvFile = file;
    });
    _showSnackSuccess('CV selected.');
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

    // ✅ لا نرفع الآن — بس نخزن محلي ونحدث المعاينة
    setState(() {
      _pendingPhotoFile = File(img.path);
    });
    _showSnackSuccess('Photo selected.');
  }

  Future<void> _save(Map<String, dynamic> current) async {
    if (_progress != null) {
      _showSnackError('Please wait for uploads to finish');
      return;
    }

    // قيم حالية من السيرفر
    final dobCurrent = current[UserFields.dob] is Timestamp
        ? (current[UserFields.dob] as Timestamp).toDate()
        : null;

    // تحقّق الجنسية (لو تم تغييرها)
    if (_nationality != null && _nationality!.isEmpty) {
      _showSnackError('Select nationality');
      return;
    }

    // تحقّق الهاتف المحلي (5XXXXXXXX)
    final local = _phone.text.trim();
    if (local.isNotEmpty && !_localSaPhone.hasMatch(local)) {
      _showSnackError('Enter a valid Saudi mobile number');
      return;
    }

    // حضّري التحديثات
    final updates = <String, dynamic>{};

    // ========== 1) ارفعي الملفات المعلّقة ==========
    String? newPhotoUrl, newPhotoPath;
    String? newCvUrl, newCvPath;

    try {
      if (_pendingPhotoFile != null) {
        final res = await _uploadPhoto(_pendingPhotoFile!);
        newPhotoUrl = res['url'];
        newPhotoPath = res['path'];
        _pendingPhotoFile = null;
      }

      if (_pendingCvFile != null) {
        final res = await _uploadCv(_pendingCvFile!);
        newCvUrl = res['url'];
        newCvPath = res['path'];
        _pendingCvFile = null;
      }
    } catch (e) {
      _showSnackError(e.toString());
      return;
    }

    // ========== 2) ضعي التغييرات في updates ==========
    // CV - check new uploads first, then deletions
    if (newCvUrl != null) {
      updates[UserFields.cvUrl] = newCvUrl;
      if (newCvPath != null) updates[UserFields.cvPath] = newCvPath;
      _cvUrl = newCvUrl;
    } else if (_cvUrl == '') {
      updates[UserFields.cvUrl] = FieldValue.delete();
      updates[UserFields.cvPath] = FieldValue.delete();
    }

    // Photo - check new uploads first, then deletions
    if (newPhotoUrl != null) {
      updates[UserFields.photoUrl] = newPhotoUrl;
      if (newPhotoPath != null) updates[UserFields.photoPath] = newPhotoPath;
      _photoUrl = newPhotoUrl;
    } else if (_photoUrl == '') {
      updates[UserFields.photoUrl] = FieldValue.delete();
      updates[UserFields.photoPath] = FieldValue.delete();
    }

    // DOB
    if (_dob != null && _dob != dobCurrent) {
      updates[UserFields.dob] = Timestamp.fromDate(_dob!);
    }

    // Nationality
    if (_nationality != null &&
        _nationality != current[UserFields.nationality]) {
      updates[UserFields.nationality] = _nationality;
    }

    // Phone (حفظ بصيغة E.164 +9665XXXXXXXX إذا تغيّر)
    if (local.isNotEmpty && _localSaPhone.hasMatch(local)) {
      final e164 = '$_saPrefix$local';
      if (e164 != (current[UserFields.phone] ?? '')) {
        updates[UserFields.phone] = e164;
      }
    }

    if (updates.isEmpty) {
      _showSnackError('No changes to save');
      return;
    }

    // ========== 3) احسبي IsProfileComplete بعد الدمج ==========
    final merged = {...current, ...updates};

    final cvOk = (merged[UserFields.cvUrl] ?? '').toString().isNotEmpty;
    final photoOk = (merged[UserFields.photoUrl] ?? '').toString().isNotEmpty;
    final dobOk = merged[UserFields.dob] != null;
    final natOk = (merged[UserFields.nationality] ?? '').toString().isNotEmpty;

    final phoneMerged = (merged[UserFields.phone] ?? '').toString();
    final phoneLocal =
        phoneMerged.startsWith(_saPrefix) ? _toLocal(phoneMerged) : phoneMerged;
    final phoneOk = phoneLocal.isNotEmpty && _localSaPhone.hasMatch(phoneLocal);

    final complete = cvOk && photoOk && dobOk && natOk && phoneOk;
    updates[UserFields.isProfileComplete] = complete;

    // ========== 4) نفّذي الحفظ ==========
    final uid = FirebaseAuth.instance.currentUser!.uid;
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection(kUsersCollection)
          .doc(uid)
          .set(updates, SetOptions(merge: true));

      // ========== 5) تنظيف الملفات القديمة إن تغيّرت ==========
      // Photo
      if (newPhotoUrl != null) {
        final oldPhotoPath = (current[UserFields.photoPath] ?? '').toString();
        if (oldPhotoPath.isNotEmpty) {
          await _deleteStorageFile(oldPhotoPath);
        } else {
          final oldPhotoUrl = (current[UserFields.photoUrl] ?? '').toString();
          if (oldPhotoUrl.isNotEmpty) await _deleteStorageFile(oldPhotoUrl);
        }
      }
      if (_photoUrl == '' &&
          (current[UserFields.photoPath]?.toString().isNotEmpty ?? false)) {
        await _deleteStorageFile(current[UserFields.photoPath]?.toString());
      } else if (_photoUrl == '' &&
          (current[UserFields.photoUrl]?.toString().isNotEmpty ?? false)) {
        await _deleteStorageFile(current[UserFields.photoUrl]?.toString());
      }

      // CV
      if (newCvUrl != null) {
        final oldCvPath = (current[UserFields.cvPath] ?? '').toString();
        if (oldCvPath.isNotEmpty) {
          await _deleteStorageFile(oldCvPath);
        } else {
          final oldCvUrl = (current[UserFields.cvUrl] ?? '').toString();
          if (oldCvUrl.isNotEmpty) await _deleteStorageFile(oldCvUrl);
        }
      }
      if (_cvUrl == '' &&
          (current[UserFields.cvPath]?.toString().isNotEmpty ?? false)) {
        await _deleteStorageFile(current[UserFields.cvPath]?.toString());
      } else if (_cvUrl == '' &&
          (current[UserFields.cvUrl]?.toString().isNotEmpty ?? false)) {
        await _deleteStorageFile(current[UserFields.cvUrl]?.toString());
      }

      if (!mounted) return;
      _showSnackSuccess('✅ Profile updated successfully');
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      _showSnackError('❌ Failed to update profile');
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

        final serverPhoneE164 = (data[UserFields.phone] ?? '').toString();
        if (_phone.text.isEmpty && serverPhoneE164.isNotEmpty) {
          final local = _toLocal(serverPhoneE164);
          _phone.text = local.startsWith('5') ? local : '';
        }

        final dobCurrent = data[UserFields.dob] is Timestamp
            ? (data[UserFields.dob] as Timestamp).toDate()
            : null;

        final dobText = (_dob ?? dobCurrent) == null
            ? 'Select date'
            : DateFormat('yyyy/MM/dd').format(_dob ?? dobCurrent!);

        final hasCV = _pendingCvFile != null ||
            (_cvUrl != '' &&
                ((_cvUrl ?? data[UserFields.cvUrl])?.toString().isNotEmpty ??
                    false));

        final hasPhoto = _pendingPhotoFile != null ||
            (_photoUrl != '' &&
                ((_photoUrl ?? data[UserFields.photoUrl])
                        ?.toString()
                        .isNotEmpty ==
                    true));

        final phoneLocal = _phone.text.trim();
        final phoneValid = _localSaPhone.hasMatch(phoneLocal);

        final profileComplete = (data[UserFields.isProfileComplete] == true) ||
            (hasCV &&
                hasPhoto &&
                ((_dob ?? dobCurrent) != null) &&
                ((_nationality ?? data[UserFields.nationality])
                        ?.toString()
                        .isNotEmpty ==
                    true) &&
                phoneValid);
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
                  : const Text('Update Profile'),
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
                        radius: 54,
                        backgroundImage: _pendingPhotoFile != null
                            ? FileImage(_pendingPhotoFile!) as ImageProvider
                            : ((_photoUrl ?? data[UserFields.photoUrl]) !=
                                        null &&
                                    (_photoUrl ?? data[UserFields.photoUrl])
                                        .toString()
                                        .isNotEmpty)
                                ? NetworkImage(
                                    (_photoUrl ?? data[UserFields.photoUrl])
                                        .toString())
                                : null,
                        child: (_pendingPhotoFile == null &&
                                ((_photoUrl ?? data[UserFields.photoUrl]) ==
                                        null ||
                                    (_photoUrl ?? data[UserFields.photoUrl])
                                        .toString()
                                        .isEmpty))
                            ? const Icon(Icons.person)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Spacer(),
                    FilledButton.tonal(
                      onPressed:
                          (_saving || _progress != null) ? null : _pickPhoto,
                      child: const Text('Upload Photo'),
                    ),
                    const SizedBox(width: 8),
                    if (_pendingPhotoFile != null || hasPhoto)
                      TextButton(
                        onPressed: (_saving || _progress != null)
                            ? null
                            : () {
                                setState(() {
                                  _pendingPhotoFile = null;
                                  _photoUrl = '';
                                });
                              },
                        child: const Text('Remove'),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('CV File'),
                  subtitle: Text(
                    _pendingCvFile != null ||
                            (_cvUrl != '' &&
                                (data[UserFields.cvUrl]
                                        ?.toString()
                                        .isNotEmpty ??
                                    false))
                        ? 'File selected'
                        : 'No file',
                    style: const TextStyle(color: Colors.black54),
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
                          onPressed: (_saving || _progress != null)
                              ? null
                              : () {
                                  setState(() {
                                    _pendingCvFile = null;
                                    _cvUrl = '';
                                  });
                                },
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
                  validator: (v) {
                    final hasServerNat = (data[UserFields.nationality] ?? '')
                        .toString()
                        .isNotEmpty;
                    if (hasServerNat) return null;
                    return (v == null || v.isEmpty)
                        ? 'Select nationality'
                        : null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(9), // 5XXXXXXXX (9 digits)
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Phone',
                    hintText: '5XXXXXXXX',
                    prefixText: '+966 ',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    final hasServerPhone =
                        (data[UserFields.phone] ?? '').toString().isNotEmpty;
                    if (t.isEmpty) return hasServerPhone ? null : 'Enter phone';
                    if (!_localSaPhone.hasMatch(t)) {
                      return 'Must start with 5 and be 9 digits';
                    }
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
