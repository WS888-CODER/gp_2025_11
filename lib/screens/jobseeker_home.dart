// lib/screens/jobseeker_home.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gp_2025_11/screens/all_jobs.dart';
import 'package:gp_2025_11/screens/job_seeker_profile_page.dart';

class JobSeekerHome extends StatefulWidget {
  const JobSeekerHome({super.key, this.userId});
  final String? userId;

  @override
  State<JobSeekerHome> createState() => _JobSeekerHomeState();
}

class _JobSeekerHomeState extends State<JobSeekerHome> {
  // 0 = Reports, 1 = Home, 2 = Wishlist
  int _tab = 1;
  final _homeScroll = ScrollController();

  static const _brand = Color(0xFF4A5FBC);

  String get _effectiveUserId {
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final fromArgs = (args?['userId'] ?? '').toString();
    if (fromArgs.isNotEmpty) return fromArgs;

    final current = FirebaseAuth.instance.currentUser;
    if (current != null && current.uid.isNotEmpty) return current.uid;

    return widget.userId ?? '';
  }

  @override
  void dispose() {
    _homeScroll.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    // hide any previous MaterialBanner
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
      }
    });

    final homeBody = ListView(
      controller: _homeScroll,
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: _BigTile(
                label: 'Mock Interviews',
                icon: Icons.quiz_outlined,
                color: _brand,
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Mock Interviews – قريبًا')),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _BigTile(
                label: 'CV Enhancement',
                icon: Icons.description_outlined,
                color: _brand,
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('CV Enhancement – قريبًا')),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),

        Row(
          children: [
            const Text('Jobs',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const Spacer(),
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const JobsPage(),
                  ),
                );
              },
              child: const Text('All'),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Preview section now styled like All Jobs cards
        const _JobsPreview(limit: 2),

        const SizedBox(height: 16),
      ],
    );

    final userId = _effectiveUserId;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F6FC),
      appBar: AppBar(
        backgroundColor: _brand,
        elevation: 0,
        // ⬇️ زر البروفايل فوق يسار
        leadingWidth: 56,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: _ProfileButton(userId: userId),
        ),
        title: _WelcomeTitle(userId: userId),
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
                  arguments: {'userType': 'JobSeeker', 'userId': uid},
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
            child: Text('Reports – قريبًا',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          homeBody,
          const _WishlistPlaceholder(),
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
            const SizedBox(width: 80),
            _buildNavItem(
              icon: Icons.home_outlined,
              filledIcon: Icons.home,
              label: 'Home',
              isSelected: _tab == 1,
              onTap: () {
                if (_tab == 1) {
                  _homeScroll.animateTo(0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut);
                } else {
                  setState(() => _tab = 1);
                }
              },
            ),
            const SizedBox(width: 80),
            _buildNavItem(
              icon: Icons.favorite_border,
              filledIcon: Icons.favorite,
              label: 'Wishlist',
              isSelected: _tab == 2,
              onTap: () => setState(() => _tab = 2),
            ),
          ],
        ),
      ),
    );
  }
}

class _WelcomeTitle extends StatelessWidget {
  const _WelcomeTitle({required this.userId});
  final String userId;

  Stream<String> _displayNameStream() {
    if (userId.isEmpty) return Stream.value('User');

    return FirebaseFirestore.instance
        .collection('Users')
        .doc(userId)
        .snapshots()
        .map((snap) {
      final data = snap.data() ?? {};
      // New schema: CompanyName / Name / Email
      final companyName = (data['CompanyName'] ?? '').toString();
      final name = (data['Name'] ?? '').toString();
      if (companyName.trim().isNotEmpty) return companyName.trim();
      if (name.trim().isNotEmpty) return name.trim();

      final email = (data['Email'] ?? data['email'] ?? '').toString();
      if (email.contains('@')) return email.split('@').first;

      return 'User';
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String>(
      stream: _displayNameStream(),
      builder: (context, snap) {
        final name = (snap.data ?? 'User').trim();
        return Text(
          'Welcome, $name!',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        );
      },
    );
  }
}

class _ProfileButton extends StatelessWidget {
  const _ProfileButton({required this.userId});
  final String userId;

  Stream<Map<String, dynamic>> _userMiniStream() {
    if (userId.isEmpty) {
      return Stream.value({
        'name': 'User',
        'email': '',
        'photo': '',
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
        'name': (d['Name'] ?? '').toString().trim(),
        'email': (d['Email'] ?? '').toString().trim(),
        'photo': (d['PhotoURL'] ?? '').toString().trim(),
        'complete': d['IsProfileComplete'] == true,
      };
    });
  }

  String _initials(String nameOrEmail) {
    final s = nameOrEmail.trim();
    if (s.isEmpty) return 'U';
    final parts = s.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
    final base = s.contains('@') ? s.split('@').first : s;
    return base.isNotEmpty
        ? base.substring(0, base.length > 1 ? 2 : 1).toUpperCase()
        : 'U';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: _userMiniStream(),
      builder: (context, snap) {
        final name = (snap.data?['name'] ?? '').toString();
        final email = (snap.data?['email'] ?? '').toString();
        final photo = (snap.data?['photo'] ?? '').toString();
        final complete = (snap.data?['complete'] == true);
        final placeholder = _initials(name.isNotEmpty ? name : email);

        final avatar = Hero(
          tag: 'profileAvatar',
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
                child: photo.isEmpty
                    ? Text(
                        placeholder,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      )
                    : null,
                backgroundColor: const Color(0xFFFF7B7B),
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
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const JobSeekerProfile(),
                ),
              );
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

class _BigTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  const _BigTile({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 4,
      shadowColor: Colors.black.withOpacity(0.2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 90,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 28),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _JobsPreview extends StatefulWidget {
  final int limit;
  const _JobsPreview({this.limit = 2});

  @override
  State<_JobsPreview> createState() => _JobsPreviewState();
}

class _JobsPreviewState extends State<_JobsPreview> {
  final Map<String, CompanyInfo> _companyCache = {};

  Future<CompanyInfo> _companyInfo(String userId) async {
    if (userId.isEmpty) return const CompanyInfo();
    if (_companyCache.containsKey(userId)) return _companyCache[userId]!;

    final doc =
        await FirebaseFirestore.instance.collection('Users').doc(userId).get();
    final data = doc.data() ?? {};

    final rawCompany = (data['CompanyName'] ?? '').toString().trim();
    final rawName = (data['Name'] ?? '').toString().trim();
    final display = rawCompany.isNotEmpty
        ? rawCompany
        : (rawName.isNotEmpty ? rawName : 'Company');

    final info = CompanyInfo(
      name: display,
      logoUrl: (data['PhotoURL'] ?? '').toString().trim(),
      location: (data['Location'] ?? '').toString().trim(),
      description: (data['Description'] ?? '').toString().trim(),
      contactEmail: (data['ContactEmail'] ?? '').toString().trim(),
      phone: (data['Phone'] ?? '').toString().trim(),
    );

    _companyCache[userId] = info;
    return info;
  }

  String _fmtDate(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('Jobs')
          .orderBy('StartDate', descending: true)
          .limit(widget.limit)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          );
        }
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Error: ${snap.error}'),
          );
        }

        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text('No jobs yet',
                style: Theme.of(context).textTheme.bodyMedium),
          );
        }

        final jobs = docs.map((d) => Job.fromDoc(d)).toList();

        return Column(
          children: jobs.map((j) {
            return FutureBuilder<CompanyInfo>(
              future: _companyInfo(j.userId),
              builder: (context, companySnap) {
                final info = companySnap.data ?? const CompanyInfo();
                final hasKeywords = j.keywords.isNotEmpty;
                final canApply =
                    j.applyUrl != null && j.applyUrl!.trim().isNotEmpty;

                return Card(
                  elevation: 0.5,
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => JobDetailsPage(
                            job: j,
                            company: info,
                          ),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      j.title,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      info.name,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Posted: ${_fmtDate(j.postedAt)}',
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (hasKeywords)
                            Wrap(
                              spacing: 6,
                              runSpacing: -8,
                              children: j.keywords.take(3).map((k) {
                                return Chip(
                                  label: Text(k),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                );
                              }).toList(),
                            ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              if (j.specialty.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withOpacity(.08),
                                  ),
                                  child: Text(
                                    j.specialty,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              const Spacer(),
                              FilledButton(
                                onPressed: canApply
                                    ? () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => JobDetailsPage(
                                              job: j,
                                              company: info,
                                            ),
                                          ),
                                        );
                                      }
                                    : null,
                                child: const Text('Apply'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          }).toList(),
        );
      },
    );
  }
}

class _WishlistPlaceholder extends StatelessWidget {
  const _WishlistPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text('Wishlist – قريبًا',
          style: Theme.of(context).textTheme.titleMedium),
    );
  }
}
