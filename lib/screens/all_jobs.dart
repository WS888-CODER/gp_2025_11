import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gp_2025_11/config/themed_scaffold.dart';
import 'package:url_launcher/url_launcher.dart';

/* ========================== FIRESTORE CONSTANTS ========================== */

const kJobsCollection = 'Jobs';
const kUsersCollection = 'Users';

class JobFields {
  static const jobId = 'JobID';
  static const title = 'JobTitle';
  static const position = 'Position';
  static const keywords = 'JobKeywords';
  static const startDate = 'StartDate';
  static const endDate = 'EndDate';
  static const description = 'JobDescription';
  static const status = 'JobStatus';
  static const requirements = 'Requirements';
  static const specialty = 'Specialty';
  static const userId = 'UserID';
  static const company =
      'Company'; // not in schema but kept for backward-safety
}

class UserDocFields {
  static const userType = 'UserType';
  static const isProfileComplete = 'IsProfileComplete';
  static const cvUrl = 'CVURL';
  static const name = 'Name';
  static const companyName = 'CompanyName';
  static const cvKeywords = 'CVKeywords';

  static const photoUrl = 'PhotoURL';
  static const location = 'Location';
  static const description = 'Description';
  static const contactEmail = 'ContactEmail';
  static const phone = 'Phone';
}

class CompanyInfo {
  final String name;
  final String logoUrl;
  final String location;
  final String description;
  final String contactEmail;
  final String phone;

  const CompanyInfo({
    this.name = 'Company',
    this.logoUrl = '',
    this.location = '',
    this.description = '',
    this.contactEmail = '',
    this.phone = '',
  });
}

/* ========================== MODEL ========================== */

class Job {
  final String id;
  final String jobId;
  final String title;
  final String position;
  final List<String> keywords;
  final DateTime postedAt;
  final DateTime? endDate;
  final String description;
  final String status;
  final List<String> requirements;
  final String specialty;
  final String userId;

  const Job({
    required this.id,
    required this.jobId,
    required this.title,
    required this.position,
    required this.keywords,
    required this.postedAt,
    this.endDate,
    required this.description,
    required this.status,
    required this.requirements,
    required this.specialty,
    required this.userId,
  });

  factory Job.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};

    DateTime? asDate(dynamic v) =>
        v is Timestamp ? v.toDate() : (v is DateTime ? v : null);

    List<String> asStringList(dynamic v) =>
        v is List ? v.map((e) => e.toString()).toList() : <String>[];

    return Job(
      id: doc.id,
      jobId: (d[JobFields.jobId] ?? '').toString(),
      title: (d[JobFields.title] ?? '').toString(),
      position: (d[JobFields.position] ?? '').toString(),
      keywords: asStringList(d[JobFields.keywords]),
      postedAt: asDate(d[JobFields.startDate]) ?? DateTime.now(),
      endDate: asDate(d[JobFields.endDate]),
      description: (d[JobFields.description] ?? '').toString(),
      status: (d[JobFields.status] ?? '').toString(),
      requirements: asStringList(d[JobFields.requirements]),
      specialty: (d[JobFields.specialty] ?? '').toString(),
      userId: (d[JobFields.userId] ?? '').toString(),
    );
  }
}

/* ========================== DATA STREAM ========================== */

Stream<List<Job>> _jobsStream() {
  return FirebaseFirestore.instance
      .collection(kJobsCollection)
      .orderBy(JobFields.startDate, descending: true)
      .snapshots()
      .map((qs) => qs.docs.map((d) => Job.fromDoc(d)).toList());
}

/* ========================== UI ========================== */

enum SortOrder { newestFirst, oldestFirst }

class JobsPage extends StatefulWidget {
  final UserProfile profile;

  const JobsPage({
    super.key,
    this.profile = const UserProfile(),
  });

  @override
  State<JobsPage> createState() => _JobsPageState();
}

class _JobsPageState extends State<JobsPage> {
  String _search = '';
  String _selectedSpecialty = 'All';
  SortOrder _sort = SortOrder.newestFirst;
  bool _forYou = false;
  bool _showClosedJobs = false;
  bool _showProfileReminder = false;
  final TextEditingController _searchController = TextEditingController();

  late Set<String> _saved;
  List<String> _specialties = ['All'];
  List<Job> _allJobs = [];

  String _userType = 'JobSeeker';
  bool _isProfileComplete = false;
  UserProfile? _liveProfile;

  StreamSubscription<List<Job>>? _jobsSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;
  final Map<String, CompanyInfo> _company = {};
  bool _loadingCompanies = false;

  @override
  void initState() {
    super.initState();
    _saved = {...widget.profile.savedJobIds};

    _jobsSub = _jobsStream().listen((jobs) {
      _ensureCompanyNames(jobs.map((j) => j.userId).toSet());

      if (!mounted) return;
      setState(() {
        _allJobs = jobs;

        _specialties = [
          'All',
          ...{
            for (final j in jobs)
              j.specialty.trim().isEmpty ? null : j.specialty.trim(),
          }.whereType<String>().toList()
        ];
      });
    });

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _userSub = FirebaseFirestore.instance
          .collection(kUsersCollection)
          .doc(uid)
          .snapshots()
          .listen((doc) {
        final d = doc.data() ?? {};
        final type = (d[UserDocFields.userType] ?? 'JobSeeker').toString();
        final complete = d[UserDocFields.isProfileComplete] == true;
        final cv = (d[UserDocFields.cvUrl] ?? '').toString();
        final cvKeys = (d[UserDocFields.cvKeywords] is List)
            ? List<String>.from(
                (d[UserDocFields.cvKeywords] as List).map((e) => e.toString()))
            : <String>[];

        if (!mounted) return;
        setState(() {
          _userType = type;
          _isProfileComplete = complete;
          _liveProfile = UserProfile(
            cvUrl: cv.isEmpty ? null : cv,
            cvKeywords: cvKeys.toSet(),
            hasMinimumInfo: complete,
            savedJobIds: _saved,
          );
        });
      });
    }
  }

  @override
  void dispose() {
    _jobsSub?.cancel();
    _userSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  UserProfile get _profile => _liveProfile ?? widget.profile;

  bool _matchesSpecialty(Job j, String specialty) {
    final m = specialty.toLowerCase().trim();
    final spec = j.specialty.toLowerCase().trim();
    final inSpec = spec.contains(m);
    final inTags = j.keywords.any((k) => k.toLowerCase().trim().contains(m));
    return inSpec || inTags;
  }

  bool _matchesCvKeywords(Job j, Set<String> userCvKeywords) {
    if (userCvKeywords.isEmpty) return false;

    final jobBagRaw = {
      j.specialty.toLowerCase().trim(),
      ...j.keywords.map((k) => k.toLowerCase().trim()),
    };

    final Set<String> jobTokens = {
      for (final chunk in jobBagRaw)
        ...chunk.split(RegExp(r'[^a-z0-9+#]+')).where((t) => t.isNotEmpty)
    };

    int matchCount = 0;

    for (final kw in userCvKeywords) {
      final cleanKw = kw.toLowerCase().trim();
      if (cleanKw.isEmpty) continue;

      if (jobTokens.contains(cleanKw)) {
        matchCount += 1;

        if (matchCount >= 2) {
          return true;
        }
      }
    }

    return false;
  }

  List<Job> _applyFilters(List<Job> jobs) {
    Iterable<Job> res = jobs;

    if (!_showClosedJobs) {
      res = res.where((j) => j.status != 'Closed');
    }

    if (_forYou) {
      if (_profile.cvUrl == null) {
        res = const <Job>[];
      } else {
        res = res.where((j) => _matchesCvKeywords(j, _profile.cvKeywords));
      }

      return res.toList()
        ..sort(
          (a, b) => b.postedAt.compareTo(a.postedAt),
        );
    }

    if (_search.trim().isNotEmpty) {
      final q = _search.toLowerCase();
      res = res.where((j) {
        final compName = _company[j.userId]?.name.toLowerCase() ?? '';
        return j.title.toLowerCase().contains(q) ||
            j.position.toLowerCase().contains(q) ||
            j.specialty.toLowerCase().contains(q) ||
            compName.contains(q) ||
            j.keywords.any((k) => k.toLowerCase().contains(q));
      });
    }

    if (_selectedSpecialty != 'All') {
      res = res.where((j) => _matchesSpecialty(j, _selectedSpecialty));
    }

    final list = res.toList();
    list.sort(
      (a, b) => _sort == SortOrder.newestFirst
          ? b.postedAt.compareTo(a.postedAt)
          : a.postedAt.compareTo(b.postedAt),
    );

    return list;
  }

  Future<void> _ensureCompanyNames(Set<String> uids) async {
    final missing = uids.where((id) => !_company.containsKey(id)).toList();
    if (missing.isEmpty || _loadingCompanies) return;

    if (!mounted) return;
    setState(() => _loadingCompanies = true);

    try {
      // Firestore whereIn يسمح بـ 10 عناصر لكل استعلام
      for (var i = 0; i < missing.length; i += 10) {
        final chunk = missing.sublist(
            i, i + 10 > missing.length ? missing.length : i + 10);

        final qs = await FirebaseFirestore.instance
            .collection(kUsersCollection)
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        for (final doc in qs.docs) {
          final data = doc.data();

          final rawCompany =
              (data[UserDocFields.companyName] ?? '').toString().trim();
          final rawName = (data[UserDocFields.name] ?? '').toString().trim();
          final displayName = rawCompany.isNotEmpty
              ? rawCompany
              : (rawName.isNotEmpty ? rawName : 'Company');

          _company[doc.id] = CompanyInfo(
            name: displayName,
            logoUrl: (data[UserDocFields.photoUrl] ?? '').toString(),
            location: (data[UserDocFields.location] ?? '').toString(),
            description: (data[UserDocFields.description] ?? '').toString(),
            contactEmail: (data[UserDocFields.contactEmail] ?? '').toString(),
            phone: (data[UserDocFields.phone] ?? '').toString(),
          );
        }

        // أي عنصر ما رجع من الكويري نعبّيه باسم افتراضي
        for (final id in chunk) {
          _company.putIfAbsent(id, () => const CompanyInfo());
        }
      }
    } finally {
      if (mounted) setState(() => _loadingCompanies = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final jobs = _applyFilters(_allJobs);

    return ThemedScaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF4A5FBC),
        title: const Text(
          'Jobs',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.07),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search company, title, position or keyword…',
                  hintStyle: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 14,
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    color: Colors.grey[600],
                  ),
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                ),
                onChanged: (v) {
                  setState(() {
                    _search = v;
                  });
                },
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ================= ROW 1: specialty + sort =================
                  Row(
                    children: [
                      // specialty
                      Expanded(
                        child: _FilterBox(
                          borderColor: const Color(0xFF4A5FBC),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isDense: true,
                              isExpanded: true,
                              value: _selectedSpecialty,
                              icon: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: Color(0xFF4A5FBC), // لون السهم بنفسجي
                              ),
                              // ⬇️ لون النص داخل القائمة
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.black,
                                fontWeight: FontWeight.w500,
                              ),
                              // ⬇️ النص المختار بلون بنفسجي واضح
                              selectedItemBuilder: (context) {
                                return _specialties.map((m) {
                                  return Text(
                                    m,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(
                                          0xFF4A5FBC), // ← اللون البنفسجي للنص المختار
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  );
                                }).toList();
                              },
                              items: _specialties
                                  .map(
                                    (m) => DropdownMenuItem(
                                      value: m,
                                      child: Text(
                                        m,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (val) {
                                setState(
                                    () => _selectedSpecialty = val ?? 'All');
                              },
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(width: 8),

                      // sort
                      Expanded(
                        child: _FilterBox(
                          borderColor: const Color(0xFF4A5FBC),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<SortOrder>(
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF4A5FBC),
                                fontWeight: FontWeight.w600,
                              ),
                              isDense: true,
                              isExpanded: true,
                              value: _sort,
                              icon:
                                  const Icon(Icons.keyboard_arrow_down_rounded),
                              items: const [
                                DropdownMenuItem(
                                  value: SortOrder.newestFirst,
                                  child: Text('Newest first'),
                                ),
                                DropdownMenuItem(
                                  value: SortOrder.oldestFirst,
                                  child: Text('Oldest first'),
                                ),
                              ],
                              onChanged: (val) {
                                setState(() => _sort = val!);
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // ================= ROW 2: For You + Show closed =================
                  Row(
                    children: [
                      // For You chip
                      _ForYouChip(
                        selected: _forYou,
                        onTap: (v) {
                          setState(() {
                            _forYou = v;

                            if (v) {
                              _selectedSpecialty = 'All';

                              _sort = SortOrder.newestFirst;

                              _search = '';
                              _searchController.text = '';

                              _showClosedJobs = false;
                            }

                            _showProfileReminder = v && !_isProfileComplete;
                          });
                        },
                      ),

                      const Spacer(),

                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Show closed',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF4A5FBC),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Theme(
                            data: Theme.of(context).copyWith(
                              switchTheme: SwitchThemeData(
                                trackColor:
                                    WidgetStateProperty.resolveWith((states) {
                                  if (states.contains(WidgetState.selected)) {
                                    return const Color(0xFFFD6C67);
                                  } else {
                                    return Colors.white;
                                  }
                                }),
                                thumbColor:
                                    WidgetStateProperty.resolveWith((states) {
                                  if (states.contains(WidgetState.selected)) {
                                    return Colors.white;
                                  } else {
                                    return const Color(0xFF4A5FBC);
                                  }
                                }),
                                trackOutlineColor:
                                    WidgetStateProperty.resolveWith((states) {
                                  if (states.contains(WidgetState.selected)) {
                                    return const Color(0xFFFD6C67);
                                  } else {
                                    return const Color(0xFF4A5FBC);
                                  }
                                }),
                              ),
                            ),
                            child: Transform.scale(
                              scale: 0.9,
                              child: Switch.adaptive(
                                value: _showClosedJobs,
                                onChanged: (val) {
                                  setState(() => _showClosedJobs = val);
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (_showProfileReminder) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3F2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFFD6C67),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.info_outline,
                            size: 20,
                            color: Color(0xFFFD6C67),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Complete your profile to get better matches.',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey[900],
                                height: 1.3,
                              ),
                            ),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              minimumSize: const Size(0, 0),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () {
                              if (_userType == 'Company') {
                                Navigator.pushNamed(
                                    context, '/profile/company');
                              } else {
                                Navigator.pushNamed(
                                    context, '/profile/jobseeker');
                              }
                            },
                            child: const Text(
                              'Open',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF4A5FBC),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: Builder(
              builder: (_) {
                if (_allJobs.isEmpty) {
                  return Center(
                    child: Text(
                      _forYou && _profile.cvUrl == null
                          ? 'Upload your CV to see personalized jobs.'
                          : 'No jobs available.',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  );
                }

                if (jobs.isEmpty) {
                  return Center(
                    child: Text(
                      _forYou && _profile.cvUrl == null
                          ? 'Upload your CV to see personalized jobs.'
                          : 'No jobs match your filters.',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: jobs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final j = jobs[i];
                    final info = _company[j.userId] ?? const CompanyInfo();
                    return JobCard(job: j, company: info);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/* ========================== PROFILE SNAPSHOT MODEL ========================== */

class UserProfile {
  final String? cvUrl;
  final Set<String> cvKeywords;
  final bool hasMinimumInfo;
  final Set<String> savedJobIds;

  const UserProfile({
    this.cvUrl,
    this.cvKeywords = const {},
    this.hasMinimumInfo = false,
    this.savedJobIds = const {},
  });
}

/* ========================== DETAILS PAGE ========================== */

class JobDetailsPage extends StatefulWidget {
  final Job job;
  final CompanyInfo? company;
  const JobDetailsPage({super.key, required this.job, this.company});

  @override
  State<JobDetailsPage> createState() => _JobDetailsPageState();
}

// ===== Helpers داخل JobDetailsPage =====
Widget _infoRow(
  BuildContext ctx, {
  required IconData icon,
  required String label,
  required String value,
}) {
  if (value.trim().isEmpty) return const SizedBox.shrink();

  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.grey[700]),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                    fontSize: 13.5,
                    color: Colors.grey[900],
                    height: 1.3,
                  ),
              children: [
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                TextSpan(text: value),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _ExpandableText extends StatefulWidget {
  final String text;
  final int maxLines;
  const _ExpandableText(this.text, {this.maxLines = 2});
  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    if (widget.text.trim().isEmpty) {
      return const Text('No description provided.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.text,
          maxLines: _expanded ? null : widget.maxLines,
          overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        TextButton(
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            minimumSize: const Size(40, 28),
          ),
          onPressed: () => setState(() => _expanded = !_expanded),
          child: Text(_expanded ? 'Show less' : 'Show more'),
        ),
      ],
    );
  }
}

class _JobDetailsPageState extends State<JobDetailsPage> {
  bool _companyExpanded = false;
  bool _saved = false;

  String _fmtDate(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    final company = widget.company;
    final isClosed = job.status.trim().toLowerCase() == 'closed';

    return ThemedScaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF4A5FBC),
        title: const Text(
          'Job Details',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        iconTheme: const IconThemeData(
          color: Colors.white,
        ),
        actions: [
          IconButton(
            tooltip:
                isClosed ? 'Closed job' : (_saved ? 'Saved' : 'Save for later'),
            onPressed: isClosed
                ? null
                : () {
                    setState(() {
                      _saved = !_saved;
                    });
                  },
            icon: Icon(
              _saved ? Icons.favorite : Icons.favorite_border,
              color:
                  isClosed ? Colors.grey : (_saved ? Colors.red : Colors.white),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.07),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.only(bottom: 8),
          child: FilledButton(
            onPressed: isClosed
                ? null
                : () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Coming soon')),
                    );
                  },
            style: FilledButton.styleFrom(
              backgroundColor:
                  isClosed ? Colors.grey[400] : const Color(0xFF4A5FBC),
              disabledBackgroundColor: Colors.grey[400],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            child: Text(isClosed ? 'Closed' : 'Apply'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Company details card (with truncated/expandable description)
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 2,
            shadowColor: Colors.black.withOpacity(0.05),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundImage: (company?.logoUrl ?? '').isNotEmpty
                        ? NetworkImage(company!.logoUrl)
                        : null,
                    backgroundColor: const Color(0xFFE8E8FF),
                    child: (company?.logoUrl ?? '').isEmpty
                        ? const Icon(Icons.business, size: 28)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                (company?.name ?? 'Company'),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: isClosed
                                      ? Colors.grey[600]
                                      : const Color(0xFF4A5FBC),
                                ),
                              ),
                            ),
                            if (isClosed)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
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
                          ],
                        ),
                        if ((company?.location ?? '').isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.location_on_outlined,
                                  size: 14, color: Colors.grey[600]),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  company!.location,
                                  style: TextStyle(
                                    color: Colors.grey[700],
                                    fontSize: 13,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if ((company?.description ?? '').isNotEmpty) ...[
                          const SizedBox(height: 8),
                          AnimatedCrossFade(
                            firstChild: Text(
                              company!.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[800],
                                height: 1.35,
                              ),
                            ),
                            secondChild: Text(
                              company.description,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[800],
                                height: 1.35,
                              ),
                            ),
                            crossFadeState: _companyExpanded
                                ? CrossFadeState.showSecond
                                : CrossFadeState.showFirst,
                            duration: const Duration(milliseconds: 200),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(40, 24),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () => setState(
                                () => _companyExpanded = !_companyExpanded),
                            child: Text(
                              _companyExpanded ? 'Show less' : 'Show more',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 12,
                          runSpacing: 6,
                          children: [
                            if ((company?.contactEmail ?? '').isNotEmpty)
                              InkWell(
                                onTap: () {
                                  final uri = Uri(
                                    scheme: 'mailto',
                                    path: company!.contactEmail,
                                  );
                                  launchUrl(uri,
                                      mode: LaunchMode.externalApplication);
                                },
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.email, size: 16),
                                    const SizedBox(width: 4),
                                    Text(
                                      company!.contactEmail,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                            if ((company?.phone ?? '').isNotEmpty)
                              InkWell(
                                onTap: () {
                                  final uri =
                                      Uri(scheme: 'tel', path: company!.phone);
                                  launchUrl(uri,
                                      mode: LaunchMode.externalApplication);
                                },
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.phone, size: 16),
                                    const SizedBox(width: 4),
                                    Text(
                                      company!.phone,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

// ===== Job Summary (Clear & Explicit) =====
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 2,
            shadowColor: Colors.black.withOpacity(0.05),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    job.title.isEmpty ? 'Untitled Job' : job.title,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: isClosed ? Colors.grey[700] : Colors.black,
                      height: 1.2,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  _infoRow(
                    context,
                    icon: Icons.local_offer_outlined,
                    label: 'Specialty',
                    value: job.specialty.isEmpty ? '—' : job.specialty,
                  ),
                  _infoRow(
                    context,
                    icon: Icons.work_outline,
                    label: 'Position',
                    value: job.position.isEmpty ? '—' : job.position,
                  ),
                  _infoRow(
                    context,
                    icon: Icons.calendar_today,
                    label: 'Posted',
                    value: _fmtDate(job.postedAt),
                  ),
                  if (job.endDate != null)
                    _infoRow(
                      context,
                      icon: Icons.event_available,
                      label: 'Ends',
                      value: _fmtDate(job.endDate!),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

// ===== Description (Expandable) =====
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Job Description',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  _ExpandableText(
                    job.description.isEmpty
                        ? 'No description provided.'
                        : job.description,
                    maxLines: 3, // سويها 2 أو 3 حسب مزاجك
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

// ===== Requirements (Bullet list) =====
          if (job.requirements.isNotEmpty)
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Requirements',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: job.requirements.map((r) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.check_circle_outline, size: 18),
                              const SizedBox(width: 8),
                              Expanded(child: Text(r)),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/* ========================== JOB CARD WIDGET ========================== */

class JobCard extends StatefulWidget {
  final Job job;
  final CompanyInfo company;

  const JobCard({
    super.key,
    required this.job,
    required this.company,
  });

  @override
  State<JobCard> createState() => _JobCardState();
}

class _JobCardState extends State<JobCard> {
  bool _saved = false;

  String _fmtDate(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    final company = widget.company;
    final isClosed = job.status.trim().toLowerCase() == 'closed';

    return Card(
      elevation: 0.5,
      color: isClosed ? Colors.grey[200] : null,
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
              // ===== Header: Logo + Company name + Favorite =====
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

                  // زر المفضلة (قلب)
                  IconButton(
                    tooltip: isClosed
                        ? 'Closed job'
                        : (_saved ? 'Saved' : 'Save for later'),
                    onPressed: isClosed
                        ? null
                        : () {
                            setState(() {
                              _saved = !_saved;
                            });
                          },
                    icon: Icon(
                      _saved ? Icons.favorite : Icons.favorite_border,
                      color: isClosed
                          ? Colors.grey
                          : (_saved ? Colors.red : Colors.grey[600]),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // ===== Job title =====
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

              // ===== Posted date =====
              Text(
                'Posted: ${_fmtDate(job.postedAt)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isClosed ? Colors.grey[600] : null,
                    ),
              ),

              const SizedBox(height: 12),

              // ===== Bottom row: Specialty or Closed badge =====
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
                  FilledButton(
                    onPressed: isClosed
                        ? null
                        : () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Coming soon'),
                              ),
                            );
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          isClosed ? Colors.grey[400] : const Color(0xFF4A5FBC),
                      disabledBackgroundColor: Colors.grey[400],
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    child: Text(
                      isClosed ? 'Closed' : 'Apply',
                      style: const TextStyle(
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

class _FilterBox extends StatelessWidget {
  final Widget child;
  final Color borderColor;
  const _FilterBox({
    required this.child,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: borderColor,
          width: 1,
        ),
      ),
      child: child,
    );
  }
}

class _ForYouChip extends StatelessWidget {
  final bool selected;
  final ValueChanged<bool> onTap;
  const _ForYouChip({
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isOn = selected;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onTap(!isOn),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isOn ? const Color(0xFFFD6C67) : const Color(0xFFFAFAFA),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isOn ? const Color(0xFFFD6C67) : const Color(0xFF4A5FBC),
            width: 1.3,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          'For You',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isOn ? Colors.white : const Color(0xFF4A5FBC),
          ),
        ),
      ),
    );
  }
}
