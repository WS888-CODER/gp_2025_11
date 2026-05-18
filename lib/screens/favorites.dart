import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gp_2025_11/config/theme.dart';
import 'package:gp_2025_11/screens/job_card.dart';

const String kJobsCollection = 'Jobs';
const String kUsersCollection = 'Users';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  final Map<String, Job> _jobsById = {};
  final Map<String, CompanyInfo> _companies = {};

  Set<String> _favoriteIds = {};
  // Jobs the user just un-favourited but Firestore hasn't confirmed yet.
  // Kept separate so a stale _favSub snapshot can't resurrect a removed card.
  final Set<String> _pendingRemovals = {};
  Set<String> _appliedJobIds = {};

  bool _loading = true;
  bool _loadingCompanies = false;

  StreamSubscription<List<Job>>? _jobsSub;
  StreamSubscription<Set<String>>? _favSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _appliedSub;

  @override
  void initState() {
    super.initState();

    _jobsSub = _jobsStream().listen((jobs) {
      if (!mounted) return;

      setState(() {
        _jobsById
          ..clear()
          ..addEntries(jobs.map((j) => MapEntry(j.jobId, j)));
        _loading = false;
      });

      _ensureCompanyNames(
        jobs.map((j) => j.userId).toSet(),
      );
    });

    _favSub = FavoritesService.favoritesStream().listen((ids) {
      if (!mounted) return;
      setState(() {
        _favoriteIds = ids;
        // Once Firestore confirms a removal, drop it from _pendingRemovals.
        _pendingRemovals.removeWhere((id) => !ids.contains(id));
      });
    });

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _appliedSub = FirebaseFirestore.instance
          .collection('Applications')
          .where('UserID', isEqualTo: uid)
          .snapshots()
          .listen((qs) {
        if (!mounted) return;
        setState(() {
          _appliedJobIds =
              qs.docs.map((d) => (d.data()['JobID'] ?? '').toString()).toSet();
        });
      });
    }
  }

  @override
  void dispose() {
    _jobsSub?.cancel();
    _favSub?.cancel();
    _appliedSub?.cancel();
    super.dispose();
  }

  Stream<List<Job>> _jobsStream() {
    return FirebaseFirestore.instance
        .collection(kJobsCollection)
        .orderBy(JobFields.postedAt, descending: true)
        .snapshots()
        .map((qs) => qs.docs.map((d) => Job.fromDoc(d)).toList());
  }

  List<Job> get _favoriteJobs {
    final jobs = (_favoriteIds.difference(_pendingRemovals))
        .where((id) => _jobsById.containsKey(id))
        .map((id) => _jobsById[id]!)
        .toList();

    jobs.sort((a, b) => b.postedAt.compareTo(a.postedAt));
    return jobs;
  }

  Future<void> _handleToggleFavorite(Job job, bool newValue) async {
    if (!newValue) {
      // Hide immediately; _pendingRemovals blocks the job from reappearing
      // even if _favSub fires a stale snapshot before Firestore confirms.
      setState(() => _pendingRemovals.add(job.jobId));
    }

    try {
      await FavoritesService.toggleFavorite(job.jobId, newValue);
    } catch (e) {
      // Revert: let the job reappear.
      if (mounted) setState(() => _pendingRemovals.remove(job.jobId));
      if (!mounted) return;
      SnackHelper.error(
        context,
        'Failed to update favorites. Please try again.',
      );
    }
  }

  Future<void> _ensureCompanyNames(Set<String> uids) async {
    final missing = uids.where((id) => !_companies.containsKey(id)).toList();
    if (missing.isEmpty || _loadingCompanies) return;

    if (!mounted) return;
    setState(() => _loadingCompanies = true);

    try {
      for (var i = 0; i < missing.length; i += 10) {
        final chunk = missing.sublist(
          i,
          i + 10 > missing.length ? missing.length : i + 10,
        );

        final qs = await FirebaseFirestore.instance
            .collection(kUsersCollection)
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        for (final doc in qs.docs) {
          final data = doc.data();

          final rawCompany = (data['CompanyName'] ?? '').toString().trim();
          final rawName = (data['Name'] ?? '').toString().trim();
          final displayName = rawCompany.isNotEmpty
              ? rawCompany
              : (rawName.isNotEmpty ? rawName : 'Company');

          _companies[doc.id] = CompanyInfo(
            name: displayName,
            logoUrl: (data['PhotoURL'] ?? '').toString(),
            location: (data['Location'] ?? '').toString(),
            description: (data['Description'] ?? '').toString(),
            contactEmail: (data['ContactEmail'] ?? '').toString(),
            phone: (data['Phone'] ?? '').toString(),
            website: (data['Website'] ?? '').toString(),
          );
        }

        for (final id in chunk) {
          _companies.putIfAbsent(id, () => const CompanyInfo());
        }
      }
    } finally {
      if (mounted) {
        setState(() => _loadingCompanies = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final Color primaryTop = scheme.primary;
    final Color primaryBottom =
        isDark ? scheme.primary.withOpacity(0.95) : scheme.primary;

    final Color bubbleColor = Colors.white.withOpacity(isDark ? 0.04 : 0.06);
    final Color shadowColor = scheme.primary.withOpacity(isDark ? 0.55 : 0.4);

    return Scaffold(
      backgroundColor: isDark ? scheme.background : const Color(0xFFF5F5F5),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(120),
        child: Container(
          height: 120,
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [primaryTop, primaryBottom],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(40),
              bottomRight: Radius.circular(40),
            ),
            boxShadow: [
              BoxShadow(
                color: shadowColor,
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                top: -60,
                right: -40,
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: bubbleColor,
                  ),
                ),
              ),
              Positioned(
                bottom: -20,
                left: -30,
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: bubbleColor,
                  ),
                ),
              ),
              const SafeArea(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.only(top: 50),
                    child: Text(
                      'Favorites',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _favoriteJobs.isEmpty
              ? const EmptyState(
                  icon: Icons.favorite_border,
                  title: 'No Favorite Jobs Yet',
                  subtitle: 'Jobs you save will appear here',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _favoriteJobs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final job = _favoriteJobs[index];
                    final company =
                        _companies[job.userId] ?? const CompanyInfo();

                    return JobCard(
                      key: ValueKey(job.jobId),
                      job: job,
                      company: company,
                      isSaved: true,
                      isApplied: _appliedJobIds.contains(job.jobId),
                      onSavedChanged: (newValue) {
                        _handleToggleFavorite(job, newValue);
                      },
                    );
                  },
                ),
    );
  }
}

class FavoritesService {
  static const String usersCollection = 'Users';
  static const String favoriteField = 'favorite';

  static DocumentReference<Map<String, dynamic>>? _userDoc() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;

    return FirebaseFirestore.instance.collection(usersCollection).doc(uid);
  }

  static Future<void> toggleFavorite(String jobId, bool newValue) async {
    final doc = _userDoc();
    if (doc == null) return;

    await doc.set(
      {
        favoriteField: newValue
            ? FieldValue.arrayUnion([jobId])
            : FieldValue.arrayRemove([jobId]),
      },
      SetOptions(merge: true),
    );
  }

  static Stream<Set<String>> favoritesStream() {
    final doc = _userDoc();
    if (doc == null) {
      return const Stream.empty();
    }

    return doc.snapshots().map((snap) {
      final data = snap.data();
      if (data == null) return <String>{};

      final raw = data[favoriteField];
      if (raw is! List) return <String>{};

      return raw
          .map((e) => e.toString().trim())
          .where((id) => id.isNotEmpty)
          .cast<String>()
          .toSet();
    });
  }
}
