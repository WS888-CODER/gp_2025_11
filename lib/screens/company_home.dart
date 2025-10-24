// lib/screens/company_home.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gp_2025_11/screens/company_profile_page.dart';
import 'dart:async';

class CompanyHome extends StatefulWidget {
  const CompanyHome({
    super.key,
    this.companyId,
    this.fallbackCompanyName = 'Company',
  });

  /// uid الخاص بحساب الشركة (يوصل من اللوق إن)
  final String? companyId;

  /// اسم احتياطي لو ما وُجد شي في الداتابيس
  final String fallbackCompanyName;

  @override
  State<CompanyHome> createState() => _CompanyHomeState();
}

class _CompanyHomeState extends State<CompanyHome> {
  static const Color _brand = Color(0xFF4A5FBC);
  int _tab = 1; // 0: Reports, 1: Home

  String get _effectiveCompanyId {
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final fromArgs = (args?['companyId'] ?? '').toString();
    return fromArgs.isNotEmpty ? fromArgs : (widget.companyId ?? '');
  }

  /// Check if profile is complete before allowing job operations
  Future<bool> _checkProfileComplete() async {
    final companyId = _effectiveCompanyId;
    if (companyId.isEmpty) return false;

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(companyId)
          .get();

      if (!userDoc.exists) return false;

      final userData = userDoc.data() as Map<String, dynamic>;
      final isProfileComplete = userData['IsProfileComplete'] ?? false;

      if (!isProfileComplete) {
        if (!mounted) return false;
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text(
              'Profile Incomplete',
              textAlign: TextAlign.center,
            ),
            content: const Text(
              'Please complete your company profile before creating or editing job postings.',
              textAlign: TextAlign.center,
            ),
            contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            actionsPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFF4A5FBC),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return false;
      }

      return true;
    } catch (e) {
      if (!mounted) return false;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Error'),
          content: Text('Failed to verify profile: $e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
      }
    });
  }

  Widget _buildNavItem({
    required IconData icon,
    required IconData filledIcon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer layer for bold outline (coral orange)
          if (isSelected)
            Icon(
              filledIcon,
              size: 34,
              color: const Color(0xFFFC686A),
            ),
          // Middle layer filled icon (light coral)
          if (isSelected)
            Icon(
              filledIcon,
              size: 32,
              color: const Color(0xFFFFDADD),
            ),
          // Foreground outlined icon (coral orange or lighter grey)
          Icon(
            icon,
            size: 32,
            color: isSelected ? const Color(0xFFFC686A) : Colors.grey[400],
          ),
        ],
      ),
    );
  }

  /// اسم الشركة من Firestore (Users/{companyId})
  Stream<String> _companyNameStream(String companyId) {
    if (companyId.isEmpty) return Stream.value(widget.fallbackCompanyName);

    return FirebaseFirestore.instance
        .collection('Users')
        .doc(companyId)
        .snapshots()
        .map((snap) {
      final data = snap.data() ?? {};
      final name = (data['CompanyName'] ?? data['companyName'] ?? '')
          .toString()
          .trim();
      return name.isEmpty ? widget.fallbackCompanyName : name;
    });
  }

  /// وظائف الشركة (Jobs). لو companyId فاضي، نعرض كل الوظائف (للتجربة).
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _jobsStream(
      String companyId) {
    Query<Map<String, dynamic>> q =
        FirebaseFirestore.instance.collection('Jobs');
    if (companyId.isNotEmpty) {
      q = q.where('UserID', isEqualTo: companyId);
    }
    return q.snapshots().map((snap) {
      final docs = snap.docs.toList();
      // ترتيب محلي حسب StartDate (الأحدث أولًا)
      docs.sort((a, b) {
        final sa = a.data()['StartDate'];
        final sb = b.data()['StartDate'];
        final da = sa is Timestamp
            ? sa.toDate()
            : DateTime.fromMillisecondsSinceEpoch(0);
        final db = sb is Timestamp
            ? sb.toDate()
            : DateTime.fromMillisecondsSinceEpoch(0);
        return db.compareTo(da);
      });
      return docs;
    });
  }

  @override
  Widget build(BuildContext context) {
    final companyId = _effectiveCompanyId;

    final homeBody = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // زر Create (يمين)
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8.0, top: 8),
              child: ElevatedButton(
                onPressed: () async {
                  // Check profile completion first
                  final canProceed = await _checkProfileComplete();
                  if (canProceed && mounted) {
                    Navigator.pushNamed(context, '/job-posting');
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _brand,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text(
                  'Create Job Post',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        const _SectionTitle(),

        // قائمة الوظائف
        StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
          stream: _jobsStream(companyId),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snap.hasError) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Error: ${snap.error}'),
              );
            }

            final jobs = snap.data ?? const [];
            if (jobs.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: Text('No job posts yet')),
              );
            }

            return Column(
              children: jobs.map((doc) {
                final data = doc.data();

                final title = (data['JobTitle'] ?? 'Untitled').toString();
                final position = (data['Position'] ?? '').toString();
                final specialty = (data['Specialty'] ?? '').toString();

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(.05),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // نصوص الوظيفة
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              [position, specialty]
                                  .where((e) => e.isNotEmpty)
                                  .join(' • '),
                              style: const TextStyle(color: Colors.black54),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Edit => يفتح صفحة job_posting ببيانات الوظيفة للتحرير
                      OutlinedButton(
                        onPressed: () async {
                          // Check profile completion first
                          final canProceed = await _checkProfileComplete();
                          if (!canProceed || !mounted) return;

                          final desc = data['JobDescription'] ??
                              data['Description'] ??
                              '';
                          final req = data['Requirements'] ??
                              data['Requirments'] ??
                              [];
                          final start = data['StartDate'];
                          final end = data['EndDate'];

                          Navigator.pushNamed(
                            context,
                            '/job-posting',
                            arguments: <String, dynamic>{
                              'jobId': doc.id,
                              'title': title,
                              'position': position,
                              'specialty': specialty,
                              'description': desc,
                              'requirements':
                                  req is List ? req : <String>[],
                              'startDate': start,
                              'endDate': end,
                            },
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: _brand),
                          foregroundColor: _brand,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text('Edit'),
                      ),
                    ],
                  ),
                );
              }).toList(),
            );
          },
        ),

        const SizedBox(height: 12),
      ],
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF7F6FC),
      appBar: AppBar(
        backgroundColor: _brand,
        elevation: 0,
        centerTitle: true,
        // ⬇️ زر الملف الشخصي للشركة
        leadingWidth: 56,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: _ProfileButton(userId: companyId),
        ),
        // العنوان ديناميكي: Welcome, {CompanyName}!
        title: StreamBuilder<String>(
          stream: _companyNameStream(companyId),
          builder: (context, snap) {
            final name = (snap.data ?? widget.fallbackCompanyName).trim();
            return Text(
              'Welcome, $name!',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            );
          },
        ),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            icon: const Icon(Icons.notifications_none, color: Colors.white),
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Notifications – قريبًا')),
            ),
          ),
          // ⬇️ ربط زر الإعدادات بصفحة الإعدادات
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined, color: Colors.white),
            onPressed: () {
              final uid = FirebaseAuth.instance.currentUser?.uid;
              if (uid != null) {
                Navigator.pushNamed(
                  context,
                  '/settings',
                  arguments: {'userType': 'Company', 'userId': uid},
                );
              }
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          Center(
            child: Text(
              'Reports – قريبًا',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          homeBody,
        ],
      ),
      bottomNavigationBar: Container(
        height: 70,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(15),
            topRight: Radius.circular(15),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildNavItem(
              icon: Icons.assessment_outlined,
              filledIcon: Icons.assessment,
              label: 'Reports',
              isSelected: _tab == 0,
              onTap: () => setState(() => _tab = 0),
            ),
            const SizedBox(width: 120),
            _buildNavItem(
              icon: Icons.home_outlined,
              filledIcon: Icons.home,
              label: 'Home',
              isSelected: _tab == 1,
              onTap: () => setState(() => _tab = 1),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text('Job Posts',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Spacer(),
        ],
      ),
    );
  }
}

// ⬇️ زر الملف الشخصي الموحد (يعرض الأحرف الأولى بلون أحمر إذا لم تكن هناك صورة)
class _ProfileButton extends StatelessWidget {
  const _ProfileButton({required this.userId});
  final String userId;

  Stream<Map<String, dynamic>> _userMiniStream() {
    if (userId.isEmpty) {
      return Stream.value({
        'name': 'Company',
        'photo': null,
        'complete': false,
      });
    }
    return FirebaseFirestore.instance
        .collection('Users')
        .doc(userId)
        .snapshots()
        .map((snap) {
      final d = snap.data() ?? {};
      return {
        'name': (d['CompanyName'] ?? '').toString().trim(),
        'photo': (d['PhotoURL'] ?? '').toString().trim(),
        'complete': d['IsProfileComplete'] == true,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: _userMiniStream(),
      builder: (context, snap) {
        final photo = (snap.data?['photo'] ?? '').toString();
        final complete = (snap.data?['complete'] == true);
        final name = (snap.data?['name'] ?? '').toString();

        String initials = '';
        if (name.isNotEmpty) {
          final parts = name.split(' ').where((s) => s.isNotEmpty).toList();
          if (parts.length >= 2) {
            initials = parts[0][0] + parts[1][0];
          } else if (parts.isNotEmpty) {
            initials = name.substring(0, 1);
          }
          initials = initials.toUpperCase();
        }

        final avatar = Hero(
          tag: 'profileAvatar',
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
                child: photo.isEmpty && initials.isNotEmpty
                    ? Text(
                        initials,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      )
                    : null,
                // لون الخلفية الأحمر الموحد
                backgroundColor: const Color(0xFFFF7B7B),
                foregroundColor: Colors.white,
              ),
              Positioned(
                right: -1,
                bottom: -1,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: complete ? Colors.green : Colors.orange,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                ),
              ),
            ],
          ),
        );

        return Tooltip(
          message: complete ? 'Profile complete' : 'Profile incomplete',
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () {
              Navigator.pushNamed(context, '/profile/company');
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: avatar,
            ),
          ),
        );
      },
    );
  }
}