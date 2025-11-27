import 'dart:async';
import 'dart:io';

import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:gp_2025_11/config/theme.dart';
import 'package:gp_2025_11/config/themed_scaffold.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:intl_phone_field/country_picker_dialog.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:intl_phone_field/phone_number.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

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
  static const contactEmail = 'ContactEmail';
}

final _email =
    RegExp(r"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$", caseSensitive: false);

const nationalities = <String>[
  "Saudi",
  "Emirati",
  "Kuwaiti",
  "Qatari",
  "Bahraini",
  "Omani",
  "Egyptian",
  "Jordanian",
  "Lebanese",
  "Syrian",
  "Iraqi",
  "Palestinian",
  "Sudanese",
  "Yemeni",
  "Moroccan",
  "Tunisian",
  "Algerian",
  "Libyan",
  "Somali",
  "Indian",
  "Pakistani",
  "Bangladeshi",
  "Filipino",
  "Indonesian",
  "Malaysian",
  "Singaporean",
  "Turkish",
  "Chinese",
  "Japanese",
  "Korean",
  "Thai",
  "Vietnamese",
  "Cambodian",
  "Laotian",
  "Afghan",
  "Nepalese",
  "Sri Lankan",
  "British",
  "Irish",
  "French",
  "German",
  "Italian",
  "Spanish",
  "Portuguese",
  "Dutch",
  "Belgian",
  "Swiss",
  "Swedish",
  "Norwegian",
  "Finnish",
  "Danish",
  "Austrian",
  "Greek",
  "Romanian",
  "Bulgarian",
  "Polish",
  "Czech",
  "Slovak",
  "Hungarian",
  "Ukrainian",
  "Russian",
  "American",
  "Canadian",
  "Mexican",
  "Brazilian",
  "Argentinian",
  "Colombian",
  "Chilean",
  "Peruvian",
  "Venezuelan",
  "Nigerian",
  "Ethiopian",
  "Kenyan",
  "Ghanaian",
  "Rwandan",
  "South African",
  "Australian",
  "New Zealander",
];

const nationalityFlags = {
  "Saudi": "🇸🇦",
  "Emirati": "🇦🇪",
  "Kuwaiti": "🇰🇼",
  "Qatari": "🇶🇦",
  "Bahraini": "🇧🇭",
  "Omani": "🇴🇲",
  "Egyptian": "🇪🇬",
  "Jordanian": "🇯🇴",
  "Lebanese": "🇱🇧",
  "Syrian": "🇸🇾",
  "Iraqi": "🇮🇶",
  "Palestinian": "🇵🇸",
  "Sudanese": "🇸🇩",
  "Moroccan": "🇲🇦",
  "Tunisian": "🇹🇳",
  "Algerian": "🇩🇿",
  "Somali": "🇸🇴",
  "American": "🇺🇸",
  "Canadian": "🇨🇦",
  "British": "🇬🇧",
  "French": "🇫🇷",
  "German": "🇩🇪",
  "Italian": "🇮🇹",
  "Spanish": "🇪🇸",
  "Chinese": "🇨🇳",
  "Indian": "🇮🇳",
  "Pakistani": "🇵🇰",
  "Bangladeshi": "🇧🇩",
  "Filipino": "🇵🇭",
  "Japanese": "🇯🇵",
  "Korean": "🇰🇷",
  "Turkish": "🇹🇷",
  "Russian": "🇷🇺",
  "South African": "🇿🇦",
  "Australian": "🇦🇺",
  "New Zealander": "🇳🇿",
};

class JobSeekerProfile extends StatelessWidget {
  const JobSeekerProfile({super.key});

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
        final dobCurrent = data[UserFields.dob] is Timestamp
            ? (data[UserFields.dob] as Timestamp).toDate()
            : null;

        final cvUrl = (data[UserFields.cvUrl] ?? '').toString().trim();
        final photoUrl = (data[UserFields.photoUrl] ?? '').toString().trim();

        final phoneValid = phoneE164.isNotEmpty;
        final natOk = nationality.isNotEmpty;
        final dobOk = dobCurrent != null;
        final cvOk = cvUrl.isNotEmpty;
        final photoOk = photoUrl.isNotEmpty;

        final contactEmail =
            (data[UserFields.contactEmail] ?? '').toString().trim();
        final emailValid =
            contactEmail.isNotEmpty && _email.hasMatch(contactEmail);
        final contactPhoneLabel = phoneValid ? phoneE164 : '';
        final hasAnyContact = emailValid || phoneValid;
        final profileComplete = data[UserFields.isProfileComplete] == true ||
            (cvOk && photoOk && dobOk && natOk && (emailValid || phoneValid));

        final nationalityValue = natOk ? nationality : 'Not set';
        final dobValue =
            dobOk ? DateFormat('yyyy/MM/dd').format(dobCurrent!) : 'Not set';

        final photoSource = photoUrl;

        final scheme = Theme.of(context).colorScheme;
        const brand = Color(0xFF4A5FBC);
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final chipBg = isDark
            ? scheme.surfaceVariant.withOpacity(0.9)
            : const Color(0xFFEFF2FF);
        final chipTextColor = isDark ? scheme.onSurface : brand;

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
                          if (nationalityValue != 'Not set') ...[
                            Text(
                              nationalityFlags[nationalityValue] ?? '',
                              style: const TextStyle(fontSize: 20),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Flexible(
                            child: Text(
                              [
                                if (nationalityValue != 'Not set')
                                  nationalityValue,
                                if (dobValue != 'Not set') dobValue,
                              ].join(' • '),
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? scheme.onSurface : brand,
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 10),
                    if (cvOk) ...[
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.description_outlined,
                            size: 16,
                            color: brand,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'CV uploaded',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: brand,
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.description_outlined,
                            size: 16,
                            color: Colors.grey,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'CV not uploaded',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (hasAnyContact)
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
                            if (emailValid)
                              Text(
                                contactEmail,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: chipTextColor,
                                ),
                              ),
                            if (emailValid && phoneValid)
                              Text(
                                '  |  ',
                                style: TextStyle(
                                  color: chipTextColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            if (phoneValid)
                              Text(
                                contactPhoneLabel,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: chipTextColor,
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
                    color: const Color(0xFFFD6C67).withOpacity(0.08),
                  ),
                ),
                child: _SettingsRowSeeker(
                  icon: Icons.person_outline,
                  color: const Color(0xFFFD6C67),
                  title: 'Profile Information',
                  subtitle: 'Photo, nationality, date of birth, and CV',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => EditJobSeekerPage(
                          data: data,
                          initialTab: 0,
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
                        Theme.of(context).brightness == Brightness.dark
                            ? 0.12
                            : 0.04,
                      ),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  border: Border.all(
                    color: const Color(0xFFFD6C67).withOpacity(0.08),
                  ),
                ),
                child: _SettingsRowSeeker(
                  icon: Icons.mail_outline,
                  color: const Color(0xFFFD6C67),
                  title: 'Contact Information',
                  subtitle: 'Email and phone number',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => EditJobSeekerPage(
                          data: data,
                          initialTab: 1,
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
    final onSurface = Theme.of(context).colorScheme.onSurface;
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
                      color: onSurface.withOpacity(0.7),
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
            ),
          ],
        ),
      ),
    );
  }
}

class EditJobSeekerPage extends StatefulWidget {
  final Map<String, dynamic> data;
  final int initialTab;

  const EditJobSeekerPage({
    super.key,
    required this.data,
    this.initialTab = 0,
  });

  @override
  State<EditJobSeekerPage> createState() => _EditJobSeekerPageState();
}

class _EditJobSeekerPageState extends State<EditJobSeekerPage>
    with SingleTickerProviderStateMixin {
  final _phoneKey = GlobalKey<FormFieldState>();
  final _phoneFocus = FocusNode();

  final _emailKey = GlobalKey<FormFieldState>();
  final _emailFocus = FocusNode();
  final _phoneCtrl = TextEditingController();

  String _convertCountryToNationality(String country) {
    final map = {
      "Saudi Arabia": "Saudi",
      "United Arab Emirates": "Emirati",
      "Qatar": "Qatari",
      "Kuwait": "Kuwaiti",
      "Bahrain": "Bahraini",
      "Oman": "Omani",
      "United States": "American",
      "United Kingdom": "British",
      "France": "French",
      "Italy": "Italian",
      "Spain": "Spanish",
      "Germany": "German",
      "Netherlands": "Dutch",
      "Sweden": "Swedish",
      "Switzerland": "Swiss",
      "India": "Indian",
      "Pakistan": "Pakistani",
      "Bangladesh": "Bangladeshi",
      "Philippines": "Filipino",
      "China": "Chinese",
      "Japan": "Japanese",
      "South Korea": "Korean",
      "Russia": "Russian",
      "Turkey": "Turkish",
      "Egypt": "Egyptian",
      "Sudan": "Sudanese",
      "Morocco": "Moroccan",
      "Tunisia": "Tunisian",
      "Algeria": "Algerian",
      "Nigeria": "Nigerian",
      "Ethiopia": "Ethiopian",
      "South Africa": "South African",
    };

    return map[country] ?? country;
  }

  Country? _selectedCountry;
  final _form = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();

  String? _nationality;
  DateTime? _dob;

  File? _pendingPhotoFile;
  File? _pendingCvFile;

  String? _photoUrl;
  String? _cvUrl;

  String? _phoneE164Draft;
  late final String _originalPhoneE164;

  bool _saving = false;
  double? _progress;
  StreamSubscription<TaskSnapshot>? _uploadSub;

  static const int _kMaxImageBytes = 5 * 1024 * 1024;
  static const int _kMaxCvBytes = 10 * 1024 * 1024;

  late TabController _tabController;

  void _showProfileRequirements() {
    showDialog(
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
              'Your profile is marked as complete when:',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            SizedBox(height: 12),
            Text(
              '• A profile photo is uploaded\n'
              '• Date of birth is set\n'
              '• Nationality is set\n'
              '• A CV file is uploaded',
              style: TextStyle(
                color: Colors.white,
                height: 1.4,
              ),
            ),
            SizedBox(height: 12),
            Text(
              'And at least one contact method:',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            SizedBox(height: 6),
            Text(
              '• A valid contact email, or\n'
              '• A valid phone number with country code',
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

  @override
  void initState() {
    super.initState();

    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab,
    );
    final data = widget.data;

    _originalPhoneE164 = (data[UserFields.phone] ?? '').toString().trim();
    final phoneE164 = _originalPhoneE164;

    if (phoneE164.startsWith('+966') && phoneE164.length > 4) {
      _phoneCtrl.text = phoneE164.substring(4);
    }
    _phoneE164Draft = phoneE164.isEmpty ? null : phoneE164;

    _emailCtrl.text = (data[UserFields.contactEmail] ?? '').toString().trim();

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
    _tabController.dispose();
    _uploadSub?.cancel();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _phoneFocus.dispose();
    _emailFocus.dispose();
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

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CvPdfViewerScreen(pdfUrl: url),
      ),
    );
  }

  Future<void> _save() async {
    final formValid = _form.currentState?.validate() ?? false;

    final email = _emailCtrl.text.trim();
    final hasPhoneDigits = _phoneCtrl.text.trim().isNotEmpty;

    if (!formValid) {
      final emailInvalid = email.isNotEmpty && !_email.hasMatch(email);

      if (emailInvalid) {
        _emailKey.currentState?.validate();
        FocusScope.of(context).requestFocus(_emailFocus);
        SnackHelper.error(context, 'Enter a valid email address');
        return;
      }

      if (hasPhoneDigits) {
        FocusScope.of(context).requestFocus(_phoneFocus);
        SnackHelper.error(
            context, 'Enter a valid phone number with country code');
        return;
      }

      SnackHelper.error(context, 'Please check your contact information');
      return;
    }

    if (_progress != null) {
      SnackHelper.error(context, 'Please wait for uploads to finish');
      return;
    }

    _form.currentState?.save();

    final current = widget.data;

    final emailValid = email.isNotEmpty && _email.hasMatch(email);

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

    final currentEmail =
        (current[UserFields.contactEmail] ?? '').toString().trim();
    if (!emailValid && email.isNotEmpty) {
      SnackHelper.error(context, 'Enter a valid email address');
      return;
    }
    if (email.isEmpty && currentEmail.isNotEmpty) {
      updates[UserFields.contactEmail] = FieldValue.delete();
    } else if (email.isNotEmpty && email != currentEmail) {
      updates[UserFields.contactEmail] = email;
    }

    final currentPhone = (current[UserFields.phone] ?? '').toString().trim();
    final draft = (_phoneE164Draft ?? '').trim();
    final hasDigits = hasPhoneDigits;

    String? newPhoneE164;
    if (draft.isNotEmpty && draft != currentPhone) {
      newPhoneE164 = draft;
    }

    if (!hasDigits) {
      if (currentPhone.isNotEmpty) {
        updates[UserFields.phone] = FieldValue.delete();
      }
    } else if (newPhoneE164 != null) {
      updates[UserFields.phone] = newPhoneE164;
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

    final mergedPhone = (next[UserFields.phone] ?? '').toString().trim();
    final mergedEmail = (next[UserFields.contactEmail] ?? '').toString().trim();
    final mergedEmailValid =
        mergedEmail.isNotEmpty && _email.hasMatch(mergedEmail);
    final phoneOk = mergedPhone.isNotEmpty;

    final complete =
        cvOk && photoOk && dobOk && natOk && (mergedEmailValid || phoneOk);
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
    bool hasUnsavedChanges() {
      final current = widget.data;

      final origEmail =
          (current[UserFields.contactEmail] ?? '').toString().trim();
      final origNat = (current[UserFields.nationality] ?? '').toString().trim();

      DateTime? origDob;
      if (current[UserFields.dob] is Timestamp) {
        final d = (current[UserFields.dob] as Timestamp).toDate();
        origDob = DateTime(d.year, d.month, d.day);
      }

      final origPhotoUrl =
          (current[UserFields.photoUrl] ?? '').toString().trim();
      final origCvUrl = (current[UserFields.cvUrl] ?? '').toString().trim();

      final uiEmail = _emailCtrl.text.trim();
      final uiNat = (_nationality ?? '').trim();

      DateTime? uiDob = _dob;
      if (uiDob != null) {
        uiDob = DateTime(uiDob.year, uiDob.month, uiDob.day);
      }

      final emailChanged = uiEmail != origEmail;
      final natChanged = uiNat != origNat;

      bool dobChanged;
      if (origDob == null && uiDob == null) {
        dobChanged = false;
      } else if (origDob == null || uiDob == null) {
        dobChanged = true;
      } else {
        dobChanged = uiDob != origDob;
      }

      final photoChanged =
          _pendingPhotoFile != null || (_photoUrl ?? '').trim() != origPhotoUrl;
      final cvChanged =
          _pendingCvFile != null || (_cvUrl ?? '').trim() != origCvUrl;

      final draftPhone = _phoneE164Draft?.trim() ?? '';
      final phoneChanged = draftPhone != _originalPhoneE164;

      return emailChanged ||
          natChanged ||
          dobChanged ||
          photoChanged ||
          cvChanged ||
          phoneChanged;
    }

    Future<bool> onWillPop() async {
      if (!hasUnsavedChanges()) {
        return true;
      }

      final shouldLeave = await showDialog<bool>(
        context: context,
        builder: (ctx) => const JadeerDialog<bool>(
          title: 'Discard changes?',
          content: Text(
            'You have unsaved changes. Are you sure you want to leave without saving?',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
            ),
          ),
          secondaryLabel: 'Stay',
          secondaryResult: false,
          primaryLabel: 'Leave',
          primaryResult: true,
        ),
      );

      return shouldLeave == true;
    }

    const brand = Color(0xFF4A5FBC);
    final dobText = _dob == null
        ? ((_dobFromData() == null)
            ? 'Select date'
            : DateFormat('yyyy/MM/dd').format(_dobFromData()!))
        : DateFormat('yyyy/MM/dd').format(_dob!);

    final hasCV = _pendingCvFile != null || ((_cvUrl ?? '').isNotEmpty);
    final hasPhoto =
        _pendingPhotoFile != null || ((_photoUrl ?? '').isNotEmpty);

    return WillPopScope(
      onWillPop: onWillPop,
      child: ThemedScaffold(
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
            onPressed: () async {
              final shouldPop = await onWillPop();
              if (shouldPop && mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.info_outline, color: Colors.white),
              tooltip: 'Profile requirements',
              onPressed: _showProfileRequirements,
            ),
          ],
        ),
        body: Column(
          children: [
            if (_progress != null)
              LinearProgressIndicator(
                value: (_progress ?? 0) == 0 ? null : _progress,
                minHeight: 4,
                backgroundColor: Colors.black12,
                color: brand,
              ),
            if (_progress != null) const SizedBox(height: 8),
            Container(
              color: brand,
              child: TabBar(
                controller: _tabController,
                indicatorColor: Colors.white,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                tabs: const [
                  Tab(
                    child: Text(
                      'Profile Info',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Tab(
                    child: Text(
                      'Contact Info',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Form(
                key: _form,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    ListView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      children: [
                        const Text(
                          'Profile Photo',
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
                                backgroundImage: _pendingPhotoFile != null
                                    ? FileImage(_pendingPhotoFile!)
                                        as ImageProvider
                                    : ((_photoUrl ?? '').isNotEmpty
                                        ? NetworkImage(_photoUrl!)
                                        : null),
                                child: (_pendingPhotoFile == null &&
                                        (_photoUrl ?? '').isEmpty)
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
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                  ),
                                  onPressed: (_saving || _progress != null)
                                      ? null
                                      : _pickPhoto,
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
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        buildJadeerInputCard(
                          context: context,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: (_saving || _progress != null)
                                ? null
                                : () async {
                                    final now = DateTime.now();
                                    final initial = _dob ??
                                        _dobFromData() ??
                                        DateTime(
                                          now.year - 20,
                                          now.month,
                                          now.day,
                                        );
                                    final first = DateTime(now.year - 80, 1, 1);
                                    final last = DateTime(
                                      now.year - 18,
                                      now.month,
                                      now.day,
                                    );
                                    final picked = await showDatePicker(
                                      context: context,
                                      initialDate: initial,
                                      firstDate: first,
                                      lastDate: last,
                                      builder: (context, child) {
                                        final theme = Theme.of(context);
                                        final scheme = theme.colorScheme;

                                        return Theme(
                                          data: theme.copyWith(
                                            colorScheme: scheme.copyWith(
                                              primary: const Color(0xFFFC686A),
                                              onPrimary: Colors.white,
                                              onSurface: Colors.white,
                                              surface: const Color(0xFF4A5FBC)
                                                  .withOpacity(0.95),
                                            ),
                                            textTheme: theme.textTheme.copyWith(
                                              bodyLarge: const TextStyle(
                                                  color: Colors.white),
                                              bodyMedium: const TextStyle(
                                                  color: Colors.white),
                                              headlineMedium: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                              ),
                                              titleLarge: const TextStyle(
                                                  color: Colors.white),
                                            ),
                                            inputDecorationTheme:
                                                InputDecorationTheme(
                                              labelStyle: const TextStyle(
                                                  color: Colors.white),
                                              hintStyle: TextStyle(
                                                  color: Colors.white
                                                      .withOpacity(0.7)),
                                              enabledBorder:
                                                  const UnderlineInputBorder(
                                                borderSide: BorderSide(
                                                    color: Colors.white),
                                              ),
                                            ),
                                            textButtonTheme:
                                                TextButtonThemeData(
                                              style: TextButton.styleFrom(
                                                foregroundColor:
                                                    const Color(0xFFFC686A),
                                              ),
                                            ),
                                            datePickerTheme:
                                                DatePickerThemeData(
                                              backgroundColor:
                                                  const Color(0xFF4A5FBC)
                                                      .withOpacity(0.95),
                                              headerForegroundColor:
                                                  Colors.white,
                                              weekdayStyle: const TextStyle(
                                                  color: Colors.white),
                                              yearStyle: const TextStyle(
                                                  color: Colors.white),
                                              dayStyle: const TextStyle(
                                                  color: Colors.white),
                                              yearForegroundColor:
                                                  MaterialStateColor
                                                      .resolveWith((states) {
                                                if (states.contains(
                                                    MaterialState.selected)) {
                                                  return Colors.white;
                                                }
                                                return Colors.white;
                                              }),
                                              yearBackgroundColor:
                                                  MaterialStateColor
                                                      .resolveWith((states) {
                                                if (states.contains(
                                                    MaterialState.selected)) {
                                                  return const Color(
                                                      0xFFFC686A);
                                                }
                                                return Colors.transparent;
                                              }),
                                              dayForegroundColor:
                                                  MaterialStateColor
                                                      .resolveWith((states) {
                                                if (states.contains(
                                                    MaterialState.selected)) {
                                                  return Colors.white;
                                                }
                                                if (states.contains(
                                                    MaterialState.disabled)) {
                                                  return Colors.white
                                                      .withOpacity(0.3);
                                                }
                                                return Colors.white;
                                              }),
                                              todayBorder: BorderSide.none,
                                              todayBackgroundColor:
                                                  MaterialStateColor
                                                      .resolveWith((states) {
                                                if (states.contains(
                                                    MaterialState.selected)) {
                                                  return const Color(
                                                      0xFFFC686A);
                                                }
                                                return const Color(0xFFFC686A)
                                                    .withOpacity(0.15);
                                              }),
                                              todayForegroundColor:
                                                  MaterialStateColor
                                                      .resolveWith((states) {
                                                if (states.contains(
                                                    MaterialState.selected)) {
                                                  return Colors.white;
                                                }
                                                return Colors.white;
                                              }),
                                            ),
                                          ),
                                          child: child!,
                                        );
                                      },
                                    );
                                    if (picked != null) {
                                      setState(() => _dob = picked);
                                    }
                                  },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 14,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    dobText,
                                    style: TextStyle(
                                      color: dobText == 'Select date'
                                          ? Colors.grey
                                          : Theme.of(context)
                                              .colorScheme
                                              .onSurface,
                                    ),
                                  ),
                                  const Icon(
                                    Icons.calendar_today_outlined,
                                    size: 18,
                                    color: Color(0xFFFD6C67),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Nationality',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () {
                            showCountryPicker(
                              context: context,
                              showPhoneCode: false,
                              countryListTheme: CountryListThemeData(
                                bottomSheetHeight:
                                    MediaQuery.of(context).size.height * 0.45,
                                backgroundColor:
                                    const Color(0xFF4A5FBC).withOpacity(0.95),
                                borderRadius: BorderRadius.circular(24),
                                flagSize: 20,
                                textStyle: const TextStyle(
                                  fontSize: 18,
                                  color: Colors.white,
                                ),
                                inputDecoration: InputDecoration(
                                  hintText: 'Search country',
                                  hintStyle:
                                      const TextStyle(color: Colors.white70),
                                  filled: true,
                                  fillColor: Colors.white.withOpacity(0.1),
                                  prefixIcon: const Icon(Icons.search,
                                      color: Colors.white),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(18),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                              onSelect: (Country country) {
                                setState(() {
                                  _selectedCountry = country;
                                  _nationality = _convertCountryToNationality(
                                      country.name);
                                });
                              },
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 14, horizontal: 12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    if (_selectedCountry != null) ...[
                                      Text(
                                        _selectedCountry!.flagEmoji,
                                        style: const TextStyle(fontSize: 20),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    Text(
                                      _nationality ?? 'Select nationality',
                                      style: const TextStyle(fontSize: 16),
                                    ),
                                  ],
                                ),
                                const Icon(Icons.arrow_drop_down,
                                    color: Color(0xFFFD6C67)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                        const Text(
                          'CV File',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.06),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                            border: Border.all(
                              color: AppTheme.primaryPurple.withOpacity(0.08),
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color:
                                      AppTheme.primaryPurple.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Iconsax.document_text,
                                  size: 40,
                                  color: AppTheme.primaryPurple,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                hasCV ? 'CV (PDF)' : 'No CV uploaded',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primaryPurple,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                hasCV
                                    ? 'Your CV is saved to your profile and ready to use.'
                                    : 'Upload your CV to get more accurate job recommendations.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 16),
                              if (hasCV) ...[
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 140,
                                      child: ElevatedButton.icon(
                                        onPressed:
                                            (_saving || _progress != null)
                                                ? null
                                                : _openCv,
                                        style: FilledButton.styleFrom(
                                          backgroundColor:
                                              AppTheme.primaryPurple,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 12,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(24),
                                          ),
                                        ),
                                        icon: const Icon(Iconsax.eye, size: 20),
                                        label: const Text('View'),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    SizedBox(
                                      width: 140,
                                      child: ElevatedButton.icon(
                                        onPressed:
                                            (_saving || _progress != null)
                                                ? null
                                                : _pickCV,
                                        style: FilledButton.styleFrom(
                                          backgroundColor:
                                              const Color(0xFFFD6C67),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 12,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(24),
                                          ),
                                        ),
                                        icon: const Icon(
                                            Iconsax.document_upload,
                                            size: 20),
                                        label: const Text('Replace'),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
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
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ] else ...[
                                SizedBox(
                                  width: 160,
                                  child: ElevatedButton.icon(
                                    onPressed: (_saving || _progress != null)
                                        ? null
                                        : _pickCV,
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
                                    icon: const Icon(Iconsax.document_upload,
                                        size: 20),
                                    label: const Text('Upload CV'),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    ListView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      children: [
                        const Text(
                          'Email',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        buildJadeerInputCard(
                          context: context,
                          child: TextFormField(
                            key: _emailKey,
                            focusNode: _emailFocus,
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              hintText: 'Enter contact email',
                              hintStyle: TextStyle(color: Colors.grey),
                              filled: true,
                              fillColor: Colors.transparent,
                              border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.all(Radius.circular(12)),
                                borderSide: BorderSide.none,
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
                          'Phone',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        buildJadeerInputCard(
                            context: context,
                            child: IntlPhoneField(
                              key: _phoneKey,
                              controller: _phoneCtrl,
                              focusNode: _phoneFocus,
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
                                  prefixIcon: const Icon(Icons.search,
                                      color: Colors.white),
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
                                    vertical: 4, horizontal: 14),
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
                                if (phone.number.trim().isEmpty) {
                                  _phoneE164Draft = '';
                                } else {
                                  _phoneE164Draft =
                                      phone.completeNumber; // مثل +9665...
                                }
                              },
                              onSaved: (PhoneNumber? phone) {
                                if (phone == null ||
                                    phone.number.trim().isEmpty) {
                                  _phoneE164Draft = '';
                                } else {
                                  _phoneE164Draft = phone.completeNumber;
                                }
                              },
                              validator: (PhoneNumber? phone) {
                                if (phone == null ||
                                    phone.number.trim().isEmpty) {
                                  return null;
                                }
                                if (!RegExp(r'^[0-9]+$')
                                    .hasMatch(phone.number.trim())) {
                                  return 'Digits only';
                                }
                                if (phone.number.trim().length < 6) {
                                  return 'Enter a valid phone number';
                                }
                                return null;
                              },
                            )),
                        const SizedBox(height: 120),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
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
      ),
    );
  }

  DateTime? _dobFromData() {
    final d = widget.data[UserFields.dob];
    if (d is Timestamp) return d.toDate();
    return null;
  }
}

Widget buildJadeerInputCard({
  required BuildContext context,
  required Widget child,
}) {
  final scheme = Theme.of(context).colorScheme;

  return Container(
    decoration: BoxDecoration(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.08),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: child,
  );
}

class CvPdfViewerScreen extends StatelessWidget {
  final String pdfUrl;

  const CvPdfViewerScreen({super.key, required this.pdfUrl});

  @override
  Widget build(BuildContext context) {
    return ThemedScaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.primaryPurple,
        foregroundColor: Colors.white,
        title: const Text(
          'CV',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
      body: SfPdfViewer.network(
        pdfUrl,
        canShowScrollHead: true,
        canShowScrollStatus: true,
        enableDoubleTapZooming: true,
      ),
    );
  }
}
