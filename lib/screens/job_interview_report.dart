import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../config/theme.dart';
import 'package:gp_2025_11/screens/jobseeker_home.dart';

class JobInterviewReportScreen extends StatefulWidget {
  final String applicationId;
  final bool fromHistory;

  const JobInterviewReportScreen({
    Key? key,
    required this.applicationId,
    this.fromHistory = false,
  }) : super(key: key);

  @override
  State<JobInterviewReportScreen> createState() =>
      _JobInterviewReportScreenState();
}

class _JobInterviewReportScreenState extends State<JobInterviewReportScreen>
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

  // ── Status helpers (matching report: Pending / Shortlisted / Rejected) ──
  String _formatStatus(String raw) {
    switch (raw) {
      case 'Pending':
      case 'Submitted':
        return 'Pending';
      case 'Shortlisted':
        return 'Shortlisted';
      case 'Rejected':
        return 'Rejected';
      case 'InInterview':
        return 'In Progress';
      case 'InterviewCancelled':
        return 'Cancelled';
      default:
        return raw.isNotEmpty ? raw : 'Unknown';
    }
  }

  Color _statusColor(String raw) {
    switch (raw) {
      case 'Pending':
      case 'Submitted':
        return Colors.grey;
      case 'Shortlisted':
        return Colors.orange;
      case 'Rejected':
        return Colors.red;
      case 'InInterview':
        return Colors.blue;
      case 'InterviewCancelled':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  IconData _statusIcon(String raw) {
    switch (raw) {
      case 'Pending':
        return Icons.hourglass_top_rounded;
      case 'Shortlisted':
        return Icons.check_circle_outline;
      case 'Rejected':
        return Icons.cancel_outlined;
      case 'InInterview':
        return Icons.play_circle_outline;
      default:
        return Icons.info_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ThemedScaffold(
      appBar: CustomHeader(
        title: 'Application Report',
        showBack: widget.fromHistory,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('Applications')
            .doc(widget.applicationId)
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
              title: 'Application not found',
              subtitle: 'This application may have been deleted',
            );
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final report = data['Report'] as Map<String, dynamic>?;
          final jobTitle = (data['JobTitle'] ?? 'Job Application').toString();
          final companyName = (data['CompanyName'] ?? '').toString();
          final status = (data['ApplicationStatus'] ?? '').toString();
          final date = data['Date'] as Timestamp?;
          final score = data['Score'];

          // ── Report not yet generated ──
          if (report == null) {
            // Interview still in progress — not completed
            if (status == 'InInterview') {
              return const EmptyState(
                icon: Icons.play_circle_outline,
                title: 'Interview Not Completed',
                subtitle:
                    'The interview was not completed and the application cannot continue',
              );
            }

            // Interview was cancelled
            if (status == 'InterviewCancelled') {
              return const EmptyState(
                icon: Icons.cancel_outlined,
                title: 'Interview Cancelled',
                subtitle:
                    'This interview was not completed',
              );
            }

            // Status is Pending — interview was completed,
            // cloud function is generating the report right now
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

          // ── Parse report fields ──
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

          // Score: Applications use 0-100, report field may also have
          // overallScore on a 0-10 scale — handle both
          final reportScore = report['overallScore'];
          double displayScore;
          double maxScore;

          if (score != null && score is num && score > 0) {
            // Use Application-level Score (0-100)
            displayScore = score.toDouble();
            maxScore = 100;
          } else if (reportScore != null && reportScore is num) {
            // Fallback to report-level overallScore (0-10)
            displayScore = reportScore.toDouble();
            maxScore = 10;
          } else {
            displayScore = 0;
            maxScore = 100;
          }

          final overallSummary = (report['overallSummary'] ??
                  'Your interview has been submitted for review.')
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
                      // ── Header Card ──
                      _buildHeaderCard(
                        context,
                        jobTitle: jobTitle,
                        companyName: companyName,
                        date: date,
                        status: status,
                      ),
                      const SizedBox(height: 20),

                      // ── Overview Section ──
                      _buildOverviewSection(
                        context,
                        score: displayScore,
                        maxScore: maxScore,
                        summary: overallSummary,
                      ),
                      const SizedBox(height: 20),

                      // ── Tabs Section ──
                      _buildTabsSection(
                        context,
                        strengths,
                        weaknesses,
                        advice,
                        voiceAnalysis,
                      ),
                    ],
                  ),
                ),
              ),

              // ── Done button (only when NOT from history) ──
              if (!widget.fromHistory)
                Padding(
                  padding: const EdgeInsets.all(20),
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

  // ════════════════════════════════════════════════════════
  // HEADER CARD
  // ════════════════════════════════════════════════════════
  Widget _buildHeaderCard(
    BuildContext context, {
    required String jobTitle,
    required String companyName,
    required Timestamp? date,
    required String status,
  }) {
    final dateStr = date != null
        ? DateFormat('MMM dd, yyyy').format(date.toDate())
        : 'Unknown date';

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final stClr = _statusColor(status);

    return Card(
      elevation: isDark ? 4 : 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppTheme.primaryPurple, Color(0xFF6B7FD7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row
            const Row(
              children: [
                Icon(Icons.work_rounded, color: Colors.white, size: 28),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Application Report',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Job title chip
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                jobTitle.isEmpty ? 'Job Application' : jobTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            // Company name
            if (companyName.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.business, color: Colors.white70, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    companyName,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 8),

            // Date row
            Row(
              children: [
                const Icon(Icons.calendar_today,
                    color: Colors.white70, size: 16),
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

            const SizedBox(height: 12),

            // Status chip
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_statusIcon(status), color: stClr, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    _formatStatus(status),
                    style: TextStyle(
                      color: stClr,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  // OVERVIEW SECTION (score circle + summary)
  // ════════════════════════════════════════════════════════
  Widget _buildOverviewSection(
    BuildContext context, {
    required double score,
    required double maxScore,
    required String summary,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final pct = maxScore > 0 ? score / maxScore : 0.0;

    Color scoreColor;
    String scoreLabel;
    if (pct >= 0.8) {
      scoreColor = Colors.green;
      scoreLabel = 'Excellent';
    } else if (pct >= 0.6) {
      scoreColor = const Color(0xFFFD6C67);
      scoreLabel = 'Good';
    } else {
      scoreColor = Colors.red;
      scoreLabel = 'Needs Improvement';
    }

    return Card(
      elevation: isDark ? 4 : 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Overview',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Score circle
                Column(
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 80,
                          height: 80,
                          child: CircularProgressIndicator(
                            value: pct,
                            strokeWidth: 8,
                            backgroundColor: Colors.grey[300],
                            valueColor:
                                AlwaysStoppedAnimation<Color>(scoreColor),
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              maxScore == 100
                                  ? score.toInt().toString()
                                  : score.toStringAsFixed(1),
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: scoreColor,
                              ),
                            ),
                            Text(
                              '/ ${maxScore.toInt()}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: scoreColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        scoreLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: scoreColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 20),
                // Summary text
                Expanded(
                  child: Text(
                    summary,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          height: 1.5,
                          fontSize: 14,
                        ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  // TABS SECTION (Strengths / Weaknesses / Tips / Voice)
  // ════════════════════════════════════════════════════════
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
      child: ListenableBuilder(
        listenable: _tabController,
        builder: (context, _) {
          return Column(
            children: [
              // Pill-style tab bar
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[850] : Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    _buildPillTab(context,
                        index: 0,
                        label: 'Strengths',
                        icon: Icons.star_rounded),
                    _buildPillTab(context,
                        index: 1,
                        label: 'Improve',
                        icon: Icons.trending_up_rounded),
                    _buildPillTab(context,
                        index: 2,
                        label: 'Tips',
                        icon: Icons.lightbulb_rounded),
                    _buildPillTab(context,
                        index: 3,
                        label: 'Voice Tone',
                        icon: Icons.mic_rounded),
                  ],
                ),
              ),

              // Tab content
              SizedBox(
                height: 500,
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildListTab(context,
                        items: strengths,
                        itemColor: Colors.green[700]!,
                        emptyMessage: 'No strengths identified yet.'),
                    _buildListTab(context,
                        items: weaknesses,
                        itemColor: const Color(0xFFFD6C67),
                        emptyMessage: 'No areas for improvement identified.'),
                    _buildListTab(context,
                        items: advice,
                        itemColor: AppTheme.primaryPurple,
                        emptyMessage: 'No recommendations yet.'),
                    _buildVoiceTab(context, voiceAnalysis),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Pill tab builder ──
  Widget _buildPillTab(
    BuildContext context, {
    required int index,
    required String label,
    required IconData icon,
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
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primaryPurple : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppTheme.primaryPurple.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected
                    ? Colors.white
                    : (isDark ? Colors.grey[400] : Colors.grey[600]),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight:
                      isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected
                      ? Colors.white
                      : (isDark ? Colors.grey[400] : Colors.grey[700]),
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── List tab ──
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
            style: const TextStyle(fontSize: 15, color: Colors.grey),
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
          padding:
              EdgeInsets.only(bottom: index < items.length - 1 ? 16 : 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 6),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: itemColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  items[index],
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        height: 1.6,
                        fontSize: 15,
                      ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Voice analysis tab (per story #33: voice feedback if available) ──
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

  // ── Voice metric bar ──
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








































