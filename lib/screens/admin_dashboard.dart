import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gp_2025_11/config/theme.dart';
import 'package:gp_2025_11/config/themed_scaffold.dart';
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

  @override
  void initState() {
    super.initState();
    loadCompanies();
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
    await FirebaseFirestore.instance
        .collection('Users')
        .doc(id)
        .update({'AccountStatus': newStatus});
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
    final Color borderColor = theme.colorScheme.secondary;
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
      side: BorderSide(
        color: borderColor,
        width: 1.2,
      ),
      showCheckmark: false,
      onSelected: (sel) async {
        selectedStatus = value;
        await loadCompanies();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(
        context); // Ø¹Ø´Ø§Ù† Ù…Ø§ Ù†ÙƒØ±Ø± Theme.of(context) Ù…Ù„ÙŠÙˆÙ† Ù…Ø±Ø©
    final textColor = theme.textTheme.bodyLarge?.color ?? Colors.black87;

    return ThemedScaffold(
      appBar: const _AdminDashboardAppBar(),
      body: Column(
        children: [
          // ======== Filter chips row (All / Pending / ...) ========
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8.0),
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
                    ? Center(
                        child: Text(
                          'No companies found',
                          style: TextStyle(
                            fontSize: 18,
                            color: textColor.withOpacity(0.6),
                          ),
                        ),
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

                                if (!context.mounted) return;
                                SnackHelper.success(
                                    context, 'Status updated to "$newStatus"');

                                await loadCompanies();
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

// ================== APP BAR ==================
class _AdminDashboardAppBar extends StatefulWidget
    implements PreferredSizeWidget {
  const _AdminDashboardAppBar();

  @override
  State<_AdminDashboardAppBar> createState() => _AdminDashboardAppBarState();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _AdminDashboardAppBarState extends State<_AdminDashboardAppBar> {
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
      final theme = Theme.of(context);

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: theme.colorScheme.primary.withOpacity(0.7),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
          ),
          title: const Text(
            'Session Expired',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: const Text(
            'You have been automatically logged out after 1 hour.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          actionsPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.pushReplacementNamed(context, '/login');
              },
              style: TextButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: theme.colorScheme.primary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
              child: const Text(
                'OK',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
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

  Future<void> _handleLogout() async {
    final theme = Theme.of(context);

    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.colorScheme.primary.withOpacity(0.7),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
        title: const Text(
          'Confirm Logout',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          'Are you sure you want to log out?',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white),
        ),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        actionsPadding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.9),
              foregroundColor: theme.colorScheme.primary,
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _sessionTimer?.cancel();
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isLowTime = _remainingSeconds < 300;

    return AppBar(
      backgroundColor: theme.colorScheme.primary,
      elevation: 0,
      leadingWidth: 105,
      leading: Container(
        margin: const EdgeInsets.only(left: 12),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 5,
            ),
            decoration: BoxDecoration(
              color:
                  isLowTime ? Colors.red[100] : Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.timer,
                  color: isLowTime ? Colors.red[700] : Colors.white,
                  size: 16,
                ),
                const SizedBox(width: 5),
                Text(
                  _formatTime(_remainingSeconds),
                  style: TextStyle(
                    color: isLowTime ? Colors.red[700] : Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      centerTitle: true,
      title: const Text(
        'Admin Dashboard',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.settings, color: Colors.white),
          tooltip: 'Settings',
          onPressed: () {
            Navigator.pushNamed(
              context,
              '/settings',
              arguments: {
                'userId': FirebaseAuth.instance.currentUser?.uid ?? '',
                'userType': 'Admin',
              },
            );
          },
        ),
      ],
    );
  }
}

// ================== COMPANY CARD ==================
class _CompanyCard extends StatelessWidget {
  const _CompanyCard({
    required this.data,
    required this.onSelected,
  });

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
    final isEmailVerified = data['IsEmailVerified'] ?? false;
    final createdAt = (data['Date'] as Timestamp?)?.toDate();

    final bgColor = theme.colorScheme.surface;
    final borderColor = isDark
        ? Colors.white.withOpacity(0.06)
        : theme.colorScheme.primary.withOpacity(0.15);

    final primaryColor = theme.colorScheme.primary;
    final secondaryColor = theme.colorScheme.secondary;
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
        padding: const EdgeInsets.all(12.0),
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
                      fontSize: 15,
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
              trailing: Icon(
                isEmailVerified ? Icons.verified : Iconsax.close_circle,
                color: isEmailVerified ? Colors.green : secondaryColor,
                size: 16,
              ),
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
                icon: Icon(
                  Iconsax.edit,
                  color: primaryColor,
                  size: 16,
                ),
                label: Text(
                  'Change Status',
                  style: TextStyle(
                    color: primaryColor,
                    fontSize: 12,
                  ),
                ),
              ),
              onSelected: onSelected,
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'Pending',
                  child: Text('Set as Pending'),
                ),
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
  const _InfoRow({
    required this.icon,
    required this.label,
    this.trailing,
    this.labelColor,
  });

  final IconData icon;
  final String label;
  final Widget? trailing;
  final Color? labelColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: theme.colorScheme.secondary,
        ),
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
              fontSize: 12,
            ),
          ),
        ),
        trailing ?? const SizedBox(),
      ],
    );
  }
}
