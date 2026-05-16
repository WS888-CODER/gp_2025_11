import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gp_2025_11/config/theme.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  String selectedStatus = 'All';
  bool isLoading = false;
  List<QueryDocumentSnapshot>? companies;

  GlobalKey<AdminDashboardAppBarState> adminAppBarKey =
      GlobalKey<AdminDashboardAppBarState>();

  @override
  void initState() {
    super.initState();
    loadCompanies();
    deleteExpiredCompanies(); // ← هنا
  }

  Future<void> deleteExpiredCompanies() async {
    final now = DateTime.now();

    final snapshot = await FirebaseFirestore.instance
        .collection('Users')
        .where('UserType', isEqualTo: 'Company')
        .where('AccountStatus', whereIn: ['Rejected', 'Pending']).get();

    for (final doc in snapshot.docs) {
      final data = doc.data();

      if (!data.containsKey('UpdatedAt')) continue;

      final updatedAt = DateTime.tryParse(data['UpdatedAt']);
      if (updatedAt == null) continue;

      final diff = now.difference(updatedAt);

      final status = data['AccountStatus'];

      bool shouldDelete = false;

      if (status == 'Rejected' && diff.inHours >= 24) {
        shouldDelete = true;
      }

      if (status == 'Pending' && diff.inDays >= 7) {
        shouldDelete = true;
      }

      if (shouldDelete) {
        await FirebaseFirestore.instance
            .collection('Users')
            .doc(doc.id)
            .delete();
      }
    }
  }

  // == Firestore logic ==
  Future<QuerySnapshot> getCompanies() async {
    final baseQuery = FirebaseFirestore.instance
        .collection('Users')
        .where('UserType', isEqualTo: 'Company');

    if (selectedStatus == 'All') {
      return await baseQuery.get();
    } else {
      return await baseQuery
          .where('AccountStatus', isEqualTo: selectedStatus)
          .get();
    }
  }

  Future<void> updateCompanyStatus(String id, String newStatus) async {
    await FirebaseFirestore.instance.collection('Users').doc(id).update({
      'AccountStatus': newStatus,
      'UpdatedAt': DateTime.now().toIso8601String(),
    });
  }

  Future<void> loadCompanies() async {
    setState(() => isLoading = true);
    try {
      final snapshot = await getCompanies();
      companies = snapshot.docs;
    } finally {
      setState(() => isLoading = false);
    }
  }

  ChoiceChip _buildStatusChip(String value) {
    final bool isSelected = selectedStatus == value;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final Color selectedBg = theme.colorScheme.secondary;
    final Color borderColor =
        isSelected ? selectedBg : theme.colorScheme.primary;
    final Color unselectedText =
        isDark ? Colors.white70 : theme.colorScheme.primary;

    return ChoiceChip(
      label: Text(
        value,
        style: TextStyle(
          color: isSelected ? Colors.white : unselectedText,
          fontWeight: FontWeight.w600,
        ),
      ),
      selected: isSelected,
      selectedColor: selectedBg,
      side: BorderSide(color: borderColor, width: 2),
      showCheckmark: false,
      onSelected: (sel) async {
        selectedStatus = value;
        await loadCompanies();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: adminAppBarKey.currentState?.resetSessionTimer,
      onPanDown: (_) => adminAppBarKey.currentState?.resetSessionTimer(),
      child: ThemedScaffold(
        appBar: AdminDashboardAppBar(key: adminAppBarKey),
        body: Column(
          children: [
            const SizedBox(height: 20),
            // ======== Filter chips row (All / Pending / ...) ========
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),
                child: Wrap(
                  spacing: 8,
                  children: [
                    _buildStatusChip('All'),
                    _buildStatusChip('Pending'),
                    _buildStatusChip('Verified'),
                    _buildStatusChip('Rejected'),
                  ],
                ),
              ),
            ),

            // ======== Companies list ========
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : (companies == null || companies!.isEmpty)
                      ? const EmptyState(
                          icon: Iconsax.briefcase,
                          title: 'No companies found',
                          subtitle:
                              'New company registrations will appear here.',
                        )
                      : RefreshIndicator(
                          onRefresh: loadCompanies,
                          child: ListView.builder(
                            itemCount: companies!.length,
                            itemBuilder: (context, index) {
                              final doc = companies![index];
                              final data = doc.data() as Map<String, dynamic>;

                              return _CompanyCard(
                                data: data,
                                onSelected: (newStatus) async {
                                  await updateCompanyStatus(doc.id, newStatus);

                                  if (newStatus == 'Verified' ||
                                      newStatus == 'Rejected') {
                                    try {
                                      final functions =
                                          FirebaseFunctions.instanceFor(
                                              region: 'us-central1');
                                      final callable = functions.httpsCallable(
                                          'notifyCompanyStatusChange');
                                      await callable.call({
                                        'companyEmail': data['Email'] ?? '',
                                        'companyName':
                                            data['CompanyName'] ?? '',
                                        'status': newStatus == 'Verified'
                                            ? 'Accepted'
                                            : 'Rejected',
                                      });
                                    } catch (e) {
                                      print(
                                          'Company status notification failed: $e');
                                    }
                                  }

                                  if (!context.mounted) return;
                                  SnackHelper.success(context,
                                      'Status updated to "$newStatus"');
                                  await loadCompanies();
                                },
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// ================== APP BAR ==================
class AdminDashboardAppBar extends StatefulWidget
    implements PreferredSizeWidget {
  const AdminDashboardAppBar({super.key});

  @override
  State<AdminDashboardAppBar> createState() => AdminDashboardAppBarState();

  @override
  Size get preferredSize => const Size.fromHeight(180);
}

class AdminDashboardAppBarState extends State<AdminDashboardAppBar> {
  Timer? _sessionTimer;
  int _remainingSeconds = 3600; // 1h

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

  void resetSessionTimer() {
    // فقط إذا بقي 15 دقيقة أو أقل
    if (_remainingSeconds <= 900) {
      _sessionTimer?.cancel();
      _remainingSeconds = 3600; // إعادة ضبط 60 دقيقة
      _startSessionTimer();
    }
  }

  void _startSessionTimer() {
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
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
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const JadeerDialog(
          title: 'Session Expired',
          content: Text(
            'You have been automatically logged out after 1 hour.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 15),
          ),
          primaryLabel: 'OK',
          primaryResult: true,
        ),
      ).then((confirmed) {
        if (confirmed == true) {
          Navigator.pushReplacementNamed(context, '/login');
        }
      });
    }
  }

  String _formatTime(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final bool isLowTime = _remainingSeconds < 300;

    final pillColor =
        isLowTime ? Colors.red[100] : Colors.white.withOpacity(0.2);
    final timerColor = isLowTime ? Colors.red[700] : Colors.white;

    final bubbleColor = Colors.white.withOpacity(isDark ? 0.04 : 0.06);
    final shadowColor = scheme.primary.withOpacity(isDark ? 0.55 : 0.4);

    return Container(
      height: widget.preferredSize.height,
      width: double.infinity,
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
            color: shadowColor,
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
                color: bubbleColor,
              ),
            ),
          ),
          Positioned(
            bottom: -20,
            left: -30,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: bubbleColor,
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: pillColor,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.timer, color: timerColor, size: 16),
                            const SizedBox(width: 5),
                            Text(
                              _formatTime(_remainingSeconds),
                              style: TextStyle(
                                color: timerColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.pushNamed(
                            context,
                            '/settings',
                            arguments: {
                              'userId':
                                  FirebaseAuth.instance.currentUser?.uid ?? '',
                              'userType': 'Admin',
                            },
                          );
                        },
                        child: Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.settings_outlined,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Center(
                    child: Text(
                      'Admin Dashboard',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ================== COMPANY CARD ==================
class _CompanyCard extends StatelessWidget {
  const _CompanyCard({required this.data, required this.onSelected});

  final Map<String, dynamic> data;
  final void Function(String) onSelected;

  Color _statusColor(String status) {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final companyName = data['CompanyName'] ?? 'Unnamed';
    final email = data['Email'] ?? 'No email';
    final accountStatus = data['AccountStatus'] ?? 'Pending';
    final createdAt = (data['Date'] as Timestamp?)?.toDate();

    final bgColor = theme.colorScheme.surface;
    final borderColor = isDark
        ? Colors.white.withOpacity(0.06)
        : theme.colorScheme.primary.withOpacity(0.15);

    final primaryColor = theme.colorScheme.primary;
    final textColor = theme.textTheme.bodyLarge?.color ?? Colors.black87;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.5 : 0.1),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          children: [
            // name + status
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    companyName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: primaryColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor(accountStatus).withAlpha(30),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    accountStatus.toUpperCase(),
                    style: TextStyle(
                      color: _statusColor(accountStatus),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // email row
            _InfoRow(
              icon: Iconsax.sms_copy,
              label: email,
              labelColor: textColor,
            ),

            const SizedBox(height: 5),

            // created date row
            _InfoRow(
              icon: Iconsax.calendar_1_copy,
              label: (createdAt == null)
                  ? '---'
                  : 'Registered: ${createdAt.toLocal().toString().split(' ')[0]}',
              labelColor: textColor,
            ),

            const SizedBox(height: 8),

            // status action menu
            PopupMenuButton<String>(
              padding: EdgeInsets.zero,
              icon: TextButton.icon(
                onPressed: null,
                icon: Icon(Iconsax.edit, color: primaryColor, size: 18),
                label: Text(
                  'Change Status',
                  style: TextStyle(color: primaryColor, fontSize: 14),
                ),
              ),
              onSelected: onSelected,
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'Pending', child: Text('Set as Pending')),
                PopupMenuItem(
                  value: 'Verified',
                  child: Text('Set as Verified'),
                ),
                PopupMenuItem(
                  value: 'Rejected',
                  child: Text('Set as Rejected'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// row for email/date
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, this.labelColor});

  final IconData icon;
  final String label;
  final Color? labelColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.secondary),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: labelColor ??
                  theme.textTheme.bodyLarge?.color ??
                  Colors.black87,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}
