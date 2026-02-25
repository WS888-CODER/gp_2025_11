import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:gp_2025_11/config/theme.dart';

class Notification {
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
  const NotificationsPage({super.key, required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ThemedScaffold(
      appBar: const CustomHeader(title: 'Notifications'),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('Notification')
            .where('UserID', isEqualTo: userId)
            .orderBy('Date', descending: true)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data?.docs ?? [];

          if (docs.isEmpty) {
            return const Center(child: Text('No notifications yet.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final doc = docs[i];
              final data = doc.data();

              final title = (data['JobTitle'] ?? 'Job Update').toString();
              final msg = (data['Message'] ?? '').toString();
              final status = (data['Status'] ?? '').toString();
              final read = (data['Read'] ?? false) == true;

              return InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () async {
                  // mark as read
                  await doc.reference.update({'Read': true});

                  final jobId = (data['JobID'] ?? '').toString();
                  if (jobId.isNotEmpty && context.mounted) {
                    Navigator.pushNamed(
                      context,
                      '/job-details-view',
                      arguments: {'jobId': jobId},
                    );
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: read
                        ? scheme.surface
                        : scheme.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: scheme.primary.withOpacity(0.15),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.notifications_outlined,
                        color: read
                            ? scheme.onSurface.withOpacity(0.6)
                            : scheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontWeight:
                                    read ? FontWeight.w600 : FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              msg,
                              style: TextStyle(
                                color: scheme.onSurface.withOpacity(0.75),
                              ),
                            ),
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
              );
            },
          );
        },
      ),
    );
  }
}
