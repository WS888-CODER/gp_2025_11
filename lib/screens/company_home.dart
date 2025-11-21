// lib/screens/company_home.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gp_2025_11/config/theme.dart';
import 'package:gp_2025_11/config/themed_scaffold.dart';
import 'dart:async';

class CompanyHome extends StatefulWidget {
  const CompanyHome({
    super.key,
    this.companyId,
    this.fallbackCompanyName = 'Company',
  });

  final String? companyId;

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
        showDialog<void>(
          context: context,
          builder: (context) => const JadeerDialog<void>(
            title: 'Profile Incomplete',
            primaryLabel: 'OK',
            primaryResult: null,
            content: Text(
              'Please complete your company profile before creating or editing job postings.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white),
            ),
          ),
        );

        return false;
      }

      return true;
    } catch (e) {
      if (!mounted) return false;
      showDialog<void>(
        context: context,
        builder: (context) => JadeerDialog<void>(
          title: 'Error',
          primaryLabel: 'OK',
          primaryResult: null,
          content: Text(
            'Failed to verify profile: $e',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
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

      SnackHelper.success(
        ctx,
        isClosed ? 'Job reopened successfully' : 'Job closed successfully',
      );
    } catch (e) {
      if (!mounted) return;

      SnackHelper.error(ctx, 'Error: $e');
    }
  }

  /// Delete a job with confirmation
  Future<void> _deleteJob(
      String jobId, String jobTitle, BuildContext ctx) async {
    if (!mounted) return;

    final shouldDelete = await showDialog<bool>(
      context: ctx,
      builder: (context) => JadeerDialog<bool>(
        title: 'Delete Job?',
        primaryLabel: 'Delete',
        primaryResult: true,
        secondaryLabel: 'Cancel',
        secondaryResult: false,
        content: Text(
          'Are you sure you want to permanently delete "$jobTitle"? This action cannot be undone.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );

    // Check mounted after dialog closes
    if (!mounted) return;

    if (shouldDelete == true) {
      try {
        await FirebaseFirestore.instance.collection('Jobs').doc(jobId).delete();

        // Check mounted after async operation
        if (!mounted) return;

        SnackHelper.success(ctx, 'Job deleted successfully');
      } catch (e) {
        if (!mounted) return;

        SnackHelper.error(ctx, 'Error: $e');
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

        // بس رتبنا الوظائف حسب startDate بدون أي تحديث في الداتابيس
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
                    await Navigator.pushNamed(context, '/job-posting');
                    // Refresh the page after returning
                    if (mounted) {
                      setState(() {});
                    }
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
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.work_outline,
                      size: 40,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.4),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No job posts yet',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tap "Create Job Post" to add your first opening.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.7),
                          ),
                    ),
                  ],
                ),
              );
            }

            return Column(
              children: jobs.map((doc) {
                final data = doc.data();

                final title = (data['JobTitle'] ?? 'Untitled').toString();
                final position = (data['Position'] ?? '').toString();
                final specialty = (data['Specialty'] ?? '').toString();
                final endDateField = data['EndDate'];
                DateTime? endDate;
                if (endDateField is Timestamp) {
                  endDate = endDateField.toDate();
                }
                final now = DateTime.now();

                final jobStatus = (data['JobStatus'] ?? 'Open').toString();
                final isClosed = jobStatus == 'Closed' ||
                    (endDate != null && endDate.isBefore(now));

                final theme = Theme.of(context);
                final scheme = theme.colorScheme;

                final cardBackgroundColor = isClosed
                    ? scheme.surface.withOpacity(
                        theme.brightness == Brightness.dark ? 0.7 : 0.5)
                    : scheme.surface;
                final titleColorBase =
                    theme.textTheme.bodyLarge?.color ?? scheme.onSurface;

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: cardBackgroundColor,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(
                          theme.brightness == Brightness.dark ? 0.3 : 0.05,
                        ),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                color: isClosed
                                    ? titleColorBase.withOpacity(0.65)
                                    : titleColorBase,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              [position, specialty]
                                  .where((e) => e.isNotEmpty)
                                  .join(' • '),
                              style: TextStyle(
                                color: isClosed
                                    ? titleColorBase.withOpacity(0.65)
                                    : titleColorBase,
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
                      Row(
                        children: [
                          // ===== Edit Icon =====
                          IconButton(
                            onPressed: () async {
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

                              await Navigator.pushNamed(
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

                              if (mounted) setState(() {});
                            },
                            icon: const Icon(Icons.edit),
                            color: _brand,
                            iconSize: 26,
                            tooltip: 'Edit',
                          ),

                          // Space
                          const SizedBox(width: 4),

                          // ===== View Icon =====
                          IconButton(
                            onPressed: () {
                              Navigator.pushNamed(
                                context,
                                '/questions',
                                arguments: {
                                  'jobId': doc.id,
                                  'locked': true,
                                },
                              );
                            },
                            icon: const Icon(Icons.visibility),
                            color: _brand,
                            iconSize: 26,
                            tooltip: 'View',
                          ),
                        ],
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
      appBar: AppBar(
        backgroundColor: _brand,
        elevation: 0,
        centerTitle: true,
        leadingWidth: 56,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: _ProfileButton(userId: companyId),
        ),
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
            onPressed: () => SnackHelper.error(
                context, 'Notifications will be available soon'),
          ),
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
              'Reports – soon',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          homeBody,
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
          border: Border(
            top: BorderSide(
              color: Theme.of(context).colorScheme.outline.withOpacity(0.15),
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 6),
        child: SafeArea(
          top: false,
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
                radius: 22,
                backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
                backgroundColor: const Color(0xFFFF7B7B),
                foregroundColor: Colors.white,
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
