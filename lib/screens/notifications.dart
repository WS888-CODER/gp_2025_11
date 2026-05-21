import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:gp_2025_11/config/theme.dart';
import 'package:intl/intl.dart';

class NotificationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<bool> enableForUser(String uid) async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    final granted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;

    if (!granted) return false;

    final token = await _messaging.getToken();
    if (token == null) return false;

    await _db.collection('Users').doc(uid).set({
      'notificationsEnabled': true,
      'fcmTokens': FieldValue.arrayUnion([token]),
    }, SetOptions(merge: true));

    _messaging.onTokenRefresh.listen((newToken) async {
      await _db.collection('Users').doc(uid).set({
        'fcmTokens': FieldValue.arrayUnion([newToken]),
      }, SetOptions(merge: true));
    });

    return true;
  }

  Future<void> disableForUser(String uid) async {
    await _db.collection('Users').doc(uid).set({
      'notificationsEnabled': false,
    }, SetOptions(merge: true));
  }

  Future<bool> loadEnabled(String uid) async {
    final snap = await _db.collection('Users').doc(uid).get();
    return (snap.data()?['notificationsEnabled'] ?? false) == true;
  }
}

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const ThemedScaffold(
        appBar: CustomHeader(title: 'Notifications'),
        body: Center(child: Text('Not logged in')),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      color: isDark ? scheme.background : const Color(0xFFF5F5F5),
      child: ThemedScaffold(
        appBar: const CustomHeader(title: 'Notifications'),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('Notification')
              .where('UserID', isEqualTo: uid)
              .orderBy('Date', descending: true)
              .snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(child: Text('Error: ${snap.error}'));
            }
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snap.data?.docs ?? [];

            if (docs.isEmpty) {
              return const EmptyState(
                  icon: Icons.notifications_none_outlined,
                  title: 'No notifications yet',
                  subtitle: 'Your updates will appear here');
            }

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Row(
                    children: [
                      Text(
                        '${docs.length} Notifications',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (_) => const JadeerDialog<bool>(
                              title: 'Clear all notifications?',
                              content: Text(
                                'This will permanently delete all your notifications.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white70),
                              ),
                              primaryLabel: 'Clear',
                              primaryResult: true,
                              secondaryLabel: 'Cancel',
                              secondaryResult: false,
                            ),
                          );

                          if (confirmed != true) return;

                          final snap = await FirebaseFirestore.instance
                              .collection('Notification')
                              .where('UserID', isEqualTo: uid)
                              .get();

                          final batch = FirebaseFirestore.instance.batch();
                          for (final d in snap.docs) {
                            batch.delete(d.reference);
                          }
                          await batch.commit();

                          if (context.mounted) {
                            SnackHelper.success(
                              context,
                              'Notifications cleared.',
                            );
                          }
                        },
                        icon: const Icon(
                          Icons.delete_sweep_outlined,
                          size: 18,
                        ),
                        label: const Text('Clear all'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: docs.length,
                    itemBuilder: (context, i) {
                      final doc = docs[i];
                      final data = doc.data();

                      final title =
                          (data['JobTitle'] ?? 'Job Update').toString();
                      final msg = (data['Message'] ?? '').toString();
                      final status = (data['Status'] ?? '').toString();
                      final read = (data['Read'] ?? false) == true;
                      final dateValue = data['Date'];
                      String dateText = '';

                      if (dateValue is Timestamp) {
                        dateText = DateFormat('MMM d • h:mm a')
                            .format(dateValue.toDate());
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Dismissible(
                          key: Key(doc.id),
                          direction: DismissDirection.endToStart,
                          background: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              alignment: Alignment.centerRight,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              color: Colors.redAccent,
                              child: const Icon(
                                Icons.delete,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          onDismissed: (_) async {
                            await doc.reference.delete();

                            if (context.mounted) {
                              SnackHelper.success(
                                context,
                                'Notification deleted.',
                              );
                            }
                          },
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () async {
                              await doc.reference.update({'Read': true});
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.surface,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color:
                                      const Color(0xFF4A5FBC).withOpacity(0.08),
                                  width: 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.04),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.notifications_none,
                                    color: scheme.primary,
                                    size: 24,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          title,
                                          style: TextStyle(
                                            fontWeight: read
                                                ? FontWeight.w600
                                                : FontWeight.bold,
                                            fontSize: 15,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          msg,
                                          style: TextStyle(
                                            color: scheme.onSurface
                                                .withOpacity(0.75),
                                          ),
                                        ),
                                        if (dateText.isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          Text(
                                            dateText,
                                            style: TextStyle(
                                              color: scheme.onSurface
                                                  .withOpacity(0.45),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                        if (status.isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          Text(
                                            status,
                                            style: TextStyle(
                                              color: scheme.primary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  if (!read)
                                    Container(
                                      width: 10,
                                      height: 10,
                                      margin: const EdgeInsets.only(top: 4),
                                      decoration: BoxDecoration(
                                        color: scheme.primary,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
