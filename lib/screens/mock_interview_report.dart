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
          final voiceToneAnalysis = data['VoiceToneAnalysis'] as List<dynamic>?;
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

          // Extract the dynamic overall voice feedback comments cleanly
          final List<String> voiceComments = [];
          if (voiceToneAnalysis != null && voiceToneAnalysis.isNotEmpty) {
            for (var item in voiceToneAnalysis) {
              String commentText = item['result'] ?? '';
              if (commentText.isNotEmpty) {
                voiceComments.add(commentText);
              }
            }
          }

          // Per-question SER results (new field from updated function)
          final voiceRawResults = data['VoiceToneRawResults'] as List<dynamic>?;
          final voiceConfidenceScore = (data['VoiceConfidenceScore'] as num?)?.toInt();

          // Force the overall score scale display rules to be /100 instead of /10
          final overallScore = (report['overallScore'] ?? 70.0) as num;
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
                      _buildHeaderCard(context, specialty, date),
                      const SizedBox(height: 20),
                      _buildOverviewSection(context, score, overallSummary),
                      const SizedBox(height: 20),
                      _buildTabsSection(context, strengths, weaknesses, advice, voiceComments, voiceRawResults, voiceConfidenceScore),
                    ],
                  ),
                ),
              ),
              if (!widget.fromHistory)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
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

  Widget _buildHeaderCard(BuildContext context, String specialty, Timestamp? date) {
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

  Widget _buildOverviewSection(BuildContext context, double score, String summary) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color scoreColor;
    String scoreLabel;
    Color accentGold = const Color(0xFFD4A843);
    if (score >= 80) {
      scoreColor = const Color(0xFF2E7D32);
      scoreLabel = 'Excellent';
    } else if (score >= 60) {
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
            color: Colors.black.withOpacity(isDark ? 0.12 : 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Column(
        children: [
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
          Stack(
            alignment: Alignment.center,
            children: [
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
              SizedBox(
                width: 135,
                height: 135,
                child: CircularProgressIndicator(
                  value: 1.0,
                  strokeWidth: 12,
                  strokeCap: StrokeCap.round,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isDark ? Colors.grey[850]! : Colors.grey[200]!,
                  ),
                ),
              ),
              SizedBox(
                width: 135,
                height: 135,
                child: CircularProgressIndicator(
                  value: score / 100,
                  strokeWidth: 12,
                  strokeCap: StrokeCap.round,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(scoreColor),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    score.toStringAsFixed(0),
                    style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.w800,
                      color: scoreColor,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '/ 100',
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.grey[500],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
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
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[800]!.withOpacity(0.5) : Colors.grey[100]!.withOpacity(0.8),
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
    List<String> voiceComments,
    List<dynamic>? voiceRawResults,
    int? voiceConfidenceScore,
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
                    _buildPillTab(context, index: 0, label: 'Strengths', color: Colors.green[700]!),
                    _buildPillTab(context, index: 1, label: 'Improve', color: const Color(0xFFFD6C67)),
                    _buildPillTab(context, index: 2, label: 'Tips', color: AppTheme.primaryPurple),
                    _buildPillTab(context, index: 3, label: 'Voice', color: const Color(0xFF2196F3)),
                  ],
                ),
              );
            },
          ),
          SizedBox(
            height: 500,
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildListTab(context, items: strengths, itemColor: Colors.green[700]!, emptyMessage: 'No strengths identified yet.'),
                _buildListTab(context, items: weaknesses, itemColor: const Color(0xFFFD6C67), emptyMessage: 'No areas for improvement identified.'),
                _buildListTab(context, items: advice, itemColor: AppTheme.primaryPurple, emptyMessage: 'No recommendations yet.'),
                _buildVoiceTab(context, voiceComments, voiceRawResults, voiceConfidenceScore),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPillTab(BuildContext context, {required int index, required String label, required Color color}) {
    final isSelected = _tabController.index == index;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Expanded(
      child: GestureDetector(
        onTap: () => _tabController.animateTo(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? Colors.white : (isDark ? Colors.grey[400] : Colors.grey[700]),
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
          ),
        ),
      ),
    );
  }

  Widget _buildListTab(BuildContext context, {required List<String> items, required Color itemColor, required String emptyMessage}) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(emptyMessage, style: const TextStyle(fontSize: 15, color: Colors.grey), textAlign: TextAlign.center),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: items.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: EdgeInsets.only(bottom: index < items.length - 1 ? 16 : 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: itemColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  items[index],
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.7, fontSize: 15, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVoiceTab(
    BuildContext context,
    List<String> voiceComments,
    List<dynamic>? rawResults,
    int? confidenceScore,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Parse per-question data from raw SER results
    final List<_VoiceQuestionData> questions = [];
    final resultsList = rawResults ?? [];

    for (final item in resultsList) {
      final resultText = (item['result'] ?? '').toString();
      final match = RegExp(r'Assessment Score:\s*([\d.]+)%').firstMatch(resultText);
      final score = match != null ? (double.tryParse(match.group(1)!) ?? 0).round() : 0;
      final insight = resultText.contains('Insight:')
          ? resultText.split('Insight:').last.trim()
          : resultText;
      questions.add(_VoiceQuestionData(score: score, insight: insight));
    }

    // Calculate average if not provided
    final avgScore = confidenceScore ??
        (questions.isNotEmpty
            ? (questions.map((q) => q.score).reduce((a, b) => a + b) / questions.length).round()
            : 0);

    final gptFeedback = voiceComments.isNotEmpty ? voiceComments.first : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 1. Info message ──
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF2196F3).withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF2196F3).withOpacity(0.15),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: const Color(0xFF2196F3).withOpacity(0.7),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'These results are based on an AI analysis of your vocal confidence during the mock interview. The model evaluates tone, pacing, and delivery for each answer.',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── 2. Per-question results ──
          if (questions.isNotEmpty) ...[
            Text(
              'Per-Question Analysis',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            ...List.generate(questions.length, (i) {
              final q = questions[i];
              final qColor = q.score >= 70
                  ? const Color(0xFF2E7D32)
                  : q.score >= 40
                      ? const Color(0xFFE67E22)
                      : const Color(0xFFC0392B);

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[900] : Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2196F3).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Q${i + 1}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                              color: Color(0xFF2196F3),
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${q.score} / 100',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: qColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (q.score / 100).clamp(0.0, 1.0),
                        backgroundColor:
                            isDark ? Colors.grey[800] : Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation<Color>(qColor),
                        minHeight: 5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      q.insight,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 10),

            // Divider
            Divider(color: isDark ? Colors.grey[800] : Colors.grey[200]),
            const SizedBox(height: 14),
          ],

          // ── 3. Overall voice feedback from GPT ──
          if (gptFeedback != null && gptFeedback.isNotEmpty) ...[
            Text(
              'Overall Voice Feedback',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[900] : Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                gptFeedback,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.grey[300] : Colors.grey[700],
                  height: 1.6,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── 4. Average score — subtle footer ──
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[900] : Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2196F3).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.mic_rounded,
                    color: Color(0xFF2196F3),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Average Voice Confidence',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.grey[500] : Colors.grey[500],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          '$avgScore',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        Text(
                          ' / 100',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.grey[500] : Colors.grey[400],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          // No per-question data fallback
          if (questions.isEmpty && (gptFeedback == null || gptFeedback.isEmpty))
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Voice analysis will be available soon.',
                  style: TextStyle(
                    fontSize: 15,
                    color: isDark ? Colors.grey[500] : Colors.grey[400],
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _VoiceQuestionData {
  final int score;
  final String insight;
  const _VoiceQuestionData({required this.score, required this.insight});
}