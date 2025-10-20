import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // kDebugMode
import 'package:flutter/services.dart'; // <-- NEW for input formatters
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
  static const phoneVerified =
      'PhoneVerified'; // لم نعد نستخدمه، لكن نتركه للتوافق
  static const isProfileComplete = 'IsProfileComplete';
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
  double? _progress; // 0..1 while uploading

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

  // Helpers to convert phone formats
  String _toE164(String local) => '$_saPrefix${local.trim()}'; // +9665XXXXXXXX
  String _toLocal(String e164) {
    final t = e164.trim();
    if (t.startsWith(_saPrefix)) return t.substring(_saPrefix.length);
    return t;
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
    try {
      final encoded = Uri.encodeFull(url);
      final uri = Uri.parse(encoded);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw 'Cannot open';
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot open CV file')),
      );
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

  Future<void> _save(Map<String, dynamic> current) async {
    if (_progress != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please wait for uploads to finish')),
      );
      return;
    }

    // المسترجع من السيرفر
    final dobCurrent = current[UserFields.dob] is Timestamp
        ? (current[UserFields.dob] as Timestamp).toDate()
        : null;
    final serverPhoneE164 = (current[UserFields.phone] ?? '').toString();
    final hasServerNat =
        (current[UserFields.nationality] ?? '').toString().isNotEmpty;

    // نحدد فقط الحقول التي تغيّرت
    final updates = <String, dynamic>{};

    // CV & Photo (دعم الإزالة أو الإضافة فقط إذا تغيّر)
    if (_cvUrl == '') {
      updates[UserFields.cvUrl] = FieldValue.delete();
    } else if (_cvUrl != null && _cvUrl != current[UserFields.cvUrl]) {
      updates[UserFields.cvUrl] = _cvUrl;
    }

    if (_photoUrl == '') {
      updates[UserFields.photoUrl] = FieldValue.delete();
    } else if (_photoUrl != null && _photoUrl != current[UserFields.photoUrl]) {
      updates[UserFields.photoUrl] = _photoUrl;
    }

    // DOB: نحفظ فقط إذا اخترتي تاريخًا جديدًا يختلف عن الحالي
    if (_dob != null && _dob != dobCurrent) {
      if (!_isAdult(_dob!)) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Must be at least 18')));
        return;
      }
      updates[UserFields.dob] = Timestamp.fromDate(_dob!);
    }

    // Nationality: نحفظ فقط إذا تغيّرت
    if (_nationality != null &&
        _nationality != current[UserFields.nationality]) {
      if (_nationality!.isEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Select nationality')));
        return;
      }
      updates[UserFields.nationality] = _nationality;
    }

    // Phone: إذا كتبتي شيئًا في الحقل، نتحقق منه ونحفظه إن تغيّر
    final local = _phone.text.trim(); // 5XXXXXXXX
    if (local.isNotEmpty) {
      if (!_localSaPhone.hasMatch(local)) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invalid phone format')));
        return;
      }
      final e164 = _toE164(local); // +9665XXXXXXXX
      if (e164 != serverPhoneE164) {
        updates[UserFields.phone] = e164;
      }
    }

    if (updates.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No changes to save')));
      return;
    }

    // نحدّث IsProfileComplete بناءً على (القيم القديمة + التغييرات)
    final merged = {...current, ...updates};

    final cvOk = (merged[UserFields.cvUrl] ?? '').toString().isNotEmpty;
    final photoOk = (merged[UserFields.photoUrl] ?? '').toString().isNotEmpty;
    final dobOk = merged[UserFields.dob] != null;
    final natOk = (merged[UserFields.nationality] ?? '').toString().isNotEmpty;
    final phoneMerged = (merged[UserFields.phone] ?? '').toString();
    final phoneLocal =
        phoneMerged.startsWith(_saPrefix) ? _toLocal(phoneMerged) : phoneMerged;
    final phoneOk = _localSaPhone.hasMatch(phoneLocal);

    final complete = cvOk && photoOk && dobOk && natOk && phoneOk;
    updates[UserFields.isProfileComplete] = complete;

    // تنفيذ الحفظ
    final uid = FirebaseAuth.instance.currentUser!.uid;
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection(kUsersCollection)
          .doc(uid)
          .set(updates, SetOptions(merge: true));

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

        // مليء الحقل من القيمة المخزنة إن وُجدت
        final serverPhoneE164 = (data[UserFields.phone] ?? '').toString();
        if (_phone.text.isEmpty && serverPhoneE164.isNotEmpty) {
          final local = _toLocal(serverPhoneE164);
          // نتأكد أنه يبدو محلياً (يتجاهل أي بادئات أخرى غير +966)
          _phone.text = local.startsWith('5') ? local : '';
        }

        final dobCurrent = data[UserFields.dob] is Timestamp
            ? (data[UserFields.dob] as Timestamp).toDate()
            : null;

        final dobText = (_dob ?? dobCurrent) == null
            ? 'Select date'
            : DateFormat('yyyy/MM/dd').format(_dob ?? dobCurrent!);

        final hasCV =
            (_cvUrl ?? data[UserFields.cvUrl])?.toString().isNotEmpty == true;
        final hasPhoto =
            (_photoUrl ?? data[UserFields.photoUrl])?.toString().isNotEmpty ==
                true;

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
        final hasServerPhone = serverPhoneE164.isNotEmpty;
        final hasServerNat =
            (data[UserFields.nationality] ?? '').toString().isNotEmpty;
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
                  validator: (v) {
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
                    if (t.isEmpty) return hasServerPhone ? null : 'Enter phone';
                    if (!_localSaPhone.hasMatch(t))
                      return 'Must start with 5 and be 9 digits';
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
