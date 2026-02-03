import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:gp_2025_11/config/theme.dart';
import 'package:gp_2025_11/screens/cv_ready.dart';

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
                      tabs: const [
                        Tab(
                          child: Text(
                            'CV Enhancement',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        Tab(
                          child: Text(
                            'Mock Interview',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        Tab(
                          child: Text(
                            'Job Application',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
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

  // ---------------- CV HISTORY ----------------
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
        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final date = (data['Date'] as Timestamp?)?.toDate();
            final title = (data['JobTitle'] ?? 'CV Enhancement').toString();
            final cvHistoryId =
                (data['CVHistoryID'] ?? docs[index].id).toString();

            return _historyTile(
              context,
              title: title.isEmpty ? 'CV Enhancement' : title,
              subtitle: date != null
                  ? DateFormat('MMM dd, yyyy - hh:mm a').format(date)
                  : '',
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
            );
          },
        );
      },
    );
  }

  // ---------------- MOCK INTERVIEW HISTORY ----------------
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
        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final date = (data['Date'] as Timestamp?)?.toDate();
            final specialty =
                (data['Specialty'] ?? 'Mock Interview').toString();

            return _historyTile(
              context,
              title: specialty.isEmpty ? 'Mock Interview' : specialty,
              subtitle: date != null
                  ? DateFormat('MMM dd, yyyy - hh:mm a').format(date)
                  : '',
              leadingIcon: Icons.mic,
              leadingBgColor: AppTheme.accentCoral,
              onTap: () {},
            );
          },
        );
      },
    );
  }

  // ---------------- JOB APPLICATIONS HISTORY ----------------
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
        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final date = (data['Date'] as Timestamp?)?.toDate();
            final jobTitle = (data['JobTitle'] ?? 'Job Application').toString();
            final status = (data['ApplicationStatus'] ?? '').toString();

            return _historyTile(
              context,
              title: jobTitle.isEmpty ? 'Job Application' : jobTitle,
              subtitle: [
                if (date != null)
                  DateFormat('MMM dd, yyyy - hh:mm a').format(date),
                if (status.isNotEmpty) status,
              ].join('  •  '),
              leadingIcon: Icons.work,
              leadingBgColor: AppTheme.accentCoral,
              onTap: () {},
            );
          },
        );
      },
    );
  }

  // ---------------- SHARED WIDGETS ----------------
  Widget _historyTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData leadingIcon,
    required Color leadingBgColor,
    VoidCallback? onTap,
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
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? scheme.onSurface.withOpacity(0.7)
                            : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
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
