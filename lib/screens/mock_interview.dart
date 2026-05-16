import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:gp_2025_11/config/theme.dart';
import 'package:gp_2025_11/screens/jobseeker_home.dart';
import 'package:gp_2025_11/screens/mock_interview_report.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:http/http.dart' as http;

String _normalizeSpecialtyForFunction(String specialty) {
  final s = specialty.toLowerCase();

  // --- Cybersecurity ---
  if (s.contains('cybersecurity')) return 'cybersecurity';

  // --- Data / AI ---
  if (s.contains('data') ||
      s.contains('ai') ||
      s.contains('machine learning')) {
    return 'data & artificial intelligence';
  }

  // --- Engineering ---
  if (s.contains('engineering') ||
      s.contains('civil') ||
      s.contains('mechanical') ||
      s.contains('electrical') ||
      s.contains('chemical') ||
      s.contains('industrial') ||
      s.contains('petroleum')) {
    return 'engineering';
  }

  // --- Marketing / Media ---
  if (s.contains('marketing') ||
      s.contains('content') ||
      s.contains('copywriting') ||
      s.contains('branding') ||
      s.contains('advertising') ||
      s.contains('public relations') ||
      s.contains('media') ||
      s.contains('journalism') ||
      s.contains('photography') ||
      s.contains('videography') ||
      s.contains('motion') ||
      s.contains('graphic')) {
    return 'media & communication';
  }

  // --- Finance & Accounting ---
  if (s.contains('accounting') ||
      s.contains('auditing') ||
      s.contains('finance') ||
      s.contains('investment') ||
      s.contains('risk')) {
    return 'finance & accounting';
  }

  // --- HR ---
  if (s.contains('human resources') || s == 'hr') return 'human resources';

  // --- Law ---
  if (s.contains('legal') || s.contains('compliance')) return 'law';

  // --- Education ---
  if (s.contains('teaching') || s.contains('training')) return 'education';

  // --- Default (Tech/IT + Business/Operations + others)
  if (s.contains('business') ||
      s.contains('operations') ||
      s.contains('project') ||
      s.contains('supply chain') ||
      s.contains('procurement') ||
      s.contains('strategy')) {
    return 'business administration';
  }

  return 'computer & information technology';
}

Future<List<String>> _fetchMockQuestionsFromFunction(String specialty) async {
  final raw = _normalizeSpecialtyForFunction(specialty);

  final resp = await http.post(
    Uri.parse(
        'https://us-central1-jadeer-b4953.cloudfunctions.net/generateMockInterviewQuestions'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'specialty': raw, 'count': 10}),
  );

  final data = jsonDecode(resp.body);
  final list = (data['questions'] as List?) ?? [];
  return list.map((q) => q['text'].toString()).toList();
}

class MockInterviewSpecialtyScreen extends StatefulWidget {
  const MockInterviewSpecialtyScreen({super.key});

  @override
  State<MockInterviewSpecialtyScreen> createState() =>
      _MockInterviewSpecialtyScreenState();
}

class _MockInterviewSpecialtyScreenState
    extends State<MockInterviewSpecialtyScreen> {
  Widget _buildStartingInterviewLoading() {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      color: scheme.background,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(
              'Preparing your interview...\nThis may take a moment.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isStartingInterview = false;
  String _activeSection = 'All';
  final Set<String> _expandedSections = {};

  final TextEditingController _search = TextEditingController();
  String _query = '';
  String? _selected;

  // ✅ Sections: general category -> sub-specialties
  static const Map<String, List<String>> _specialtySections = {
    // --- Technology & IT ---
    "Technology & IT": [
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
    ],

    // --- Engineering ---
    "Engineering": [
      "Mechanical Engineering",
      "Electrical Engineering",
      "Industrial Engineering",
      "Chemical Engineering",
      "Civil Engineering",
      "Petroleum Engineer",
    ],

    // --- Business & Operations ---
    "Business & Operations": [
      "Business Administration",
      "Operations Management",
      "Project Management",
      "Supply Chain & Logistics",
      "Procurement",
      "Quality Management",
      "Strategy & Consulting",
    ],

    // --- Sales & Marketing ---
    "Sales & Marketing": [
      "Sales",
      "Business Development",
      "Digital Marketing",
      "Content Creation",
      "Copywriting",
      "Branding",
      "Creative Direction",
      "Advertising & Public Relations",
    ],

    // --- Finance & Legal ---
    "Finance & Legal": [
      "Accounting",
      "Auditing",
      "Finance & Investment",
      "Legal & Compliance",
      "Risk Management",
    ],

    // --- HR ---
    "HR": [
      "Human Resources",
    ],

    // --- Environment & Safety ---
    "Environment & Safety": [
      "Health, Safety & Environment (HSE)",
      "Environmental Management",
    ],

    // --- Manufacturing & Production ---
    "Manufacturing & Production": [
      "Manufacturing & Production",
      "Quality Assurance (Industrial)",
      "Research & Development (R&D)",
    ],

    // --- Media & Creative ---
    "Media & Creative": [
      "Media & Journalism",
      "Graphic Design",
      "Motion Design",
      "Photography & Videography",
    ],

    // --- Customer Service & Admin ---
    "Customer Service & Admin": [
      "Customer Support",
      "Office Administration",
    ],

    // --- Hospitality ---
    "Hospitality": [
      "Hospitality & Tourism",
    ],

    // --- Education ---
    "Education": [
      "Teaching & Training",
    ],
  };

  Future<bool> consumeMockInterviewCredit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final userDocRef =
        FirebaseFirestore.instance.collection('Users').doc(user.uid);

    return FirebaseFirestore.instance.runTransaction<bool>((tx) async {
      final snap = await tx.get(userDocRef);
      final data = snap.data() ?? {};
      final aiUsage = (data['AiUsage'] as Map<String, dynamic>?) ?? {};

      int credits = (aiUsage['MockInterview'] ?? 2) as int;

      if (credits <= 0) return false;

      tx.update(userDocRef, {
        'AiUsage.MockInterview': credits - 1,
      });

      return true;
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  int _mockInterviewCredits = 0;
  bool _loadingCredits = true;
  @override
  void initState() {
    super.initState();
    _loadCredits();
  }

  Future<void> _loadCredits() async {
    setState(() => _loadingCredits = true);
    final usage = await fetchAndResetAiUsageIfNeeded();
    if (!mounted) return;
    setState(() {
      _mockInterviewCredits = usage['MockInterview'] ?? 0;
      _loadingCredits = false;
    });
  }

  Widget _buildMockCreditsInfo() {
    if (_loadingCredits) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF4A5FBC).withOpacity(0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFF4A5FBC).withOpacity(0.25),
            width: 1,
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('Loading credits...'),
          ],
        ),
      );
    }

    final hasCredits = _mockInterviewCredits > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: hasCredits
            ? const Color(0xFF4A5FBC).withOpacity(0.10)
            : Colors.red.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasCredits
              ? const Color(0xFF4A5FBC).withOpacity(0.25)
              : Colors.red.withOpacity(0.25),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            hasCredits ? Icons.auto_awesome : Icons.warning_rounded,
            color: hasCredits ? const Color(0xFF4A5FBC) : Colors.red,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasCredits
                      ? 'Mock Interview Credits'
                      : 'No Credits Remaining',
                  style: TextStyle(
                    color: hasCredits ? const Color(0xFF4A5FBC) : Colors.red,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasCredits
                      ? '$_mockInterviewCredits ${_mockInterviewCredits == 1 ? 'credit' : 'credits'} remaining today'
                      : 'Credits reset daily at midnight',
                  style: TextStyle(
                    color: hasCredits
                        ? const Color(0xFF4A5FBC).withOpacity(0.75)
                        : Colors.red.withOpacity(0.75),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final q = _query.toLowerCase().trim();

    final allSections = _specialtySections.keys.toList();
    final sectionOptions = ['All', ...allSections];

    Map<String, List<String>> filteredMap = {};

    for (final entry in _specialtySections.entries) {
      final sectionTitle = entry.key;
      final items = entry.value.where((item) {
        if (q.isEmpty) return true;
        return item.toLowerCase().contains(q) ||
            sectionTitle.toLowerCase().contains(q);
      }).toList();

      if (items.isNotEmpty) filteredMap[sectionTitle] = items;
    }

// apply active section filter
    if (_activeSection != 'All') {
      filteredMap = filteredMap.containsKey(_activeSection)
          ? {_activeSection: filteredMap[_activeSection]!}
          : {};
    }

    final shadowColor =
        isDark ? Colors.black.withOpacity(0.6) : Colors.black.withOpacity(0.07);
    final canContinue = _selected != null &&
        !_loadingCredits &&
        _mockInterviewCredits > 0 &&
        !_isStartingInterview;

    return PopScope(
        canPop: !_isStartingInterview,
        child: ThemedScaffold(
          appBar: CustomHeader(
            title: 'Choose your specialty',
            showBack: !_isStartingInterview,
          ),

          body: _isStartingInterview
              ? _buildStartingInterviewLoading()
              : Container(
                  color: isDark ? scheme.background : const Color(0xFFF5F5F5),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _buildMockCreditsInfo(),
                        const SizedBox(height: 12),
                        // Search
                        Container(
                          decoration: BoxDecoration(
                            color: isDark ? scheme.surface : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: shadowColor,
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          child: Row(
                            children: [
                              Icon(
                                Icons.search,
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: _search,
                                  onChanged: (v) => setState(() => _query = v),
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: isDark
                                        ? scheme.onSurface
                                        : Colors.black87,
                                  ),
                                  decoration: InputDecoration(
                                    border: InputBorder.none,
                                    isDense: true,
                                    hintText:
                                        'Search specialty, e.g. Marketing…',
                                    hintStyle: TextStyle(
                                      fontSize: 15,
                                      color: isDark
                                          ? Colors.grey[400]
                                          : Colors.grey[500],
                                    ),
                                  ),
                                ),
                              ),
                              if (_query.trim().isNotEmpty)
                                GestureDetector(
                                  onTap: () {
                                    _search.clear();
                                    setState(() => _query = '');
                                  },
                                  child: Icon(
                                    Icons.close,
                                    size: 20,
                                    color: isDark
                                        ? Colors.grey[400]
                                        : Colors.grey[600],
                                  ),
                                ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 40,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: sectionOptions.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(width: 8),
                                  itemBuilder: (_, i) {
                                    final s = sectionOptions[i];
                                    final selected = _activeSection == s;

                                    return ChoiceChip(
                                      label: Text(
                                        s,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: selected
                                              ? Colors.white
                                              : (isDark
                                                  ? scheme.onSurface
                                                  : Colors.black87),
                                        ),
                                      ),
                                      selected: selected,
                                      onSelected: (_) => setState(() {
                                        _activeSection = s;
                                        if (s != 'All')
                                          _expandedSections.add(s);
                                      }),
                                      selectedColor: const Color(0xFF4A5FBC),
                                      backgroundColor: isDark
                                          ? scheme.surface
                                          : Colors.white,
                                      shape: StadiumBorder(
                                        side: BorderSide(
                                          width: 2.0,
                                          color: selected
                                              ? const Color(0xFF4A5FBC)
                                              : (isDark
                                                  ? scheme.onSurface
                                                      .withOpacity(0.15)
                                                  : const Color(0xFF4A5FBC)),
                                        ),
                                      ),
                                      showCheckmark: false,
                                    );
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        // List
                        Expanded(
                          child: filteredMap.isEmpty
                              ? const EmptyState(
                                  icon: Icons.manage_search,
                                  title: 'No specialties found',
                                  subtitle: 'Try a different keyword.',
                                )
                              : ListView(
                                  children: filteredMap.entries.map((section) {
                                    final sectionTitle = section.key;
                                    final items = section.value;

                                    final expanded = _expandedSections
                                        .contains(sectionTitle);

                                    return AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 180),
                                      curve: Curves.easeOut,
                                      margin: const EdgeInsets.only(bottom: 12),
                                      decoration: BoxDecoration(
                                        color: scheme.surface,
                                        borderRadius: BorderRadius.circular(16),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(
                                              Theme.of(context).brightness ==
                                                      Brightness.dark
                                                  ? 0.12
                                                  : 0.05,
                                            ),
                                            blurRadius: 12,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        children: [
                                          // ✅ Section header (tap to expand)
                                          InkWell(
                                            borderRadius:
                                                BorderRadius.circular(18),
                                            onTap: () {
                                              setState(() {
                                                if (expanded) {
                                                  _expandedSections
                                                      .remove(sectionTitle);
                                                } else {
                                                  _expandedSections
                                                      .add(sectionTitle);
                                                }
                                              });
                                            },
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 14,
                                                      vertical: 14),
                                              child: Row(
                                                children: [
                                                  Container(
                                                    width: 40,
                                                    height: 40,
                                                    decoration: BoxDecoration(
                                                      shape: BoxShape.circle,
                                                      color: const Color(
                                                              0xFF4A5FBC)
                                                          .withOpacity(isDark
                                                              ? 0.22
                                                              : 0.12),
                                                    ),
                                                    child: const Icon(
                                                        Icons.grid_view_rounded,
                                                        color:
                                                            Color(0xFF4A5FBC)),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    child: Text(
                                                      sectionTitle,
                                                      style: TextStyle(
                                                        fontSize: 15,
                                                        fontWeight:
                                                            FontWeight.w900,
                                                        color: isDark
                                                            ? scheme.onSurface
                                                            : Colors.black87,
                                                      ),
                                                    ),
                                                  ),
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 10,
                                                        vertical: 6),
                                                    decoration: BoxDecoration(
                                                      color: expanded
                                                          ? const Color(
                                                                  0xFF4A5FBC)
                                                              .withOpacity(0.12)
                                                          : (isDark
                                                              ? scheme.onSurface
                                                                  .withOpacity(
                                                                      0.06)
                                                              : Colors.black
                                                                  .withOpacity(
                                                                      0.05)),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              999),
                                                    ),
                                                    child: Row(
                                                      children: [
                                                        Icon(
                                                          expanded
                                                              ? Icons
                                                                  .keyboard_arrow_up
                                                              : Icons
                                                                  .keyboard_arrow_down,
                                                          color: const Color(
                                                              0xFF4A5FBC),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),

                                          // ✅ Expand content
                                          AnimatedCrossFade(
                                            duration: const Duration(
                                                milliseconds: 180),
                                            crossFadeState: expanded
                                                ? CrossFadeState.showFirst
                                                : CrossFadeState.showSecond,
                                            firstChild: Padding(
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                      10, 0, 10, 12),
                                              child: Column(
                                                children: items.map((title) {
                                                  final selected =
                                                      _selected == title;

                                                  return InkWell(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            14),
                                                    onTap: () => setState(() =>
                                                        _selected = title),
                                                    child: AnimatedContainer(
                                                      duration: const Duration(
                                                          milliseconds: 150),
                                                      curve: Curves.easeOut,
                                                      margin:
                                                          const EdgeInsets.only(
                                                              top: 8),
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 12,
                                                          vertical: 12),
                                                      decoration: BoxDecoration(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(14),
                                                        color: selected
                                                            ? const Color(
                                                                    0xFF4A5FBC)
                                                                .withOpacity(
                                                                    isDark
                                                                        ? 0.22
                                                                        : 0.10)
                                                            : (isDark
                                                                ? scheme.surface
                                                                : const Color(
                                                                    0xFFF9F9F9)),
                                                        border: Border.all(
                                                          color: selected
                                                              ? const Color(
                                                                  0xFF4A5FBC)
                                                              : (isDark
                                                                  ? scheme
                                                                      .onSurface
                                                                      .withOpacity(
                                                                          0.10)
                                                                  : Colors.black
                                                                      .withOpacity(
                                                                          0.06)),
                                                        ),
                                                      ),
                                                      child: Row(
                                                        children: [
                                                          Container(
                                                            width: 36,
                                                            height: 36,
                                                            decoration:
                                                                BoxDecoration(
                                                              shape: BoxShape
                                                                  .circle,
                                                              color: selected
                                                                  ? const Color(
                                                                      0xFF4A5FBC)
                                                                  : const Color(
                                                                          0xFF4A5FBC)
                                                                      .withOpacity(
                                                                          0.12),
                                                            ),
                                                            child: Icon(
                                                              Icons
                                                                  .business_center_outlined,
                                                              color: selected
                                                                  ? Colors.white
                                                                  : const Color(
                                                                      0xFF4A5FBC),
                                                              size: 20,
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                              width: 12),
                                                          Expanded(
                                                            child: Text(
                                                              title,
                                                              style: TextStyle(
                                                                fontSize: 14.5,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w800,
                                                                color: isDark
                                                                    ? scheme
                                                                        .onSurface
                                                                    : Colors
                                                                        .black87,
                                                              ),
                                                            ),
                                                          ),
                                                          if (selected)
                                                            const Icon(
                                                                Icons
                                                                    .check_circle,
                                                                color: Color(
                                                                    0xFF4A5FBC)),
                                                        ],
                                                      ),
                                                    ),
                                                  );
                                                }).toList(),
                                              ),
                                            ),
                                            secondChild:
                                                const SizedBox.shrink(),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
          // Continue button

          bottomNavigationBar: _isStartingInterview
              ? const SizedBox.shrink()
              : SafeArea(
                  minimum: const EdgeInsets.symmetric(horizontal: 16).copyWith(
                    bottom: 30,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton(
                      onPressed: canContinue
                          ? () => _confirmPermissionsThenStart(_selected!)
                          : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF4A5FBC),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      child: _isStartingInterview
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Continue',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w700),
                            ),
                    ),
                  ),
                ),
        ));
  }

  Future<void> _confirmPermissionsThenStart(String specialty) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return const JadeerDialog<bool>(
          title: 'Camera & Microphone Access',
          content: Text(
            'To record your interview answers, Jadeer needs permission to:\n\n'
            'Use your camera\n'
            'Use your microphone\n\n'
            'Your privacy is important to us. Recordings are only used to generate your interview report.',
          ),
          primaryLabel: 'Allow Access',
          primaryResult: true,
          secondaryLabel: 'Cancel',
          secondaryResult: false,
        );
      },
    );

    if (ok != true) return;

    await _startMockInterviewFlow(specialty);
  }

  Future<void> _startMockInterviewFlow(String specialty) async {
    if (_isStartingInterview) return;

    if (!mounted) return;
    setState(() => _isStartingInterview = true);

    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      if (!mounted) return;
      setState(() => _isStartingInterview = false);
      SnackHelper.error(context, 'Please login again.');
      return;
    }
    try {
      // 1) reset if needed
      final usage = await fetchAndResetAiUsageIfNeeded();
      if (!mounted) return;
      setState(() {
        _mockInterviewCredits = usage['MockInterview'] ?? _mockInterviewCredits;
      });

      // 2) consume credit
      final ok = await consumeMockInterviewCredit();
      if (!ok) {
        if (!mounted) return;
        setState(() => _isStartingInterview = false);
        SnackHelper.error(
          context,
          'You have no Mock Interview credits remaining today. Credits reset at midnight.',
        );
        return;
      }

      if (!mounted) return;
      setState(() =>
          _mockInterviewCredits = (_mockInterviewCredits - 1).clamp(0, 999));

      // 3) create interview doc
      final docRef =
          FirebaseFirestore.instance.collection('MockInterviews').doc();

      await docRef.set({
        'MockInterviewsID': docRef.id,
        'UserID': uid,
        'Specialty': specialty,
        'Date': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final questions = await _fetchMockQuestionsFromFunction(specialty);

      await docRef.set({'Questions': questions}, SetOptions(merge: true));

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => MockInterviewSessionScreen(
            mockInterviewId: docRef.id,
            questions: questions,
          ),
        ),
      );
    } catch (e) {
      await refundMockInterviewCredit();
      if (!mounted) return;
      setState(() => _isStartingInterview = false);
      SnackHelper.error(context, 'Failed to start mock interview: $e');
    }
  }
}

class MockInterviewSessionScreen extends StatefulWidget {
  const MockInterviewSessionScreen({
    super.key,
    required this.mockInterviewId,
    required this.questions,
  });

  final String mockInterviewId;
  final List<String> questions;

  @override
  State<MockInterviewSessionScreen> createState() =>
      _MockInterviewSessionScreenState();
}

class _MockInterviewSessionScreenState
    extends State<MockInterviewSessionScreen> {
  final AudioPlayer _ttsPlayer = AudioPlayer();
  final AudioPlayer _playbackPlayer = AudioPlayer();
  bool _isGeneratingReport = false;
  late List<int> _recordAttempts;
  bool _isUploadingAnswer = false;
  double _uploadProgress = 0.0;
  StreamSubscription<TaskSnapshot>? _uploadSub;
  bool _isFinishing = false;

  String? _currentPlaybackUrl;
  bool _isPlaying = false;
  bool get _canGoNext =>
      !_isRecording &&
      !_isUploadingAnswer &&
      _answerUrls[_index].trim().isNotEmpty;

  CameraController? _camera;
  bool _initializing = true;
  String? _error;

  int _index = 0;

  String get _currentQuestion =>
      (widget.questions.isEmpty) ? '—' : widget.questions[_index];

  bool get _isLast => _index >= widget.questions.length - 1;
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  Duration _recordDuration = Duration.zero;
  Timer? _recordTimer;

  late List<String> _answerUrls;
  bool _isSpeaking = false;
  bool _ttsLoading = false;

  // ✅ FACE DETECTION
  late final FaceDetector _faceDetector;
  bool _faceDetected = false;
  bool _processingFrame = false;

  @override
  void initState() {
    super.initState();
    _answerUrls = List<String>.filled(widget.questions.length, '');
    _recordAttempts = List<int>.filled(widget.questions.length, 0);

    // Initialize face detector
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableContours: false,
        enableClassification: true,
        enableTracking: false,
        minFaceSize: 0.05,
        performanceMode: FaceDetectorMode.fast,
      ),
    );

    _initTts().then((_) {
      if (!mounted) return;
      _initPermissionsAndCamera();
    });

    _playbackPlayer.playerStateStream.listen((state) {
      if (!mounted) return;
      if (state.processingState == ProcessingState.completed) {
        setState(() => _isPlaying = false);
      }
    });
  }

  Future<void> _cancelInterviewAndCleanup() async {
    try {
      _recordTimer?.cancel();
      if (_isRecording) {
        await _recorder.stop();
        _isRecording = false;
      }
      await _ttsPlayer.stop();
      await _playbackPlayer.stop();
      final docRef = FirebaseFirestore.instance
          .collection('MockInterviews')
          .doc(widget.mockInterviewId);

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null && uid.isNotEmpty) {
        final folderRef = FirebaseStorage.instance
            .ref()
            .child('mock_interviews/$uid/${widget.mockInterviewId}');

        final list = await folderRef.listAll();
        for (final item in list.items) {
          try {
            await item.delete();
          } catch (_) {}
        }
      }

      await docRef.delete();
    } catch (e) {
      if (mounted) {
        SnackHelper.error(context, 'Cleanup failed: $e');
      }
    }
  }

  Future<void> _initTts() async {
    // لا نحتاج initialization للـ Google TTS
  }

  Future<void> _speakCurrentQuestion() async {
    if (_isRecording) return;
    await _googleSpeak(_currentQuestion);
  }

  Future<void> _stopTts() async {
    await _ttsPlayer.stop();
    if (!mounted) return;
    setState(() => _isSpeaking = false);
  }

  Future<void> _googleSpeak(String text) async {
    try {
      if (!mounted) return;
      setState(() {
        _isSpeaking = true;
        _ttsLoading = true;
      });

      final response = await http.post(
        Uri.parse(
            'https://us-central1-jadeer-b4953.cloudfunctions.net/synthesizeSpeech'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'text': text}),
      );

      print('TTS status: ${response.statusCode}');
      print('TTS body: ${response.body}');

      if (!mounted) return;
      setState(() => _ttsLoading = false);

      if (!mounted) return;
      setState(() => _ttsLoading = false);

      final data = jsonDecode(response.body);
      final audioContent = data['audioContent'] as String?;

      if (audioContent == null || audioContent.isEmpty) {
        setState(() => _isSpeaking = false);
        return;
      }

      // احفظ الـ audio مؤقتاً وشغّله
      final dir = await getTemporaryDirectory();
      final file =
          File('${dir.path}/tts_${DateTime.now().millisecondsSinceEpoch}.mp3');
      await file.writeAsBytes(base64Decode(audioContent));

      await _ttsPlayer.setFilePath(file.path);
      await _ttsPlayer.play();

      if (!mounted) return;
      setState(() => _isSpeaking = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSpeaking = false;
        _ttsLoading = false;
      });
    }
  }

  Future<void> _toggleSpeak() async {
    if (_isSpeaking) {
      await _stopTts();
      return;
    }
    await _speakCurrentQuestion();
  }

  Future<void> _initPermissionsAndCamera() async {
    try {
      if (!mounted) return;
      setState(() {
        _initializing = true;
        _error = null;
      });

      final cam = await Permission.camera.request();
      final mic = await Permission.microphone.request();

      if (!mounted) return;

      if (!cam.isGranted || !mic.isGranted) {
        setState(() {
          _error = 'Camera/Microphone permission is required to continue.';
          _initializing = false;
        });
        return;
      }

      final cams = await availableCameras();

      if (!mounted) return;

      if (cams.isEmpty) {
        setState(() {
          _error = 'No camera found on this device.';
          _initializing = false;
        });
        return;
      }

      final front = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cams.first,
      );

      final controller = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await controller.initialize();

      if (!mounted) return;

      setState(() {
        _camera = controller;
        _initializing = false;
      });

      // ✅ START FACE DETECTION
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      _processCameraImage();

      await _speakCurrentQuestion();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to initialize camera: $e';
        _initializing = false;
      });
    }
  }

  // ✅ FACE DETECTION PROCESSING
  Future<void> _processCameraImage() async {
    if (_processingFrame || _camera == null || !_camera!.value.isInitialized) {
      return;
    }

    _processingFrame = true;

    try {
      final image = await _camera!.takePicture();
      final inputImage = InputImage.fromFilePath(image.path);
      final faces = await _faceDetector.processImage(inputImage);

      if (!mounted) return;

      // ✅ STRICT FACE DETECTION
      bool hasValidFace = false;

      if (faces.isNotEmpty) {
        final face = faces.first;
        final boundingBox = face.boundingBox;

        // Face must be reasonably visible (not too tiny)
        final faceWidth = boundingBox.width;
        final faceHeight = boundingBox.height;

        // Minimum size check - relaxed for normal arm's length
        final isLargeEnough = faceWidth > 50 && faceHeight > 60;

        if (isLargeEnough) {
          // Check head angles - must face forward
          final headAngleY = face.headEulerAngleY ?? 0;
          final headAngleZ = face.headEulerAngleZ ?? 0;

          // Allow 30 degrees rotation (more forgiving)
          final isFacingForward =
              headAngleY.abs() < 30 && headAngleZ.abs() < 30;

          if (isFacingForward) {
            // ✅ EYE CHECK - both eyes must be visible and open
            // Covers: eyes covered, half face covered
            final leftEye = face.leftEyeOpenProbability ?? -1;
            final rightEye = face.rightEyeOpenProbability ?? -1;
            final bothEyesVisible = leftEye > 0.15 && rightEye > 0.15;

            // ✅ ASPECT RATIO - face must have normal proportions
            // Covers: mouth/nose covered (bounding box gets shorter)
            final aspectRatio = faceHeight / faceWidth;
            final hasNormalProportions = aspectRatio >= 1.0;

            // Must pass BOTH checks
            if (bothEyesVisible && hasNormalProportions) {
              hasValidFace = true;
            }
          }
        }
      }

      setState(() {
        _faceDetected = hasValidFace;
      });

      if (faces.isNotEmpty) {}
    } catch (e) {
      if (mounted) {
        setState(() {
          _faceDetected = false;
        });
      }
    } finally {
      _processingFrame = false;

      if (mounted) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) _processCameraImage();
        });
      }
    }
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _recorder.dispose();
    _camera?.dispose();
    _uploadSub?.cancel();
    _ttsPlayer.dispose();
    _playbackPlayer.dispose();
    _faceDetector.close();
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    final url = _answerUrls[_index].trim();
    if (url.isEmpty) return;

    try {
      if (_isPlaying) {
        await _playbackPlayer.pause();
        if (!mounted) return;
        setState(() => _isPlaying = false);
        return;
      }

      if (_currentPlaybackUrl != url) {
        await _playbackPlayer.setUrl(url);
        _currentPlaybackUrl = url;
      }

      await _playbackPlayer.play();
      if (!mounted) return;
      setState(() => _isPlaying = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isPlaying = false);
      SnackHelper.error(context, 'Playback error: $e');
    }
  }

  Future<void> _next() async {
    if (_isRecording) {
      SnackHelper.error(context, 'Stop recording first.');
      return;
    }

    // ✅ CHECK FACE BEFORE ALLOWING NEXT
    if (!_faceDetected) {
      SnackHelper.error(context, 'Please show your face to continue.');
      return;
    }

    final hasAnswer = _answerUrls[_index].trim().isNotEmpty;
    if (!hasAnswer) {
      SnackHelper.error(context, 'Please record your answer first.');
      return;
    }

    if (_isLast) {
      await _finish();
      return;
    }

    setState(() {
      _index++;
      _recordDuration = Duration.zero;
    });

    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    await _speakCurrentQuestion();
  }

  void _startTimer() {
    _recordTimer?.cancel();
    _recordDuration = Duration.zero;
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _recordDuration += const Duration(seconds: 1));
    });
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<String> _uploadAudioAndGetUrlWithProgress(File file) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
    final storagePath =
        'mock_interviews/$uid/${widget.mockInterviewId}/q${_index + 1}.m4a';

    final ref = FirebaseStorage.instance.ref().child(storagePath);
    final task = ref.putFile(file, SettableMetadata(contentType: 'audio/m4a'));

    _uploadSub?.cancel();
    _uploadSub = task.snapshotEvents.listen((s) {
      final total = s.totalBytes;
      if (total == 0) return;
      final p = s.bytesTransferred / total;
      if (!mounted) return;
      setState(() => _uploadProgress = p);
    });

    await task;
    return await ref.getDownloadURL();
  }

  Future<void> _toggleRecording() async {
    // ✅ CHECK FOR FACE FIRST
    if (!_faceDetected && !_isRecording) {
      SnackHelper.error(
          context, 'Please position your face in front of the camera.');
      return;
    }

    try {
      if (_isRecording) {
        final path = await _recorder.stop();
        _recordTimer?.cancel();

        if (!mounted) return;
        setState(() => _isRecording = false);

        if (path == null || path.isEmpty) {
          SnackHelper.error(context, 'Recording failed. Try again.');
          return;
        }

        setState(() {
          _isUploadingAnswer = true;
          _uploadProgress = 0.0;
        });

        try {
          final url = await _uploadAudioAndGetUrlWithProgress(File(path));
          _answerUrls[_index] = url;

          await FirebaseFirestore.instance
              .collection('MockInterviews')
              .doc(widget.mockInterviewId)
              .set({'AnswersRecordsURL': _answerUrls}, SetOptions(merge: true));

          if (!mounted) return;
          setState(() => _isUploadingAnswer = false);

          SnackHelper.success(context, 'Your answer has been uploaded.');
        } catch (e) {
          if (!mounted) return;
          setState(() => _isUploadingAnswer = false);
          SnackHelper.error(context, 'Upload failed: $e');
        }

        return;
      }

      if (_answerUrls[_index].trim().isNotEmpty) {
        if (_recordAttempts[_index] >= 3) {
          SnackHelper.error(
            context,
            'You have reached the maximum of 3 recording attempts for this question.',
          );
          return;
        }

        final overwrite = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => JadeerDialog<bool>(
            title: 'Replace recording?',
            content: Text(
              'You already recorded an answer for this question.\n\n'
              'Attempts remaining: ${3 - _recordAttempts[_index]}',
            ),
            primaryLabel: 'Replace',
            primaryResult: true,
            secondaryLabel: 'Cancel',
            secondaryResult: false,
          ),
        );

        if (overwrite != true) return;

        _answerUrls[_index] = '';
        if (!mounted) return;
        setState(() {});
      }

      await Permission.microphone.request();

      final hasMic = await _recorder.hasPermission();

      if (!hasMic) {
        if (!mounted) return;
        SnackHelper.error(context, 'Microphone permission is required.');
        return;
      }

      final dir = await getTemporaryDirectory();
      final fileName =
          'mock_${widget.mockInterviewId}_q${_index + 1}_${DateTime.now().millisecondsSinceEpoch}.m4a';
      final path = '${dir.path}/$fileName';
      await _stopTts();

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: path,
      );

      _startTimer();
      _recordAttempts[_index]++;

      if (!mounted) return;
      setState(() => _isRecording = true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isRecording = false;
      });
      SnackHelper.error(context, 'Recording error: $e');
    }
  }

  Future<void> _finish() async {
    if (_isFinishing) return;
    _isFinishing = true;

    if (!mounted) return;
    setState(() => _isGeneratingReport = true);

    try {
      await FirebaseFirestore.instance
          .collection('MockInterviews')
          .doc(widget.mockInterviewId)
          .set({
        'Finished': true,
        'FinishedAt': FieldValue.serverTimestamp(),
        'AnsweredCount': _answerUrls.where((e) => e.trim().isNotEmpty).length,
        'TotalQuestions': widget.questions.length,
        'Report': null,
      }, SetOptions(merge: true));

      final functions = FirebaseFunctions.instance;

      final callable = functions.httpsCallable(
        'generateMockInterviewReport',
        options: HttpsCallableOptions(timeout: const Duration(minutes: 30)),
      );

      await callable.call({
        'mockInterviewID': widget.mockInterviewId,
      });

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => MockInterviewReportScreen(
            mockInterviewID: widget.mockInterviewId,
            fromHistory: false,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isGeneratingReport = false);
      _isFinishing = false;
      SnackHelper.error(context, 'Failed to generate report: $e');
    }
  }

  Widget _buildGeneratingReportUI(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              color: AppTheme.primaryPurple,
            ),
            const SizedBox(height: 24),
            Text(
              'Generating your report...',
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'AI is analyzing your interview answers\nThis may take up to 30 seconds',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.grey[600],
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;

        final shouldExit = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const JadeerDialog<bool>(
            title: 'Exit Interview?',
            content: Text(
              'Exiting now will count this attempt, and you will not be able to continue the interview.\n\n'
              'Are you sure you want to exit?',
            ),
            primaryLabel: 'Exit',
            primaryResult: true,
            secondaryLabel: 'Continue',
            secondaryResult: false,
          ),
        );

        if (shouldExit == true && context.mounted) {
          await _cancelInterviewAndCleanup();

          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const JobSeekerHome()),
            (route) => false,
          );
        }
      },
      child: ThemedScaffold(
        appBar: CustomHeader(
          title: 'Mock Interview',
          showBack: false,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Color(0xFFFFFFFF)),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          transparent: false,
          rounded: true,
        ),
        extendBodyBehindAppBar: true,
        body: _isGeneratingReport
            ? _buildGeneratingReportUI(context)
            : _initializing
                ? const Center(child: CircularProgressIndicator())
                : (_error != null)
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: scheme.error),
                          ),
                        ),
                      )
                    : Stack(
                        children: [
                          Positioned.fill(
                            child: CameraPreview(_camera!),
                          ),
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.black.withOpacity(0.25),
                                    Colors.transparent,
                                    Colors.black.withOpacity(0.75),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 128,
                            left: 0,
                            right: 250,
                            child: Center(
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: _faceDetected
                                      ? Colors.green.withOpacity(0.85)
                                      : Colors.red.withOpacity(0.85),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _faceDetected
                                          ? Icons.check_circle
                                          : Icons.warning_rounded,
                                      color: Colors.white,
                                      size: 14,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _faceDetected
                                          ? 'Face detected'
                                          : 'No face detected',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 16,
                            right: 16,
                            bottom: 150,
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.55),
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.18),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Question ${_index + 1}/${widget.questions.length}',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          _currentQuestion,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 17,
                                            fontWeight: FontWeight.w800,
                                            height: 1.35,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: _toggleSpeak,
                                        icon: Icon(
                                          _isSpeaking
                                              ? Icons.stop_circle
                                              : Icons.volume_up_rounded,
                                          color: _isSpeaking
                                              ? const Color(0xFFFD6C67)
                                              : Colors.white,
                                          size: 30,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 50,
                            child: Column(
                              children: [
                                GestureDetector(
                                  onTap: _isUploadingAnswer
                                      ? null
                                      : _toggleRecording,
                                  child: Container(
                                    width: 86,
                                    height: 86,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _isRecording
                                          ? const Color(0xFFFD6C67)
                                          : const Color(0xFF4A5FBC),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.35),
                                          blurRadius: 18,
                                          offset: const Offset(0, 8),
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      _isRecording
                                          ? Icons.stop_rounded
                                          : Icons.mic_rounded,
                                      size: 42,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  _isRecording
                                      ? 'Recording… ${_fmt(_recordDuration)}'
                                      : _isUploadingAnswer
                                          ? 'Uploading… ${(_uploadProgress * 100).toStringAsFixed(0)}%'
                                          : (_answerUrls[_index].isNotEmpty
                                              ? 'Answer uploaded'
                                              : 'Tap the mic to record'),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (_isUploadingAnswer) ...[
                                  const SizedBox(height: 8),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 32),
                                    child: LinearProgressIndicator(
                                      value: _uploadProgress,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
        bottomNavigationBar: _isGeneratingReport
            ? const SizedBox.shrink()
            : SafeArea(
                minimum: const EdgeInsets.symmetric(horizontal: 16)
                    .copyWith(bottom: 30, top: 10),
                child: SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton(
                    onPressed: _canGoNext ? _next : null,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: const Color(0xFF4A5FBC),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    child: Text(_isLast ? 'Finish' : 'Next'),
                  ),
                ),
              ),
      ),
    );
  }
}

Future<Map<String, int>> fetchAndResetAiUsageIfNeeded() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return {'CvEnhancement': 0, 'MockInterview': 0};

  final userDocRef =
      FirebaseFirestore.instance.collection('Users').doc(user.uid);

  final snap = await userDocRef.get();
  final data = snap.data() ?? {};
  final aiUsage = (data['AiUsage'] as Map<String, dynamic>?) ?? {};

  int cv = (aiUsage['CvEnhancement'] ?? 2) as int;
  int mock = (aiUsage['MockInterview'] ?? 2) as int;
  final lastReset = aiUsage['LastReset'] as Timestamp?;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  bool shouldReset;
  if (lastReset == null) {
    shouldReset = true;
  } else {
    final last = lastReset.toDate();
    final lastDay = DateTime(last.year, last.month, last.day);
    shouldReset = lastDay.isBefore(today);
  }

  if (shouldReset) {
    cv = 2;
    mock = 2;
    await userDocRef.update({
      'AiUsage.CvEnhancement': 2,
      'AiUsage.MockInterview': 2,
      'AiUsage.LastReset': FieldValue.serverTimestamp(),
    });
  }

  return {'CvEnhancement': cv, 'MockInterview': mock};
}

Future<void> refundMockInterviewCredit() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final userDocRef =
      FirebaseFirestore.instance.collection('Users').doc(user.uid);

  await FirebaseFirestore.instance.runTransaction((tx) async {
    final snap = await tx.get(userDocRef);
    final data = snap.data() ?? {};
    final aiUsage = (data['AiUsage'] as Map<String, dynamic>?) ?? {};
    final credits = (aiUsage['MockInterview'] ?? 0) as int;

    tx.update(userDocRef, {'AiUsage.MockInterview': credits + 1});
  });
}
