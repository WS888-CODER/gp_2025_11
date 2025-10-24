// lib/screens/admin_dashboard.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gp_2025_11/config/theme.dart';
import 'dart:async';

import 'package:iconsax_flutter/iconsax_flutter.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  @override
  void initState() {
    super.initState();
    loadCompanies();
  }

  String selectedStatus = 'all';
  bool isLoading = false;
  List<QueryDocumentSnapshot>? companies;

  // ✅ جلب الشركات من Firestore
  Future<QuerySnapshot> getCompanies() async {
    final collection = FirebaseFirestore.instance
        .collection('Users')
        .where('UserType', isEqualTo: 'Company');

    if (selectedStatus == 'all') {
      return await collection.get();
    } else {
      return await collection
          .where('AccountStatus', isEqualTo: selectedStatus)
          .get();
    }
  }

  // ✅ تحديث حالة الشركة
  Future<void> updateCompanyStatus(String id, String newStatus) async {
    await FirebaseFirestore.instance
        .collection('Users')
        .doc(id)
        .update({'AccountStatus': newStatus});
  }

  // ✅ تحميل الشركات
  Future<void> loadCompanies() async {
    setState(() => isLoading = true);
    try {
      final snapshot = await getCompanies();
      companies = snapshot.docs;
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const _AdminDashboardAppBar(),
      body: Column(
        children: [
          // 🔹 فلتر الحالات
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: DropdownButtonFormField<String>(
              value: selectedStatus,
              decoration: const InputDecoration(
                labelText: 'Filter by status',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All')),
                DropdownMenuItem(value: 'Pending', child: Text('Pending')),
                DropdownMenuItem(value: 'Verified', child: Text('Verified')),
                DropdownMenuItem(value: 'Rejected', child: Text('Rejected')),
              ],
              onChanged: (value) async {
                selectedStatus = value!;
                await loadCompanies();
              },
            ),
          ),

          // 🔹 عرض القائمة
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : (companies == null || companies!.isEmpty)
                    ? const Center(
                        child: Text(
                          'No companies found',
                          style: TextStyle(fontSize: 18, color: Colors.grey),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: loadCompanies,
                        child: ListView.builder(
                          itemCount: companies!.length,
                          itemBuilder: (context, index) {
                            final doc = companies![index];
                            final data = doc.data() as Map<String, dynamic>;

                            return _CardCompanyWidget(
                                data: data,
                                doc: doc,
                                onSelected: (value) async {
                                  await updateCompanyStatus(doc.id, value);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content:
                                          Text('Status updated to "$value"'),
                                    ),
                                  );
                                  await loadCompanies(); // تحديث البيانات
                                });
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _AdminDashboardAppBar extends StatefulWidget
    implements PreferredSizeWidget {
  const _AdminDashboardAppBar({super.key});

  @override
  State<_AdminDashboardAppBar> createState() => _AdminDashboardAppBarState();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _AdminDashboardAppBarState extends State<_AdminDashboardAppBar> {
  Timer? _sessionTimer;
  int _remainingSeconds = 3600; // 1 hour = 3600 seconds

  @override
  void initState() {
    super.initState();
    _startSessionTimer();
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    super.dispose();
  }

  void _startSessionTimer() {
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
        } else {
          _autoLogout();
        }
      });
    });
  }

  Future<void> _autoLogout() async {
    _sessionTimer?.cancel();
    await FirebaseAuth.instance.signOut();

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Session Expired'),
          content:
              const Text('You have been automatically logged out after 1 hour'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.pushReplacementNamed(context, '/login');
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  String _formatTime(int seconds) {
    int hours = seconds ~/ 3600;
    int minutes = (seconds % 3600) ~/ 60;
    int secs = seconds % 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  Future<void> _handleLogout() async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Logout'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Logout', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _sessionTimer?.cancel();
      await FirebaseAuth.instance.signOut();
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: const Color(0xFF4A5FBC),
      elevation: 0,
      centerTitle: false,
      leading: const SizedBox(),
      leadingWidth: 0,
      title: const Text(
        'Admin Dashboard',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
      actions: [
        // Timer Display
        Center(
          child: Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _remainingSeconds < 300 // Last 5 minutes
                  ? Colors.red[100]
                  : Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.timer,
                  color:
                      _remainingSeconds < 300 ? Colors.red[700] : Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  _formatTime(_remainingSeconds),
                  style: TextStyle(
                    color: _remainingSeconds < 300
                        ? Colors.red[700]
                        : Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.logout, color: Colors.white),
          tooltip: 'Logout',
          onPressed: _handleLogout,
        ),
      ],
    );
  }
}

class _CardCompanyWidget extends StatelessWidget {
  const _CardCompanyWidget(
      {required this.data, required this.doc, required this.onSelected});

  final Map<String, dynamic> data;
  final QueryDocumentSnapshot doc;
  final void Function(String) onSelected;

  @override
  Widget build(BuildContext context) {
    final companyName = data['CompanyName'] ?? 'Unnamed';
    final email = data['Email'] ?? 'No email';
    final accountStatus = data['AccountStatus'] ?? 'Pending';
    final isEmailVerified = data['IsEmailVerified'] ?? false;
    final createdAt = (data['Date'] as Timestamp?)?.toDate();

    return Card(
        elevation: 0.2,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      companyName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor(accountStatus).withAlpha(30),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      accountStatus.toUpperCase(),
                      style: TextStyle(
                        color: statusColor(accountStatus),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(thickness: 0.5, color: Colors.grey),
              _InfoWidget(
                icon: Iconsax.sms_copy,
                label: email,
                trailing: Icon(
                  isEmailVerified ? Icons.verified : Iconsax.close_circle,
                  color: isEmailVerified ? Colors.green : AppTheme.accentCoral,
                  size: 16,
                ),
              ),
              const SizedBox(height: 5),
              _InfoWidget(
                icon: Iconsax.calendar_1_copy,
                label: (createdAt == null)
                    ? "---"
                    : 'Registered: ${createdAt.toLocal().toString().split(' ')[0]}',
              ),
              const Divider(thickness: 0.5, color: Colors.grey),
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                icon: TextButton.icon(
                  onPressed: null,
                  icon: const Icon(Iconsax.edit,
                      color: AppTheme.primaryPurple, size: 16),
                  label: const Text('Change Status',
                      style: TextStyle(
                          color: AppTheme.primaryPurple, fontSize: 12)),
                ),
                onSelected: onSelected,
                itemBuilder: (context) => const [
                  PopupMenuItem(
                      value: 'Pending', child: Text('Set as Pending')),
                  PopupMenuItem(
                      value: 'Verified', child: Text('Set as Verified')),
                  PopupMenuItem(
                      value: 'Rejected', child: Text('Set as Rejected')),
                ],
              ),
            ],
          ),
        ));
  }

  // 🎨 لون الحالة
  Color statusColor(String status) {
    switch (status) {
      case 'Verified':
        return Colors.green;
      case 'Rejected':
        return Colors.red;
      case 'Pending':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }
}

class _InfoWidget extends StatelessWidget {
  const _InfoWidget({required this.icon, required this.label, this.trailing});
  final IconData icon;
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: 5,
      children: [
        Icon(icon, size: 16, color: AppTheme.accentCoral),
        Expanded(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.black87, fontSize: 12)),
        ),
        trailing ?? const SizedBox(),
      ],
    );
  }
}
