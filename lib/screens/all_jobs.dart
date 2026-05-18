import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gp_2025_11/config/theme.dart';
import 'package:gp_2025_11/screens/favorites.dart';
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
  "QA / Software Testing",

  // --- Engineering ---
  "Mechanical Engineering",
  "Electrical Engineering",
  "Industrial Engineering",
  "Chemical Engineering",
  "Civil Engineering",
  "Petroleum Engineer",

  // --- Business & Operations ---
  "Business Administration",
  "Operations Management",
  "Project Management",
  "Supply Chain & Logistics",
  "Procurement",
  "Quality Management",
  "Strategy & Consulting",

  // --- Sales & Marketing ---
  "Sales",
  "Business Development",
  "Digital Marketing",
  "Content Creation",
  "Copywriting",
  "Branding",
  "Creative Direction",
  "Advertising & Public Relations",

  // --- Finance & Legal ---
  "Accounting",
  "Auditing",
  "Finance & Investment",
  "Legal & Compliance",
  "Risk Management",

  // --- HR ---
  "Human Resources",

  // --- Environment & Safety ---
  "Health, Safety & Environment (HSE)",
  "Environmental Management",

  // --- Manufacturing & Production ---
  "Manufacturing & Production",
  "Quality Assurance (Industrial)",
  "Research & Development (R&D)",

  // --- Media & Creative ---
  "Media & Journalism",
  "Graphic Design",
  "Motion Design",
  "Photography & Videography",

  // --- Customer Service & Admin ---
  "Customer Support",
  "Office Administration",

  // --- Hospitality ---
  "Hospitality & Tourism",

  // --- Education ---
  "Teaching & Training",

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
      .orderBy(JobFields.postedAt, descending: true)
      .snapshots()
      .map((qs) => qs.docs.map((d) => Job.fromDoc(d)).toList());
}

/* ========================== UI ========================== */

enum SortOrder { newestFirst, oldestFirst, byRelevance }

class JobsPage extends StatefulWidget {
  final UserProfile profile;
  final bool autoFocusSearch;

  const JobsPage({
    super.key,
    this.profile = const UserProfile(),
    this.autoFocusSearch = false,
  });

  @override
  State<JobsPage> createState() => _JobsPageState();
}

class _JobsPageState extends State<JobsPage> {
  String _search = '';
  String _selectedSpecialty = 'All';
  SortOrder _sort = SortOrder.newestFirst;
  bool _forYou = false;
  bool _showAllJobs = false;
  bool _showProfileReminder = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  List<String> _specialties = ['All', ...kSpecialtyOptions];
  List<Job> _allJobs = [];

  String _userType = 'JobSeeker';
  UserProfile? _liveProfile;

  StreamSubscription<List<Job>>? _jobsSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _appliedSub;
  StreamSubscription<Set<String>>? _favSub;
  Set<String> _appliedJobIds = {};
  Set<String> _favoriteIds = {};
  final Map<String, CompanyInfo> _company = {};
  bool _loadingCompanies = false;

  Future<void> _handleToggleFavorite(Job job, bool newValue) async {
    setState(() {
      if (newValue) {
        _favoriteIds = {..._favoriteIds, job.jobId};
      } else {
        _favoriteIds = {..._favoriteIds}..remove(job.jobId);
      }
    });
    try {
      await FavoritesService.toggleFavorite(job.jobId, newValue);
    } catch (e) {
      setState(() {
        if (newValue) {
          _favoriteIds = {..._favoriteIds}..remove(job.jobId);
        } else {
          _favoriteIds = {..._favoriteIds, job.jobId};
        }
      });
      if (!mounted) return;
      SnackHelper.error(context, 'Failed to update favorites. Please try again.');
    }
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.autoFocusSearch) {
        _searchFocusNode.requestFocus();
      }
    });

    _jobsSub = _jobsStream().listen((jobs) {
      _ensureCompanyNames(jobs.map((j) => j.userId).toSet());

      if (!mounted) return;
      setState(() {
        _allJobs = jobs;
        _specialties = ['All', ...kSpecialtyOptions];
      });
    });

    _favSub = FavoritesService.favoritesStream().listen((ids) {
      if (!mounted) return;
      setState(() => _favoriteIds = ids);
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
          _liveProfile = UserProfile(
            cvUrl: cv.isEmpty ? null : cv,
            cvKeywords: cvKeys.toSet(),
            hasMinimumInfo: complete,
          );

          final hasCv = cv.isNotEmpty;
          final hasKeywords = cvKeys.isNotEmpty;

          if (!hasCv || !hasKeywords) {
            _forYou = false;
            _showProfileReminder = false;
          } else if (_forYou) {
            _showProfileReminder = false;
          }
        });
      });
    }
  }

  UserProfile get _profile => _liveProfile ?? widget.profile;

  bool _matchesSpecialty(Job j, String specialty) {
    final m = specialty.toLowerCase().trim();
    final spec = j.specialty.toLowerCase().trim();
    final inSpec = spec.contains(m);
    final inTags = j.keywords.any((k) => k.toLowerCase().trim().contains(m));
    return inSpec || inTags;
  }

  int _cvMatchScore(Job j, Set<String> userCvKeywords) {
    if (userCvKeywords.isEmpty) return 0;

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

    for (final kw in userCvKeywords) {
      final cleanKw = kw.toLowerCase().trim();
      if (cleanKw.isEmpty) continue;

      if (jobTokens.contains(cleanKw)) {
        // base match
        score += 2;

        // extra weight if it appears in specialty text
        if (j.specialty.toLowerCase().contains(cleanKw)) {
          score += 1;
        }
      }
    }

    return score;
  }

  bool _matchesCvKeywords(Job j, Set<String> userCvKeywords) {
    return _cvMatchScore(j, userCvKeywords) >= 2;
  }

  List<Job> _applyFilters(List<Job> jobs) {
    Iterable<Job> res = jobs;

    if (!_showAllJobs) {
      res = res.where((j) {
        final s = effectiveJobStatus(j);
        return s == 'Open';
      });
    }

    if (_forYou) {
      final hasCv = _profile.cvUrl != null;
      final hasKeywords = _profile.cvKeywords.isNotEmpty;

      if (!hasCv || !hasKeywords) {
        return const <Job>[];
      }

      res = res.where((j) => _matchesCvKeywords(j, _profile.cvKeywords));
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

    Map<String, int> relevanceScores = {};
    if (_forYou) {
      for (final j in list) {
        relevanceScores[j.jobId] = _cvMatchScore(j, _profile.cvKeywords);
      }
    }

    list.sort((a, b) {
      if (_sort == SortOrder.byRelevance) {
        final scoreA = relevanceScores[a.jobId] ?? 0;
        final scoreB = relevanceScores[b.jobId] ?? 0;
        if (scoreA != scoreB) return scoreB.compareTo(scoreA);
        return b.postedAt.compareTo(a.postedAt);
      }

      return _sort == SortOrder.newestFirst
          ? b.postedAt.compareTo(a.postedAt)
          : a.postedAt.compareTo(b.postedAt);
    });

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
  void dispose() {
    _jobsSub?.cancel();
    _userSub?.cancel();
    _appliedSub?.cancel();
    _favSub?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final jobs = _applyFilters(_allJobs);
    final int filteredCount = jobs.length;

    return ThemedScaffold(
      appBar: const CustomHeader(
        title: 'Jobs',
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
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
                    focusNode: _searchFocusNode,
                    style: TextStyle(
                      fontSize: 14,
                      color: scheme.onSurface,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search company, title or keyword…',
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
                      setState(() => _search = v);
                    },
                  ),
                );
              },
            ),
          ),
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
                                  items: [
                                    if (_forYou)
                                      const DropdownMenuItem(
                                        value: SortOrder.byRelevance,
                                        child: Text('Best match'),
                                      ),
                                    const DropdownMenuItem(
                                      value: SortOrder.newestFirst,
                                      child: Text('Newest first'),
                                    ),
                                    const DropdownMenuItem(
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
                                  _sort = SortOrder.byRelevance;
                                  _search = '';
                                  _searchController.text = '';
                                  _showAllJobs = false;
                                } else {
                                  if (_sort == SortOrder.byRelevance) {
                                    _sort = SortOrder.newestFirst;
                                  }
                                }

                                final hasCv = _profile.cvUrl != null;
                                final hasKeywords =
                                    _profile.cvKeywords.isNotEmpty;

                                _showProfileReminder =
                                    _forYou && (!hasCv || !hasKeywords);
                              });
                            },
                          ),

                          const Spacer(),

                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Show all',
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
                                    value: _showAllJobs,
                                    onChanged: (val) {
                                      setState(() => _showAllJobs = val);
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
                                      'Upload your CV to see personalized matches.',
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
                      Builder(
                        builder: (context) {
                          final scheme = Theme.of(context).colorScheme;
                          final label = filteredCount == 1
                              ? '1 job found'
                              : '$filteredCount jobs found';

                          return Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              label,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: scheme.primary.withOpacity(0.8),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: _allJobs.isEmpty
                ? Center(
                    child: Text(
                      _forYou && _profile.cvUrl == null
                          ? 'Upload your CV to see personalized jobs.'
                          : 'No jobs available.',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  )
                : jobs.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.work_off_rounded,
                              size: 56,
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withOpacity(0.30),
                            ),
                            const SizedBox(height: 16),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 300),
                              child: Text(
                                () {
                                  if (_forYou) {
                                    final hasCv = _profile.cvUrl != null;
                                    final hasKeywords =
                                        _profile.cvKeywords.isNotEmpty;
                                    if (!hasCv) {
                                      return 'Upload your CV to see personalized jobs.';
                                    } else if (!hasKeywords) {
                                      return "We couldn't analyze your CV. Try uploading a clearer version.";
                                    } else {
                                      return 'No strong matches found yet – check All Jobs for more opportunities.';
                                    }
                                  }
                                  return 'No jobs match your filters.';
                                }(),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14.5,
                                  height: 1.45,
                                  fontWeight: FontWeight.w500,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withOpacity(0.75),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: jobs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final j = jobs[i];
                          final info = _company[j.userId] ?? const CompanyInfo();

                          return JobCard(
                            key: ValueKey(j.jobId),
                            job: j,
                            company: info,
                            isSaved: _favoriteIds.contains(j.jobId),
                            isApplied: _appliedJobIds.contains(j.jobId),
                            onSavedChanged: (bool newValue) {
                              _handleToggleFavorite(j, newValue);
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

  const UserProfile({
    this.cvUrl,
    this.cvKeywords = const {},
    this.hasMinimumInfo = false,
  });
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