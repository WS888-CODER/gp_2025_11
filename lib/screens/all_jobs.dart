import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gp_2025_11/config/themed_scaffold.dart';
import 'package:gp_2025_11/screens/job_card.dart';

const kJobsCollection = 'Jobs';
const kUsersCollection = 'Users';
List<String> kSpecialtyOptions = [
  // --- Technology & IT ---
  "Frontend Development",
  "Backend Development",
  "Full-Stack Development",
  "Mobile Development",
  "Software Engineering",
  "Cybersecurity",
  "Data Science",
  "Data Engineering",
  "Data Analysis",
  "AI / Machine Learning",
  "Cloud / DevOps",
  "IT Support / System Administration",
  "Product Management",
  "UI/UX Design",
  "QA / Testing",

  // --- Engineering ---
  "Engineering",

  // --- Business & Operations ---
  "Business / Operations",
  "Project Management",
  "Supply Chain / Logistics",
  "Procurement",
  "Quality Management",
  "Strategy / Consulting",

  // --- Sales & Marketing ---
  "Sales & Business Development",
  "Digital Marketing",
  "Content Creation / Copywriting",
  "Branding / Creative",
  "Advertising / PR",

  // --- Finance & Legal ---
  "Accounting / Auditing",
  "Finance / Investment",
  "Legal / Compliance",

  // --- HR ---
  "Human Resources",

  // --- Healthcare ---
  "Healthcare / Medical",

  // --- Education ---
  "Teaching / Training",

  // --- Media & Creative ---
  "Media / Journalism",
  "Graphic / Motion Design",
  "Photography / Videography",

  // --- Customer Service ---
  "Customer Support / Service",

  // --- Hospitality ---
  "Hospitality & Tourism",

  // --- Other ---
  "Other",
];

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
  static const website = 'Website';
}

/* ========================== MODEL ========================== */

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
  List<String> _specialties = ['All', ...kSpecialtyOptions];
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
        _specialties = ['All', ...kSpecialtyOptions];
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
        return const <Job>[];
      } else {
        res = res.where((j) => _matchesCvKeywords(j, _profile.cvKeywords));
      }
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
            website: (data[UserDocFields.website] ?? '').toString(),
          );
        }

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
            child: Builder(
              builder: (context) {
                final scheme = Theme.of(context).colorScheme;
                final isDark = Theme.of(context).brightness == Brightness.dark;

                final shadowColor = isDark
                    ? Colors.black.withOpacity(0.6)
                    : Colors.black.withOpacity(0.07);

                return Container(
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
                  child: TextField(
                    controller: _searchController,
                    style: TextStyle(
                      fontSize: 14,
                      color: scheme.onSurface,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search company, title, position or keyword…',
                      hintStyle: TextStyle(
                        color: isDark ? Colors.grey[500] : Colors.grey[500],
                        fontSize: 14,
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                    ),
                    onChanged: (v) {
                      setState(() {
                        _search = v;
                      });
                    },
                  ),
                );
              },
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Builder(
              builder: (context) {
                final scheme = Theme.of(context).colorScheme;
                final isDark = Theme.of(context).brightness == Brightness.dark;

                final cardShadowColor = isDark
                    ? Colors.black.withOpacity(0.5)
                    : Colors.black.withOpacity(0.03);

                return Container(
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: cardShadowColor,
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
                          Expanded(
                            child: _FilterBox(
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  menuMaxHeight: 200,
                                  isDense: true,
                                  isExpanded: true,
                                  value: _selectedSpecialty,
                                  icon: Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    color: scheme.primary,
                                  ),
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  items: _specialties.map((spec) {
                                    final display = spec == 'All'
                                        ? 'All specialties'
                                        : spec;
                                    return DropdownMenuItem<String>(
                                      value: spec,
                                      child: Text(
                                        display,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    if (val == null) return;
                                    setState(() => _selectedSpecialty = val);
                                  },
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(width: 8),

                          // sort
                          Expanded(
                            child: _FilterBox(
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<SortOrder>(
                                  isDense: true,
                                  isExpanded: true,
                                  value: _sort,
                                  icon: Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    color: scheme.primary,
                                  ),
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
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
                              Text(
                                'Show closed',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: scheme.primary,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Theme(
                                data: Theme.of(context).copyWith(
                                  switchTheme: SwitchThemeData(
                                    trackColor:
                                        MaterialStateProperty.resolveWith(
                                            (states) {
                                      if (states
                                          .contains(MaterialState.selected)) {
                                        return scheme.secondary;
                                      } else {
                                        return scheme.surface;
                                      }
                                    }),
                                    thumbColor:
                                        MaterialStateProperty.resolveWith(
                                            (states) {
                                      if (states
                                          .contains(MaterialState.selected)) {
                                        return Colors.white;
                                      } else {
                                        return scheme.primary;
                                      }
                                    }),
                                    trackOutlineColor:
                                        MaterialStateProperty.resolveWith(
                                            (states) {
                                      if (states
                                          .contains(MaterialState.selected)) {
                                        return scheme.secondary;
                                      } else {
                                        return scheme.primary;
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
                        // alert box
                        Builder(
                          builder: (context) {
                            final danger = scheme.secondary;
                            final bgSoft = danger.withOpacity(0.08);

                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: bgSoft,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: danger,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    size: 20,
                                    color: danger,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Complete your profile to get better matches.',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: scheme.onSurface,
                                        height: 1.3,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      minimumSize: const Size(0, 0),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
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
                                    child: Text(
                                      'Open',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: scheme.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                );
              },
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
        Icon(icon, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                    fontSize: 13.5,
                    height: 1.3,
                  ),
              children: [
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
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

class _FilterBox extends StatelessWidget {
  final Widget child;
  const _FilterBox({
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: scheme.primary,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.5 : 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
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
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOn = selected;

    final Color bgColor = isOn ? scheme.secondary : scheme.surface;
    final Color borderColor = isOn ? scheme.secondary : scheme.primary;
    final Color textColor = isOn ? Colors.white : scheme.primary;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onTap(!isOn),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: borderColor,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.6 : 0.04),
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
            color: textColor,
          ),
        ),
      ),
    );
  }
}
