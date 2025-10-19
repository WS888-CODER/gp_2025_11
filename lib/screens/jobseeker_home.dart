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
        const Row(
          children: [
            Icon(Icons.work_outline, size: 36, color: _brand),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Job Seeker Dashboard',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: _brand,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        Row(
          children: [
            Expanded(
              child: _BigTile(
                label: 'Mock',
                icon: Icons.quiz_outlined,
                color: _brand,
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Mock – قريبًا')),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _BigTile(
                label: 'CV',
                icon: Icons.description_outlined,
                color: _brand,
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('CV – قريبًا')),
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
      backgroundColor: Colors.white,
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
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined, color: Colors.white),
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Settings – قريبًا')),
            ),
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          if (i == _tab) {
            if (i == 1) {
              _homeScroll.animateTo(0,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut);
            }
            return;
          }
          setState(() => _tab = i);
        },
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.bar_chart_outlined), label: 'Reports'),
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.favorite_border), label: 'Wishlist'),
        ],
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
    return base.isNotEmpty ? base[0].toUpperCase() : 'U';
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
                        ),
                      )
                    : null,
                backgroundColor: Theme.of(context).colorScheme.secondary,
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        height: 90,
        decoration: BoxDecoration(
          color: color.withOpacity(.08),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(color: color, fontWeight: FontWeight.w700),
              ),
            ],
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
  final Map<String, String> _companyCache = {};

  Future<String> _companyName(String userId) async {
    if (userId.isEmpty) return 'Company';
    if (_companyCache.containsKey(userId)) return _companyCache[userId]!;
    final doc =
        await FirebaseFirestore.instance.collection('Users').doc(userId).get();
    final data = doc.data() ?? {};
    final companyName = (data['CompanyName'] ?? '').toString().trim();
    final name = (data['Name'] ?? '').toString().trim();
    final display = companyName.isNotEmpty
        ? companyName
        : (name.isNotEmpty ? name : 'Company');
    _companyCache[userId] = display;
    return display;
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
            return FutureBuilder<String>(
              future: _companyName(j.userId),
              builder: (context, companySnap) {
                final companyName = companySnap.data ?? 'Company';
                final hasKeywords = j.keywords.isNotEmpty;
                final canApply =
                    j.applyUrl != null && j.applyUrl!.trim().isNotEmpty;

                return Card(
                  elevation: 0.5,
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => JobDetailsPage(
                            job: j,
                            companyName: companyName,
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
                                      companyName,
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
                              // compact preview (no save button)
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
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
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
                                              companyName: companyName,
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
