// lib/screens/jobseeker_home.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gp_2025_11/config/themed_scaffold.dart';
import 'package:gp_2025_11/screens/all_jobs.dart';
import 'package:gp_2025_11/screens/job_seeker_profile_page.dart';

class JobSeekerHome extends StatefulWidget {
  const JobSeekerHome({super.key, this.userId});
  final String? userId;

  @override
  State<JobSeekerHome> createState() => _JobSeekerHomeState();
}

class _JobSeekerHomeState extends State<JobSeekerHome> {
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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                if (isSelected)
                  Icon(
                    filledIcon,
                    size: 34,
                    color: const Color(0xFFFC686A),
                  ),
                if (isSelected)
                  Icon(
                    filledIcon,
                    size: 32,
                    color: const Color(0xFFFFDADD),
                  ),
                Icon(
                  icon,
                  size: 32,
                  color: isSelected
                      ? const Color(0xFFFC686A)
                      : Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.color
                          ?.withOpacity(0.6),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                icon: Icons.mic_none,
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
        const _JobsPreview(limit: 3),
        const SizedBox(height: 16),
      ],
    );

    final userId = _effectiveUserId;

    return ThemedScaffold(
      appBar: AppBar(
        backgroundColor: _brand,
        elevation: 0,
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
        color: Theme.of(context).colorScheme.surface,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildNavItem(
              icon: Icons.bar_chart_outlined,
              filledIcon: Icons.bar_chart,
              label: 'Reports',
              isSelected: _tab == 0,
              onTap: () => setState(() => _tab = 0),
            ),
            const SizedBox(width: 60),
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
            const SizedBox(width: 60),
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
          overflow: TextOverflow.ellipsis,
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
    final dynamicCardColor = Theme.of(context).colorScheme.surface;
    final dynamicTextColor = Theme.of(context).textTheme.bodyLarge?.color;

    return Material(
      color: dynamicCardColor,
      borderRadius: BorderRadius.circular(16),
      elevation: 4,
      shadowColor: Colors.black.withOpacity(0.2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 90,
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    color: dynamicTextColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
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
  const _JobsPreview({this.limit = 3});

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

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('Jobs')
            .orderBy('StartDate', descending: true)
            .limit(widget.limit * 5)
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

          final jobs = docs
              .map((d) => Job.fromDoc(d))
              .where((j) => j.status.trim().toLowerCase() != 'closed')
              .toList();

          if (jobs.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No open jobs',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            );
          }

          return Column(
            children: jobs.map((j) {
              return FutureBuilder<CompanyInfo>(
                future: _companyInfo(j.userId),
                builder: (context, companySnap) {
                  if (companySnap.connectionState == ConnectionState.waiting) {
                    return Card(
                      elevation: 0.5,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(16),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 12),
                            Text('Loading...'),
                          ],
                        ),
                      ),
                    );
                  }

                  final info = companySnap.data ?? const CompanyInfo();

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: JobCard(job: j, company: info),
                  );
                },
              );
            }).toList(),
          );
        });
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
