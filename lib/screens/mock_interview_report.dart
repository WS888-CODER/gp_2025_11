import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../config/theme.dart';
import 'package:gp_2025_11/screens/jobseeker_home.dart';

class MockInterviewReportScreen extends StatelessWidget {
  final String mockInterviewID;
  final bool fromHistory;

  const MockInterviewReportScreen({
    Key? key,
    required this.mockInterviewID,
    this.fromHistory = false,
  }) : super(key: key);

  @override
  @override
Widget build(BuildContext context) {
  return ThemedScaffold(
    appBar: const CustomHeader(
      title: 'Interview Report',
      showBack: true,
    ),
    body: StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('MockInterviews')
          .doc(mockInterviewID)
          .snapshots(),
      builder: (context, snapshot) {
        // Loading state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(
              color: AppTheme.primaryPurple,
            ),
          );
        }

        // Error state
        if (snapshot.hasError) {
          return const EmptyState(
            icon: Icons.error_outline,
            title: 'Error loading report',
            subtitle: 'Please try again later',
          );
        }

        // No data
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

        // Report not generated yet
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

        // Extract report data
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

        // Display report
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Card
              _buildHeaderCard(context, specialty, date),
              const SizedBox(height: 20),

              // Strengths Section
              if (strengths.isNotEmpty) ...[
                _buildSectionCard(
                  context,
                  title: 'Strengths',
                  icon: Icons.star_rounded,
                  iconColor: Colors.green,
                  items: strengths,
                  itemColor: Colors.green[700]!,
                ),
                const SizedBox(height: 16),
              ],

              // Weaknesses Section
              if (weaknesses.isNotEmpty) ...[
                _buildSectionCard(
                  context,
                  title: 'Areas for Improvement',
                  icon: Icons.trending_up_rounded,
                  iconColor: Colors.orange,
                  items: weaknesses,
                  itemColor: Colors.orange[700]!,
                ),
                const SizedBox(height: 16),
              ],

              // Advice Section
              if (advice.isNotEmpty) ...[
                _buildSectionCard(
                  context,
                  title: 'Recommendations',
                  icon: Icons.lightbulb_rounded,
                  iconColor: AppTheme.primaryPurple,
                  items: advice,
                  itemColor: AppTheme.primaryPurple,
                ),
                const SizedBox(height: 16),
              ],

              // Voice Analysis Section
              _buildVoiceAnalysisCard(context, voiceAnalysis),

              const SizedBox(height: 24),
            ],
          ),
        );
      },
    ),
  );
}

  Widget _buildHeaderCard(BuildContext context, String specialty, Timestamp? date) {
    final dateStr = date != null
        ? '${date.toDate().day}/${date.toDate().month}/${date.toDate().year}'
        : 'Unknown date';

    final isDark = Theme.of(context).brightness == Brightness.dark;

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
      ),
    );
  }

  Widget _buildSectionCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color iconColor,
    required List<String> items,
    required Color itemColor,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      elevation: isDark ? 4 : 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor, size: 24),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontSize: 18,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...items.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              return Padding(
                padding: EdgeInsets.only(
                  bottom: index < items.length - 1 ? 12 : 0,
                ),
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
                        item,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              height: 1.6,
                              fontSize: 15,
                            ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceAnalysisCard(BuildContext context, Map<String, dynamic>? voiceAnalysis) {
    final isAvailable = voiceAnalysis?['available'] == true;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      elevation: isDark ? 4 : 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (isAvailable ? Colors.purple : Colors.grey).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isAvailable ? Icons.mic_rounded : Icons.info_outline_rounded,
                    color: isAvailable ? Colors.purple : Colors.grey,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Voice Tone Analysis',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontSize: 18,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (isAvailable) ...[
              _buildVoiceMetric(
                context,
                'Confidence',
                voiceAnalysis?['confidence'] ?? 0,
                Colors.blue,
              ),
              const SizedBox(height: 12),
              _buildVoiceMetric(
                context,
                'Clarity',
                voiceAnalysis?['clarity'] ?? 0,
                Colors.green,
              ),
              const SizedBox(height: 12),
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
            ] else ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.schedule_rounded, color: Colors.orange[700], size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        voiceAnalysis?['message'] ??
                            'Voice analysis will be available soon',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[700],
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
    );
  }

  Widget _buildVoiceMetric(BuildContext context, String label, int value, Color color) {
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