import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAwsdQS_OzbphwZPtkvHP0lyo7RK5P9bqE',
    appId: '1:153965158809:web:f25f9a8066c7f310d4f308',
    messagingSenderId: '153965158809',
    projectId: 'jadeer-b4953',
    authDomain: 'jadeer-b4953.firebaseapp.com',
    storageBucket: 'jadeer-b4953.firebasestorage.app',
    measurementId: 'G-DH3F76H9RX',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAgESmq4Q5DPyO6XqagtGADzvxFqVTBzEI',
    appId: '1:153965158809:android:f13d0950a3a3d5a0d4f308',
    messagingSenderId: '153965158809',
    projectId: 'jadeer-b4953',
    storageBucket: 'jadeer-b4953.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDQ9i9sKfZUkZwHCvIw2eYZsAYP60FfS4c',
    appId: '1:153965158809:ios:8183156c3a637fdfd4f308',
    messagingSenderId: '153965158809',
    projectId: 'jadeer-b4953',
    storageBucket: 'jadeer-b4953.firebasestorage.app',
    iosBundleId: 'com.example.gp202511',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyDQ9i9sKfZUkZwHCvIw2eYZsAYP60FfS4c',
    appId: '1:153965158809:ios:8183156c3a637fdfd4f308',
    messagingSenderId: '153965158809',
    projectId: 'jadeer-b4953',
    storageBucket: 'jadeer-b4953.firebasestorage.app',
    iosBundleId: 'com.example.gp202511',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyAwsdQS_OzbphwZPtkvHP0lyo7RK5P9bqE',
    appId: '1:153965158809:web:d8848c053acf6f3cd4f308',
    messagingSenderId: '153965158809',
    projectId: 'jadeer-b4953',
    authDomain: 'jadeer-b4953.firebaseapp.com',
    storageBucket: 'jadeer-b4953.firebasestorage.app',
    measurementId: 'G-05XK7W7P0P',
  );
}
