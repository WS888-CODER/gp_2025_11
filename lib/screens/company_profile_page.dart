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
  if (!t.startsWith(_saPrefix)) return t;

  final rest = t.substring(_saPrefix.length); // بعد +966
  // موبايل: يبدأ بـ 5 → عرض محلي كما هو (5XXXXXXXXX)
  if (rest.startsWith('5')) return rest;

  // أرضي: يبدأ بـ 1X… → نرجع له الصفر: 0 + الباقي (011, 012, ...)
  if (RegExp(r'^1[1-7]\d{6,7}$').hasMatch(rest)) return '0$rest';

  // fallback
  return rest;
}

class CompanyProfile extends StatefulWidget {
  const CompanyProfile({super.key});

  @override
  State<CompanyProfile> createState() => _CompanyProfileState();
}

class _CompanyProfileState extends State<CompanyProfile> {
  final _form = GlobalKey<FormState>();
  final _desc = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phone = TextEditingController();
  File? _pendingLogoFile;
  static const int _kMaxImageBytes = 5 * 1024 * 1024; // 5MB
  String? _logoUrl;
  bool _saving = false;
  double? _progress;
  final _descKey = GlobalKey<FormFieldState>();
  final _emailKey = GlobalKey<FormFieldState>();
  final _phoneKey = GlobalKey<FormFieldState>();
  final _descFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _locCtrl = TextEditingController();
  final _locKey = GlobalKey<FormFieldState>();
  final _locFocus = FocusNode();
  bool _filledFromServer = false;

  final _locAllowed =
      RegExp(r"^[A-Za-z\u0600-\u06FF][A-Za-z\u0600-\u06FF\s\.'-]{1,39}$");
  String _cleanLoc(String raw) => raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  // 1) تحقق صارم: الحجم + الامتداد + ترويسة الملف (PNG/JPG فقط)
  String? _validateImageFile(File f) {
    final len = f.lengthSync();
    if (len > _kMaxImageBytes) return 'Image too large (max 5 MB)';

    final ext = f.path.split('.').last.toLowerCase();
    // نرفض jpeg صراحةً
    if (!(ext == 'png' || ext == 'jpg')) {
      return 'Unsupported image type. Use PNG or JPG (JPEG is not allowed).';
    }

    try {
      final bytes = f.openSync(mode: FileMode.read)..setPositionSync(0);
      final header = bytes.readSync(12);
      bytes.closeSync();

      bool isPng = header.length >= 8 &&
          header[0] == 0x89 &&
          header[1] == 0x50 && // 'P'
          header[2] == 0x4E && // 'N'
          header[3] == 0x47 && // 'G'
          header[4] == 0x0D &&
          header[5] == 0x0A &&
          header[6] == 0x1A &&
          header[7] == 0x0A;

      bool isJpeg = header.length >= 3 &&
          header[0] == 0xFF &&
          header[1] == 0xD8 &&
          header[2] == 0xFF;

      if (ext == 'png' && !isPng) {
        return 'File content is not valid PNG.';
      }
      if (ext == 'jpg' && !isJpeg) {
        return 'File content is not valid JPG.';
      }
    } catch (_) {
      return 'Could not read image file.';
    }

    return null; // valid
  }

  void _showSnackSuccess(String message, {BuildContext? inContext}) {
    final ctx = inContext ?? context;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showSnackError(String message, {BuildContext? inContext}) {
    final ctx = inContext ?? context;
    ScaffoldMessenger.of(ctx).showSnackBar(
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
    _emailCtrl.dispose();
    _phone.dispose();

    _descFocus.dispose();
    _emailFocus.dispose();
    _phoneFocus.dispose();
    _locCtrl.dispose();
    _locFocus.dispose();

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

  // 2) الرفع: نفس القيود تمامًا (بدون أي تطبيع لـ jpeg)
  Future<Map<String, String>> _uploadLogoWithProgress(File file) async {
    final len = await file.length();
    if (len > 5 * 1024 * 1024) throw Exception('Image too large');

    final ext = file.path.split('.').last.toLowerCase();
    if (!(ext == 'png' || ext == 'jpg')) {
      throw Exception('Unsupported image type. Use PNG or JPG only.');
    }

    // فحص ترويسة سريع قبل الرفع (دفاع مزدوج)
    try {
      final raf = file.openSync(mode: FileMode.read)..setPositionSync(0);
      final header = raf.readSync(12);
      raf.closeSync();

      bool isPng = header.length >= 8 &&
          header[0] == 0x89 &&
          header[1] == 0x50 &&
          header[2] == 0x4E &&
          header[3] == 0x47 &&
          header[4] == 0x0D &&
          header[5] == 0x0A &&
          header[6] == 0x1A &&
          header[7] == 0x0A;

      bool isJpeg = header.length >= 3 &&
          header[0] == 0xFF &&
          header[1] == 0xD8 &&
          header[2] == 0xFF;

      if ((ext == 'png' && !isPng) || (ext == 'jpg' && !isJpeg)) {
        throw Exception('File content does not match extension.');
      }
    } catch (e) {
      throw Exception('Corrupted or unreadable image.');
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

    try {
      final snap = await task;
      final url = await snap.ref.getDownloadURL();
      final path = snap.ref.fullPath;
      if (mounted) setState(() => _progress = null);
      return {'url': url, 'path': path};
    } on FirebaseException catch (e) {
      if (mounted) {
        _showSnackError('Upload failed: ${e.message ?? e.code}');
        setState(() => _progress = null);
      }
      rethrow;
    }
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

  bool _hasAnyLogo(Map<String, dynamic> current) {
    final hasPending = _pendingLogoFile != null;
    final hasExisting =
        ((_logoUrl ?? current[UserFields.photoUrl])?.toString().isNotEmpty ??
            false);
    // لو المستخدم ضغط "Remove" نخزن _logoUrl = '' (يعني حذف)، فـ hasExisting تصير false
    return hasPending || hasExisting;
  }

  Future<bool> _save(Map<String, dynamic> current,
      {BuildContext? inContext}) async {
    // 1) فعّل الفالديت على كل الحقول (يظهر الأحمر لو فيه غلط)
    final formOk = _form.currentState?.validate() ?? false;

    // بنفس منطقك: لازم يكون فيه لوقو
    final hasLogoNow = _hasAnyLogo(current);

    // لازم (ايميل صحيح OR رقم صحيح)
    final email = _emailCtrl.text.trim();
    final phoneLocal = _phone.text.trim();
    final hasEmailValid = email.isNotEmpty && _email.hasMatch(email);
    final hasPhoneValid =
        phoneLocal.isNotEmpty && _localSaPhone.hasMatch(phoneLocal);

    // لو أي شرط أساسي ناقص -> لا نبدأ أبداً عملية الحفظ ولا نظهر progress
    if (!formOk) {
      _showSnackError('Please fix the highlighted fields',
          inContext: inContext ?? context);
      return false;
    }
    if (!hasLogoNow) {
      _showSnackError('Company logo is required before updating.',
          inContext: inContext ?? context);
      return false;
    }
    if (!(hasEmailValid || hasPhoneValid)) {
      _showSnackError('Provide at least a valid email OR a valid phone number',
          inContext: inContext ?? context);
      return false;
    }

    // وصلنا هنا؟ يعني جاهزين نحفظ فعلاً ✅
    // الآن فقط نولّع الـsaving والـprogress
    setState(() {
      _saving = true;
      _progress = 0; // يخلي الشريط يطلع
    });

    try {
      // 2) جهّز رقم الهاتف بصيغة E.164
      String normalizePhoneToE164(String local) {
        final s = local.trim();
        if (RegExp(r'^5\d{8}$').hasMatch(s)) return '+966$s'; // mobile
        if (RegExp(r'^(01[1-7]\d{6,7})$').hasMatch(s)) {
          return '+966${s.substring(1)}'; // landline
        }
        return '';
      }

      final oldPhoneE164 = (current[UserFields.phone] ?? '').toString();
      String? newPhoneE164;
      if (hasPhoneValid) {
        final candidate = normalizePhoneToE164(phoneLocal);
        if (candidate.isEmpty) {
          throw Exception('Phone format not recognized');
        }
        if (candidate != oldPhoneE164) {
          newPhoneE164 = candidate;
        }
      }

      // 3) ارفعي اللوقو لو فيه pending
      String? newLogoUrl;
      String? newLogoPath;

      if (_pendingLogoFile != null) {
        final err = _validateImageFile(_pendingLogoFile!);
        if (err != null) {
          throw Exception(err);
        }

        final res = await _uploadLogoWithProgress(_pendingLogoFile!);
        newLogoUrl = res['url'];
        newLogoPath = res['path'];
        _pendingLogoFile = null;
      }

      // 4) جهّزي باقي القيم للتحديث
      final desc = _desc.text.trim();
      final loc = _cleanLoc(_locCtrl.text);

      final complete = desc.length >= 100 &&
          loc.isNotEmpty &&
          (hasEmailValid || hasPhoneValid);

      final updates = <String, dynamic>{
        UserFields.description: desc,
        UserFields.location: loc,
        UserFields.isProfileComplete: complete,
      };

      final oldEmail = (current[UserFields.contactEmail] ?? '').toString();
      if (email != oldEmail) {
        if (email.isEmpty) {
          updates[UserFields.contactEmail] = FieldValue.delete();
        } else {
          updates[UserFields.contactEmail] = email;
        }
      }

      if (newPhoneE164 != null) {
        updates[UserFields.phone] = newPhoneE164;
      }

      if (newLogoUrl != null) {
        updates[UserFields.photoUrl] = newLogoUrl;
        if (newLogoPath != null) {
          updates[UserFields.photoPath] = newLogoPath;
        }
        _logoUrl = newLogoUrl;
      } else if (_logoUrl == '') {
        // user pressed Remove
        updates[UserFields.photoUrl] = FieldValue.delete();
        updates[UserFields.photoPath] = FieldValue.delete();
      }

      if (updates.isEmpty) {
        _showSnackError('No changes to save', inContext: inContext ?? context);
        return false;
      }

      // 5) اكتبي في Firestore
      final uid = FirebaseAuth.instance.currentUser!.uid;
      await FirebaseFirestore.instance
          .collection(kUsersCollection)
          .doc(uid)
          .set(updates, SetOptions(merge: true));

      // 6) تنظيف الشعار القديم لو تبدّل
      if (newLogoUrl != null) {
        final oldPath = (current[UserFields.photoPath] ?? '').toString();
        if (oldPath.isNotEmpty) {
          await _deleteStorageFile(oldPath);
        } else {
          final oldUrl = (current[UserFields.photoUrl] ?? '').toString();
          if (oldUrl.isNotEmpty) {
            await _deleteStorageFile(oldUrl);
          }
        }
      }

      if (_logoUrl == '' &&
          (current[UserFields.photoPath]?.toString().isNotEmpty ?? false)) {
        await _deleteStorageFile(current[UserFields.photoPath]?.toString());
      } else if (_logoUrl == '' &&
          (current[UserFields.photoUrl]?.toString().isNotEmpty ?? false)) {
        await _deleteStorageFile(current[UserFields.photoUrl]?.toString());
      }

      // كل شي تمام 🎉
      _showSnackSuccess('✅ Profile updated successfully',
          inContext: inContext ?? context);

      return true; // <--- نجاح
    } catch (e) {
      _showSnackError('❌ Failed to update profile',
          inContext: inContext ?? context);
      return false; // <--- فشل
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
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final data = snap.data?.data() ?? {};

        // نحسب أشياء جاهزة للعرض
        final logoUrlLocal = _pendingLogoFile != null
            ? null // لو فيه pending local بنعرضها تحت
            : (_logoUrl ?? data[UserFields.photoUrl])?.toString();

        final companyName =
            (data['CompanyName'] ?? data['Name'] ?? 'Company').toString();

        final contactEmail =
            (data[UserFields.contactEmail] ?? '').toString().trim();

        final rawPhone = (data[UserFields.phone] ?? '').toString().trim();
        final prettyPhone = rawPhone.isEmpty ? '' : _toLocal(rawPhone);

        final location = (data[UserFields.location] ?? '').toString().trim();
        final desc = (data[UserFields.description] ?? '').toString().trim();

        final profileComplete = data[UserFields.isProfileComplete] == true;
        if (!_filledFromServer) {
          // نعبيه في next frame عشان ما نصطدم مع setState داخل build
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;

            _desc.text = _desc.text.isNotEmpty
                ? _desc.text
                : (data[UserFields.description] ?? '').toString();

            _locCtrl.text = _locCtrl.text.isNotEmpty
                ? _locCtrl.text
                : (data[UserFields.location] ?? '').toString();

            _emailCtrl.text = _emailCtrl.text.isNotEmpty
                ? _emailCtrl.text
                : (data[UserFields.contactEmail] ?? '').toString();

            _phone.text = _phone.text.isNotEmpty
                ? _phone.text
                : (() {
                    final raw = (data[UserFields.phone] ?? '').toString();
                    return raw.isEmpty ? '' : _toLocal(raw);
                  })();

            _filledFromServer = true;
            setState(() {});
          });
        }

        return Scaffold(
          backgroundColor: const Color(0xFFF7F6FC),
          appBar: AppBar(
            backgroundColor: const Color(0xFF4A5FBC),
            elevation: 0,
            title: const Text(
              'Company Profile',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            iconTheme: const IconThemeData(color: Colors.white),
          ),

          // زر حفظ ما نحتاجه هنا لأن هذي شاشة عرض مو تعديل.
          // نخلي زر تسجيل خروج / أو ما نخلي شي أبداً.
          bottomNavigationBar: SafeArea(
            minimum: const EdgeInsets.all(16),
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF4A5FBC),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                foregroundColor: Colors.white,
              ),
              onPressed: () => _openEditSheet(context, data),
              child: const Text('Edit Company Info'),
            ),
          ),

          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ====== CARD العلوية: الهيدر (يشبه الصورة) ======
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 20,
                ),
                child: Column(
                  children: [
                    // الصورة (اللوقو)
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          padding:
                              const EdgeInsets.all(3), // مساحة جوّا البوردر
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFF4A5FBC),
                              width: 4,
                            ),
                          ),
                          child: CircleAvatar(
                            radius: 42,
                            backgroundColor: Colors.white,
                            backgroundImage: _pendingLogoFile != null
                                ? FileImage(_pendingLogoFile!) as ImageProvider
                                : (logoUrlLocal != null &&
                                        logoUrlLocal.isNotEmpty)
                                    ? NetworkImage(logoUrlLocal)
                                    : null,
                            child: (logoUrlLocal == null ||
                                        logoUrlLocal.isEmpty) &&
                                    _pendingLogoFile == null
                                ? const Icon(
                                    Icons.business,
                                    size: 32,
                                    color: Color(0xFF4A5FBC),
                                  )
                                : null,
                          ),
                        ),

                        // حالة الاكتمال (زي البادج الأزرق بالصورة)
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

                    // اسم الشركة
                    Text(
                      companyName.isEmpty ? 'Company' : companyName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF4A5FBC),
                      ),
                    ),

                    const SizedBox(height: 6),
// موقع الشركة (location)
                    if (location.isNotEmpty)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            size: 16,
                            color: Color(0xFF4A5FBC),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              location,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF4A5FBC),
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 12),

                    // "بادج" فيها تواصل أساسي: إيميل أو رقم
                    if (contactEmail.isNotEmpty || prettyPhone.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF2FF),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (contactEmail.isNotEmpty)
                              Text(
                                contactEmail,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF4A5FBC),
                                ),
                              ),
                            if (contactEmail.isNotEmpty &&
                                prettyPhone.isNotEmpty)
                              const Text(
                                '  |  ', // فاصل بين الإيميل والرقم
                                style: TextStyle(
                                  color: Color(0xFF4A5FBC),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            if (prettyPhone.isNotEmpty)
                              Text(
                                prettyPhone,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF4A5FBC),
                                ),
                              ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 16),

                    // وصف الشركة (مقتطع سطرين)
                    if (desc.isNotEmpty) _ExpandableDescription(text: desc),
                  ],
                ),
              ),

              const SizedBox(height: 24),

// ====== CARD الخيارات (زي اللستة في الصورة) ======
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _SettingsRow(
                      icon: Icons.info_outline,
                      color: const Color(0xFF4A5FBC),
                      title: 'Company Info',
                      subtitle: 'Description, logo, location',
                      onTap: () =>
                          _openEditSheet(context, data, initialTab: 'company'),
                    ),
                    const Divider(height: 1),
                    _SettingsRow(
                      icon: Icons.mail_outline,
                      color: const Color(0xFF4A5FBC),
                      title: 'Contact Details',
                      subtitle: 'Email / phone for applicants',
                      onTap: () =>
                          _openEditSheet(context, data, initialTab: 'contact'),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }

  void _openEditSheet(
    BuildContext context,
    Map<String, dynamic> data, {
    String initialTab = 'company', // 'company' أو 'contact'
  }) {
    final int initialIndex = initialTab == 'contact' ? 1 : 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.9,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (ctx, scrollController) {
            return _EditCompanySheet(
              data: data,
              scrollController: scrollController,
              initialTabIndex: initialIndex,
              // نبغى نوصل له state حقتنا عشان يستدعي _save ويستخدم الكونترولرز
              parentState: this,
            );
          },
        );
      },
    );
  }
}

class _ExpandableDescription extends StatefulWidget {
  final String text;
  const _ExpandableDescription({required this.text});

  @override
  State<_ExpandableDescription> createState() => _ExpandableDescriptionState();
}

class _ExpandableDescriptionState extends State<_ExpandableDescription> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final text = widget.text.trim();
    final maxLines = _expanded ? null : 3;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          text,
          maxLines: maxLines,
          overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
          textAlign: TextAlign.justify, // 👈 ضبط النص
          style: const TextStyle(
            fontSize: 13.5,
            height: 1.5,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Text(
            _expanded ? 'Show less' : 'Show more',
            style: const TextStyle(
              color: Color(0xFF4A5FBC),
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsRow({
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
                      color: Colors.black,
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

class _EditCompanySheet extends StatefulWidget {
  final Map<String, dynamic> data;
  final ScrollController scrollController;
  final int initialTabIndex;
  final _CompanyProfileState parentState;

  const _EditCompanySheet({
    required this.data,
    required this.scrollController,
    required this.initialTabIndex,
    required this.parentState,
  });

  @override
  State<_EditCompanySheet> createState() => _EditCompanySheetState();
}

class _EditCompanySheetState extends State<_EditCompanySheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const brand = Color(0xFF4A5FBC);
    final parent = widget.parentState;

    return Scaffold(
      // هذا السكافولد خاص بالـsheet
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            if (parent._progress != null)
              LinearProgressIndicator(
                value: parent._progress == 0 ? null : parent._progress,
                minHeight: 4,
                backgroundColor: Colors.black12,
                color: const Color(0xFF4A5FBC),
              ),
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Edit Company Info',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F3FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: TabBar(
                  controller: _tabCtrl,
                  isScrollable: false,
                  dividerColor: Colors.transparent,
                  indicator: BoxDecoration(
                    color: brand,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  labelColor: Colors.white,
                  unselectedLabelColor: brand,
                  labelPadding: EdgeInsets.zero,
                  tabs: const [
                    Tab(
                      child: SizedBox.expand(
                        child: Center(
                          child: Text(
                            'Company Info',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Tab(
                      child: SizedBox.expand(
                        child: Center(
                          child: Text(
                            'Contact Details',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Form(
                key: parent._form,
                child: TabBarView(
                  controller: _tabCtrl,
                  children: [
                    // ---------------- TAB 0 ----------------
                    SingleChildScrollView(
                      controller: widget.scrollController,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Logo',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(
                                    2), // سمك البوردر من داخل
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color:
                                        const Color(0xFF4A5FBC), // لون البوردر
                                    width: 2, // سماكة البوردر
                                  ),
                                ),
                                child: CircleAvatar(
                                  radius: 32,
                                  backgroundColor: Colors.white, // داخل الدائرة
                                  backgroundImage: parent._pendingLogoFile !=
                                          null
                                      ? FileImage(parent._pendingLogoFile!)
                                          as ImageProvider
                                      : ((parent._logoUrl ??
                                                      widget.data[
                                                          UserFields.photoUrl])
                                                  ?.toString()
                                                  .isNotEmpty ==
                                              true
                                          ? NetworkImage(
                                              (parent._logoUrl ??
                                                      widget.data[
                                                          UserFields.photoUrl])
                                                  .toString(),
                                            )
                                          : null),
                                  child: (parent._pendingLogoFile == null &&
                                          !((parent._logoUrl ??
                                                      widget.data[
                                                          UserFields.photoUrl])
                                                  ?.toString()
                                                  .isNotEmpty ==
                                              true))
                                      ? const Icon(
                                          Icons.business,
                                          color: Color(0xFF4A5FBC),
                                          size: 28,
                                        )
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 16),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFFD6C67),
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                ),
                                onPressed:
                                    parent._saving || parent._progress != null
                                        ? null
                                        : () async {
                                            await parent._pickLogo();
                                            if (mounted) setState(() {});
                                          },
                                child: const Text(
                                  'Upload Logo',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              if (parent._pendingLogoFile != null ||
                                  ((parent._logoUrl ??
                                              widget.data[UserFields.photoUrl])
                                          ?.toString()
                                          .isNotEmpty ==
                                      true))
                                TextButton(
                                  onPressed:
                                      parent._saving || parent._progress != null
                                          ? null
                                          : () {
                                              parent.setState(() {
                                                parent._pendingLogoFile = null;
                                                parent._logoUrl = '';
                                              });
                                              if (mounted) setState(() {});
                                            },
                                  child: const Text('Remove'),
                                ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Description (min 100 chars)',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            key: parent._descKey,
                            controller: parent._desc,
                            maxLines: 4,
                            maxLength: 600,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                            ),
                            validator: (v) {
                              final t = v?.trim() ?? '';
                              if (t.isEmpty) return 'Enter description';
                              if (t.length < 100) return 'Too short';
                              if (t.length > 600) {
                                return 'Too long (max 600)';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Location',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            key: parent._locKey,
                            controller: parent._locCtrl,
                            textCapitalization: TextCapitalization.words,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r"[A-Za-z\u0600-\u06FF\s\.'-]"),
                              ),
                              LengthLimitingTextInputFormatter(40),
                            ],
                            decoration: const InputDecoration(
                              hintText: 'e.g., Riyadh / جدة / Al Khobar',
                              border: OutlineInputBorder(),
                            ),
                            validator: (v) {
                              final t = parent._cleanLoc(v ?? '');
                              if (t.isEmpty) return 'Enter location';
                              if (!parent._locAllowed.hasMatch(t)) {
                                return '2–40 letters only (Arabic/English), no numbers';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 120),
                        ],
                      ),
                    ),

                    // ---------------- TAB 1 ----------------
                    SingleChildScrollView(
                      controller: widget.scrollController,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Contact Email',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            key: parent._emailKey,
                            controller: parent._emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              helperText:
                                  'Provide email OR phone (one is enough)',
                            ),
                            validator: (v) {
                              final t = v?.trim() ?? '';
                              if (t.isEmpty) return null;
                              if (!_email.hasMatch(t)) return 'Invalid email';
                              return null;
                            },
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Contact Phone',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ValueListenableBuilder<TextEditingValue>(
                            valueListenable: parent._phone,
                            builder: (context, value, _) {
                              final t = value.text.trim();
                              final isMobile = t.startsWith('5');
                              return TextFormField(
                                key: parent._phoneKey,
                                controller: parent._phone,
                                keyboardType: TextInputType.phone,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(10),
                                ],
                                decoration: InputDecoration(
                                  hintText: '5XXXXXXXX or 01XXXXXXXX',
                                  prefixText: isMobile ? '+966 ' : '',
                                  border: const OutlineInputBorder(),
                                ),
                                validator: (v) {
                                  final s = v?.trim() ?? '';
                                  if (s.isEmpty) return null;
                                  final reg =
                                      RegExp(r'^(5\d{8}|01[1-7]\d{6,7})$');
                                  if (!reg.hasMatch(s)) {
                                    return 'Enter a valid Saudi mobile or landline number';
                                  }
                                  return null;
                                },
                              );
                            },
                          ),
                          const SizedBox(height: 120),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              minimum: const EdgeInsets.symmetric(horizontal: 16)
                  .copyWith(bottom: 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: brand,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed: parent._saving || parent._progress != null
                      ? null
                      : () async {
                          final ok = await parent._save(
                            widget.data,
                            inContext: context, // Snack هنا
                          );

                          if (!mounted) return;

                          if (ok) {
                            Navigator.of(context).pop();
                          }
                        },
                  child: const Text('Save changes'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
