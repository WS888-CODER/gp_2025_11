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

  bool _loading = true;
  bool _loadingCompanies = false;

  StreamSubscription<List<Job>>? _jobsSub;
  StreamSubscription<Set<String>>? _favSub;

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
      });
    });
  }

  @override
  void dispose() {
    _jobsSub?.cancel();
    _favSub?.cancel();
    super.dispose();
  }

  Stream<List<Job>> _jobsStream() {
    return FirebaseFirestore.instance
        .collection(kJobsCollection)
        .orderBy(JobFields.startDate, descending: true)
        .snapshots()
        .map((qs) => qs.docs.map((d) => Job.fromDoc(d)).toList());
  }

  List<Job> get _favoriteJobs {
    final jobs = _favoriteIds
        .where((id) => _jobsById.containsKey(id))
        .map((id) => _jobsById[id]!)
        .toList();

    jobs.sort((a, b) => b.postedAt.compareTo(a.postedAt));
    return jobs;
  }

  Future<void> _handleToggleFavorite(Job job, bool newValue) async {
    try {
      await FavoritesService.toggleFavorite(job.jobId, newValue);
    } catch (e) {
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
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final favJobs = _favoriteJobs;

    if (favJobs.isEmpty) {
      return Column(
        children: [
          // Purple curved header with decorative circles
          Container(
            height: 120,
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
                  bottom: -20,
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
                // Page title centered
                const Center(
                  child: Padding(
                    padding: EdgeInsets.only(top: 35),
                    child: Text(
                      'Favorites',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Expanded(
            child: EmptyState(
              icon: Icons.favorite_border,
              title: 'No Favorite Jobs Yet',
              subtitle: 'Jobs you save will appear here',
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        // Purple curved header with decorative circles
        Container(
          height: 120,
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
                bottom: -20,
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
              // Page title centered
              const Center(
                child: Padding(
                  padding: EdgeInsets.only(top: 35),
                  child: Text(
                    'Favorites',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: favJobs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final job = favJobs[index];
              final company = _companies[job.userId] ?? const CompanyInfo();

              return JobCard(
                job: job,
                company: company,
                isSaved: true,
                onSavedChanged: (newValue) {
                  _handleToggleFavorite(job, newValue);
                },
              );
            },
          ),
        ),
      ],
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