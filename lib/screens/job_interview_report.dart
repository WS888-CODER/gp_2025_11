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

          if (report == null) {
            if (status == 'InInterview') {
              return const EmptyState(
                icon: Icons.play_circle_outline,
                title: 'Interview Not Completed',
                subtitle:
                    'The interview was not completed and the application cannot continue',
              );
            }

            if (status == 'InterviewCancelled') {
              return const EmptyState(
                icon: Icons.cancel_outlined,
                title: 'Interview Cancelled',
                subtitle: 'This interview was not completed',
              );
            }

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
          final List<dynamic> voiceAnalysisList =
              data['VoiceToneAnalysis'] as List<dynamic>? ?? [];

          final overallSummary = (report['overallSummary'] ??
              'Your interview has been submitted for review.') as String;

          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeaderCard(
                        context,
                        jobTitle: jobTitle,
                        companyName: companyName,
                        date: date,
                        status: status,
                      ),
                      const SizedBox(height: 20),
                      _buildOverviewSection(
                        context,
                        summary: overallSummary,
                      ),
                      const SizedBox(height: 20),
                      _buildTabsSection(
                        context,
                        strengths: strengths,
                        weaknesses: weaknesses,
                        advice: advice,
                        voiceAnalysisList: voiceAnalysisList,
                      ),
                    ],
                  ),
                ),
              ),
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
            Row(
              children: [
                const Icon(Icons.work_rounded, color: Colors.white, size: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    jobTitle.isEmpty ? 'Job Application' : jobTitle,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (companyName.isNotEmpty) ...[
              Text(
                companyName,
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 15,
                    fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 4),
            ],
            Text(
              dateStr,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(20)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_statusIcon(status), color: stClr, size: 16),
                  const SizedBox(width: 6),
                  Text(_formatStatus(status),
                      style: TextStyle(
                          color: stClr,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewSection(
    BuildContext context, {
    required String summary,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.insights_rounded,
                color: AppTheme.primaryPurple,
                size: 22,
              ),
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
          const SizedBox(height: 16),
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
    BuildContext context, {
    required List<String> strengths,
    required List<String> weaknesses,
    required List<String> advice,
    required List<dynamic> voiceAnalysisList,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // ── حساب السكور هنا عشان نعرف إذا الـ Voice tab محتاج height خاص ──
    final isVoiceTab = _tabController.index == 3;

    return Container(
      clipBehavior: Clip.antiAlias,
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
      child: AnimatedBuilder(
        animation: _tabController,
        builder: (context, _) {
          final isVoice = _tabController.index == 3;
          return Column(
            children: [
              // ── Pill Tab Bar ──
              Container(
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
              ),

              // ── Tab Content ──
              if (isVoice)
                // Voice tab: الدائرة ثابتة + الأسئلة تسكرول داخلها
                _buildVoiceContent(context, voiceAnalysisList)
              else
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: _buildSelectedTabContent(
                    context,
                    strengths: strengths,
                    weaknesses: weaknesses,
                    advice: advice,
                    voiceAnalysisList: voiceAnalysisList,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

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

  Widget _buildSelectedTabContent(
    BuildContext context, {
    required List<String> strengths,
    required List<String> weaknesses,
    required List<String> advice,
    required List<dynamic> voiceAnalysisList,
  }) {
    switch (_tabController.index) {
      case 0:
        return _buildListContent(
          context,
          items: strengths,
          itemColor: Colors.green[700]!,
          emptyMessage: 'No strengths identified yet.',
        );
      case 1:
        return _buildListContent(
          context,
          items: weaknesses,
          itemColor: const Color(0xFFFD6C67),
          emptyMessage: 'No areas for improvement identified.',
        );
      case 2:
        return _buildListContent(
          context,
          items: advice,
          itemColor: AppTheme.primaryPurple,
          emptyMessage: 'No recommendations yet.',
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildListContent(
    BuildContext context, {
    required List<String> items,
    required Color itemColor,
    required String emptyMessage,
  }) {
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          emptyMessage,
          style: const TextStyle(fontSize: 15, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items.asMap().entries.map((entry) {
        final index = entry.key;
        final item = entry.value;
        return Padding(
          padding: EdgeInsets.only(bottom: index < items.length - 1 ? 16 : 0),
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
                  item,
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
      }).toList(),
    );
  }

  // ════════════════════════════════════════════════════════
  // VOICE TAB — دائرة ثابتة + أسئلة تسكرول لوحدها
  // اللوجيك والربط ما تغير
  // ════════════════════════════════════════════════════════
  Widget _buildVoiceContent(BuildContext context, List<dynamic> voiceList) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // ── Empty state ──
    if (voiceList.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
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
      );
    }

    // ── حساب السكور — نفس اللوجيك الأصلي ما تغير ──
    double totalScore = 0.0;
    for (var item in voiceList) {
      final String resultText = (item['result'] ?? '').toString();
      if (!resultText.contains('REJECTED')) {
        final match =
            RegExp(r'Assessment Score:\s*([\d.]+)%').firstMatch(resultText);
        if (match != null) {
          totalScore += double.tryParse(match.group(1) ?? '0.0') ?? 0.0;
        }
      }
    }

    final int totalPercentage =
        voiceList.isNotEmpty ? (totalScore / voiceList.length).round() : 0;

    Color ringColor;
    String evaluationText;
    if (totalPercentage >= 80) {
      ringColor = const Color(0xFF2E7D32);
      evaluationText = 'Excellent';
    } else if (totalPercentage >= 50) {
      ringColor = const Color(0xFFE67E22);
      evaluationText = 'Good';
    } else {
      ringColor = const Color(0xFFC0392B);
      evaluationText = 'Needs Improvement';
    }

    return Column(
      children: [
        // ── الدائرة ثابتة — ما تسكرول ──
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[900] : Colors.grey[50],
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.withOpacity(0.1)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Glowing circular progress — نفس التصميم الأصلي
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 85,
                      height: 85,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: ringColor.withOpacity(0.2),
                            blurRadius: 20,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 75,
                      height: 75,
                      child: CircularProgressIndicator(
                        value: 1.0,
                        strokeWidth: 7,
                        strokeCap: StrokeCap.round,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isDark ? Colors.grey[800]! : Colors.grey[200]!,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 75,
                      height: 75,
                      child: CircularProgressIndicator(
                        value: totalPercentage / 100,
                        strokeWidth: 7,
                        strokeCap: StrokeCap.round,
                        backgroundColor: Colors.transparent,
                        valueColor: AlwaysStoppedAnimation<Color>(ringColor),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$totalPercentage%',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: ringColor,
                            height: 1,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                // Label & pill — نفس التصميم الأصلي
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Overall Vocal Confidence',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: ringColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: ringColor.withOpacity(0.3),
                            width: 1.0,
                          ),
                        ),
                        child: Text(
                          evaluationText,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: ringColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // ── الأسئلة تسكرول لوحدها بـ height ثابت ──
        SizedBox(
          height: 320,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            itemCount: voiceList.length,
            itemBuilder: (context, index) {
              final item = voiceList[index] as Map<String, dynamic>? ?? {};
              final int qIndex = item['questionIndex'] as int? ?? index;
              final String resultText = item['result'] as String? ?? 'N/A';

              return Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 6, right: 10),
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF2196F3),
                        shape: BoxShape.circle,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Question ${qIndex + 1}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF2196F3),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            resultText,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              height: 1.6,
                              color: isDark ? Colors.grey[300] : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
