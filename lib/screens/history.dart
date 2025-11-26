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
    return Column(
      children: [
        _buildTabs(context),
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
    );
  }

  Widget _buildTabs(BuildContext context) {
    return Container(
      color: AppTheme.primaryPurple,
      child: TabBar(
        controller: _tabController,
        indicatorColor: Colors.white,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white70,
        tabs: const [
          Tab(
            child: Text(
              'CV Enhancement',
              textAlign: TextAlign.center, // ← ضيفي هذا السطر
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
          Tab(
            child: Text(
              'Mock Interview',
              textAlign: TextAlign.center, // ← ضيفي هذا السطر
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
          Tab(
            child: Text(
              'Job Application',
              textAlign: TextAlign.center, // ← ضيفي هذا السطر
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
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
                      isFromHistory: true, // ← نضيف هذا
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
              leadingBgColor: AppTheme.primaryPurple,
              onTap: () {
                // TODO: open mock interview details later
              },
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
              leadingBgColor: AppTheme.primaryPurple,
              onTap: () {
                // TODO: open job application details later
              },
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
    return Material(
      color: Colors.white,
      elevation: 1.5,
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
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.black45),
            ],
          ),
        ),
      ),
    );
  }
}
