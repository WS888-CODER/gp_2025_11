import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gp_2025_11/config/themed_scaffold.dart';
import 'package:gp_2025_11/screens/all_jobs.dart';

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
        // لا توجد مفضلات
        if (favSnapshot.docs.isEmpty) {
          if (!mounted) return;
          setState(() {
            _jobs.clear();
            _companies.clear();
            _loading = false;
          });
          return;
        }

        // IDs بدون تكرار
        // IDs بدون تكرار + trim
        final favoriteJobIds = favSnapshot.docs
            .map((d) => (d.data()['JobID'] ?? '').toString().trim())
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList();

        final Map<String, Job> newJobs = {};
        final Map<String, CompanyInfo> newCompanies = {};

// ---- الطور الأول: documentId whereIn ----
        final idsLeft = <String>{...favoriteJobIds}; // سنحذف منها اللي لقيناه
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
            newJobs[job.jobId] = job; // مفتاحنا الموحّد = doc.id
            idsLeft.remove(doc.id); // لقيناه بالـdocId
          }
        }

// ---- الطور الثاني (fallback): الحقل JobID whereIn لأي IDs ما رجعت ----
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
            newJobs[job.jobId] = job; // نفس المفتاح
          }
        }

        // حمّل بيانات الشركات لأصحاب هذه الوظائف
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
            );
          }

          // ضعي قيَم افتراضية لأي مالك لم يرجع
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

  Future<void> _removeFromFavorites(String jobId) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    try {
      final docId = '${userId}_$jobId';
      await FirebaseFirestore.instance
          .collection('Favourite')
          .doc(docId)
          .delete();

      if (!mounted) return; // <-- مهم
      SnackHelper.success(context, 'Removed from favorites');
    } catch (e) {
      if (!mounted) return; // <-- مهم
      SnackHelper.error(context, 'Failed to remove from favorites');
    }
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
                      return _FavoriteJobCard(
                        job: job,
                        company: company,
                        onRemove: () => _removeFromFavorites(job.jobId),
                      );
                    },
                  ));
  }
}

class _FavoriteJobCard extends StatelessWidget {
  final Job job;
  final CompanyInfo company;
  final VoidCallback onRemove;

  const _FavoriteJobCard({
    required this.job,
    required this.company,
    required this.onRemove,
  });

  String _fmtDate(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final isClosed = job.status.trim().toLowerCase() == 'closed';

    return Card(
      elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => JobDetailsPage(
                job: job,
                company: company,
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
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundImage: company.logoUrl.isNotEmpty
                        ? NetworkImage(company.logoUrl)
                        : null,
                    child: company.logoUrl.isEmpty
                        ? const Icon(Icons.business, size: 20)
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      company.name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isClosed
                            ? Colors.grey[600]
                            : const Color(0xFF4A5FBC),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove from favorites',
                    onPressed: onRemove,
                    icon: const Icon(
                      Icons.favorite,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                job.title.isEmpty ? 'Untitled Job' : job.title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: isClosed ? Colors.grey[600] : null,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                'Posted: ${_fmtDate(job.postedAt)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isClosed ? Colors.grey[600] : null,
                    ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (job.specialty.isNotEmpty && !isClosed)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: const Color(0xFF4A5FBC).withOpacity(.08),
                      ),
                      child: Text(
                        job.specialty,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF4A5FBC),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (isClosed)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.grey[500],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Closed',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => JobDetailsPage(
                            job: job,
                            company: company,
                          ),
                        ),
                      );
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF4A5FBC),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                    child: const Text(
                      'View Details',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SnackHelper {
  // ✅ Success message
  static void success(BuildContext context, String message) {
    _show(
      context,
      message,
      const Color(0xFF4CAF50), // Green
    );
  }

  // ✅ Error message
  static void error(BuildContext context, String message) {
    _show(
      context,
      message,
      const Color(0xFFFF7B7B), // Red
    );
  }

  // ✅ Base snack builder
  static void _show(BuildContext context, String message, Color color) {
    if (context.mounted == false) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        backgroundColor: color.withOpacity(0.8),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}
