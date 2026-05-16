import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:gp_2025_11/config/theme.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:url_launcher/url_launcher.dart';

class CompanyReportsPage extends StatelessWidget {
  const CompanyReportsPage({
    super.key,
    required this.companyId,
  });

  final String companyId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      color: isDark ? scheme.background : const Color(0xFFF5F5F5),
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? scheme.background : const Color(0xFFF5F5F5),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(30),
                  topRight: Radius.circular(30),
                ),
              ),
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('Jobs')
                    .where('UserID', isEqualTo: companyId)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Failed to load jobs: ${snapshot.error}',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }

                  final jobs = snapshot.data?.docs.toList() ?? [];

                  jobs.sort((a, b) {
                    final aDate = _asDate(a.data()['PostedAt']) ??
                        _asDate(a.data()['StartDate']) ??
                        DateTime.fromMillisecondsSinceEpoch(0);
                    final bDate = _asDate(b.data()['PostedAt']) ??
                        _asDate(b.data()['StartDate']) ??
                        DateTime.fromMillisecondsSinceEpoch(0);
                    return bDate.compareTo(aDate);
                  });

                  if (jobs.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No job posts found for reports.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.all(20),
                    itemCount: jobs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 14),
                    itemBuilder: (context, index) {
                      final job = jobs[index];
                      final data = job.data();

                      final title =
                          (data['JobTitle'] ?? 'Untitled Job').toString();
                      final position = (data['Position'] ?? '').toString();
                      final specialty = (data['Specialty'] ?? '').toString();

                      return Container(
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 20,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 14,
                          ),
                          title: Text(
                            title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 17,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              [position, specialty]
                                  .where((e) => e.isNotEmpty)
                                  .join(' / '),
                            ),
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CompanyJobApplicationsPage(
                                  jobId: job.id,
                                  jobTitle: title,
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CompanyJobApplicationsPage extends StatefulWidget {
  const CompanyJobApplicationsPage({
    super.key,
    required this.jobId,
    required this.jobTitle,
  });

  final String jobId;
  final String jobTitle;

  @override
  State<CompanyJobApplicationsPage> createState() =>
      _CompanyJobApplicationsPageState();
}

class _CompanyJobApplicationsPageState
    extends State<CompanyJobApplicationsPage> {
  final Set<String> _selectedApplicationIds = {};
  bool _bulkLoading = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: const CustomHeader(title: 'Applications'),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('Applications')
            .where('JobID', isEqualTo: widget.jobId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Failed to load applications: ${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final apps = (snapshot.data?.docs ?? []).where((doc) {
            final s = (doc.data()['ApplicationStatus'] ?? '').toString();
            return s != 'InInterview' && s != 'InterviewCancelled';
          }).toList();

          if (apps.isEmpty) {
            return const Center(
              child: Padding(
                  padding: EdgeInsets.all(24),
                  child: EmptyState(
                      icon: Icons.work_outline_outlined,
                      title: 'No applications yet',
                      subtitle: 'There are no applications for this job yet')),
            );
          }

          apps.sort((a, b) {
            final scoreA = _finalScore(a.data());
            final scoreB = _finalScore(b.data());
            return scoreB.compareTo(scoreA);
          });

          return Column(
            children: [
              _ApplicationsSummary(apps: apps),
              if (_selectedApplicationIds.isNotEmpty)
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: scheme.primary.withOpacity(0.15),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '${_selectedApplicationIds.length} selected',
                        style: TextStyle(
                          color: scheme.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      PopupMenuButton<String>(
                        onSelected: _bulkLoading
                            ? null
                            : (value) async {
                                await _bulkUpdateStatus(
                                  context,
                                  apps,
                                  value,
                                );
                              },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'Shortlisted',
                            child: Text('Mark as Shortlisted'),
                          ),
                          PopupMenuItem(
                            value: 'Rejected',
                            child: Text('Mark as Rejected'),
                          ),
                        ],
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            //  color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.edit_outlined,
                                color: scheme.primary,
                                size: 25,
                              ),
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Clear selection',
                        onPressed: () {
                          setState(() {
                            _selectedApplicationIds.clear();
                          });
                        },
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  itemCount: apps.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final app = apps[index];
                    final data = app.data();
                    final applicantId = (data['UserID'] ?? '').toString();
                    final score = _finalScore(data);
                    final rank = _rankForIndex(apps, index);

                    return FutureBuilder<
                        DocumentSnapshot<Map<String, dynamic>>>(
                      future: FirebaseFirestore.instance
                          .collection('Users')
                          .doc(applicantId)
                          .get(),
                      builder: (context, userSnap) {
                        final user = userSnap.data?.data() ?? {};
                        final fullName =
                            (user['FullName'] ?? user['Name'] ?? 'Unknown')
                                .toString();
                        final photoUrl = (user['PhotoURL'] ?? '').toString();
                        final status =
                            (data['ApplicationStatus'] ?? 'Pending').toString();
                        final reportUrl = (data['ReportURL'] ?? '').toString();

                        return Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.08),
                                blurRadius: 18,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Checkbox(
                                      value: _selectedApplicationIds
                                          .contains(app.id),
                                      onChanged: (value) {
                                        setState(() {
                                          if (value == true) {
                                            _selectedApplicationIds.add(app.id);
                                          } else {
                                            _selectedApplicationIds
                                                .remove(app.id);
                                          }
                                        });
                                      },
                                    ),
                                    CircleAvatar(
                                      radius: 24,
                                      backgroundImage: photoUrl.isNotEmpty
                                          ? NetworkImage(photoUrl)
                                          : null,
                                      child: photoUrl.isEmpty
                                          ? const Icon(Icons.person)
                                          : null,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            fullName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 16,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Rank #$rank',
                                            style: TextStyle(
                                              color: scheme.primary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    _StatusChip(status: status),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _InfoBox(
                                        label: 'Final Score',
                                        value: '$score / 100',
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _ReportStatusBox(
                                          isAvailable: reportUrl.isNotEmpty),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                          side: const BorderSide(
                                            color: Color(0xFF4A5FBC),
                                            width: 2,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                        ),
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  CandidateDetailsPage(
                                                applicationId: app.id,
                                                applicationData: data,
                                                userData: user,
                                              ),
                                            ),
                                          );
                                        },
                                        child: const Text('View Details'),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: PopupMenuButton<String>(
                                        onSelected: (value) async {
                                          await _updateSingleStatus(
                                            context,
                                            applicationId: app.id,
                                            applicantId: applicantId,
                                            applicantName: fullName,
                                            newStatus: value,
                                          );
                                        },
                                        itemBuilder: (_) => const [
                                          PopupMenuItem(
                                            value: 'Shortlisted',
                                            child: Text('Shortlisted'),
                                          ),
                                          PopupMenuItem(
                                            value: 'Rejected',
                                            child: Text('Rejected'),
                                          ),
                                        ],
                                        child: Container(
                                          height: 40,
                                          decoration: BoxDecoration(
                                            color: scheme.primary,
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          alignment: Alignment.center,
                                          child: const Text(
                                            'Change Status',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  int _rankForIndex(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> apps,
    int index,
  ) {
    if (index == 0) return 1;

    final currentScore = _finalScore(apps[index].data());
    final previousScore = _finalScore(apps[index - 1].data());

    if (currentScore == previousScore) {
      return _rankForIndex(apps, index - 1);
    }

    return index + 1;
  }

  Future<void> _updateSingleStatus(
    BuildContext context, {
    required String applicationId,
    required String applicantId,
    required String applicantName,
    required String newStatus,
  }) async {
    if (!(newStatus == 'Shortlisted' || newStatus == 'Rejected')) {
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('Applications')
          .doc(applicationId)
          .update({
        'ApplicationStatus': newStatus,
        'StatusUpdatedAt': FieldValue.serverTimestamp(),
      });

      await _sendInAppNotification(
        userId: applicantId,
        title: 'Application Status Updated',
        body: 'Your application status is now: $newStatus',
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Status updated to $newStatus')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update status: $e')),
      );
    }
  }

  Future<void> _bulkUpdateStatus(
    BuildContext context,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> apps,
    String newStatus,
  ) async {
    final selectedApps =
        apps.where((app) => _selectedApplicationIds.contains(app.id)).toList();

    if (selectedApps.isEmpty) return;

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Confirm Bulk Update'),
            content: Text(
              'Update ${selectedApps.length} selected candidate(s) to $newStatus?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Confirm'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    setState(() => _bulkLoading = true);

    final failed = <String>[];

    for (final app in selectedApps) {
      try {
        final data = app.data();
        final applicantId = (data['UserID'] ?? '').toString();

        await FirebaseFirestore.instance
            .collection('Applications')
            .doc(app.id)
            .update({
          'ApplicationStatus': newStatus,
          'StatusUpdatedAt': FieldValue.serverTimestamp(),
        });

        await _sendInAppNotification(
          userId: applicantId,
          title: 'Application Status Updated',
          body: 'Your application status is now: $newStatus',
        );
      } catch (_) {
        failed.add(app.id);
      }
    }

    setState(() {
      _bulkLoading = false;
      _selectedApplicationIds.clear();
    });

    if (!context.mounted) return;

    if (failed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('All selected candidates updated to $newStatus')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Some updates failed (${failed.length}). You can retry those only.',
          ),
        ),
      );
    }
  }

  Future<void> _sendInAppNotification({
    required String userId,
    required String title,
    required String body,
  }) async {
    if (userId.isEmpty) return;

    await FirebaseFirestore.instance.collection('Notification').add({
      'UserID': userId,
      'Title': title,
      'Body': body,
      'CreatedAt': FieldValue.serverTimestamp(),
      'IsRead': false,
      'Type': 'application_status',
    });
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase();

    Color color;
    if (s == 'shortlisted') {
      color = Colors.green;
    } else if (s == 'rejected') {
      color = Colors.red;
    } else {
      color = Colors.orange;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreItem {
  final String label;
  final double score;
  final double weight;
  final double contribution;

  const _ScoreItem({
    required this.label,
    required this.score,
    required this.weight,
    required this.contribution,
  });

  String get weightText => '${(weight * 100).toStringAsFixed(0)}%';
}

List<_ScoreItem> _scoreBreakdown(Map<String, dynamic> data) {
  final cv = _pickScore(data, ['CVAnalysisScore', 'CvScore', 'cvScore'], 'CV');
  final jobMatch = _pickScore(
    data,
    ['JobRequirementsMatchScore', 'JobMatchScore', 'jobMatchScore'],
    'JobRequirementsMatch',
  );
  final psycho = _pickScore(
    data,
    ['PsychometricScore', 'psychometricScore'],
    'Psychometric',
  );
  final voice = _pickScore(
    data,
    ['VoiceToneScore', 'voiceToneScore'],
    'VoiceTone',
  );
  final technical = _pickScore(
    data,
    ['TechnicalEvaluationScore', 'TechnicalScore', 'technicalScore'],
    'TechnicalEvaluation',
  );

  return [
    _ScoreItem(
      label: 'CV Analysis',
      score: cv,
      weight: 0.30,
      contribution: cv * 0.30,
    ),
    _ScoreItem(
      label: 'Job Requirements Match',
      score: jobMatch,
      weight: 0.20,
      contribution: jobMatch * 0.20,
    ),
    _ScoreItem(
      label: 'Psychometric Analysis',
      score: psycho,
      weight: 0.20,
      contribution: psycho * 0.20,
    ),
    _ScoreItem(
      label: 'Voice Tone Analysis',
      score: voice,
      weight: 0.10,
      contribution: voice * 0.10,
    ),
    _ScoreItem(
      label: 'Technical Evaluation',
      score: technical,
      weight: 0.20,
      contribution: technical * 0.20,
    ),
  ];
}

int _finalScore(Map<String, dynamic> data) {
  if (data['Score'] != null) {
    final stored = _toDouble(data['Score']);
    return stored.round();
  }

  final items = _scoreBreakdown(data);
  final total = items.fold<double>(0, (sum, item) => sum + item.contribution);
  return total.round();
}

double _pickScore(
  Map<String, dynamic> data,
  List<String> flatKeys,
  String breakdownKey,
) {
  for (final key in flatKeys) {
    if (data[key] != null) {
      return _toDouble(data[key]).clamp(0, 100);
    }
  }

  final breakdown = data['ScoreBreakdown'];
  if (breakdown is Map<String, dynamic> && breakdown[breakdownKey] != null) {
    return _toDouble(breakdown[breakdownKey]).clamp(0, 100);
  }

  return 0;
}

double _toDouble(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value.toDouble();
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

DateTime? _asDate(dynamic v) {
  if (v == null) return null;
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
  return null;
}

String _formatDate(DateTime? date) {
  if (date == null) return '-';
  return '${date.day}/${date.month}/${date.year}';
}

Widget _detailRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 150,
          child: Text(
            '$label:',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

class _ApplicationsSummary extends StatelessWidget {
  const _ApplicationsSummary({required this.apps});

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> apps;

  @override
  Widget build(BuildContext context) {
    int countStatus(String status) {
      return apps.where((app) {
        final s = (app.data()['ApplicationStatus'] ?? 'Pending')
            .toString()
            .toLowerCase();
        return s == status.toLowerCase();
      }).length;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Row(
        children: [
          Expanded(child: _SummaryBox(label: 'Total', value: apps.length)),
          const SizedBox(width: 8),
          Expanded(
              child:
                  _SummaryBox(label: 'Pending', value: countStatus('Pending'))),
          const SizedBox(width: 8),
          Expanded(
              child: _SummaryBox(
                  label: 'Shortlisted', value: countStatus('Shortlisted'))),
          const SizedBox(width: 8),
          Expanded(
              child: _SummaryBox(
                  label: 'Rejected', value: countStatus('Rejected'))),
        ],
      ),
    );
  }
}

class _SummaryBox extends StatelessWidget {
  const _SummaryBox({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 14,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            '$value',
            style: TextStyle(
              color: scheme.primary,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _ReportStatusBox extends StatelessWidget {
  const _ReportStatusBox({required this.isAvailable});

  final bool isAvailable;

  @override
  Widget build(BuildContext context) {
    final color = isAvailable ? Colors.green : Colors.grey;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(
            isAvailable
                ? Icons.check_circle_rounded
                : Icons.hourglass_empty_rounded,
            color: color,
          ),
          const SizedBox(height: 6),
          Text(
            isAvailable ? 'Report ready' : 'No report yet',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreProgressItem extends StatelessWidget {
  const _ScoreProgressItem({required this.item});

  final _ScoreItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = (item.score / 100).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${item.label} (${item.weightText})',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                '${item.contribution.toStringAsFixed(1)} pts',
                style: TextStyle(
                  color: scheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            borderRadius: BorderRadius.circular(20),
          ),
          const SizedBox(height: 4),
          Text(
            '${item.score.toStringAsFixed(0)} / 100',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _PsychometricBar extends StatelessWidget {
  const _PsychometricBar({
    required this.label,
    required this.score,
    required this.color,
  });

  final String label;
  final double score;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final progress = (score / 100).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                '${score.toStringAsFixed(0)} / 100',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            borderRadius: BorderRadius.circular(20),
            color: color,
            backgroundColor: color.withOpacity(0.12),
          ),
        ],
      ),
    );
  }
}

class CandidateDetailsPage extends StatelessWidget {
  const CandidateDetailsPage({
    super.key,
    required this.applicationId,
    required this.applicationData,
    required this.userData,
  });

  final String applicationId;
  final Map<String, dynamic> applicationData;
  final Map<String, dynamic> userData;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final reportUrl = (applicationData['ReportURL'] ?? '').toString();
    final cvUrl = ((applicationData['ApplicationCVURL'] ??
                userData['CVURL'] ??
                userData['CvURL']) ??
            '')
        .toString();

    final fullName =
        (userData['FullName'] ?? userData['Name'] ?? 'Unknown').toString();
    final nationality = (userData['Nationality'] ?? '').toString();
    final phone = (userData['Phone'] ?? '').toString();
    final email =
        (userData['ContactEmail'] ?? userData['Email'] ?? '').toString();
    final photo = (userData['PhotoURL'] ?? '').toString();
    final dob = _formatDate(_asDate(userData['DoB']));
    final status =
        (applicationData['ApplicationStatus'] ?? 'Pending').toString();

    final breakdown = _scoreBreakdown(applicationData);
    final finalScore = _finalScore(applicationData);

    return Scaffold(
      appBar: const CustomHeader(title: 'Candidate Details'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 42,
                  backgroundImage:
                      photo.isNotEmpty ? NetworkImage(photo) : null,
                  child:
                      photo.isEmpty ? const Icon(Icons.person, size: 38) : null,
                ),
                const SizedBox(height: 12),
                Text(
                  fullName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                _StatusChip(status: status),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: scheme.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '$finalScore / 100',
                        style: TextStyle(
                          color: scheme.primary,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Final Score',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _SectionCard(
            title: 'Profile Information',
            children: [
              _detailRow('Full Name', fullName),
              _detailRow(
                  'Nationality', nationality.isEmpty ? '-' : nationality),
              _detailRow('Date of Birth', dob),
              _detailRow('Phone', phone.isEmpty ? '-' : phone),
              _detailRow('Email', email.isEmpty ? '-' : email),
            ],
          ),
          const SizedBox(height: 18),
          _SectionCard(
            title: 'Score Breakdown',
            children: [
              ...breakdown.map((item) => _ScoreProgressItem(item: item)),
            ],
          ),
          // ── Requirements Checklist (Story 34) ──
          if (applicationData['RequirementsChecklist'] != null &&
              (applicationData['RequirementsChecklist'] as List).isNotEmpty)
            ...[
              const SizedBox(height: 18),
              _SectionCard(
                title: 'Job Requirements Checklist',
                children: [
                  ...(applicationData['RequirementsChecklist'] as List)
                      .map<Widget>((item) {
                    final req = (item['requirement'] ?? '').toString();
                    final met = item['met'] == true;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 2),
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: (met ? Colors.green : Colors.red)
                                  .withOpacity(0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              met
                                  ? Icons.check_rounded
                                  : Icons.close_rounded,
                              size: 16,
                              color: met ? Colors.green : Colors.red,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              req,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ],

          // ── Psychometric Analysis (Story 34) ──
          if (applicationData['PsychometricAnalysis'] != null &&
              applicationData['PsychometricAnalysis'] is Map)
            ...[
              const SizedBox(height: 18),
              Builder(builder: (context) {
                final pa =
                    applicationData['PsychometricAnalysis'] as Map<String, dynamic>;
                final confidence = _toDouble(pa['confidence']);
                final communication = _toDouble(pa['communication']);
                final traits =
                    (pa['personalityTraits'] ?? '').toString();
                final workStyle = (pa['workStyle'] ?? '').toString();

                return _SectionCard(
                  title: 'Psychometric Analysis',
                  children: [
                    if (confidence > 0)
                      _PsychometricBar(
                        label: 'Confidence',
                        score: confidence,
                        color: scheme.primary,
                      ),
                    if (communication > 0)
                      _PsychometricBar(
                        label: 'Communication',
                        score: communication,
                        color: scheme.primary,
                      ),
                    if (traits.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _detailRow('Personality Traits', traits),
                    ],
                    if (workStyle.isNotEmpty)
                      _detailRow('Work Style', workStyle),
                  ],
                );
              }),
            ],

          // ── Voice Tone Analysis (Story 34) ──
          if (applicationData['VoiceToneAnalysis'] != null &&
              (applicationData['VoiceToneAnalysis'] as List).isNotEmpty)
            ...[
              const SizedBox(height: 18),
              Builder(builder: (context) {
                final voiceList =
                    applicationData['VoiceToneAnalysis'] as List;
                double total = 0;
                int count = 0;

                for (final item in voiceList) {
                  final result = (item['result'] ?? '').toString();
                  final match =
                      RegExp(r'Assessment Score:\s*([\d.]+)%')
                          .firstMatch(result);
                  if (match != null) {
                    total +=
                        double.tryParse(match.group(1)!) ?? 0;
                    count++;
                  }
                }

                final avgScore =
                    count > 0 ? (total / count).round() : 0;
                final avgColor = avgScore >= 70
                    ? Colors.green
                    : avgScore >= 40
                        ? Colors.orange
                        : Colors.red;

                return _SectionCard(
                  title: 'Voice Tone Analysis',
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: avgColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.mic_rounded,
                              color: avgColor, size: 28),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$avgScore / 100',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  color: avgColor,
                                ),
                              ),
                              const Text(
                                'Average Voice Confidence',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }),
            ],

          // ── Interview Q&A (Story 34) ──
          if (applicationData['Report'] != null &&
              applicationData['Report'] is Map &&
              applicationData['Report']['questionsAndAnswers'] != null)
            ...[
              const SizedBox(height: 18),
              _SectionCard(
                title: 'Interview Questions & Answers',
                children: [
                  ...(applicationData['Report']['questionsAndAnswers']
                          as List)
                      .asMap()
                      .entries
                      .map<Widget>((entry) {
                    final i = entry.key;
                    final qa = entry.value as Map<String, dynamic>;
                    final question = (qa['question'] ?? '').toString();
                    final answer = (qa['answer'] ?? '').toString();

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Q${i + 1}: $question',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: scheme.primary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: scheme.primary.withOpacity(0.04),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              answer,
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                          ),
                          if (i <
                              (applicationData['Report']
                                              ['questionsAndAnswers']
                                          as List)
                                      .length -
                                  1)
                            Padding(
                              padding:
                                  const EdgeInsets.only(top: 12),
                              child: Divider(
                                color: Colors.grey.shade200,
                                height: 1,
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ],

          const SizedBox(height: 18),
          _SectionCard(
            title: 'Documents',
            children: [
              Row(
                children: [
                  Expanded(
                    child: _DocumentButton(
                      title: 'View CV',
                      icon: Icons.visibility_outlined,
                      enabled: cvUrl.isNotEmpty,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => InAppPdfViewerPage(
                              title: 'CV',
                              pdfUrl: cvUrl,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DocumentButton(
                      title: 'Download CV',
                      icon: Icons.download_outlined,
                      enabled: cvUrl.isNotEmpty,
                      onTap: () => _downloadFileFromPage(
                        context,
                        url: cvUrl,
                        fileName: 'cv_$applicationId.pdf',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _DocumentButton(
                      title: 'View Report',
                      icon: Icons.description_outlined,
                      enabled: reportUrl.isNotEmpty,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => InAppPdfViewerPage(
                              title: 'Report',
                              pdfUrl: reportUrl,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DocumentButton(
                      title: 'Download Report',
                      icon: Icons.download_rounded,
                      enabled: reportUrl.isNotEmpty,
                      onTap: () => _downloadFileFromPage(
                        context,
                        url: reportUrl,
                        fileName: 'report_$applicationId.pdf',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

Future<void> _openUrlFromPage(BuildContext context, String url) async {
  try {
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open file')),
      );
    }
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Open failed: $e')),
    );
  }
}

Future<void> _downloadFileFromPage(
  BuildContext context, {
  required String url,
  required String fileName,
}) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final savePath = '${dir.path}/$fileName';

    await Dio().download(url, savePath);

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Downloaded successfully: $fileName'),
        action: SnackBarAction(
          label: 'Open',
          onPressed: () {
            OpenFilex.open(savePath);
          },
        ),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Download failed: $e')),
    );
  }
}

class _DocumentButton extends StatelessWidget {
  const _DocumentButton({
    required this.title,
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return OutlinedButton.icon(
      onPressed: enabled ? onTap : null,
      icon: Icon(icon),
      label: Text(title),
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.primary,
        side: BorderSide(
          color: enabled ? scheme.primary : Colors.grey.withOpacity(0.4),
          width: 1.5,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class InAppPdfViewerPage extends StatelessWidget {
  const InAppPdfViewerPage({
    super.key,
    required this.title,
    required this.pdfUrl,
  });

  final String title;
  final String pdfUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomHeader(title: title),
      body: SfPdfViewer.network(
        pdfUrl,
        canShowScrollHead: true,
        canShowScrollStatus: true,
        enableDoubleTapZooming: true,
      ),
    );
  }
}