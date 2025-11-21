import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gp_2025_11/config/theme.dart';
import 'package:gp_2025_11/screens/job_card.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  final Map<String, Job> _jobs = {};
  final Map<String, CompanyInfo> _companies = {};
  bool _loading = true;

  StreamSubscription<Set<String>>? _favSub;

  Future<void> _handleToggleFavorite(Job job, bool newValue) async {
    try {
      await FavoritesService.toggleFavorite(job.jobId, newValue);
    } catch (e) {
      if (!mounted) return;
      SnackHelper.error(context, 'Failed to update favorites: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _listenFavorites();
  }

  void _listenFavorites() {
    final userId = FirebaseAuth.instance.currentUser?.uid;

    if (userId == null) {
      setState(() {
        _loading = false;
        _jobs.clear();
        _companies.clear();
      });
      return;
    }

    _favSub =
        FavoritesService.favoritesStream().listen((favoriteJobIdsSet) async {
      try {
        final favoriteJobIds = favoriteJobIdsSet.toList();

        if (favoriteJobIds.isEmpty) {
          if (!mounted) return;
          setState(() {
            _jobs.clear();
            _companies.clear();
            _loading = false;
          });
          return;
        }

        final Map<String, Job> newJobs = {};
        final Map<String, CompanyInfo> newCompanies = {};

        final idsLeft = <String>{...favoriteJobIds};
        for (var i = 0; i < favoriteJobIds.length; i += 10) {
          final chunk = favoriteJobIds.sublist(
            i,
            (i + 10 > favoriteJobIds.length) ? favoriteJobIds.length : i + 10,
          );

          final jobDocs = await FirebaseFirestore.instance
              .collection('Jobs')
              .where(FieldPath.documentId, whereIn: chunk)
              .get();

          for (final doc in jobDocs.docs) {
            final job = Job.fromDoc(doc);
            newJobs[job.jobId] = job;
            idsLeft.remove(doc.id);
          }
        }

        final remaining = idsLeft.toList();
        for (var i = 0; i < remaining.length; i += 10) {
          final chunk = remaining.sublist(
            i,
            (i + 10 > remaining.length) ? remaining.length : i + 10,
          );

          if (chunk.isEmpty) break;

          final jobDocs = await FirebaseFirestore.instance
              .collection('Jobs')
              .where(JobFields.jobId, whereIn: chunk)
              .get();

          for (final doc in jobDocs.docs) {
            final job = Job.fromDoc(doc);
            newJobs[job.jobId] = job;
          }
        }

        final ownerIds = newJobs.values.map((j) => j.userId).toSet().toList();
        for (var i = 0; i < ownerIds.length; i += 10) {
          final chunk = ownerIds.sublist(
            i,
            (i + 10 > ownerIds.length) ? ownerIds.length : i + 10,
          );

          final usersSnap = await FirebaseFirestore.instance
              .collection('Users')
              .where(FieldPath.documentId, whereIn: chunk)
              .get();

          for (final doc in usersSnap.docs) {
            final data = doc.data();
            final rawCompany = (data['CompanyName'] ?? '').toString().trim();
            final rawName = (data['Name'] ?? '').toString().trim();
            final displayName = rawCompany.isNotEmpty
                ? rawCompany
                : (rawName.isNotEmpty ? rawName : 'Company');

            newCompanies[doc.id] = CompanyInfo(
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
            newCompanies.putIfAbsent(id, () => const CompanyInfo());
          }
        }

        if (!mounted) return;
        setState(() {
          _jobs
            ..clear()
            ..addAll(newJobs);
          _companies
            ..clear()
            ..addAll(newCompanies);
          _loading = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() => _loading = false);
        SnackHelper.error(context, 'Error loading favorites: $e');
      }
    }, onError: (e) {
      if (!mounted) return;
      setState(() => _loading = false);

      if (e.toString().contains('permission-denied')) {
        return;
      }

      SnackHelper.error(context, 'Error listening to favorites: $e');
    });
  }

  List<Job> get jobsList =>
      _jobs.values.toList()..sort((a, b) => b.postedAt.compareTo(a.postedAt));

  @override
  void dispose() {
    _favSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_jobs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.favorite_border,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No Favorite Jobs Yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Jobs you save will appear here',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: jobsList.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final job = jobsList[index];
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
