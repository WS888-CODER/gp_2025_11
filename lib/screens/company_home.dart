// lib/screens/company_home.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gp_2025_11/config/themed_scaffold.dart';
import 'package:gp_2025_11/screens/company_profile.dart';
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
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

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
            backgroundColor: const Color(0xFF4A5FBC).withOpacity(0.7),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            title: const Text(
              'Profile Incomplete',
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            content: const Text(
              'Please complete your company profile before creating or editing job postings.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white),
            ),
            contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            actionsPadding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.9),
                  foregroundColor: const Color(0xFF4A5FBC),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text('OK',
                    style: TextStyle(fontWeight: FontWeight.bold)),
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

  /// Close or reopen a job
  Future<void> _closeJob(String jobId, bool isClosed, BuildContext ctx) async {
    try {
      await FirebaseFirestore.instance.collection('Jobs').doc(jobId).update({
        'JobStatus': isClosed ? 'Open' : 'Closed',
      });

      // Check mounted after async operation
      if (!mounted) return;

      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text(
            isClosed ? 'Job reopened successfully' : 'Job closed successfully',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          backgroundColor: const Color(0xFF4CAF50).withOpacity(0.8),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text(
            'Error: $e',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          backgroundColor: const Color(0xFFFF7B7B).withOpacity(0.8),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  /// Delete a job with confirmation
  Future<void> _deleteJob(
      String jobId, String jobTitle, BuildContext ctx) async {
    if (!mounted) return;

    final shouldDelete = await showDialog<bool>(
      context: ctx,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF4A5FBC).withOpacity(0.7),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        title: const Text(
          'Delete Job?',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to permanently delete "$jobTitle"? This action cannot be undone.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white),
        ),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        actionsPadding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
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
            child: const Text('Cancel',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xFFFC686A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: const Text('Delete',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    // Check mounted after dialog closes
    if (!mounted) return;

    if (shouldDelete == true) {
      try {
        await FirebaseFirestore.instance.collection('Jobs').doc(jobId).delete();

        // Check mounted after async operation
        if (!mounted) return;

        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: const Text(
              'Job deleted successfully',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            backgroundColor: const Color(0xFF4CAF50).withOpacity(0.8),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      } catch (e) {
        if (!mounted) return;

        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text(
              'Error: $e',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            backgroundColor: const Color(0xFFFF7B7B).withOpacity(0.8),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
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
            color: isSelected
                ? const Color(0xFFFC686A)
                : Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.color, // Use theme color for better dark mode support
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
      final name =
          (data['CompanyName'] ?? data['companyName'] ?? '').toString().trim();
      return name.isEmpty ? widget.fallbackCompanyName : name;
    });
  }

  /// وظائف الشركة (Jobs).
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _jobsStream(
      String companyId) {
    try {
      Query<Map<String, dynamic>> q =
          FirebaseFirestore.instance.collection('Jobs');
      if (companyId.isNotEmpty) {
        q = q.where('UserID', isEqualTo: companyId);
      }
      return q.snapshots().map((snap) {
        final docs = snap.docs.toList();
        final now = DateTime.now();

        // Auto-close expired jobs only (no auto-reopening)
        for (final doc in docs) {
          final data = doc.data();
          final endDateField = data['EndDate'];
          final currentStatus = data['JobStatus'] ?? 'Open';

          if (endDateField is Timestamp) {
            final endDate = endDateField.toDate();

            // If job is past end date and still Open, close it automatically
            if (endDate.isBefore(now) && currentStatus == 'Open') {
              FirebaseFirestore.instance
                  .collection('Jobs')
                  .doc(doc.id)
                  .update({'JobStatus': 'Closed'});
            }
            // Note: We don't auto-reopen closed jobs, even if date is extended
            // Company can manually reopen using "Reopen Job" option
          }
        }

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
    } catch (e) {
      // الحل الدفاعي لخطأ 'is not a subtype of JavaScriptObject' على الويب
      print("Error in _jobsStream: $e");
      return Stream.error(e);
    }
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
                final jobStatus = (data['JobStatus'] ?? 'Open').toString();
                final isClosed = jobStatus == 'Closed';

                // ⬇️ تحديد لون الخلفية الديناميكي للعنصر
                final cardBackgroundColor = isClosed
                    ? Theme.of(context).colorScheme.surface.withOpacity(0.5)
                    : Theme.of(context).colorScheme.surface;

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  // ⬇️ تم وضع اللون الآن داخل BoxDecoration (لحظ التضارب)
                  decoration: BoxDecoration(
                    color: cardBackgroundColor,
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
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                // ⬇️ ألوان النصوص تصبح ديناميكية وتتبع الثيم
                                color: isClosed
                                    ? Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.color
                                        ?.withOpacity(0.7)
                                    : Theme.of(context)
                                        .textTheme
                                        .bodyLarge
                                        ?.color,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              [position, specialty]
                                  .where((e) => e.isNotEmpty)
                                  .join(' • '),
                              style: TextStyle(
                                color: isClosed
                                    ? Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.color
                                        ?.withOpacity(0.7)
                                    : Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.color
                                        ?.withOpacity(0.7),
                              ),
                            ),
                            // Closed badge at bottom left
                            if (isClosed)
                              Container(
                                margin: const EdgeInsets.only(top: 8),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .error
                                      .withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'Closed',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Edit button
                      OutlinedButton(
                        onPressed: () async {
                          // Check profile completion first
                          final canProceed = await _checkProfileComplete();
                          if (!canProceed || !mounted) return;

                          final desc = data['JobDescription'] ??
                              data['Description'] ??
                              '';
                          final req =
                              data['Requirements'] ?? data['Requirments'] ?? [];
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
                              'requirements': req is List ? req : <String>[],
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

                      // More options menu (using IconButton + Dialog)
                      IconButton(
                        icon: Icon(Icons.more_vert,
                            color:
                                Theme.of(context).textTheme.bodyLarge?.color),
                        onPressed: () {
                          final safeCtx = _scaffoldKey.currentContext;
                          if (safeCtx == null) return;

                          showDialog(
                            context: safeCtx,
                            // ⬇️ الآن يعتمد على لون السطح الديناميكي
                            builder: (dialogContext) => AlertDialog(
                              backgroundColor:
                                  Theme.of(context).colorScheme.surface,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 10),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Close/Reopen Option
                                  ListTile(
                                    leading: Icon(
                                      isClosed
                                          ? Icons.lock_open_outlined
                                          : Icons.lock_outline,
                                      color: isClosed
                                          ? Colors.green
                                          : Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.color, // ديناميكي
                                      size: 20,
                                    ),
                                    title: Text(
                                      isClosed ? 'Reopen Job' : 'Close Job',
                                      style: TextStyle(
                                        color: isClosed
                                            ? Colors.green
                                            : Theme.of(context)
                                                .textTheme
                                                .bodyLarge
                                                ?.color, // ديناميكي
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    onTap: () {
                                      Navigator.pop(dialogContext);
                                      _closeJob(doc.id, isClosed, safeCtx);
                                    },
                                  ),
                                  // Delete Option
                                  ListTile(
                                    leading: const Icon(
                                      Icons.delete_outline,
                                      color: Color(0xFFFF7B7B),
                                      size: 20,
                                    ),
                                    title: const Text(
                                      'Delete Job',
                                      style: TextStyle(
                                        color: Color(0xFFFF7B7B),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    onTap: () {
                                      Navigator.pop(dialogContext);
                                      _deleteJob(doc.id, title, safeCtx);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
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

    return ThemedScaffold(
      key: _scaffoldKey,
      // ⬇️ تم حذف: backgroundColor: const Color(0xFFF7F6FC), والاعتماد على الثيم
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
        // ⬇️ إزالة لون الخلفية الثابت والاعتماد على الثيم
        color: Theme.of(context).colorScheme.surface,
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

// ⬇️ زر الملف الشخصي الموحد للشركات
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
            initials = (parts[0][0] + parts[1][0]).toUpperCase();
          } else if (parts.isNotEmpty) {
            initials = name.substring(0, name.length > 1 ? 2 : 1).toUpperCase();
          }
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
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
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
