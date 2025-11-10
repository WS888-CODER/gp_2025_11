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

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
  final userId = FirebaseAuth.instance.currentUser?.uid;
  if (userId == null) {
    setState(() => _loading = false);
    return;
  }

  try {
    // Get all favorite documents for this user (no index needed!)
    final favSnapshot = await FirebaseFirestore.instance
        .collection('Favourite')
        .where('UserID', isEqualTo: userId)
        .get();

    if (favSnapshot.docs.isEmpty) {
      setState(() => _loading = false);
      return;
    }

    // Extract job IDs
    final favoriteJobIds = favSnapshot.docs
        .map((doc) => (doc.data()['JobID'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toList();

    if (favoriteJobIds.isEmpty) {
      setState(() => _loading = false);
      return;
    }

    // Fetch job details in batches
    for (var i = 0; i < favoriteJobIds.length; i += 10) {
      final chunk = favoriteJobIds.sublist(
        i,
        i + 10 > favoriteJobIds.length ? favoriteJobIds.length : i + 10,
      );

      final jobDocs = await FirebaseFirestore.instance
          .collection('Jobs')
          .where('JobID', whereIn: chunk)
          .get();

      for (final doc in jobDocs.docs) {
        final job = Job.fromDoc(doc);
        _jobs[job.jobId] = job;

        // Fetch company info
        if (!_companies.containsKey(job.userId)) {
          final companyDoc = await FirebaseFirestore.instance
              .collection('Users')
              .doc(job.userId)
              .get();

          if (companyDoc.exists) {
            final data = companyDoc.data()!;
            final rawCompany = (data['CompanyName'] ?? '').toString().trim();
            final rawName = (data['Name'] ?? '').toString().trim();
            final displayName = rawCompany.isNotEmpty
                ? rawCompany
                : (rawName.isNotEmpty ? rawName : 'Company');

            _companies[job.userId] = CompanyInfo(
              name: displayName,
              logoUrl: (data['PhotoURL'] ?? '').toString(),
              location: (data['Location'] ?? '').toString(),
              description: (data['Description'] ?? '').toString(),
              contactEmail: (data['ContactEmail'] ?? '').toString(),
              phone: (data['Phone'] ?? '').toString(),
            );
          }
        }
      }
    }

    setState(() => _loading = false);
  } catch (e) {
    print('❌ ERROR LOADING FAVORITES: $e');
    setState(() => _loading = false);
    _showError('Error loading favorites: $e');
  }
}

  Future<void> _removeFromFavorites(String jobId) async {
  final userId = FirebaseAuth.instance.currentUser?.uid;
  if (userId == null) return;

  try {
    final docId = '${userId}_$jobId';
    await FirebaseFirestore.instance.collection('Favourite').doc(docId).delete();

    setState(() {
      _jobs.remove(jobId);
    });

    _showSuccess('Removed from favorites');
  } catch (e) {
    print('❌ ERROR REMOVING: $e');
    _showError('Failed to remove from favorites');
  }
}

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
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
                  itemCount: _jobs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final job = _jobs.values.elementAt(index);
                    final company = _companies[job.userId] ?? const CompanyInfo();
                    return _FavoriteJobCard(
                      job: job,
                      company: company,
                      onRemove: () => _removeFromFavorites(job.jobId),
                    );
                  },
                ),
    );
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
    final scheme = Theme.of(context).colorScheme;

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