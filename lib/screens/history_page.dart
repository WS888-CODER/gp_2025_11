import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:gp_2025_11/config/theme.dart';

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
        Container(
          color: AppTheme.primaryPurple,
          child: TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: const [
              Tab(text: 'CV Enhancements'),
              Tab(text: 'Mock Interviews'),
              Tab(text: 'Job Applications'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [
              CVEnhancementsTab(),
              MockInterviewsTab(),
              JobApplicationsTab(),
            ],
          ),
        ),
      ],
    );
  }
}

class CVEnhancementsTab extends StatelessWidget {
  const CVEnhancementsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid ?? '';

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('CVHistory')
          .where('UserID', isEqualTo: userId)
          .orderBy('Date', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return _buildEmptyState(
            icon: Icons.description_outlined,
            title: 'No CV Enhancements Yet',
            subtitle: 'Your CV enhancement history will appear here',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final date = (data['Date'] as Timestamp?)?.toDate();
            final jobTitle = data['JobTitle'] ?? 'N/A';

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFF4A5FBC),
                  child: Icon(Icons.description, color: Colors.white),
                ),
                title: Text(
                  jobTitle.isEmpty ? 'CV Enhancement' : jobTitle,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  date != null
                      ? DateFormat('MMM dd, yyyy - hh:mm a').format(date)
                      : 'Date not available',
                ),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              ),
            );
          },
        );
      },
    );
  }
}

class MockInterviewsTab extends StatelessWidget {
  const MockInterviewsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid ?? '';

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('MockInterviews')
          .where('UserID', isEqualTo: userId)
          .orderBy('Date', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return _buildEmptyState(
            icon: Icons.mic_none,
            title: 'No Mock Interviews Yet',
            subtitle: 'Your mock interview history will appear here',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final date = (data['Date'] as Timestamp?)?.toDate();
            final specialty = data['Specialty'] ?? 'N/A';

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFF4A5FBC),
                  child: Icon(Icons.mic, color: Colors.white),
                ),
                title: Text(
                  specialty.isEmpty ? 'Mock Interview' : specialty,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  date != null
                      ? DateFormat('MMM dd, yyyy - hh:mm a').format(date)
                      : 'Date not available',
                ),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              ),
            );
          },
        );
      },
    );
  }
}

class JobApplicationsTab extends StatelessWidget {
  const JobApplicationsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid ?? '';

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('Applications')
          .where('UserID', isEqualTo: userId)
          .orderBy('Date', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return _buildEmptyState(
            icon: Icons.work_outline,
            title: 'No Job Applications Yet',
            subtitle: 'Your job application history will appear here',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final date = (data['Date'] as Timestamp?)?.toDate();
            final jobId = data['JobID'] ?? '';
            final status = data['ApplicationStatus'] ?? 'Pending';

            return FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('Jobs')
                  .doc(jobId)
                  .get(),
              builder: (context, jobSnapshot) {
                String jobTitle = 'Job Application';

                if (jobSnapshot.hasData && jobSnapshot.data!.exists) {
                  final jobData =
                      jobSnapshot.data!.data() as Map<String, dynamic>;
                  jobTitle = jobData['JobTitle'] ?? 'Job Application';
                }

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: _getStatusColor(status),
                      child: const Icon(Icons.work, color: Colors.white),
                    ),
                    title: Text(
                      jobTitle,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          date != null
                              ? DateFormat('MMM dd, yyyy').format(date)
                              : 'Date not available',
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _getStatusColor(status).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            status,
                            style: TextStyle(
                              fontSize: 12,
                              color: _getStatusColor(status),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'accepted':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'pending':
        return Colors.orange;
      default:
        return const Color(0xFF4A5FBC);
    }
  }
}

Widget _buildEmptyState({
  required IconData icon,
  required String title,
  required String subtitle,
}) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}
