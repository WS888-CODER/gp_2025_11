import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../config/theme.dart';
import 'package:gp_2025_11/screens/jobseeker_home.dart';

class MockInterviewReportScreen extends StatefulWidget {
  final String mockInterviewID;
  final bool fromHistory;

  const MockInterviewReportScreen({
    Key? key,
    required this.mockInterviewID,
    this.fromHistory = false,
  }) : super(key: key);

  @override
  State<MockInterviewReportScreen> createState() =>
      _MockInterviewReportScreenState();
}

class _MockInterviewReportScreenState extends State<MockInterviewReportScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ThemedScaffold(
      appBar: CustomHeader(
        title: 'Interview Report',
        showBack: widget.fromHistory,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('MockInterviews')
            .doc(widget.mockInterviewID)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                color: AppTheme.primaryPurple,
              ),
            );
          }

          if (snapshot.hasError) {
            return const EmptyState(
              icon: Icons.error_outline,
              title: 'Error loading report',
              subtitle: 'Please try again later',
            );
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const EmptyState(
              icon: Icons.description_outlined,
              title: 'Interview not found',
              subtitle: 'This interview may have been deleted',
            );
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final report = data['Report'] as Map<String, dynamic>?;
          final specialty = data['Specialty'] as String? ?? 'Unknown';
          final date = data['Date'] as Timestamp?;

          if (report == null) {
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

          final strengths = (report['strengths'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              [];
          final weaknesses = (report['weaknesses'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              [];
          final advice = (report['advice'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              [];
          final voiceAnalysis =
              report['voiceToneAnalysis'] as Map<String, dynamic>?;

          final overallScore = (report['overallScore'] ?? 7.0) as num;
          final score = overallScore.toDouble();
          final overallSummary = (report['overallSummary'] ??
                  'Your interview performance shows potential with room for growth.')
              as String;

          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header Card
                      _buildHeaderCard(context, specialty, date),
                      const SizedBox(height: 20),

                      // OVERVIEW SECTION (Redesigned)
                      _buildOverviewSection(context, score, overallSummary),
                      const SizedBox(height: 20),

                      // TABS (Now with Voice Analysis)
                      _buildTabsSection(context, strengths, weaknesses, advice,
                          voiceAnalysis),
                    ],
                  ),
                ),
              ),
              if (!widget.fromHistory)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(
                            builder: (_) => const JobSeekerHome(),
                          ),
                          (route) => false,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryPurple,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ),
                      child: const Text(
                        'Done',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeaderCard(
      BuildContext context, String specialty, Timestamp? date) {
    final dateStr = date != null
        ? '${date.toDate().day}/${date.toDate().month}/${date.toDate().year}'
        : 'Unknown date';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.primaryPurple, Color(0xFF6B7FD7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(
              Theme.of(context).brightness == Brightness.dark ? 0.12 : 0.05,
            ),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.assessment_rounded, color: Colors.white, size: 28),
              SizedBox(width: 12),
              Text(
                'Interview Performance',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              specialty,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.calendar_today, color: Colors.white70, size: 16),
              const SizedBox(width: 6),
              Text(
                dateStr,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewSection(
      BuildContext context, double score, String summary) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color scoreColor;
    String scoreLabel;
    Color accentGold = const Color(0xFFD4A843);
    if (score >= 8) {
      scoreColor = const Color(0xFF2E7D32);
      scoreLabel = 'Excellent';
      accentGold = const Color(0xFFD4A843);
    } else if (score >= 6) {
      scoreColor = const Color(0xFFE67E22);
      scoreLabel = 'Good';
      accentGold = const Color(0xFFE67E22);
    } else {
      scoreColor = const Color(0xFFC0392B);
      scoreLabel = 'Needs Improvement';
      accentGold = const Color(0xFFC0392B);
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(
              Theme.of(context).brightness == Brightness.dark ? 0.12 : 0.05,
            ),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Column(
        children: [
          // Title row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.insights_rounded, color: accentGold, size: 22),
              const SizedBox(width: 8),
              Text(
                'Overview',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),

          // Score Circle (CENTERED, bigger)
          Stack(
            alignment: Alignment.center,
            children: [
              // Outer glow
              Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: scoreColor.withOpacity(0.2),
                      blurRadius: 30,
                      spreadRadius: 6,
                    ),
                  ],
                ),
              ),
              // Background track
              SizedBox(
                width: 135,
                height: 135,
                child: CircularProgressIndicator(
                  value: 1.0,
                  strokeWidth: 12,
                  strokeCap: StrokeCap.round,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isDark ? Colors.grey[800]! : Colors.grey[200]!,
                  ),
                ),
              ),
              // Score arc
              SizedBox(
                width: 135,
                height: 135,
                child: CircularProgressIndicator(
                  value: score / 10,
                  strokeWidth: 12,
                  strokeCap: StrokeCap.round,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(scoreColor),
                ),
              ),
              // Score text
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    score.toStringAsFixed(1),
                    style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.w800,
                      color: scoreColor,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '/ 10',
                    style: TextStyle(
                      fontSize: 15,
                      color: isDark ? Colors.grey[500] : Colors.grey[500],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Score label pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            decoration: BoxDecoration(
              color: scoreColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: scoreColor.withOpacity(0.3),
                width: 1.5,
              ),
            ),
            child: Text(
              scoreLabel,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: scoreColor,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 20),

          const SizedBox(height: 16),

          // Summary text (BELOW score) - bolder & more readable
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.grey[800]!.withOpacity(0.5)
                  : Colors.grey[100]!.withOpacity(0.8),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              summary,
              textAlign: TextAlign.center,
              style: TextStyle(
                height: 1.7,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.grey[200] : Colors.grey[800],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabsSection(
    BuildContext context,
    List<String> strengths,
    List<String> weaknesses,
    List<String> advice,
    Map<String, dynamic>? voiceAnalysis,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // ✨ CUSTOM TAB BAR (Modern Pill Style)
          AnimatedBuilder(
            animation: _tabController,
            builder: (context, _) {
              return Container(
                margin: const EdgeInsets.fromLTRB(12, 16, 12, 8),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[850] : Colors.grey[200],
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    _buildPillTab(
                      context,
                      index: 0,
                      label: 'Strengths',
                      color: Colors.green[700]!,
                    ),
                    _buildPillTab(
                      context,
                      index: 1,
                      label: 'Improve',
                      color: const Color(0xFFFD6C67),
                    ),
                    _buildPillTab(
                      context,
                      index: 2,
                      label: 'Tips',
                      color: AppTheme.primaryPurple,
                    ),
                    _buildPillTab(
                      context,
                      index: 3,
                      label: 'Voice',
                      color: const Color(0xFF2196F3),
                    ),
                  ],
                ),
              );
            },
          ),

          // TAB CONTENT
          SizedBox(
            height: 500,
            child: TabBarView(
              controller: _tabController,
              children: [
                // Strengths
                _buildListTab(
                  context,
                  items: strengths,
                  itemColor: Colors.green[700]!,
                  emptyMessage: 'No strengths identified yet.',
                ),
                // Weaknesses
                _buildListTab(
                  context,
                  items: weaknesses,
                  itemColor: const Color(0xFFFD6C67),
                  emptyMessage: 'No areas for improvement identified.',
                ),
                // Recommendations
                _buildListTab(
                  context,
                  items: advice,
                  itemColor: AppTheme.primaryPurple,
                  emptyMessage: 'No recommendations yet.',
                ),
                // Voice Analysis
                _buildVoiceTab(context, voiceAnalysis),
              ],
            ),
          ),
        ],
      ),
    );
  }

// ✨ PILL TAB BUILDER - Modern text-only design
  Widget _buildPillTab(
    BuildContext context, {
    required int index,
    required String label,
    required Color color,
  }) {
    final isSelected = _tabController.index == index;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          _tabController.animateTo(index);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: color.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected
                  ? Colors.white
                  : (isDark ? Colors.grey[400] : Colors.grey[700]),
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
          ),
        ),
      ),
    );
  }

  Widget _buildListTab(
    BuildContext context, {
    required List<String> items,
    required Color itemColor,
    required String emptyMessage,
  }) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            emptyMessage,
            style: const TextStyle(
              fontSize: 15,
              color: Colors.grey,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: items.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: index < items.length - 1 ? 16 : 0,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: itemColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  items[index],
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        height: 1.7,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVoiceTab(
      BuildContext context, Map<String, dynamic>? voiceAnalysis) {
    final isAvailable = voiceAnalysis?['available'] == true;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!isAvailable) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFFD6C67).withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFFD6C67).withOpacity(0.5),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.schedule_rounded,
                  color: Color(0xFFFD6C67),
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  voiceAnalysis?['message'] ??
                      'Voice analysis will be available soon',
                  style: TextStyle(
                    fontSize: 15,
                    color: isDark ? Colors.white70 : Colors.grey[700],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildVoiceMetric(
          context,
          'Confidence',
          voiceAnalysis?['confidence'] ?? 0,
          Colors.blue,
        ),
        const SizedBox(height: 20),
        _buildVoiceMetric(
          context,
          'Clarity',
          voiceAnalysis?['clarity'] ?? 0,
          Colors.green,
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Text(
              'Tone: ',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            Text(
              voiceAnalysis?['tone'] ?? 'N/A',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildVoiceMetric(
      BuildContext context, String label, int value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            Text(
              '$value%',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: value / 100,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 10,
          ),
        ),
      ],
    );
  }
}
