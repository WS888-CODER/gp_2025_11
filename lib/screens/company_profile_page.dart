import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';

const kUsersCollection = 'Users';

class UserFields {
  static const photoUrl = 'PhotoURL';
  static const description = 'Description';
  static const location = 'Location';
  static const contactEmail = 'ContactEmail';
  static const phone = 'Phone';
  static const isProfileComplete = 'IsProfileComplete';
  static const photoPath = 'PhotoPath';
}

final _email =
    RegExp(r"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$", caseSensitive: false);
final _localSaPhone = RegExp(r'^(5\d{8}|01[1-7]\d{6,7})$');
const _saPrefix = '+966';
String _toLocal(String e164) {
  final t = e164.trim();
  return t.startsWith(_saPrefix) ? t.substring(_saPrefix.length) : t;
}

class CompanyProfile extends StatefulWidget {
  const CompanyProfile({super.key});

  @override
  State<CompanyProfile> createState() => _CompanyProfileState();
}

class _CompanyProfileState extends State<CompanyProfile> {
  final _form = GlobalKey<FormState>();
  final _desc = TextEditingController();
  final _loc = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phone = TextEditingController();
  File? _pendingLogoFile;
  static const int _kMaxImageBytes = 5 * 1024 * 1024; // 5MB
  String? _logoUrl;
  bool _saving = false;
  double? _progress;
  final _descKey = GlobalKey<FormFieldState>();
  final _locKey = GlobalKey<FormFieldState>();
  final _emailKey = GlobalKey<FormFieldState>();
  final _phoneKey = GlobalKey<FormFieldState>();
  final _descFocus = FocusNode();
  final _locFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _phoneFocus = FocusNode();
  bool _filledFromServer = false;

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
  // ==================================================================

  @override
  void dispose() {
    _desc.dispose();
    _loc.dispose();
    _emailCtrl.dispose();
    _phone.dispose();

    _descFocus.dispose();
    _locFocus.dispose();
    _emailFocus.dispose();
    _phoneFocus.dispose();
    super.dispose();
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
    } catch (_) {
      // تجاهل الأخطاء (الملف قد يكون محذوف مسبقاً أو لا صلاحية)
    }
  }

  Future<Map<String, String>> _uploadLogoWithProgress(File file) async {
    final len = await file.length();
    if (len > 5 * 1024 * 1024) throw Exception('Image too large');
    final ext = file.path.split('.').last.toLowerCase();
    if (!['jpg', 'png'].contains(ext)) {
      throw Exception('Unsupported image');
    }

    final uid = FirebaseAuth.instance.currentUser!.uid;
    final name = file.path.split('/').last;
    final ref = FirebaseStorage.instance.ref(
      'logos/$uid/${DateTime.now().millisecondsSinceEpoch}_$name',
    );

    final task = ref.putFile(file);
    task.snapshotEvents.listen((s) {
      final total = s.totalBytes;
      if (total > 0 && mounted) {
        setState(() => _progress = s.bytesTransferred / total);
      }
    });

    final snap = await task;
    final url = await snap.ref.getDownloadURL();
    final path = snap.ref.fullPath; // 👈 هذا المهم لحذف القديم لاحقاً
    if (mounted) setState(() => _progress = null);
    return {'url': url, 'path': path};
  }

  Future<void> _pickLogo() async {
    final img = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 92);
    if (img == null) return;

    setState(() {
      _pendingLogoFile = File(img.path); // نخزن محلي فقط
    });

    // معاينة فورية + تذكير بالتحديث
    _showSnackSuccess('Logo selected.');
  }

  Future<void> _save(Map<String, dynamic> current) async {
    if (_progress != null) {
      _showSnackError('Please wait for uploads to finish');
      return;
    }

    if (!_form.currentState!.validate()) return;

    final email = _emailCtrl.text.trim();
    final phoneLocal = _phone.text.trim();

    // صالح إذا كان غير فاضي وبصيغة صحيحة
    final hasEmailValid = email.isNotEmpty && _email.hasMatch(email);
    final hasPhoneFormat =
        phoneLocal.isNotEmpty && _localSaPhone.hasMatch(phoneLocal);

    if (!(hasEmailValid || hasPhoneFormat)) {
      _showSnackError('Provide at least a valid email OR a valid phone number');
      return;
    }

    // ===== الهاتف: E.164 للمحمول/الأرضي عند الحاجة فقط =====
    String normalizePhoneToE164(String local) {
      final s = local.trim();
      if (RegExp(r'^5\d{8}$').hasMatch(s)) return '+966$s'; // Mobile
      if (RegExp(r'^(01[1-7]\d{6,7})$').hasMatch(s))
        return '+966${s.substring(1)}'; // Landline
      return '';
    }

    final oldPhoneE164 = (current[UserFields.phone] ?? '').toString();
    String? newPhoneE164;

    if (hasPhoneFormat) {
      final candidate = normalizePhoneToE164(phoneLocal);
      if (candidate.isEmpty) {
        _showSnackError('Phone format not recognized');
        return;
      }
      if (candidate != oldPhoneE164) newPhoneE164 = candidate;
    }

    setState(() => _saving = true);
    try {
      // ========= 1) رفع اللوجو إن وُجد =========
      String? newLogoUrl;
      String? newLogoPath;
      if (_pendingLogoFile != null) {
        final err = _validateImageFile(_pendingLogoFile!);
        if (err != null) {
          _showSnackError(err);
          setState(() => _saving = false);
          return;
        }
        setState(() => _progress = 0);
        final res = await _uploadLogoWithProgress(_pendingLogoFile!);
        newLogoUrl = res['url'];
        newLogoPath = res['path'];
        _pendingLogoFile = null;
        if (mounted) setState(() => _progress = null);
      }

      // ========= 2) بناء التحديثات (بدون فرض إيميل) =========
      final desc = _desc.text.trim();
      final loc = _loc.text.trim();

      // “مكتمل” = وصف + موقع + (إيميل صحيح أو رقم صحيح)
      final complete = desc.length >= 100 &&
          loc.isNotEmpty &&
          (hasEmailValid || hasPhoneFormat);

      final updates = <String, dynamic>{
        UserFields.description: desc,
        UserFields.location: loc,
        UserFields.isProfileComplete: complete,
      };

      // حدّث/احذف الإيميل فقط لو تغيّر عن الموجود
      final oldEmail = (current[UserFields.contactEmail] ?? '').toString();
      if (email != oldEmail) {
        if (email.isEmpty) {
          updates[UserFields.contactEmail] = FieldValue.delete();
        } else {
          updates[UserFields.contactEmail] = email;
        }
      }

      // الهاتف (أضفه فقط إذا تغيّر)
      if (newPhoneE164 != null) {
        updates[UserFields.phone] = newPhoneE164;
      }

      // الشعار
      if (newLogoUrl != null) {
        updates[UserFields.photoUrl] = newLogoUrl;
        if (newLogoPath != null) updates[UserFields.photoPath] = newLogoPath;
        _logoUrl = newLogoUrl;
      } else if (_logoUrl == '') {
        updates[UserFields.photoUrl] = FieldValue.delete();
        updates[UserFields.photoPath] = FieldValue.delete();
      }

      if (updates.isEmpty) {
        _showSnackError('No changes to save');
        setState(() => _saving = false);
        return;
      }

      // ========= 3) حفظ =========
      final uid = FirebaseAuth.instance.currentUser!.uid;
      await FirebaseFirestore.instance
          .collection(kUsersCollection)
          .doc(uid)
          .set(updates, SetOptions(merge: true));

      // ========= 4) تنظيف تخزين الشعار القديم =========
      if (newLogoUrl != null) {
        final oldPath = (current[UserFields.photoPath] ?? '').toString();
        if (oldPath.isNotEmpty) {
          await _deleteStorageFile(oldPath);
        } else {
          final oldUrl = (current[UserFields.photoUrl] ?? '').toString();
          if (oldUrl.isNotEmpty) await _deleteStorageFile(oldUrl);
        }
      }
      if (_logoUrl == '' &&
          (current[UserFields.photoPath]?.toString().isNotEmpty ?? false)) {
        await _deleteStorageFile(current[UserFields.photoPath]?.toString());
      } else if (_logoUrl == '' &&
          (current[UserFields.photoUrl]?.toString().isNotEmpty ?? false)) {
        await _deleteStorageFile(current[UserFields.photoUrl]?.toString());
      }

      if (!mounted) return;
      _showSnackSuccess('✅ Profile updated successfully');
      Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      _showSnackError('❌ Failed to update profile');
    } finally {
      if (mounted) {
        setState(() {
          _progress = null;
          _saving = false;
        });
      }
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

        if (!_filledFromServer) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return; // مهم جداً

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
                : (() {
                    final p = (data[UserFields.phone] ?? '').toString();
                    return p.isEmpty ? '' : _toLocal(p);
                  })();

            _filledFromServer = true;
          });
        }

        final hasLogo = _pendingLogoFile != null ||
            ((_logoUrl ?? data[UserFields.photoUrl])?.toString().isNotEmpty ??
                false);
        final emailNow = _emailCtrl.text.trim();
        final phoneNow = _phone.text.trim();
        final hasEmailValidNow =
            emailNow.isNotEmpty && _email.hasMatch(emailNow);
        final hasPhoneValidNow =
            phoneNow.isNotEmpty && _localSaPhone.hasMatch(phoneNow);

        final profileComplete = (data[UserFields.isProfileComplete] == true) ||
            (_desc.text.trim().length >= 100 &&
                _loc.text.trim().isNotEmpty &&
                (hasEmailValidNow || hasPhoneValidNow));
        return Scaffold(
          appBar: AppBar(
            title: const Text('Company Profile'),
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
                  _saving || _progress != null ? null : () => _save(data),
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Update Profile'),
            ),
          ),
          body: Form(
            key: _form,
            autovalidateMode: AutovalidateMode.disabled,
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
                        backgroundImage: _pendingLogoFile != null
                            ? FileImage(_pendingLogoFile!) as ImageProvider
                            : (hasLogo
                                ? NetworkImage(
                                    (_logoUrl ?? data[UserFields.photoUrl])
                                        .toString())
                                : null),
                        child: (_pendingLogoFile == null && !hasLogo)
                            ? const Icon(Icons.business)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Spacer(),
                    FilledButton.tonal(
                      onPressed:
                          _saving || _progress != null ? null : _pickLogo,
                      child: const Text('Upload Logo'),
                    ),
                    const SizedBox(width: 8),
                    if (hasLogo)
                      TextButton(
                        onPressed: _saving || _progress != null
                            ? null
                            : () => setState(() {
                                  _pendingLogoFile = null;
                                  _logoUrl = '';
                                }),
                        child: const Text('Remove'),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Focus(
                  focusNode: _descFocus,
                  onFocusChange: (hasFocus) {
                    if (!hasFocus) _descKey.currentState?.validate();
                  },
                  child: TextFormField(
                    key: _descKey,
                    autovalidateMode: AutovalidateMode.disabled,
                    controller: _desc,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Description (min 100 chars)',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final t = v?.trim() ?? '';
                      if (t.isEmpty) return 'Enter description';
                      if (t.length < 100) return 'Too short';
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Focus(
                  focusNode: _locFocus,
                  onFocusChange: (hasFocus) {
                    if (!hasFocus) _locKey.currentState?.validate();
                  },
                  child: TextFormField(
                    key: _locKey,
                    autovalidateMode: AutovalidateMode.disabled,
                    controller: _loc,
                    decoration: const InputDecoration(
                      labelText: 'Location',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Enter location'
                        : null,
                  ),
                ),
                const SizedBox(height: 12),
                Focus(
                  focusNode: _emailFocus,
                  onFocusChange: (hasFocus) {
                    if (!hasFocus) _emailKey.currentState?.validate();
                  },
                  child: TextFormField(
                    key: _emailKey,
                    autovalidateMode: AutovalidateMode.disabled,
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Contact Email',
                      border: OutlineInputBorder(),
                      helperText: 'Provide email OR phone (one is enough)',
                    ),
                    validator: (v) {
                      final t = v?.trim() ?? '';
                      if (t.isEmpty) return null;
                      if (!_email.hasMatch(t)) return 'Invalid email';
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Focus(
                    focusNode: _phoneFocus,
                    onFocusChange: (hasFocus) {
                      if (!hasFocus) _phoneKey.currentState?.validate();
                    },
                    child: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _phone,
                      builder: (context, value, _) {
                        final t = value.text.trim();
                        final isMobile = t.startsWith('5');
                        return TextFormField(
                          key: _phoneKey, // (لو تستخدمين مفاتيح للفالديت منفصل)
                          autovalidateMode: AutovalidateMode.disabled,
                          controller: _phone,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(10),
                          ],
                          decoration: InputDecoration(
                            labelText: 'Contact Phone',
                            hintText: '5XXXXXXXX or 01XXXXXXXX',
                            prefixText: isMobile ? '+966 ' : '',
                            border: const OutlineInputBorder(),
                          ),
                          validator: (v) {
                            final s = v?.trim() ?? '';
                            if (s.isEmpty) return null;
                            final reg = RegExp(r'^(5\d{8}|01[1-7]\d{6,7})$');
                            if (!reg.hasMatch(s)) {
                              return 'Enter a valid Saudi mobile or landline number';
                            }
                            return null;
                          },
                        );
                      },
                    )),
              ],
            ),
          ),
        );
      },
    );
  }
}
