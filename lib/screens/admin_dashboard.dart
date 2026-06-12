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
  List<QueryDocumentSnapshot>? allCompanies; // كل الشركات دائماً

  GlobalKey<AdminDashboardAppBarState> adminAppBarKey =
      GlobalKey<AdminDashboardAppBarState>();

  List<QueryDocumentSnapshot> get filteredCompanies {
    if (allCompanies == null) return [];
    if (selectedStatus == 'All') return allCompanies!;
    return allCompanies!
        .where((d) =>
            (d.data() as Map<String, dynamic>)['AccountStatus'] ==
            selectedStatus)
        .toList();
  }

  int countByStatus(String status) {
    if (allCompanies == null) return 0;
    return allCompanies!
        .where((d) =>
            (d.data() as Map<String, dynamic>)['AccountStatus'] == status)
        .length;
  }

  @override
  void initState() {
    super.initState();
    loadCompanies();
    deleteExpiredCompanies();
  }

  Future<void> deleteExpiredCompanies() async {
    final now = DateTime.now();

    final snapshot = await FirebaseFirestore.instance
        .collection('Users')
        .where('UserType', isEqualTo: 'Company')
        .where('AccountStatus', isEqualTo: 'Rejected')
        .get();

    for (final doc in snapshot.docs) {
      final data = doc.data();

      final expiryRaw = data['ExpiryDate'];
      if (expiryRaw == null) continue;

      DateTime? expiryDate;
      if (expiryRaw is Timestamp) {
        expiryDate = expiryRaw.toDate();
      } else if (expiryRaw is String) {
        expiryDate = DateTime.tryParse(expiryRaw);
      }

      if (expiryDate == null) continue;

      if (now.isAfter(expiryDate)) {
        await FirebaseFirestore.instance
            .collection('Users')
            .doc(doc.id)
            .delete();
      }
    }
  }

  Future<void> updateCompanyStatus(String id, String newStatus) async {
    final Map<String, dynamic> updates = {
      'AccountStatus': newStatus,
      'UpdatedAt': DateTime.now().toIso8601String(),
    };

    if (newStatus == 'Rejected') {
      final expiryDate = DateTime.now().add(const Duration(days: 7));
      updates['ExpiryDate'] = Timestamp.fromDate(expiryDate);
    } else {
      updates['ExpiryDate'] = FieldValue.delete();
    }

    await FirebaseFirestore.instance.collection('Users').doc(id).update(updates);
  }

  Future<void> loadCompanies() async {
    setState(() => isLoading = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('Users')
          .where('UserType', isEqualTo: 'Company')
          .get();
      allCompanies = snapshot.docs;
    } finally {
      setState(() => isLoading = false);
    }
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
            const SizedBox(height: 16),
            // ======== Filter summary boxes ========
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  _SummaryFilterBox(
                    label: 'All',
                    value: allCompanies?.length ?? 0,
                    isSelected: selectedStatus == 'All',
                    onTap: () => setState(() => selectedStatus = 'All'),
                  ),
                  const SizedBox(width: 8),
                  _SummaryFilterBox(
                    label: 'Pending',
                    value: countByStatus('Pending'),
                    isSelected: selectedStatus == 'Pending',
                    onTap: () => setState(() => selectedStatus = 'Pending'),
                  ),
                  const SizedBox(width: 8),
                  _SummaryFilterBox(
                    label: 'Verified',
                    value: countByStatus('Verified'),
                    isSelected: selectedStatus == 'Verified',
                    onTap: () => setState(() => selectedStatus = 'Verified'),
                  ),
                  const SizedBox(width: 8),
                  _SummaryFilterBox(
                    label: 'Rejected',
                    value: countByStatus('Rejected'),
                    isSelected: selectedStatus == 'Rejected',
                    onTap: () => setState(() => selectedStatus = 'Rejected'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // ======== Companies list ========
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : filteredCompanies.isEmpty
                      ? const EmptyState(
                          icon: Iconsax.briefcase,
                          title: 'No companies found',
                          subtitle:
                              'New company registrations will appear here.',
                        )
                      : RefreshIndicator(
                          onRefresh: loadCompanies,
                          child: ListView.builder(
                            itemCount: filteredCompanies.length,
                            itemBuilder: (context, index) {
                              final doc = filteredCompanies[index];
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
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final companyName = data['CompanyName'] ?? 'Unnamed';
    final email = data['Email'] ?? 'No email';
    final accountStatus = data['AccountStatus'] ?? 'Pending';
    final createdAt = (data['Date'] as Timestamp?)?.toDate();
    final expiryAt = (data['ExpiryDate'] as Timestamp?)?.toDate();

    final statusColor = _statusColor(accountStatus);

    String? expiryText;
    Color? expiryColor;
    if (accountStatus == 'Rejected' && expiryAt != null) {
      final daysLeft = expiryAt.difference(DateTime.now()).inDays;
      if (daysLeft <= 0) {
        expiryText = 'Expires today';
        expiryColor = Colors.red;
      } else if (daysLeft <= 3) {
        expiryText = '$daysLeft days left';
        expiryColor = Colors.red;
      } else if (daysLeft <= 5) {
        expiryText = '$daysLeft days left';
        expiryColor = Colors.orange;
      } else {
        expiryText = '$daysLeft days left';
        expiryColor = Colors.green;
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Material(
        color: isDark ? scheme.surface : Colors.white,
        elevation: isDark ? 0 : 1,
        shadowColor: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Leading icon
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFFFD6C67),
                child: const Icon(Icons.business, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 16),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      companyName,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: isDark ? scheme.onSurface : Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      email,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? scheme.onSurface.withOpacity(0.7)
                            : Colors.grey.shade600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (createdAt != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Registered: ${createdAt.toLocal().toString().split(' ')[0]}',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? scheme.onSurface.withOpacity(0.5)
                              : Colors.grey.shade500,
                        ),
                      ),
                    ],
                    if (expiryText != null && expiryColor != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        expiryText,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: expiryColor,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    // Status badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Text(
                        accountStatus,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Action button
              IconButton(
                icon: Icon(Icons.more_vert,
                    color: scheme.onSurface.withOpacity(0.5)),
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      backgroundColor:
                          const Color(0xFF4A5FBC).withOpacity(0.7),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 10),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          InkWell(
                            onTap: () {
                              Navigator.pop(dialogContext);
                              onSelected('Verified');
                            },
                            child: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 14),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.check_circle_outline,
                                      color: Colors.white, size: 24),
                                  SizedBox(width: 10),
                                  Text(
                                    'Approve',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const Divider(color: Colors.white24, height: 1),
                          InkWell(
                            onTap: () {
                              Navigator.pop(dialogContext);
                              onSelected('Rejected');
                            },
                            child: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 14),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.cancel_outlined,
                                      color: Colors.white, size: 24),
                                  SizedBox(width: 10),
                                  Text(
                                    'Reject',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ================== SUMMARY FILTER BOX ==================
class _SummaryFilterBox extends StatelessWidget {
  const _SummaryFilterBox({
    required this.label,
    required this.value,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final int value;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? scheme.primary : scheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: isSelected
                ? Border.all(color: scheme.primary, width: 2)
                : Border.all(color: Colors.transparent, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isSelected ? 0.12 : 0.06),
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
                  color: isSelected ? Colors.white : scheme.primary,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white70 : null,
                ),
              ),
            ],
          ),
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
