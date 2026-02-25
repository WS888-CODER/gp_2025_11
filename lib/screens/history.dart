import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:gp_2025_11/config/theme.dart';
import 'package:gp_2025_11/screens/cv_ready.dart';
import 'package:gp_2025_11/screens/mock_interview_report.dart';
import 'package:gp_2025_11/screens/job_interview_report.dart'; // ← NEW

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── Status helpers ──────────────────────────────────────
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      color: isDark ? scheme.background : const Color(0xFFF5F5F5),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [scheme.primary, scheme.primary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(40),
                bottomRight: Radius.circular(40),
              ),
              boxShadow: [
                BoxShadow(
                  color: scheme.primary.withOpacity(isDark ? 0.6 : 0.4),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Stack(
              children: [
                Positioned(
                  top: -60,
                  right: -40,
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(isDark ? 0.03 : 0.06),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 20,
                  left: -30,
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(isDark ? 0.03 : 0.06),
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 60),
                    const Text(
                      'History',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TabBar(
                      controller: _tabController,
                      indicatorColor: Colors.white,
                      indicatorWeight: 3,
                      dividerColor: Colors.transparent,
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.white70,
                      labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                      tabs: const [
                        Tab(
                          child: Text(
                            'CV Enhancement',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Tab(
                          child: Text(
                            'Mock Interview',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Tab(
                          child: Text(
                            'Job Application',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildCVHistory(context),
                _buildMockInterviewHistory(context),
                _buildJobApplicationsHistory(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════ CV HISTORY ════════════════════
  Widget _buildCVHistory(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const EmptyState(
        icon: Icons.description_outlined,
        title: 'No CV Enhancements Yet',
        subtitle: 'Your CV enhancement history will appear here',
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('CVHistory')
          .where('UserID', isEqualTo: user.uid)
          .orderBy('Date', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const EmptyState(
            icon: Icons.description_outlined,
            title: 'No CV Enhancements Yet',
            subtitle: 'Your CV enhancement history will appear here',
          );
        }

        final docs = snapshot.data!.docs;

        final enhancedCVs = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final newCVText = data['NewCVText'];
          if (newCVText == null) return false;
          if (newCVText is String && newCVText.isEmpty) return false;
          if (newCVText is List && newCVText.isEmpty) return false;
          return true;
        }).toList();

        if (enhancedCVs.isEmpty) {
          return const EmptyState(
            icon: Icons.description_outlined,
            title: 'No CV Enhancements Yet',
            subtitle: 'Your CV enhancement history will appear here',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: enhancedCVs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final data = enhancedCVs[index].data() as Map<String, dynamic>;
            final date = (data['Date'] as Timestamp?)?.toDate();
            final title = (data['JobTitle'] ?? 'CV Enhancement').toString();
            final cvHistoryId =
                (data['CVHistoryID'] ?? enhancedCVs[index].id).toString();

            int? daysLeft;
            String? expiryText;
            Color? expiryColor;

            if (date != null) {
              final now = DateTime.now();
              final age = now.difference(date).inDays;
              daysLeft = 30 - age;

              if (daysLeft <= 0) {
                expiryText = 'Expires today';
                expiryColor = Colors.red;
              } else if (daysLeft <= 9) {
                expiryText = '$daysLeft days left';
                expiryColor = Colors.red;
              } else if (daysLeft <= 19) {
                expiryText = '$daysLeft days left';
                expiryColor = Colors.orange;
              } else {
                expiryText = '$daysLeft days left';
                expiryColor = Colors.green;
              }
            }

            final subtitleText =
                date != null ? DateFormat('MMM dd, yyyy').format(date) : '';

            return _historyTile(
              context,
              title: title.isEmpty ? 'CV Enhancement' : title,
              subtitle: subtitleText,
              expiryText: expiryText,
              expiryColor: expiryColor,
              leadingIcon: Icons.description,
              leadingBgColor: AppTheme.accentCoral,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PublishScreen(
                      cvUrl: cvHistoryId,
                      isFromHistory: true,
                    ),
                  ),
                );
              },
              onDelete: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => const JadeerDialog<bool>(
                    title: 'Delete CV Enhancement',
                    content: Text(
                      'Are you sure you want to delete this CV enhancement? This action cannot be undone.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 15,
                      ),
                    ),
                    secondaryLabel: 'Cancel',
                    secondaryResult: false,
                    primaryLabel: 'Delete',
                    primaryResult: true,
                  ),
                );

                if (confirm == true) {
                  try {
                    await FirebaseFirestore.instance
                        .collection('CVHistory')
                        .doc(cvHistoryId)
                        .delete();

                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('CV enhancement deleted successfully'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error deleting CV: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
              },
            );
          },
        );
      },
    );
  }

  // ════════════════════ MOCK INTERVIEW HISTORY ════════════════════
  Widget _buildMockInterviewHistory(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const EmptyState(
        icon: Icons.mic_none,
        title: 'No Mock Interviews Yet',
        subtitle: 'Your mock interview history will appear here',
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('MockInterviews')
          .where('UserID', isEqualTo: user.uid)
          .orderBy('Date', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const EmptyState(
            icon: Icons.mic_none,
            title: 'No Mock Interviews Yet',
            subtitle: 'Your mock interview history will appear here',
          );
        }

        final docs = snapshot.data!.docs;

        final completedInterviews = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return true;
        }).toList();

        if (completedInterviews.isEmpty) {
          return const EmptyState(
            icon: Icons.mic_none,
            title: 'No Mock Interviews Yet',
            subtitle: 'Your mock interview history will appear here',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: completedInterviews.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final data =
                completedInterviews[index].data() as Map<String, dynamic>;
            final date = (data['Date'] as Timestamp?)?.toDate();
            final specialty =
                (data['Specialty'] ?? 'Mock Interview').toString();
            final mockInterviewId = completedInterviews[index].id;

            int? daysLeft;
            String? expiryText;
            Color? expiryColor;

            if (date != null) {
              final now = DateTime.now();
              final age = now.difference(date).inDays;
              daysLeft = 30 - age;

              if (daysLeft <= 0) {
                expiryText = 'Expires today';
                expiryColor = Colors.red;
              } else if (daysLeft <= 9) {
                expiryText = '$daysLeft days left';
                expiryColor = Colors.red;
              } else if (daysLeft <= 19) {
                expiryText = '$daysLeft days left';
                expiryColor = Colors.orange;
              } else {
                expiryText = '$daysLeft days left';
                expiryColor = Colors.green;
              }
            }

            final subtitleText =
                date != null ? DateFormat('MMM dd, yyyy').format(date) : '';

            return _historyTile(
              context,
              title: specialty.isEmpty ? 'Mock Interview' : specialty,
              subtitle: subtitleText,
              expiryText: expiryText,
              expiryColor: expiryColor,
              leadingIcon: Icons.mic,
              leadingBgColor: AppTheme.accentCoral,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MockInterviewReportScreen(
                      mockInterviewID: mockInterviewId,
                      fromHistory: true,
                    ),
                  ),
                );
              },
              onDelete: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => const JadeerDialog<bool>(
                    title: 'Delete Mock Interview',
                    content: Text(
                      'Are you sure you want to delete this mock interview? This action cannot be undone.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 15,
                      ),
                    ),
                    secondaryLabel: 'Cancel',
                    secondaryResult: false,
                    primaryLabel: 'Delete',
                    primaryResult: true,
                  ),
                );

                if (confirm == true) {
                  try {
                    await FirebaseFirestore.instance
                        .collection('MockInterviews')
                        .doc(mockInterviewId)
                        .delete();

                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content:
                              Text('Mock interview deleted successfully'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content:
                              Text('Error deleting mock interview: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
              },
            );
          },
        );
      },
    );
  }

  // ════════════════════ JOB APPLICATIONS HISTORY ════════════════════
  Widget _buildJobApplicationsHistory(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const EmptyState(
        icon: Icons.work_outline,
        title: 'No Job Applications Yet',
        subtitle: 'Your job application history will appear here',
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('Applications')
          .where('UserID', isEqualTo: user.uid)
          .orderBy('Date', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const EmptyState(
            icon: Icons.work_outline,
            title: 'No Job Applications Yet',
            subtitle: 'Your job application history will appear here',
          );
        }

        final docs = snapshot.data!.docs;

        final validApps = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final status = (data['ApplicationStatus'] ?? '').toString();
          return status != 'InterviewCancelled' && status != 'InInterview';
        }).toList();

        if (validApps.isEmpty) {
          return const EmptyState(
            icon: Icons.work_outline,
            title: 'No Job Applications Yet',
            subtitle: 'Your job application history will appear here',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: validApps.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final data = validApps[index].data() as Map<String, dynamic>;
            final date = (data['Date'] as Timestamp?)?.toDate();
            final jobTitle =
                (data['JobTitle'] ?? 'Job Application').toString();
            final companyName = (data['CompanyName'] ?? '').toString();
            final status = (data['ApplicationStatus'] ?? '').toString();
            final applicationId = validApps[index].id;

            // ── Expiry badge (only for Rejected applications) ──
            int? daysLeft;
            String? expiryText;
            Color? expiryColor;

            if (status == 'Rejected') {
              final DateTime? expiryDate;

              if (date != null) {
                expiryDate = date.add(const Duration(days: 180));
              } else {
                expiryDate = null;
              }

              if (expiryDate != null) {
                daysLeft = expiryDate.difference(DateTime.now()).inDays;

                if (daysLeft <= 0) {
                  expiryText = 'Expired';
                  expiryColor = Colors.red;
                } else if (daysLeft <= 14) {
                  expiryText = '$daysLeft days left';
                  expiryColor = Colors.red;
                } else if (daysLeft <= 30) {
                  expiryText = '$daysLeft days left';
                  expiryColor = Colors.orange;
                } else {
                  expiryText = '$daysLeft days left';
                  expiryColor = Colors.green;
                }
              }
            }

            // ── Subtitle ──
            final subtitleParts = <String>[];
            if (companyName.isNotEmpty) subtitleParts.add(companyName);
            if (date != null) {
              subtitleParts.add(DateFormat('MMM dd, yyyy').format(date));
            }
            final subtitleText = subtitleParts.join('  •  ');

            return _historyTile(
              context,
              title: jobTitle.isEmpty ? 'Job Application' : jobTitle,
              subtitle: subtitleText,
              expiryText: expiryText,
              expiryColor: expiryColor,
              statusText:
                  status.isNotEmpty ? _formatStatus(status) : null,
              statusColor:
                  status.isNotEmpty ? _statusColor(status) : null,
              leadingIcon: Icons.work,
              leadingBgColor: AppTheme.accentCoral,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => JobInterviewReportScreen(
                      applicationId: applicationId,
                      fromHistory: true,
                    ),
                  ),
                );
              },
              onDelete: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => const JadeerDialog<bool>(
                    title: 'Delete Application',
                    content: Text(
                      'Are you sure you want to delete this job application? This action cannot be undone.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 15,
                      ),
                    ),
                    secondaryLabel: 'Cancel',
                    secondaryResult: false,
                    primaryLabel: 'Delete',
                    primaryResult: true,
                  ),
                );

                if (confirm == true) {
                  try {
                    await FirebaseFirestore.instance
                        .collection('Applications')
                        .doc(applicationId)
                        .delete();

                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content:
                              Text('Application deleted successfully'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content:
                              Text('Error deleting application: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
              },
            );
          },
        );
      },
    );
  }

  // ════════════════════ SHARED TILE WIDGET ════════════════════
  Widget _historyTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    String? expiryText,
    Color? expiryColor,
    String? statusText,
    Color? statusColor,
    required IconData leadingIcon,
    required Color leadingBgColor,
    VoidCallback? onTap,
    VoidCallback? onDelete,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: isDark ? scheme.surface : Colors.white,
      elevation: isDark ? 0 : 1,
      shadowColor: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: leadingBgColor,
                child: Icon(leadingIcon, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: isDark ? scheme.onSurface : Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),

                    // Date (left) + Status & Expiry (right)
                    Row(
                      children: [
                        // Date on the left
                        Expanded(
                          child: Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? scheme.onSurface.withOpacity(0.7)
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ),

                        // Status + Expiry stacked on the right
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (statusText != null && statusColor != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(12),
                                  border:
                                      Border.all(color: statusColor, width: 1),
                                ),
                                child: Text(
                                  statusText,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: statusColor,
                                  ),
                                ),
                              ),
                            if (expiryColor != null && expiryText != null) ...[
                              if (statusText != null) const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: expiryColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border:
                                      Border.all(color: expiryColor, width: 1),
                                ),
                                child: Text(
                                  expiryText,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: expiryColor,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (onDelete != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  color: Colors.red.shade400,
                  iconSize: 22,
                  onPressed: onDelete,
                  tooltip: 'Delete',
                ),
              Icon(Icons.chevron_right,
                  color: isDark
                      ? scheme.onSurface.withOpacity(0.5)
                      : Colors.black45),
            ],
          ),
        ),
      ),
    );
  }
}