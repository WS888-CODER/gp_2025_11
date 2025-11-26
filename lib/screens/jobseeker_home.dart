// lib/screens/jobseeker_home.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gp_2025_11/config/theme.dart';
import 'package:gp_2025_11/config/themed_scaffold.dart';
import 'package:gp_2025_11/screens/all_jobs.dart';
import 'package:gp_2025_11/screens/job_card.dart';
import 'package:gp_2025_11/screens/cv_enhancement.dart';
import 'package:gp_2025_11/screens/history.dart';
import 'package:gp_2025_11/screens/favorites.dart';
import 'package:gp_2025_11/screens/jobseeker_profile.dart';

class JobSeekerHome extends StatefulWidget {
  const JobSeekerHome({super.key, this.userId});
  final String? userId;

  @override
  State<JobSeekerHome> createState() => _JobSeekerHomeState();
}

class _JobSeekerHomeState extends State<JobSeekerHome> {
  int _tab = 1;
  final _homeScroll = ScrollController();
  final TextEditingController _homeSearchController = TextEditingController();

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
    _homeSearchController.dispose();
    super.dispose();
  }

  Widget _buildAnimatedNavBar() {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.bottomCenter,
      children: [
        // الـ Bottom Bar مع القطع (notch)
        ClipPath(
          clipper: _BottomBarClipper(
            circlePosition: _getCirclePosition() + 30,
            circleRadius: 45,
          ),
          child: Container(
            height: 70,
            decoration: const BoxDecoration(
              color: Colors.white,
            ),
            child: SafeArea(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildNavIcon(Icons.history, 0),
                  _buildNavIcon(Icons.home, 1),
                  _buildNavIcon(Icons.favorite, 2),
                ],
              ),
            ),
          ),
        ),

        // الدائرة المتحركة البارزة
        AnimatedPositioned(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOutCubic,
          left: _getCirclePosition(),
          bottom: 35,
          child: Container(
            width: 60,
            height: 60,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFFC686A),
            ),
            child: Icon(
              _getSelectedIcon(),
              color: Colors.white,
              size: 30,
            ),
          ),
        ),
      ],
    );
  }

  double _getCirclePosition() {
    final screenWidth = MediaQuery.of(context).size.width;
    final itemWidth = screenWidth / 3;
    return (_tab * itemWidth) + (itemWidth / 2) - 30;
  }

  IconData _getSelectedIcon() {
    switch (_tab) {
      case 0:
        return Icons.history;
      case 1:
        return Icons.home;
      case 2:
        return Icons.favorite;
      default:
        return Icons.home;
    }
  }

  Widget _buildNavIcon(IconData icon, int index) {
    final isSelected = _tab == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _tab = index;
        });
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 60,
        height: 60,
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 26,
          color: isSelected ? Colors.transparent : Colors.grey[400],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildCustomAppBar(String userId) {
    String title;
    switch (_tab) {
      case 0:
        title = 'History';
        break;
      case 1:
        title = '';
        break;
      case 2:
        title = 'Favorites';
        break;
      default:
        title = '';
    }

    // For non-home tabs, use custom AppBar with profile button
    if (_tab != 1) {
      return AppBar(
        backgroundColor: const Color(0xFF4A5FBC),
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        leadingWidth: 70,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('Users')
                .doc(userId)
                .snapshots(),
            builder: (context, snap) {
              final photoUrl = snap.hasData
                  ? (snap.data?.data()?['PhotoURL'] ?? '').toString().trim()
                  : '';

              return GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const JobSeekerProfile(),
                    ),
                  );
                },
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                    image: photoUrl.isNotEmpty
                        ? DecorationImage(
                            image: NetworkImage(photoUrl),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: photoUrl.isEmpty
                      ? const Icon(
                          Icons.person,
                          color: Colors.white,
                          size: 24,
                        )
                      : null,
                ),
              );
            },
          ),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined, color: Colors.white),
            onPressed: () {
              SnackHelper.error(context, 'Notifications coming soon');
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white),
            onPressed: () {
              final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
              if (uid.isEmpty) return;
              Navigator.pushNamed(
                context,
                '/settings',
                arguments: {'userType': 'JobSeeker', 'userId': uid},
              );
            },
          ),
        ],
      );
    }

    // For home tab, use custom design with profile button
    return PreferredSize(
      preferredSize: const Size.fromHeight(200),
      child: Container(
        height: 280,
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF4A5FBC), Color(0xFF4A5FBC)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(40),
            bottomRight: Radius.circular(40),
          ),
          boxShadow: [
            BoxShadow(
              color: Color(0x404A5FBC),
              blurRadius: 20,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Decorative background circles
            Positioned(
              top: -60,
              right: -40,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.05),
                ),
              ),
            ),
            Positioned(
              bottom: 40,
              left: -30,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.05),
                ),
              ),
            ),
            // Original content
            SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top row with profile, notification, and settings
                    Row(
                      children: [
                        // Profile button with actual photo
                        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                          stream: FirebaseFirestore.instance
                              .collection('Users')
                              .doc(userId)
                              .snapshots(),
                          builder: (context, snap) {
                            final photoUrl = snap.hasData
                                ? (snap.data?.data()?['PhotoURL'] ?? '')
                                    .toString()
                                    .trim()
                                : '';

                            return GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const JobSeekerProfile(),
                                  ),
                                );
                              },
                              child: Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  shape: BoxShape.circle,
                                  image: photoUrl.isNotEmpty
                                      ? DecorationImage(
                                          image: NetworkImage(photoUrl),
                                          fit: BoxFit.cover,
                                        )
                                      : null,
                                ),
                                child: photoUrl.isEmpty
                                    ? const Icon(
                                        Icons.person,
                                        color: Colors.white,
                                        size: 28,
                                      )
                                    : null,
                              ),
                            );
                          },
                        ),
                        const Spacer(),
                        // Notification button
                        GestureDetector(
                          onTap: () {
                            SnackHelper.error(
                                context, 'Notifications coming soon');
                          },
                          child: Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.notifications_outlined,
                              color: Colors.white,
                              size: 26,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Settings button
                        GestureDetector(
                          onTap: () {
                            final uid =
                                FirebaseAuth.instance.currentUser?.uid ?? '';
                            if (uid.isEmpty) return;
                            Navigator.pushNamed(
                              context,
                              '/settings',
                              arguments: {
                                'userType': 'JobSeeker',
                                'userId': uid
                              },
                            );
                          },
                          child: Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.settings_outlined,
                              color: Colors.white,
                              size: 26,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // Welcome text
                    _WelcomeTitle(userId: userId),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.hideCurrentMaterialBanner();
    });
    final userId = _effectiveUserId;

    final homeBody = Container(
      color: const Color(0xFFF5F5F5),
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF5F5F5),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(30),
                  topRight: Radius.circular(30),
                ),
              ),
              child: ListView(
                controller: _homeScroll,
                padding: const EdgeInsets.all(20),
                children: [
                  const SizedBox(height: 8),
                  // Search bar
                  const _JobsSearchShortcut(),
                  const SizedBox(height: 24),

                  // Feature cards
                  Row(
                    children: [
                      Expanded(
                        child: _ModernFeatureCard(
                          title: 'Mock\nInterviews',
                          subtitle: 'AI Practice',
                          icon: Icons.mic_none,
                          gradientColors: const [
                            Color(0xFF7F53AC),
                            Color(0xFF4A5FBC),
                          ],
                          onTap: () {
                            SnackHelper.error(context,
                                'Mock Interviews will be available soon');
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _ModernFeatureCard(
                          title: 'CV\nEnhancement',
                          subtitle: 'Get Reviewed',
                          icon: Icons.description_outlined,
                          gradientColors: const [
                            Color(0xFFFF5E5E),
                            Color(0xFFFD6C67),
                          ],
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const CVEnhancementScreen(),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),
                  // Jobs header
                  Row(
                    children: [
                      const Text(
                        'Jobs',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
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
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(40, 30),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'View All',
                          style: TextStyle(
                            color: Color(0xFF4A5FBC),
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _JobsPreviewCompact(
                    limit: 3,
                    userId: userId,
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    return ThemedScaffold(
      appBar: _buildCustomAppBar(userId),
      body: IndexedStack(
        index: _tab,
        children: [
          const HistoryPage(),
          homeBody,
          const FavoritesPage(),
        ],
      ),
      bottomNavigationBar: _buildAnimatedNavBar(),
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

      final userType =
          (data['UserType'] ?? data['userType'] ?? '').toString().toLowerCase();

      final companyName = (data['CompanyName'] ?? '').toString().trim();
      final fullName = (data['Name'] ?? '').toString().trim();

      if (companyName.isNotEmpty) return companyName;

      final isJobSeeker = userType == 'jobseeker' || userType == 'job_seeker';

      if (isJobSeeker && fullName.isNotEmpty) {
        return fullName.split(' ').first;
      }

      if (fullName.isNotEmpty) return fullName;

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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome back,',
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 16,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        );
      },
    );
  }
}

class _ModernFeatureCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradientColors;
  final VoidCallback onTap;

  const _ModernFeatureCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradientColors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: gradientColors.first.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Stack(
            children: [
              // Background large icon (texture)
              Positioned(
                right: -20,
                bottom: -20,
                child: Icon(
                  icon,
                  size: 120,
                  color: Colors.white.withOpacity(0.15),
                ),
              ),
              // Content
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Small Icon Bubble
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.25),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: Colors.white, size: 24),
                    ),
                    const Spacer(),
                    // Title
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Subtitle
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JobsPreviewCompact extends StatefulWidget {
  final int limit;
  final String userId;

  const _JobsPreviewCompact({
    this.limit = 2,
    required this.userId,
  });

  @override
  State<_JobsPreviewCompact> createState() => _JobsPreviewCompactState();
}

class _JobsPreviewCompactState extends State<_JobsPreviewCompact> {
  List<Job> _finalJobs = [];
  Map<String, CompanyInfo> _companyByUserId = {};
  bool _loadingCompanies = false;
  String? _error;
  String? _cvUrl;
  Set<String> _cvKeywords = {};
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileSub;
  bool get _hasCv => _cvUrl != null && _cvUrl!.isNotEmpty;
  bool get _hasKeywords => _cvKeywords.isNotEmpty;

  @override
  void initState() {
    super.initState();

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      _profileSub = FirebaseFirestore.instance
          .collection('Users')
          .doc(uid)
          .snapshots()
          .listen((doc) {
        final data = doc.data() ?? {};

        final cv = (data[UserDocFields.cvUrl] ?? '').toString().trim();
        final rawKeywords = data[UserDocFields.cvKeywords];

        final Set<String> cvKeys = {};
        if (rawKeywords is List) {
          for (final e in rawKeywords) {
            final s = e.toString().trim().toLowerCase();
            if (s.isNotEmpty) cvKeys.add(s);
          }
        }

        if (!mounted) return;
        setState(() {
          _cvUrl = cv.isNotEmpty ? cv : null;
          _cvKeywords = cvKeys;
        });
      });
    }
  }

  Future<void> _toggleFavoriteForJob(Job job, bool newValue) async {
    try {
      await FavoritesService.toggleFavorite(job.jobId, newValue);
    } catch (e) {
      if (!mounted) return;
      SnackHelper.error(context, 'Failed to update favorites: $e');
    }
  }

  int _cvMatchScore(Job j) {
    if (_cvKeywords.isEmpty) return 0;

    final jobBagRaw = {
      j.specialty.toLowerCase().trim(),
      j.title.toLowerCase().trim(),
      j.position.toLowerCase().trim(),
      ...j.keywords.map((k) => k.toLowerCase().trim()),
    };

    final Set<String> jobTokens = {
      for (final chunk in jobBagRaw)
        ...chunk.split(RegExp(r'[^a-z0-9+#]+')).where((t) => t.isNotEmpty),
    };

    int score = 0;

    for (final kw in _cvKeywords) {
      final cleanKw = kw.toLowerCase().trim();
      if (cleanKw.isEmpty) continue;

      if (jobTokens.contains(cleanKw)) {
        score += 2;

        if (j.specialty.toLowerCase().contains(cleanKw)) {
          score += 1;
        }
      }
    }

    return score;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _jobsStream() {
    return FirebaseFirestore.instance
        .collection('Jobs')
        .orderBy(JobFields.postedAt, descending: true)
        .limit(widget.limit * 5)
        .snapshots();
  }

  Future<Map<String, CompanyInfo>> _fetchCompaniesForJobs(
      List<Job> jobs) async {
    final ownerIds = jobs.map((j) => j.userId).toSet().toList();
    final Map<String, CompanyInfo> result = {};

    for (var i = 0; i < ownerIds.length; i += 10) {
      final chunk = ownerIds.sublist(
          i, (i + 10 > ownerIds.length) ? ownerIds.length : i + 10);

      final usersSnap = await FirebaseFirestore.instance
          .collection('Users')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();

      for (final doc in usersSnap.docs) {
        final data = doc.data();
        final rawCompany = (data['CompanyName'] ?? '').toString().trim();
        final rawName = (data['Name'] ?? '').toString().trim();
        final display = rawCompany.isNotEmpty
            ? rawCompany
            : (rawName.isNotEmpty ? rawName : 'Company');

        result[doc.id] = CompanyInfo(
          name: display,
          logoUrl: (data['PhotoURL'] ?? '').toString().trim(),
          location: (data['Location'] ?? '').toString().trim(),
          description: (data['Description'] ?? '').toString().trim(),
          contactEmail: (data['ContactEmail'] ?? '').toString().trim(),
          phone: (data['Phone'] ?? '').toString().trim(),
          website: (data['Website'] ?? '').toString().trim(),
        );
      }

      for (final uid in chunk) {
        result.putIfAbsent(uid, () => const CompanyInfo());
      }
    }

    return result;
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _jobsStream(),
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
            child: Text(
              'Error: ${snap.error}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          );
        }

        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return const EmptyState(
            icon: Icons.work_off_outlined,
            title: 'No jobs yet',
            subtitle: '',
          );
        }

        final allJobs = docs.map((d) => Job.fromDoc(d)).toList();

        final openJobs = allJobs
            .where((j) => j.status.trim().toLowerCase() != 'closed')
            .toList();

        List<Job> prioritized = [];

        if (_hasCv && _hasKeywords) {
          final List<Job> strongMatches = [];
          final List<Job> otherJobs = [];

          for (final j in openJobs) {
            final score = _cvMatchScore(j);
            if (score >= 2) {
              strongMatches.add(j);
            } else {
              otherJobs.add(j);
            }
          }

          strongMatches.sort((a, b) {
            final sa = _cvMatchScore(a);
            final sb = _cvMatchScore(b);

            if (sa != sb) {
              return sb.compareTo(sa);
            }
            return b.postedAt.compareTo(a.postedAt);
          });

          otherJobs.sort((a, b) => b.postedAt.compareTo(a.postedAt));

          prioritized = [...strongMatches, ...otherJobs];
        } else {
          prioritized = List<Job>.from(openJobs)
            ..sort((a, b) => b.postedAt.compareTo(a.postedAt));
        }

        final limitedJobs = prioritized.take(widget.limit).toList();

        final needToFetchCompanies = () {
          if (_loadingCompanies) return false;
          if (limitedJobs.length != _finalJobs.length) return true;

          for (var i = 0; i < limitedJobs.length; i++) {
            if (limitedJobs[i].userId != _finalJobs[i].userId ||
                limitedJobs[i].id != _finalJobs[i].id) {
              return true;
            }
          }
          return false;
        }();

        if (needToFetchCompanies) {
          _fetchCompaniesForJobs(limitedJobs).then((map) {
            if (!mounted) return;
            setState(() {
              _finalJobs = limitedJobs;
              _companyByUserId = map;
              _loadingCompanies = false;
              _error = null;
            });
          }).catchError((e) {
            if (!mounted) return;
            setState(() {
              _loadingCompanies = false;
              _error = e.toString();
            });
          });
        }

        if (_loadingCompanies && _finalJobs.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (_error != null) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Error: $_error',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          );
        }

        if (_finalJobs.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'No open jobs',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          );
        }

        return StreamBuilder<Set<String>>(
          stream: FavoritesService.favoritesStream(),
          builder: (context, favSnap) {
            final savedIds = favSnap.data ?? <String>{};

            return Column(
              children: _finalJobs.map((job) {
                final company =
                    _companyByUserId[job.userId] ?? const CompanyInfo();
                final isSaved = savedIds.contains(job.jobId);

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: JobCard(
                    key: ValueKey('job-${job.jobId}-${isSaved ? '1' : '0'}'),
                    job: job,
                    company: company,
                    isSaved: isSaved,
                    onSavedChanged: (v) => _toggleFavoriteForJob(job, v),
                  ),
                );
              }).toList(),
            );
          },
        );
      },
    );
  }
}

class _JobsSearchShortcut extends StatelessWidget {
  const _JobsSearchShortcut();

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const JobsPage(
              autoFocusSearch: true,
            ),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(
              Icons.search,
              color: Colors.grey[500],
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Search company, title or keyword…',
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey[500],
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomBarClipper extends CustomClipper<Path> {
  final double circlePosition;
  final double circleRadius;

  _BottomBarClipper({
    required this.circlePosition,
    required this.circleRadius,
  });

  @override
  Path getClip(Size size) {
    final path = Path();

    // مستطيل كامل
    path.addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    // نقص الدائرة من فوق!
    path.addOval(
      Rect.fromCircle(
        center: Offset(circlePosition, 0), // مركز الدائرة على الحافة العليا
        radius: circleRadius,
      ),
    );

    // نستخدم fillType عشان نقص الدائرة من المستطيل
    path.fillType = PathFillType.evenOdd;

    return path;
  }

  @override
  bool shouldReclip(_BottomBarClipper oldClipper) {
    return oldClipper.circlePosition != circlePosition;
  }
}
