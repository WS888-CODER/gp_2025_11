import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:gp_2025_11/config/theme.dart';
import 'package:gp_2025_11/config/themed_scaffold.dart';
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
  static const isProfileComplete = 'IsProfileComplete';
  static const cvPath = 'CVPath';
  static const photoPath = 'PhotoPath';
}

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

class JobSeekerProfile extends StatelessWidget {
  const JobSeekerProfile({super.key});

  String _toLocal(String e164) {
    final t = e164.trim();
    if (t.startsWith(_saPrefix)) return t.substring(_saPrefix.length);
    return t;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const ThemedScaffold(
        body: Center(child: Text('Not signed in')),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection(kUsersCollection)
          .doc(user.uid)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const ThemedScaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final data = snap.data?.data() ?? {};

        final fullName = (data['Name'] ?? '').toString().trim();
        final displayName = fullName;

        final nationality =
            (data[UserFields.nationality] ?? '').toString().trim();
        final phoneE164 = (data[UserFields.phone] ?? '').toString().trim();
        final phoneLocal = phoneE164.isEmpty ? '' : _toLocal(phoneE164);
        final dobCurrent = data[UserFields.dob] is Timestamp
            ? (data[UserFields.dob] as Timestamp).toDate()
            : null;

        final cvUrl = (data[UserFields.cvUrl] ?? '').toString().trim();
        final photoUrl = (data[UserFields.photoUrl] ?? '').toString().trim();

        final phoneValid =
            phoneLocal.isNotEmpty && _localSaPhone.hasMatch(phoneLocal);
        final natOk = nationality.isNotEmpty;
        final dobOk = dobCurrent != null;
        final cvOk = cvUrl.isNotEmpty;
        final photoOk = photoUrl.isNotEmpty;

        final profileComplete = data[UserFields.isProfileComplete] == true ||
            (cvOk && photoOk && dobOk && natOk && phoneValid);

        final nationalityValue = natOk ? nationality : 'Not set';
        final dobValue =
            dobOk ? DateFormat('yyyy/MM/dd').format(dobCurrent!) : 'Not set';
        final phoneValue = phoneValid ? '+966 $phoneLocal' : 'Not set';
        final cvValue = cvOk ? 'CV uploaded' : 'CV not uploaded';

        final photoSource = photoUrl;

        final scheme = Theme.of(context).colorScheme;
        const brand = Color(0xFF4A5FBC);

        return ThemedScaffold(
          appBar: AppBar(
            backgroundColor: brand,
            iconTheme: const IconThemeData(color: Colors.white),
            title: const Text(
              'Profile',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(
                        Theme.of(context).brightness == Brightness.dark
                            ? 0.12
                            : 0.05,
                      ),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: brand,
                              width: 4,
                            ),
                          ),
                          child: CircleAvatar(
                            radius: 42,
                            backgroundColor: const Color(0xFFF3F3FF),
                            backgroundImage: photoSource.isNotEmpty
                                ? NetworkImage(photoSource)
                                : null,
                            child: photoSource.isEmpty
                                ? const Icon(
                                    Icons.person,
                                    size: 32,
                                    color: brand,
                                  )
                                : null,
                          ),
                        ),
                        Positioned(
                          bottom: -2,
                          right: -2,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: profileComplete
                                  ? Colors.green
                                  : Colors.orange,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: 2,
                              ),
                            ),
                            child: Icon(
                              profileComplete
                                  ? Icons.check
                                  : Icons.error_outline,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      displayName.isEmpty ? 'Job Seeker' : displayName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: brand,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (nationalityValue != 'Not set' || dobValue != 'Not set')
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.badge_outlined,
                            size: 16,
                            color: brand,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              [
                                if (nationalityValue != 'Not set')
                                  nationalityValue,
                                if (dobValue != 'Not set') dobValue,
                              ].join(' • '),
                              style: const TextStyle(
                                fontSize: 13,
                                color: brand,
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 12),
                    if (phoneValue != 'Not set' || cvOk)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF2FF),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (phoneValue != 'Not set')
                              Text(
                                phoneValue,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: brand,
                                ),
                              ),
                            if (phoneValue != 'Not set' && cvOk)
                              const Text(
                                '  |  ',
                                style: TextStyle(
                                  color: brand,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            if (cvOk)
                              Text(
                                cvValue,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: brand,
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Container(
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(
                        Theme.of(context).brightness == Brightness.dark
                            ? 0.12
                            : 0.04,
                      ),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  border: Border.all(
                    color: const Color(0xFF4A5FBC).withOpacity(0.08),
                  ),
                ),
                child: _SettingsRowSeeker(
                  icon: Icons.person_outline,
                  color: brand,
                  title: 'Profile Information',
                  subtitle: 'Profile basics, contact info, and CV',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => EditJobSeekerPage(
                          data: data,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }
}

class _SettingsRowSeeker extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsRowSeeker({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.grey[600],
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.black38),
          ],
        ),
      ),
    );
  }
}

class EditJobSeekerPage extends StatefulWidget {
  final Map<String, dynamic> data;

  const EditJobSeekerPage({
    super.key,
    required this.data,
  });

  @override
  State<EditJobSeekerPage> createState() => _EditJobSeekerPageState();
}

class _EditJobSeekerPageState extends State<EditJobSeekerPage> {
  final _form = GlobalKey<FormState>();
  final _phone = TextEditingController();

  String? _nationality;
  DateTime? _dob;

  File? _pendingPhotoFile;
  File? _pendingCvFile;

  String? _photoUrl;
  String? _cvUrl;

  bool _saving = false;
  double? _progress;
  StreamSubscription<TaskSnapshot>? _uploadSub;

  static const int _kMaxImageBytes = 5 * 1024 * 1024;
  static const int _kMaxCvBytes = 10 * 1024 * 1024;

  @override
  void initState() {
    super.initState();

    final data = widget.data;

    final phoneE164 = (data[UserFields.phone] ?? '').toString().trim();
    if (phoneE164.startsWith(_saPrefix)) {
      final local = phoneE164.substring(_saPrefix.length);
      if (local.startsWith('5')) {
        _phone.text = local;
      }
    }

    final nat = (data[UserFields.nationality] ?? '').toString().trim();
    _nationality = nat.isEmpty ? null : nat;

    if (data[UserFields.dob] is Timestamp) {
      _dob = (data[UserFields.dob] as Timestamp).toDate();
    }

    _photoUrl = (data[UserFields.photoUrl] ?? '').toString().trim();
    _cvUrl = (data[UserFields.cvUrl] ?? '').toString().trim();
  }

  @override
  void dispose() {
    _uploadSub?.cancel();
    _phone.dispose();
    super.dispose();
  }

  String? _validateImageFile(File f) {
    final len = f.lengthSync();
    if (len > _kMaxImageBytes) return 'Image too large (max 5 MB)';
    final ext = f.path.split('.').last.toLowerCase();
    final normalized = (ext == 'jpeg') ? 'jpg' : ext;
    if (!['jpg', 'png'].contains(normalized)) {
      return 'Unsupported image (JPG/PNG only)';
    }
    return null;
  }

  String? _validateCvFile(File f) {
    final len = f.lengthSync();
    if (len > _kMaxCvBytes) return 'File too large (max 10 MB)';
    final ext = f.path.split('.').last.toLowerCase();
    if (!['pdf', 'docx'].contains(ext)) {
      return 'Unsupported file (PDF/DOCX only)';
    }
    return null;
  }

  Future<Map<String, String>> _uploadPhoto(File file) async {
    final err = _validateImageFile(file);
    if (err != null) throw Exception(err);

    final uid = FirebaseAuth.instance.currentUser!.uid;
    final name = file.path.split('/').last;
    final ref = FirebaseStorage.instance.ref(
      'photos/$uid/${DateTime.now().millisecondsSinceEpoch}_$name',
    );

    if (!mounted) {
      throw Exception('Screen closed');
    }

    setState(() => _progress = 0);

    final task = ref.putFile(file);
    _uploadSub = task.snapshotEvents.listen((s) {
      if (!mounted) return;
      final total = s.totalBytes;
      if (total > 0) {
        setState(() => _progress = s.bytesTransferred / total);
      }
    });

    try {
      final snap = await task.timeout(const Duration(seconds: 15));
      final url = await snap.ref.getDownloadURL();
      final path = snap.ref.fullPath;
      if (mounted) setState(() => _progress = null);
      return {'url': url, 'path': path};
    } on TimeoutException {
      if (mounted) setState(() => _progress = null);
      throw Exception(
        'Upload timed out. Check network / permissions / App Check.',
      );
    }
  }

  Future<Map<String, String>> _uploadCv(File file) async {
    final err = _validateCvFile(file);
    if (err != null) throw Exception(err);

    final uid = FirebaseAuth.instance.currentUser!.uid;
    final name = file.path.split('/').last;
    final ref = FirebaseStorage.instance.ref(
      'cv/$uid/${DateTime.now().millisecondsSinceEpoch}_$name',
    );

    if (!mounted) {
      throw Exception('Screen closed');
    }

    setState(() => _progress = 0);

    final task = ref.putFile(file);
    _uploadSub = task.snapshotEvents.listen((s) {
      if (!mounted) return;
      final total = s.totalBytes;
      if (total > 0) {
        setState(() => _progress = s.bytesTransferred / total);
      }
    });

    try {
      final snap = await task.timeout(const Duration(seconds: 15));
      final url = await snap.ref.getDownloadURL();
      final path = snap.ref.fullPath;
      if (mounted) setState(() => _progress = null);
      return {'url': url, 'path': path};
    } on TimeoutException {
      if (mounted) setState(() => _progress = null);
      throw Exception(
        'Upload timed out. Check network / permissions / App Check.',
      );
    }
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
    } catch (_) {}
  }

  Future<void> _pickCV() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx'],
    );
    if (res == null || res.files.single.path == null) return;

    final file = File(res.files.single.path!);

    setState(() {
      _pendingCvFile = file;
    });
    SnackHelper.success(context, 'CV selected.');
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

    setState(() {
      _pendingPhotoFile = File(img.path);
    });
    SnackHelper.success(context, 'Photo selected.');
  }

  Future<void> _openCv() async {
    final url = _cvUrl;
    if (url == null || url.isEmpty) {
      SnackHelper.error(context, 'No CV file to open');
      return;
    }

    final uri = Uri.tryParse(url);
    if (uri == null) {
      SnackHelper.error(context, 'Invalid CV URL');
      return;
    }

    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      SnackHelper.error(context, 'Could not open CV file');
    }
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) {
      SnackHelper.error(context, 'Please fix the highlighted fields');
      return;
    }

    if (_progress != null) {
      SnackHelper.error(context, 'Please wait for uploads to finish');
      return;
    }

    final current = widget.data;

    final local = _phone.text.trim();
    if (local.isNotEmpty && !_localSaPhone.hasMatch(local)) {
      SnackHelper.error(context, 'Enter a valid Saudi mobile number');
      return;
    }

    final updates = <String, dynamic>{};
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
      final msg = e.toString().contains('Unsupported image')
          ? 'Only JPG or PNG images are supported.'
          : 'Failed to upload file: ${e.toString()}';
      SnackHelper.error(context, msg);
      return;
    }

    if (newCvUrl != null) {
      updates[UserFields.cvUrl] = newCvUrl;
      if (newCvPath != null) updates[UserFields.cvPath] = newCvPath;
      _cvUrl = newCvUrl;
    } else if (_cvUrl == '') {
      updates[UserFields.cvUrl] = FieldValue.delete();
      updates[UserFields.cvPath] = FieldValue.delete();
    }

    if (newPhotoUrl != null) {
      updates[UserFields.photoUrl] = newPhotoUrl;
      if (newPhotoPath != null) updates[UserFields.photoPath] = newPhotoPath;
      _photoUrl = newPhotoUrl;
    } else if (_photoUrl == '') {
      updates[UserFields.photoUrl] = FieldValue.delete();
      updates[UserFields.photoPath] = FieldValue.delete();
    }

    final dobCurrent = current[UserFields.dob] is Timestamp
        ? (current[UserFields.dob] as Timestamp).toDate()
        : null;
    if (_dob != null && _dob != dobCurrent) {
      updates[UserFields.dob] = Timestamp.fromDate(_dob!);
    }

    final currentNat =
        (current[UserFields.nationality] ?? '').toString().trim();
    final newNat = (_nationality ?? '').trim();
    if (newNat.isEmpty && currentNat.isNotEmpty) {
      updates[UserFields.nationality] = FieldValue.delete();
    } else if (newNat.isNotEmpty && newNat != currentNat) {
      updates[UserFields.nationality] = newNat;
    }

    final currentPhone = (current[UserFields.phone] ?? '').toString().trim();
    if (local.isNotEmpty && _localSaPhone.hasMatch(local)) {
      final e164 = '$_saPrefix$local';
      if (e164 != currentPhone) {
        updates[UserFields.phone] = e164;
      }
    } else if (local.isEmpty && currentPhone.isNotEmpty) {
      updates[UserFields.phone] = FieldValue.delete();
    }

    if (updates.isEmpty) {
      SnackHelper.error(context, 'No changes to save');
      return;
    }

    final next = <String, dynamic>{...current};
    updates.forEach((key, value) {
      if (value is FieldValue) {
        next.remove(key);
      } else {
        next[key] = value;
      }
    });

    final cvOk = (next[UserFields.cvUrl] ?? '').toString().isNotEmpty;
    final photoOk = (next[UserFields.photoUrl] ?? '').toString().isNotEmpty;
    final dobOk = next[UserFields.dob] != null;
    final natOk =
        (next[UserFields.nationality] ?? '').toString().trim().isNotEmpty;

    final phoneMerged = (next[UserFields.phone] ?? '').toString();
    String toLocalPhone(String e164) {
      if (e164.startsWith(_saPrefix)) {
        return e164.substring(_saPrefix.length);
      }
      return e164;
    }

    final phoneLocalMerged = toLocalPhone(phoneMerged);
    final phoneOk =
        phoneLocalMerged.isNotEmpty && _localSaPhone.hasMatch(phoneLocalMerged);

    final complete = cvOk && photoOk && dobOk && natOk && phoneOk;
    updates[UserFields.isProfileComplete] = complete;

    final uid = FirebaseAuth.instance.currentUser!.uid;

    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection(kUsersCollection)
          .doc(uid)
          .set(updates, SetOptions(merge: true));

      if (newPhotoUrl != null) {
        final oldPhotoPath = (current[UserFields.photoPath] ?? '').toString();
        if (oldPhotoPath.isNotEmpty) {
          await _deleteStorageFile(oldPhotoPath);
        } else {
          final oldPhotoUrl = (current[UserFields.photoUrl] ?? '').toString();
          if (oldPhotoUrl.isNotEmpty) {
            await _deleteStorageFile(oldPhotoUrl);
          }
        }
      }
      if (_photoUrl == '' &&
          (current[UserFields.photoPath]?.toString().isNotEmpty ?? false)) {
        await _deleteStorageFile(current[UserFields.photoPath]?.toString());
      } else if (_photoUrl == '' &&
          (current[UserFields.photoUrl]?.toString().isNotEmpty ?? false)) {
        await _deleteStorageFile(current[UserFields.photoUrl]?.toString());
      }

      if (newCvUrl != null) {
        final oldCvPath = (current[UserFields.cvPath] ?? '').toString();
        if (oldCvPath.isNotEmpty) {
          await _deleteStorageFile(oldCvPath);
        } else {
          final oldCvUrl = (current[UserFields.cvUrl] ?? '').toString();
          if (oldCvUrl.isNotEmpty) {
            await _deleteStorageFile(oldCvUrl);
          }
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
      Navigator.pop(context);
      SnackHelper.success(context, 'Profile updated successfully');
    } catch (e) {
      if (!mounted) return;
      SnackHelper.error(context, 'Failed to update profile');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const brand = Color(0xFF4A5FBC);

    final dobText = _dob == null
        ? ((_dobFromData() == null)
            ? 'Select date'
            : DateFormat('yyyy/MM/dd').format(_dobFromData()!))
        : DateFormat('yyyy/MM/dd').format(_dob!);

    final hasCV = _pendingCvFile != null || ((_cvUrl ?? '').isNotEmpty);
    final hasPhoto =
        _pendingPhotoFile != null || ((_photoUrl ?? '').isNotEmpty);
    final canViewCv = (_cvUrl ?? '').isNotEmpty && _pendingCvFile == null;

    return ThemedScaffold(
      appBar: AppBar(
        backgroundColor: brand,
        title: const Text(
          'Edit Profile',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        bottom: _progress != null
            ? PreferredSize(
                preferredSize: const Size.fromHeight(4),
                child: LinearProgressIndicator(
                  value: _progress == 0 ? null : _progress,
                  minHeight: 4,
                  backgroundColor: Colors.black12,
                  color: Colors.white,
                ),
              )
            : null,
      ),
      body: Form(
        key: _form,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          children: [
            const Text(
              'Profile Photo',
              style: TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: brand,
                      width: 2,
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 32,
                    backgroundColor: Colors.white,
                    backgroundImage: _pendingPhotoFile != null
                        ? FileImage(_pendingPhotoFile!) as ImageProvider
                        : ((_photoUrl ?? '').isNotEmpty
                            ? NetworkImage(_photoUrl!)
                            : null),
                    child:
                        (_pendingPhotoFile == null && (_photoUrl ?? '').isEmpty)
                            ? const Icon(
                                Icons.person,
                                color: brand,
                                size: 28,
                              )
                            : null,
                  ),
                ),
                const SizedBox(width: 16),
                Row(
                  children: [
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFD6C67),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      onPressed:
                          (_saving || _progress != null) ? null : _pickPhoto,
                      child: const Text(
                        'Upload Photo',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (hasPhoto)
                      TextButton(
                        onPressed: (_saving || _progress != null)
                            ? null
                            : () {
                                setState(() {
                                  _pendingPhotoFile = null;
                                  _photoUrl = '';
                                });
                              },
                        child: const Text(
                          'Remove photo',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'Date of Birth',
              style: TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(dobText),
              trailing: FilledButton.tonal(
                onPressed: (_saving || _progress != null)
                    ? null
                    : () async {
                        final now = DateTime.now();
                        final initial = _dob ??
                            _dobFromData() ??
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
                        if (picked != null) {
                          setState(() => _dob = picked);
                        }
                      },
                child: const Text(
                  'Select date',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 24),
            DropdownButtonFormField<String>(
              value: _countries.contains(_nationality) ? _nationality : null,
              items: _countries
                  .map(
                    (c) => DropdownMenuItem(
                      value: c,
                      child: Text(
                        c,
                        style: const TextStyle(
                          color: Color(0xFF4A5FBC),
                        ),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (_saving || _progress != null)
                  ? null
                  : (v) => setState(() => _nationality = v),
              style: const TextStyle(color: Color(0xFF4A5FBC)),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Nationality',
                labelStyle: TextStyle(
                  color: Color(0xFF4A5FBC),
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              validator: (v) {
                return null;
              },
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(9),
              ],
              decoration: const InputDecoration(
                labelText: 'Phone',
                labelStyle: TextStyle(
                  color: Color(0xFF4A5FBC),
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF4A5FBC)),
                ),
                hintText: '5XXXXXXXX',
                prefixText: '+966 ',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                final t = v?.trim() ?? '';
                if (t.isEmpty) {
                  return null;
                }
                if (!_localSaPhone.hasMatch(t)) {
                  return 'Must start with 5 and be 9 digits';
                }
                return null;
              },
            ),
            const SizedBox(height: 32),
            const Text(
              'CV File',
              style: TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    hasCV ? 'CV uploaded' : 'CV not uploaded',
                    style: const TextStyle(
                      fontSize: 14,
                    ),
                  ),
                ),
                if (canViewCv) ...[
                  FilledButton.tonal(
                    onPressed: (_saving || _progress != null) ? null : _openCv,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF4A5FBC),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('View CV'),
                  ),
                  const SizedBox(width: 8),
                ],
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
                    child: const Text(
                      'Remove CV',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  )
                else
                  FilledButton.tonal(
                    onPressed: (_saving || _progress != null) ? null : _pickCV,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFD6C67),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Upload CV'),
                  ),
              ],
            ),
            const SizedBox(height: 120),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum:
            const EdgeInsets.symmetric(horizontal: 16).copyWith(bottom: 16),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: brand,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            onPressed: (_saving || _progress != null) ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Save changes'),
          ),
        ),
      ),
    );
  }

  DateTime? _dobFromData() {
    final d = widget.data[UserFields.dob];
    if (d is Timestamp) return d.toDate();
    return null;
  }
}
