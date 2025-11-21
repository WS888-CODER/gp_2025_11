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

  static const _brand = AppTheme.primaryPurple;

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

  Widget _buildNavItem({
    required IconData icon,
    required IconData filledIcon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
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

  Widget _buildAppBarTitle(String userId) {
    switch (_tab) {
      case 0:
        return const Text(
          'History',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
          overflow: TextOverflow.ellipsis,
        );
      case 1:
        return _WelcomeTitle(userId: userId);
      case 2:
        return const Text(
          'Favorites',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
          overflow: TextOverflow.ellipsis,
        );
      default:
        return _WelcomeTitle(userId: userId);
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.hideCurrentMaterialBanner();
    });
    final userId = _effectiveUserId;

    final homeBody = ListView(
      controller: _homeScroll,
      padding: const EdgeInsets.all(16),
      children: [
        const _JobsSearchShortcut(),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _BigTile(
                label: 'Mock Interviews',
                icon: Icons.mic_none,
                color: _brand,
                onTap: () {
                  SnackHelper.error(
                      context, 'Mock Interviews will be available soon');
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _BigTile(
                label: 'CV Enhancement',
                icon: Icons.description_outlined,
                color: _brand,
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
        _JobsPreviewCompact(
          limit: 3,
          userId: userId,
        ),
        const SizedBox(height: 16),
      ],
    );

    return ThemedScaffold(
      appBar: JobSeekerAppBar(
        title: _buildAppBarTitle(userId),
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          const HistoryPage(),
          homeBody,
          const FavoritesPage(),
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
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildNavItem(
                icon: Icons.history_outlined,
                filledIcon: Icons.history,
                label: 'History',
                isSelected: _tab == 0,
                onTap: () => setState(() => _tab = 0),
              ),
              _buildNavItem(
                icon: Icons.home_outlined,
                filledIcon: Icons.home,
                label: 'Home',
                isSelected: _tab == 1,
                onTap: () {
                  if (_tab == 1 && _homeScroll.hasClients) {
                    _homeScroll.animateTo(
                      0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  } else {
                    setState(() => _tab = 1);
                  }
                },
              ),
              _buildNavItem(
                icon: Icons.favorite_border,
                filledIcon: Icons.favorite,
                label: 'Favorites',
                isSelected: _tab == 2,
                onTap: () => setState(() => _tab = 2),
              ),
            ],
          ),
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
        // base match
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
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'No jobs yet',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final shadowColor =
        isDark ? Colors.black.withOpacity(0.6) : Colors.black.withOpacity(0.07);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
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
          color: scheme.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: shadowColor,
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(
              Icons.search,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Search jobs, companies or keywords…',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.grey[500] : Colors.grey[600],
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
