import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gp_2025_11/config/theme.dart';
import 'package:gp_2025_11/config/themed_scaffold.dart';
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
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _favSub;

  @override
  void initState() {
    super.initState();
    _listenFavorites();
  }

  void _listenFavorites() {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      setState(() => _loading = false);
      return;
    }

    _favSub = FirebaseFirestore.instance
        .collection('Favourite')
        .where('UserID', isEqualTo: userId)
        .snapshots()
        .listen((favSnapshot) async {
      try {
        if (favSnapshot.docs.isEmpty) {
          if (!mounted) return;
          setState(() {
            _jobs.clear();
            _companies.clear();
            _loading = false;
          });
          return;
        }

        final favoriteJobIds = favSnapshot.docs
            .map((d) => (d.data()['JobID'] ?? '').toString().trim())
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList();

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
              website: (data['Website'] ?? '').toString(), // 👈 أضف هذي
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
    return ThemedScaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF4A5FBC),
          title: const Text(
            'Favorites',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _jobs.isEmpty
                ? Center(
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
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: jobsList.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final job = jobsList[index];
                      final company =
                          _companies[job.userId] ?? const CompanyInfo();
                      return JobCard(
                        job: job,
                        company: company,
                        isSaved: true,
                      );
                    },
                  ));
  }
}
