import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:gp_2025_11/config/theme.dart';
import 'package:gp_2025_11/screens/jobseeker_profile.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';
import 'package:intl_phone_field/country_picker_dialog.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:intl_phone_field/phone_number.dart';
import 'package:url_launcher/url_launcher.dart';

const kUsersCollection = 'Users';
const kJobsCollection = 'Jobs';

class UserFields {
  static const photoUrl = 'PhotoURL';
  static const description = 'Description';
  static const location = 'Location';
  static const contactEmail = 'ContactEmail';
  static const phone = 'Phone';
  static const isProfileComplete = 'IsProfileComplete';
  static const photoPath = 'PhotoPath';
  static const website = 'Website';
}

final _email =
    RegExp(r"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$", caseSensitive: false);

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
  final _websiteCtrl = TextEditingController();
  final _websiteKey = GlobalKey<FormFieldState>();
  final _websiteFocus = FocusNode();

  final _urlReg = RegExp(
    r'^(https?:\/\/)?'
    r'([A-Za-z0-9-]+\.)+[A-Za-z]{2,}'
    r'(\/[^\s]*)?$',
    caseSensitive: false,
  );

  File? _pendingLogoFile;
  static const int _kMaxImageBytes = 5 * 1024 * 1024;
  String? _logoUrl;
  bool _saving = false;
  double? _progress;
  bool _filledFromServer = false;
  final ValueNotifier<double?> progressNotifier = ValueNotifier<double?>(null);
  String? _phoneE164Draft;

  final _locAllowed =
      RegExp(r"^[A-Za-z\u0600-\u06FF][A-Za-z\u0600-\u06FF\s\.'-]{1,39}$");

  String _cleanLoc(String raw) => raw.trim().replaceAll(RegExp(r'\s+'), ' ');

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

    return null;
  }

  Future<void> _openWebsite(String raw) async {
    final t = raw.trim();
    final url = t.startsWith(RegExp(r'https?://', caseSensitive: false))
        ? t
        : 'https://$t';
    final uri = Uri.tryParse(url);
    if (uri == null) {
      SnackHelper.error(context, 'Invalid URL');
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) SnackHelper.error(context, 'Could not open the website');
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
    _websiteCtrl.dispose();
    _websiteFocus.dispose();
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
    } catch (_) {}
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
    progressNotifier.value = 0;

    final task = ref.putFile(file);

    _uploadSub = task.snapshotEvents.listen((s) {
      if (!mounted) return;
      final total = s.totalBytes;
      if (total > 0) {
        final value = s.bytesTransferred / total;
        setState(() {
          _progress = value;
        });
        progressNotifier.value = value;
      }
    });

    try {
      final snap = await task;
      final url = await snap.ref.getDownloadURL();
      final path = snap.ref.fullPath;

      if (mounted) {
        setState(() {
          _progress = null;
        });
        progressNotifier.value = null;
      }

      return {'url': url, 'path': path};
    } on FirebaseException catch (e) {
      if (mounted) {
        setState(() {
          _progress = null;
        });
        progressNotifier.value = null;
        SnackHelper.error(
          context,
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
      progressNotifier.value = null;
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

    SnackHelper.success(context, 'Logo selected.');
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
    final uiContext = inContext ?? context;

    if (_saving) return false;

    final email = _emailCtrl.text.trim();
    final websiteRaw = _websiteCtrl.text.trim();
    final desc = _desc.text.trim();
    final loc = _cleanLoc(_locCtrl.text);
    final phoneLocal = _phone.text.trim();
    final hasPhoneDigits = phoneLocal.isNotEmpty;

    final oldPhoneE164 = (current[UserFields.phone] ?? '').toString().trim();
    final oldWebsite = (current[UserFields.website] ?? '').toString().trim();

    final wasComplete = current[UserFields.isProfileComplete] == true;
    final hadLogoBefore = _hasAnyLogo(current);

    final draftFromState = (_phoneE164Draft ?? '').trim();
    final hasContactEmail = email.isNotEmpty;
    final hasContactPhone = hasPhoneDigits || draftFromState.isNotEmpty;
    final hasAnyContact = hasContactEmail || hasContactPhone;

    final formOk = _form.currentState?.validate() ?? false;

    if (!formOk) {
      final emailInvalid = email.isNotEmpty && !_email.hasMatch(email);
      if (emailInvalid) {
        _emailKey.currentState?.validate();
        SnackHelper.error(uiContext, 'Enter a valid email address');
        return false;
      }

      if (hasPhoneDigits) {
        _phoneKey.currentState?.validate();
        SnackHelper.error(uiContext, 'Enter a valid phone number');
        return false;
      }

      if (websiteRaw.isNotEmpty) {
        final normalized =
            websiteRaw.startsWith(RegExp(r'https?://', caseSensitive: false))
                ? websiteRaw
                : 'https://$websiteRaw';

        if (!_urlReg.hasMatch(normalized)) {
          _websiteKey.currentState?.validate();
          SnackHelper.error(
            uiContext,
            'Enter a valid website URL or leave empty',
          );
          return false;
        }
      }

      if (_locKey.currentState?.hasError ?? false) {
        _locKey.currentState?.validate();
        SnackHelper.error(
          uiContext,
          'Location must be 2–40 letters (Arabic/English), no numbers',
        );
        return false;
      }

      SnackHelper.error(uiContext, 'Please check your information');
      return false;
    }

    final uid = FirebaseAuth.instance.currentUser!.uid;

    bool hasJobs = false;
    try {
      final jobsSnap = await FirebaseFirestore.instance
          .collection(kJobsCollection)
          .where('UserID', isEqualTo: uid)
          .limit(1)
          .get();
      hasJobs = jobsSnap.docs.isNotEmpty;
    } catch (_) {
      SnackHelper.error(
        uiContext,
        'Could not verify your job posts. Please try again.',
      );
      return false;
    }

    if (wasComplete && hasJobs) {
      if (!_hasAnyLogo(current)) {
        SnackHelper.error(
          uiContext,
          'While you have job posts, you must keep a company logo.',
        );
        return false;
      }
      if (desc.length < 150) {
        SnackHelper.error(
          uiContext,
          'While you have job posts, description must be at least 150 characters.',
        );
        return false;
      }
      if (loc.isEmpty) {
        SnackHelper.error(
          uiContext,
          'While you have job posts, location cannot be empty.',
        );
        return false;
      }
      if (!hasAnyContact) {
        SnackHelper.error(
          uiContext,
          'While you have job posts, you must keep at least one contact method (email or phone).',
        );
        return false;
      }
    }

    setState(() {
      _saving = true;
    });

    try {
      String? newPhoneE164;
      final draftTrim = (_phoneE164Draft ?? '').trim();
      if (draftTrim.isNotEmpty && draftTrim != oldPhoneE164) {
        newPhoneE164 = draftTrim;
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

      bool hasLogoAfter;
      if (newLogoUrl != null) {
        hasLogoAfter = true;
      } else if (_logoUrl == '') {
        hasLogoAfter = false;
      } else {
        hasLogoAfter = hadLogoBefore;
      }

      final complete = wasComplete ||
          (desc.length >= 150 &&
              loc.isNotEmpty &&
              hasLogoAfter &&
              hasAnyContact);

      final updates = <String, dynamic>{
        UserFields.description: desc,
        UserFields.location: loc,
        UserFields.isProfileComplete: complete,
      };

      final oldEmail =
          (current[UserFields.contactEmail] ?? '').toString().trim();
      if (email != oldEmail) {
        if (email.isEmpty) {
          updates[UserFields.contactEmail] = FieldValue.delete();
        } else {
          updates[UserFields.contactEmail] = email;
        }
      }

      if (phoneLocal.isEmpty && draftTrim.isEmpty) {
        if (oldPhoneE164.isNotEmpty) {
          updates[UserFields.phone] = FieldValue.delete();
        }
      } else if (newPhoneE164 != null) {
        updates[UserFields.phone] = newPhoneE164;
      }

      if (websiteRaw != oldWebsite) {
        if (websiteRaw.isEmpty) {
          updates[UserFields.website] = FieldValue.delete();
        } else {
          final normalized =
              websiteRaw.startsWith(RegExp(r'https?://', caseSensitive: false))
                  ? websiteRaw
                  : 'https://$websiteRaw';
          updates[UserFields.website] = normalized;
        }
      }

      if (newLogoUrl != null) {
        updates[UserFields.photoUrl] = newLogoUrl;
        if (newLogoPath != null) {
          updates[UserFields.photoPath] = newLogoPath;
        }
        _logoUrl = newLogoUrl;
      } else if (_logoUrl == '') {
        if (!wasComplete || !hasJobs) {
          updates[UserFields.photoUrl] = FieldValue.delete();
          updates[UserFields.photoPath] = FieldValue.delete();
        } else {
          SnackHelper.error(
            uiContext,
            'You cannot remove the logo while you have job posts.',
          );
          return false;
        }
      }

      if (updates.isEmpty) {
        SnackHelper.error(uiContext, 'No changes to save');
        return false;
      }

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

      if (!wasComplete &&
          _logoUrl == '' &&
          (current[UserFields.photoPath]?.toString().isNotEmpty ?? false)) {
        await _deleteStorageFile(current[UserFields.photoPath]?.toString());
      } else if (!wasComplete &&
          _logoUrl == '' &&
          (current[UserFields.photoUrl]?.toString().isNotEmpty ?? false)) {
        await _deleteStorageFile(current[UserFields.photoUrl]?.toString());
      }

      SnackHelper.success(uiContext, 'Profile updated successfully');
      return true;
    } catch (e) {
      SnackHelper.error(uiContext, 'Failed to update profile');
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _progress = null;
          _saving = false;
        });
        progressNotifier.value = null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const ThemedScaffold(body: Center(child: Text('Not signed in')));
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

        final logoUrlLocal = _pendingLogoFile != null
            ? null
            : ((_logoUrl == null || _logoUrl == '')
                    ? data[UserFields.photoUrl]
                    : _logoUrl)
                ?.toString();

        final companyName =
            (data['CompanyName'] ?? data['Name'] ?? 'Company').toString();

        final contactEmail =
            (data[UserFields.contactEmail] ?? '').toString().trim();
        final website = (data[UserFields.website] ?? '').toString().trim();
        final rawPhone = (data[UserFields.phone] ?? '').toString().trim();

        final phoneDigits = rawPhone.replaceAll(RegExp(r'\D'), '');

        final prettyPhone = phoneDigits.length < 6 ? '' : rawPhone;

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
                    if (rawPhone.startsWith('+')) {
                      return rawPhone.replaceFirst(RegExp(r'^\+\d+'), '');
                    }
                    return rawPhone;
                  })();
            _phoneE164Draft ??= rawPhone.isEmpty ? null : rawPhone;

            _websiteCtrl.text = _websiteCtrl.text.isNotEmpty
                ? _websiteCtrl.text
                : (data[UserFields.website] ?? '').toString();

            _filledFromServer = true;
            setState(() {});
          });
        }
        final theme = Theme.of(context);
        final scheme = Theme.of(context).colorScheme;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        const brand = Color(0xFF4A5FBC);

        final chipBg = isDark
            ? scheme.surfaceVariant.withOpacity(0.9)
            : const Color(0xFFEFF2FF);
        final chipTextColor = isDark ? scheme.onSurface : brand;

        return ThemedScaffold(
          appBar: const CustomHeader(
            title: 'Company Profile',
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
                        theme.brightness == Brightness.dark ? 0.25 : 0.05,
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
                    const SizedBox(height: 6),
                    if (website.isNotEmpty)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.link,
                              size: 16, color: Color(0xFF4A5FBC)),
                          const SizedBox(width: 4),
                          Flexible(
                            child: InkWell(
                              onTap: () => _openWebsite(website),
                              child: Text(
                                website,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF4A5FBC),
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 12),
                    if (contactEmail.isNotEmpty || prettyPhone.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: chipBg,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (contactEmail.isNotEmpty)
                              Text(
                                contactEmail,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: chipTextColor,
                                ),
                              ),
                            if (contactEmail.isNotEmpty &&
                                prettyPhone.isNotEmpty)
                              Text(
                                '  |  ',
                                style: TextStyle(
                                  color: chipTextColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            if (prettyPhone.isNotEmpty)
                              Text(
                                prettyPhone,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: chipTextColor,
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
                      color: Colors.black.withOpacity(
                        theme.brightness == Brightness.dark ? 0.25 : 0.05,
                      ),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  border: Border.all(
                      color: const Color(0xFFFD6C67).withOpacity(0.08)),
                ),
                child: _SettingsRow(
                  icon: Icons.info_outline,
                  color: const Color(0xFFFD6C67),
                  title: 'Company Information',
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
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(
                        theme.brightness == Brightness.dark ? 0.25 : 0.05,
                      ),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  border: Border.all(
                      color: const Color(0xFFFD6C67).withOpacity(0.08)),
                ),
                child: _SettingsRow(
                  icon: Icons.mail_outline,
                  color: const Color(0xFFFD6C67),
                  title: 'Contact Information',
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
    final scheme = Theme.of(context).colorScheme;
    final onSurface = scheme.onSurface;

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
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: onSurface.withOpacity(0.7),
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: onSurface.withOpacity(0.4),
            ),
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

    final parent = widget.parentState;
    final data = widget.data;

    final rawPhone = (data[UserFields.phone] ?? '').toString().trim();

    // Description
    if (parent._desc.text.isEmpty) {
      parent._desc.text =
          (data[UserFields.description] ?? '').toString().trim();
    }

    // Location
    if (parent._locCtrl.text.isEmpty) {
      parent._locCtrl.text =
          (data[UserFields.location] ?? '').toString().trim();
    }

    // Email
    if (parent._emailCtrl.text.isEmpty) {
      parent._emailCtrl.text =
          (data[UserFields.contactEmail] ?? '').toString().trim();
    }

    // Phone (controller = local part, draft = full E.164)
    if (rawPhone.startsWith('+')) {
      parent._phone.text = _stripDialCode(rawPhone);
    } else {
      parent._phone.text = rawPhone;
    }

    parent._phoneE164Draft ??= rawPhone.isEmpty ? null : rawPhone;

    // Website
    if (parent._websiteCtrl.text.isEmpty) {
      parent._websiteCtrl.text =
          (data[UserFields.website] ?? '').toString().trim();
    }

    // Logo url
    parent._logoUrl ??= (data[UserFields.photoUrl] ?? '').toString().trim();

    // Mark as filled
    parent._filledFromServer = true;
  }

  String _stripDialCode(String e164) {
    final match = RegExp(r'^\+(\d{1,3})').firstMatch(e164);
    if (match == null) return e164;
    return e164.substring(match.end);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  void _showProfileCompletionInfo() {
    showDialog<void>(
      context: context,
      builder: (ctx) => const JadeerDialog<void>(
        title: 'Profile completion',
        primaryLabel: 'Got it',
        primaryResult: null,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your company profile is marked as complete when:',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            SizedBox(height: 12),
            Text(
              '• A company logo is uploaded\n'
              '• Description is at least 150 characters (max 900)\n'
              '• Location is set\n'
              '• Website is optional but recommended',
              style: TextStyle(
                color: Colors.white,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _hasUnsavedChanges() {
    final parent = widget.parentState;
    final original = widget.data;

    final origWebsite = (original[UserFields.website] ?? '').toString().trim();
    final origDesc = (original[UserFields.description] ?? '').toString().trim();
    final origLoc =
        parent._cleanLoc((original[UserFields.location] ?? '').toString());
    final currLoc = parent._cleanLoc(parent._locCtrl.text);
    final origEmail =
        (original[UserFields.contactEmail] ?? '').toString().trim();
    final origPhone = (original[UserFields.phone] ?? '').toString().trim();
    final origLogoUrl = (original[UserFields.photoUrl] ?? '').toString().trim();

    final currWebsite = parent._websiteCtrl.text.trim();
    final currDesc = parent._desc.text.trim();
    final currEmail = parent._emailCtrl.text.trim();

    final draftE164 = parent._phoneE164Draft?.trim() ?? '';

    bool phoneChanged;
    final initialE164 = origPhone;
    final currentE164 = draftE164;

    if (initialE164.isEmpty && currentE164.isEmpty) {
      phoneChanged = false;
    } else {
      phoneChanged = currentE164 != initialE164;
    }

    final currLogoUrl =
        ((parent._logoUrl ?? original[UserFields.photoUrl]) ?? '')
            .toString()
            .trim();

    bool logoChanged = false;
    if (parent._pendingLogoFile != null) {
      logoChanged = true;
    } else if (currLogoUrl != origLogoUrl) {
      logoChanged = true;
    }

    final websiteChanged = currWebsite != origWebsite;
    final descChanged = currDesc != origDesc;
    final locChanged = currLoc != origLoc;
    final emailChanged = currEmail != origEmail;

    return websiteChanged ||
        descChanged ||
        locChanged ||
        emailChanged ||
        phoneChanged ||
        logoChanged;
  }

  void _resetParentToOriginal() {
    final parent = widget.parentState;
    final data = widget.data;

    final rawPhone = (data[UserFields.phone] ?? '').toString().trim();

    parent.setState(() {
      parent._desc.text =
          (data[UserFields.description] ?? '').toString().trim();
      parent._locCtrl.text =
          (data[UserFields.location] ?? '').toString().trim();
      parent._emailCtrl.text =
          (data[UserFields.contactEmail] ?? '').toString().trim();
      parent._websiteCtrl.text =
          (data[UserFields.website] ?? '').toString().trim();

      if (rawPhone.startsWith('+')) {
        parent._phone.text = _stripDialCode(rawPhone);
      } else {
        parent._phone.text = rawPhone;
      }

      parent._phoneE164Draft = rawPhone.isEmpty ? null : rawPhone;

      parent._pendingLogoFile = null;
      parent._logoUrl = (data[UserFields.photoUrl] ?? '').toString().trim();
    });
  }

  Future<bool?> _showLeaveConfirmDialogStyled(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => const JadeerDialog<bool>(
        title: 'Discard changes?',
        primaryLabel: 'Discard',
        primaryResult: true,
        secondaryLabel: 'Cancel',
        secondaryResult: false,
        content: Text(
          'You have unsaved changes. Are you sure you want to leave without saving?',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Future<bool> _handleWillPop() async {
    if (!_hasUnsavedChanges()) {
      return true;
    }
    final shouldLeave = await _showLeaveConfirmDialogStyled(context);
    if (shouldLeave == true) {
      _resetParentToOriginal();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    const brand = Color(0xFF4A5FBC);
    final parent = widget.parentState;

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return WillPopScope(
      onWillPop: _handleWillPop,
      child: ThemedScaffold(
        body: Container(
          color: isDark ? scheme.background : const Color(0xFFF5F5F5),
          child: Column(
            children: [
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [scheme.primary, scheme.primary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(32),
                    bottomRight: Radius.circular(32),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withOpacity(isDark ? 0.6 : 0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Positioned(
                      top: -50,
                      right: -30,
                      child: Container(
                        width: 150,
                        height: 150,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(
                            isDark ? 0.03 : 0.06,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 10,
                      left: -25,
                      child: Container(
                        width: 110,
                        height: 110,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(
                            isDark ? 0.03 : 0.06,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.only(
                        top: MediaQuery.of(context).padding.top - 16,
                        left: 16,
                        right: 16,
                        bottom: 12,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.arrow_back,
                                  color: Colors.white,
                                ),
                                onPressed: () async {
                                  final shouldPop = await _handleWillPop();
                                  if (shouldPop && mounted) {
                                    Navigator.of(context).pop();
                                  }
                                },
                              ),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(
                                  Icons.info_outline,
                                  color: Colors.white,
                                ),
                                tooltip: 'Profile completion rules',
                                onPressed: _showProfileCompletionInfo,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Edit Company Info',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 10),
                          TabBar(
                            controller: _tabCtrl,
                            indicatorColor: Colors.white,
                            indicatorWeight: 3,
                            dividerColor: Colors.transparent,
                            labelColor: Colors.white,
                            unselectedLabelColor: Colors.white70,
                            tabs: const [
                              Tab(
                                child: Text(
                                  'Company Info',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              Tab(
                                child: Text(
                                  'Contact Info',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              ValueListenableBuilder<double?>(
                valueListenable: parent.progressNotifier,
                builder: (context, progress, _) {
                  if (progress == null) return const SizedBox.shrink();
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LinearProgressIndicator(
                        value: (progress == 0) ? null : progress,
                        minHeight: 4,
                        backgroundColor: Colors.black12,
                        color: Colors.white,
                      ),
                      const SizedBox(height: 8),
                    ],
                  );
                },
              ),

              // main form content
              Expanded(
                child: Form(
                  key: parent._form,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  child: TabBarView(
                    controller: _tabCtrl,
                    children: [
                      // Company Info tab
                      ListView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        children: [
                          const Text(
                            'Logo',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
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
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(24),
                                      ),
                                    ),
                                    onPressed: parent._saving ||
                                            parent._progress != null
                                        ? null
                                        : () async {
                                            await parent._pickLogo();
                                            if (mounted) {
                                              setState(() {});
                                            }
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
                                                  widget.data[
                                                      UserFields.photoUrl])
                                              ?.toString()
                                              .isNotEmpty ==
                                          true))
                                    TextButton(
                                      onPressed: parent._saving ||
                                              parent._progress != null
                                          ? null
                                          : () {
                                              parent.setState(() {
                                                parent._pendingLogoFile = null;
                                                parent._logoUrl = '';
                                              });
                                              if (mounted) {
                                                setState(() {});
                                              }
                                            },
                                      child: const Text(
                                        'Remove logo',
                                        style: TextStyle(color: Colors.red),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Description',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          buildJadeerInputCard(
                            context: context,
                            child: ValueListenableBuilder<TextEditingValue>(
                              valueListenable: parent._desc,
                              builder: (context, value, _) {
                                final text = value.text.trim();
                                final length = text.length;
                                final tooShort = length > 0 && length < 150;

                                return TextFormField(
                                  key: parent._descKey,
                                  focusNode: parent._descFocus,
                                  controller: parent._desc,
                                  maxLines: 10,
                                  maxLength: 900,
                                  keyboardType: TextInputType.multiline,
                                  decoration: InputDecoration(
                                    hintText:
                                        'Describe your company and what you do.',
                                    hintStyle:
                                        const TextStyle(color: Colors.grey),
                                    filled: true,
                                    fillColor: Colors.transparent,
                                    border: const OutlineInputBorder(
                                      borderRadius:
                                          BorderRadius.all(Radius.circular(12)),
                                      borderSide: BorderSide.none,
                                    ),
                                    helperText: tooShort
                                        ? '$length/900 – minimum 150 characters for a complete profile'
                                        : '$length/900',
                                    helperStyle: TextStyle(
                                      fontSize: 12,
                                      color: tooShort
                                          ? const Color(0xFFFC686A)
                                          : Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withOpacity(0.6),
                                    ),
                                  ),
                                  validator: (_) => null,
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Location',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          buildJadeerInputCard(
                            context: context,
                            child: TextFormField(
                              key: parent._locKey,
                              focusNode: parent._locFocus,
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
                                hintStyle: TextStyle(color: Colors.grey),
                                border: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.all(Radius.circular(12)),
                                  borderSide: BorderSide.none,
                                ),
                                filled: true,
                                fillColor: Colors.transparent,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 14,
                                ),
                              ),
                              validator: (v) {
                                final t = parent._cleanLoc(v ?? '');
                                if (t.isEmpty) return null;
                                if (!parent._locAllowed.hasMatch(t)) {
                                  return '2–40 letters only (Arabic/English), no numbers';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),

                      // Contact Info tab
                      ListView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        children: [
                          const Text(
                            'Contact Email',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          buildJadeerInputCard(
                            context: context,
                            child: TextFormField(
                              key: parent._emailKey,
                              focusNode: parent._emailFocus,
                              controller: parent._emailCtrl,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                hintText: 'Enter contact email',
                                hintStyle: TextStyle(color: Colors.grey),
                                helperMaxLines: 2,
                                border: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.all(Radius.circular(12)),
                                  borderSide: BorderSide.none,
                                ),
                                filled: true,
                                fillColor: Colors.transparent,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 14,
                                ),
                                errorStyle: TextStyle(height: 0, fontSize: 0),
                                counterText: '',
                              ),
                              validator: (v) {
                                final t = v?.trim() ?? '';
                                if (t.isEmpty) return null;
                                if (!_email.hasMatch(t)) return 'Invalid email';
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Contact Phone',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          buildJadeerInputCard(
                            context: context,
                            child: IntlPhoneField(
                              key: parent._phoneKey,
                              controller: parent._phone,
                              focusNode: parent._phoneFocus,
                              initialCountryCode: 'SA',
                              pickerDialogStyle: PickerDialogStyle(
                                searchFieldCursorColor: Colors.white,
                                backgroundColor:
                                    const Color(0xFF4A5FBC).withOpacity(0.9),
                                width: MediaQuery.of(context).size.width * 0.9,
                                searchFieldInputDecoration: InputDecoration(
                                  hintText: 'Search country',
                                  hintStyle:
                                      const TextStyle(color: Colors.white),
                                  filled: true,
                                  fillColor: Colors.white.withOpacity(0.2),
                                  prefixIcon: const Icon(
                                    Icons.search,
                                    color: Colors.white,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(18),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                                countryNameStyle: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                                countryCodeStyle: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFFD6C67),
                                ),
                                listTilePadding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                  horizontal: 14,
                                ),
                                listTileDivider: Divider(
                                  color: Colors.white.withOpacity(0.2),
                                ),
                              ),
                              decoration: const InputDecoration(
                                hintText: 'Phone number',
                                hintStyle: TextStyle(color: Colors.grey),
                                border: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.all(Radius.circular(12)),
                                  borderSide: BorderSide.none,
                                ),
                                filled: true,
                                fillColor: Colors.transparent,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 14,
                                ),
                                errorStyle: TextStyle(height: 0, fontSize: 0),
                                counterText: '',
                              ),
                              onChanged: (PhoneNumber phone) {
                                final digits = phone.number.trim();
                                if (digits.isEmpty) {
                                  parent._phoneE164Draft = '';
                                } else {
                                  parent._phoneE164Draft = phone.completeNumber;
                                }
                              },
                              onSaved: (PhoneNumber? phone) {
                                if (phone == null ||
                                    phone.number.trim().isEmpty) {
                                  parent._phoneE164Draft = '';
                                } else {
                                  parent._phoneE164Draft = phone.completeNumber;
                                }
                              },
                              validator: (PhoneNumber? phone) {
                                if (phone == null ||
                                    phone.number.trim().isEmpty) {
                                  return null;
                                }
                                final digits = phone.number.trim();
                                if (!RegExp(r'^[0-9]+$').hasMatch(digits)) {
                                  return 'Digits only';
                                }
                                if (digits.length < 6) {
                                  return 'Enter a valid phone number';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Company Website',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          buildJadeerInputCard(
                            context: context,
                            child: TextFormField(
                              key: parent._websiteKey,
                              focusNode: parent._websiteFocus,
                              controller: parent._websiteCtrl,
                              keyboardType: TextInputType.url,
                              decoration: const InputDecoration(
                                hintText: 'example.com',
                                hintStyle: TextStyle(color: Colors.grey),
                                border: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.all(Radius.circular(12)),
                                  borderSide: BorderSide.none,
                                ),
                                filled: true,
                                fillColor: Colors.transparent,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 14,
                                ),
                                counterText: '',
                                errorStyle: TextStyle(height: 0, fontSize: 0),
                              ),
                              validator: (v) {
                                final t = (v ?? '').trim();
                                if (t.isEmpty) return null;

                                final normalized = t.startsWith(RegExp(
                                        r'https?://',
                                        caseSensitive: false))
                                    ? t
                                    : 'https://$t';

                                if (!parent._urlReg.hasMatch(normalized)) {
                                  return 'Invalid website URL';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
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
}
