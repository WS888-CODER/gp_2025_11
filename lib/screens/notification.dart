import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

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
