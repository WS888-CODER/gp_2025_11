import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:gp_2025_11/config/themed_scaffold.dart';
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
  if (rest.startsWith('5')) return rest; // موبايل
  if (RegExp(r'^1[1-7]\d{6,7}$').hasMatch(rest)) return '0$rest'; // أرضي

  return rest;
}

class CompanyProfile extends StatefulWidget {
  const CompanyProfile({super.key});

  @override
  State<CompanyProfile> createState() => _CompanyProfileState();
}

class _CompanyProfileState extends State<CompanyProfile> {
  StreamSubscription<TaskSnapshot>? _uploadSub;
  final _form = GlobalKey<FormState>();
  final _desc = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phone = TextEditingController();
  final _locCtrl = TextEditingController();

  final _descKey = GlobalKey<FormFieldState>();
  final _emailKey = GlobalKey<FormFieldState>();
  final _phoneKey = GlobalKey<FormFieldState>();
  final _locKey = GlobalKey<FormFieldState>();

  final _descFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _locFocus = FocusNode();

  File? _pendingLogoFile;
  static const int _kMaxImageBytes = 5 * 1024 * 1024; // 5MB
  String? _logoUrl;
  bool _saving = false;
  double? _progress;
  bool _filledFromServer = false;

  final _locAllowed =
      RegExp(r"^[A-Za-z\u0600-\u06FF][A-Za-z\u0600-\u06FF\s\.'-]{1,39}$");
  String _cleanLoc(String raw) => raw.trim().replaceAll(RegExp(r'\s+'), ' ');

  // تحقق صارم للصورة
  String? _validateImageFile(File f) {
    final len = f.lengthSync();
    if (len > _kMaxImageBytes) return 'Image too large (max 5 MB)';

    final ext = f.path.split('.').last.toLowerCase();
    if (!(ext == 'png' || ext == 'jpg')) {
      return 'Unsupported image type. Use PNG or JPG (JPEG is not allowed).';
    }

    try {
      final bytes = f.openSync(mode: FileMode.read)..setPositionSync(0);
      final header = bytes.readSync(12);
      bytes.closeSync();

      final isPng = header.length >= 8 &&
          header[0] == 0x89 &&
          header[1] == 0x50 &&
          header[2] == 0x4E &&
          header[3] == 0x47 &&
          header[4] == 0x0D &&
          header[5] == 0x0A &&
          header[6] == 0x1A &&
          header[7] == 0x0A;

      final isJpeg = header.length >= 3 &&
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

  @override
  void dispose() {
    _desc.dispose();
    _emailCtrl.dispose();
    _phone.dispose();
    _locCtrl.dispose();

    _descFocus.dispose();
    _emailFocus.dispose();
    _phoneFocus.dispose();
    _locFocus.dispose();

    _uploadSub?.cancel();

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
      // ignore
    }
  }

  Future<Map<String, String>> _uploadLogoWithProgress(File file) async {
    final len = await file.length();
    if (len > 5 * 1024 * 1024) {
      throw Exception('Image too large (max 5 MB)');
    }

    final ext = file.path.split('.').last.toLowerCase();
    if (!(ext == 'png' || ext == 'jpg')) {
      throw Exception('Unsupported image type. Use PNG or JPG only.');
    }

    try {
      final raf = file.openSync(mode: FileMode.read)..setPositionSync(0);
      final header = raf.readSync(12);
      raf.closeSync();

      final isPng = header.length >= 8 &&
          header[0] == 0x89 &&
          header[1] == 0x50 &&
          header[2] == 0x4E &&
          header[3] == 0x47 &&
          header[4] == 0x0D &&
          header[5] == 0x0A &&
          header[6] == 0x1A &&
          header[7] == 0x0A;

      final isJpeg = header.length >= 3 &&
          header[0] == 0xFF &&
          header[1] == 0xD8 &&
          header[2] == 0xFF;

      if ((ext == 'png' && !isPng) || (ext == 'jpg' && !isJpeg)) {
        throw Exception('File content does not match extension.');
      }
    } catch (_) {
      throw Exception('Corrupted or unreadable image.');
    }

    final uid = FirebaseAuth.instance.currentUser!.uid;
    final name = file.path.split('/').last;
    final ref = FirebaseStorage.instance.ref(
      'logos/$uid/${DateTime.now().millisecondsSinceEpoch}_$name',
    );

    if (!mounted) {
      throw Exception('Screen closed');
    }

    setState(() {
      _progress = 0;
    });

    final task = ref.putFile(file);

    _uploadSub = task.snapshotEvents.listen((s) {
      if (!mounted) return;
      final total = s.totalBytes;
      if (total > 0) {
        setState(() {
          _progress = s.bytesTransferred / total;
        });
      }
    });

    try {
      final snap = await task; // no timeout here (you CAN add one if you want)
      final url = await snap.ref.getDownloadURL();
      final path = snap.ref.fullPath;

      if (mounted) {
        setState(() {
          _progress = null;
        });
      }

      return {'url': url, 'path': path};
    } on FirebaseException catch (e) {
      if (mounted) {
        setState(() {
          _progress = null;
        });
        _showSnackError(
          'Upload failed: ${e.message ?? e.code}',
        );
      }
      rethrow;
    } catch (e) {
      if (mounted) {
        setState(() {
          _progress = null;
        });
      }
      rethrow;
    }
  }

  Future<void> _pickLogo() async {
    final img = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 92);
    if (img == null) return;

    setState(() {
      _pendingLogoFile = File(img.path);
    });

    _showSnackSuccess('Logo selected.');
  }

  bool _hasAnyLogo(Map<String, dynamic> current) {
    final hasPending = _pendingLogoFile != null;
    final hasExisting =
        ((_logoUrl ?? current[UserFields.photoUrl])?.toString().isNotEmpty ??
            false);
    return hasPending || hasExisting;
  }

  Future<bool> _save(Map<String, dynamic> current,
      {BuildContext? inContext}) async {
    final formOk = _form.currentState?.validate() ?? false;

    final hasLogoNow = _hasAnyLogo(current);

    final email = _emailCtrl.text.trim();
    final phoneLocal = _phone.text.trim();
    final hasEmailValid = email.isNotEmpty && _email.hasMatch(email);
    final hasPhoneValid =
        phoneLocal.isNotEmpty && _localSaPhone.hasMatch(phoneLocal);

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

    setState(() {
      _saving = true;
      _progress = 0;
    });

    try {
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

      final desc = _desc.text.trim();
      final loc = _cleanLoc(_locCtrl.text);

      final complete = desc.length >= 100 &&
          loc.isNotEmpty &&
          (hasEmailValid || hasPhoneValid) &&
          _hasAnyLogo(current);

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
        updates[UserFields.photoUrl] = FieldValue.delete();
        updates[UserFields.photoPath] = FieldValue.delete();
      }

      if (updates.isEmpty) {
        _showSnackError('No changes to save', inContext: inContext ?? context);
        return false;
      }

      final uid = FirebaseAuth.instance.currentUser!.uid;
      await FirebaseFirestore.instance
          .collection(kUsersCollection)
          .doc(uid)
          .set(updates, SetOptions(merge: true));

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

      _showSnackSuccess('✅ Profile updated successfully',
          inContext: inContext ?? context);

      return true;
    } catch (e) {
      _showSnackError('❌ Failed to update profile',
          inContext: inContext ?? context);
      return false;
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
      return const ThemedScaffold(body: Center(child: Text('Not signed in')));
    }
    final scheme = Theme.of(context).colorScheme;
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

        final logoUrlLocal = _pendingLogoFile != null
            ? null
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

        return ThemedScaffold(
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
          bottomNavigationBar: SafeArea(
            minimum: const EdgeInsets.all(16),
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF4A5FBC),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => EditCompanyPage(
                      data: data,
                      parentState: this,
                      initialTabIndex: 0,
                    ),
                  ),
                );
              },
              child: const Text('Edit Company Info'),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // card header
              Container(
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(
                        Theme.of(context).brightness == Brightness.dark
                            ? 0.6
                            : 0.05,
                      ),
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
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(3),
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
                      companyName.isEmpty ? 'Company' : companyName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF4A5FBC),
                      ),
                    ),
                    const SizedBox(height: 6),
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
                                '  |  ',
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
                    if (desc.isNotEmpty) _ExpandableDescription(text: desc),
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
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => EditCompanyPage(
                              data: data,
                              parentState: this,
                              initialTabIndex: 0,
                            ),
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1),
                    _SettingsRow(
                      icon: Icons.mail_outline,
                      color: const Color(0xFF4A5FBC),
                      title: 'Contact Details',
                      subtitle: 'Email / phone for applicants',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => EditCompanyPage(
                              data: data,
                              parentState: this,
                              initialTabIndex: 1,
                            ),
                          ),
                        );
                      },
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
          textAlign: TextAlign.justify,
          style: const TextStyle(
            fontSize: 13.5,
            height: 1.5,
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

class EditCompanyPage extends StatefulWidget {
  final Map<String, dynamic> data;
  final _CompanyProfileState parentState;
  final int initialTabIndex;

  const EditCompanyPage({
    super.key,
    required this.data,
    required this.parentState,
    this.initialTabIndex = 0,
  });

  @override
  State<EditCompanyPage> createState() => _EditCompanyPageState();
}

class _EditCompanyPageState extends State<EditCompanyPage>
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

    return WillPopScope(
      onWillPop: () async {
        final hasChanges = _hasUnsavedChanges();
        if (!hasChanges) return true;

        final shouldLeave = await _showLeaveConfirmDialogStyled(context);
        return shouldLeave ?? false;
      },
      child: ThemedScaffold(
        appBar: AppBar(
          backgroundColor: brand,
          title: const Text(
            'Edit Company Info',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () async {
              final hasChanges = _hasUnsavedChanges();
              if (!hasChanges) {
                Navigator.of(context).pop();
                return;
              }

              final shouldLeave = await _showLeaveConfirmDialogStyled(context);
              if (shouldLeave == true && mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48 + 4),
            child: Column(
              children: [
                if (parent._progress != null)
                  LinearProgressIndicator(
                    value: parent._progress == 0 ? null : parent._progress,
                    minHeight: 4,
                    backgroundColor: Colors.black12,
                    color: Colors.white,
                  ),
                const SizedBox(height: 8),
                Container(
                  height: 44,
                  margin: const EdgeInsets.symmetric(horizontal: 16)
                      .copyWith(bottom: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F3FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: TabBar(
                    controller: _tabCtrl,
                    isScrollable: false,
                    dividerColor: Colors.transparent,
                    indicator: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    labelColor: brand,
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
              ],
            ),
          ),
        ),
        body: Form(
          key: parent._form,
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              // TAB 0: Company Info
              ListView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                children: [
                  const Text(
                    'Logo',
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
                          backgroundImage: parent._pendingLogoFile != null
                              ? FileImage(parent._pendingLogoFile!)
                                  as ImageProvider
                              : ((parent._logoUrl ??
                                              widget.data[UserFields.photoUrl])
                                          ?.toString()
                                          .isNotEmpty ==
                                      true
                                  ? NetworkImage(
                                      (parent._logoUrl ??
                                              widget.data[UserFields.photoUrl])
                                          .toString(),
                                    )
                                  : null),
                          child: (parent._pendingLogoFile == null &&
                                  !((parent._logoUrl ??
                                              widget.data[UserFields.photoUrl])
                                          ?.toString()
                                          .isNotEmpty ==
                                      true))
                              ? const Icon(
                                  Icons.business,
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
                                color: Colors.white,
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
                              child: const Text(
                                'Remove',
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Description (min 100 chars)',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
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
                      hintText: 'e.g., Riyadh / Jeddah / Al Khobar',
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

              // TAB 1: Contact
              ListView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                children: [
                  const Text(
                    'Contact Email',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: parent._emailKey,
                    controller: parent._emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
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
                  const SizedBox(height: 24),
                  const Text(
                    'Contact Phone',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
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
                          final reg = RegExp(r'^(5\d{8}|01[1-7]\d{6,7})$');
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
              onPressed: parent._saving || parent._progress != null
                  ? null
                  : () async {
                      final ok = await parent._save(
                        widget.data,
                        inContext: context,
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
      ),
    );
  }

  bool _hasUnsavedChanges() {
    final parent = widget.parentState;
    final original = widget.data;

    final origDesc = (original[UserFields.description] ?? '').toString().trim();
    final currDesc = parent._desc.text.trim();
    if (currDesc != origDesc) return true;

    final origLoc = (original[UserFields.location] ?? '').toString().trim();
    final currLoc = parent._locCtrl.text.trim();
    if (currLoc != origLoc) return true;

    final origEmail =
        (original[UserFields.contactEmail] ?? '').toString().trim();
    final currEmail = parent._emailCtrl.text.trim();
    if (currEmail != origEmail) return true;

    final origPhoneE164 = (original[UserFields.phone] ?? '').toString().trim();
    final currPhoneLocal = parent._phone.text.trim();

    String _toComparableLocal(String e164) {
      if (e164.isEmpty) return '';
      final t = e164.trim();
      if (!t.startsWith(_saPrefix)) return t;

      final rest = t.substring(_saPrefix.length);

      if (rest.startsWith('5')) {
        return rest;
      }

      if (RegExp(r'^1[1-7]\d{6,7}$').hasMatch(rest)) {
        return '0$rest';
      }

      return rest;
    }

    final origPhoneLocal = _toComparableLocal(origPhoneE164);
    if (currPhoneLocal != origPhoneLocal) return true;

    final origLogoUrl = (original[UserFields.photoUrl] ?? '').toString().trim();

    if (parent._pendingLogoFile != null) {
      return true;
    }

    if (parent._logoUrl == '') {
      if (origLogoUrl.isNotEmpty) {
        return true;
      }
    }

    if (parent._logoUrl != null &&
        parent._logoUrl!.isNotEmpty &&
        parent._logoUrl!.trim() != origLogoUrl) {
      return true;
    }

    return false;
  }

  Future<bool?> _showLeaveConfirmDialogStyled(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF4A5FBC).withOpacity(0.7),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
        title: const Text(
          'Discard changes?',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          'You have unsaved changes. Are you sure you want to leave without saving?',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
          ),
        ),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        actionsPadding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          // زر Cancel (أبغى أكمل تعديل، لا تطلعني)
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.9),
              foregroundColor: const Color(0xFF4A5FBC),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: const Text(
              'Cancel',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),

          const SizedBox(width: 12),

          // زر Discard (اخرج وامسح التعديلات)
          TextButton(
            onPressed: () {
              // نرجع القيم الأصلية قبل ما نطلع
              _restoreParentFromOriginal();
              Navigator.pop(context, true);
            },
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xFFFC686A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: const Text(
              'Discard',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _restoreParentFromOriginal() {
    final parent = widget.parentState;
    final original = widget.data;

    parent.setState(() {
      // رجّعي الوصف
      parent._desc.text =
          (original[UserFields.description] ?? '').toString().trim();

      // رجّعي الموقع
      parent._locCtrl.text =
          (original[UserFields.location] ?? '').toString().trim();

      // رجّعي الإيميل
      parent._emailCtrl.text =
          (original[UserFields.contactEmail] ?? '').toString().trim();

      // رجّعي الرقم (حوّلي من E.164 للعرض المحلي)
      final origPhoneE164 =
          (original[UserFields.phone] ?? '').toString().trim();

      String _toComparableLocal(String e164) {
        if (e164.isEmpty) return '';
        final t = e164.trim();
        if (!t.startsWith(_saPrefix)) return t;

        final rest = t.substring(_saPrefix.length);

        if (rest.startsWith('5')) {
          // جوال: نخليه 5XXXXXXXX
          return rest;
        }

        if (RegExp(r'^1[1-7]\d{6,7}$').hasMatch(rest)) {
          // أرضي: 011 ... -> نرجع له الصفر
          return '0$rest';
        }

        return rest;
      }

      parent._phone.text = _toComparableLocal(origPhoneE164);

      // رجّعي حالة اللوقو:
      // 1. ما عاد فيه ملف pending
      parent._pendingLogoFile = null;

      // 2. لو كانت _logoUrl = '' لأن المستخدم ضغط Remove
      //    نرجعها للي في الداتا الأصلية
      final origLogoUrl =
          (original[UserFields.photoUrl] ?? '').toString().trim();
      parent._logoUrl = origLogoUrl.isEmpty ? null : origLogoUrl;

      // reset حالات ui
      parent._saving = false;
      parent._progress = null;
    });
  }
}
