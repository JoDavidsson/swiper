// Copy this file to apps/Swiper_flutter/lib/firebase_options.dart
// and fill in the values from Firebase Console → Project settings → Your apps → Web app (SDK setup and config).

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      default:
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'YOUR_WEB_API_KEY',
    appId: 'YOUR_WEB_APP_ID',
    messagingSenderId: 'YOUR_MESSAGING_SENDER_ID',
    projectId: 'swiper-95482',
    authDomain: 'swiper-95482.firebaseapp.com',
    databaseURL: 'https://swiper-95482.firebaseio.com',
    storageBucket: 'swiper-95482.appspot.com',
    measurementId: 'G-XXXXXXXXXX',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'YOUR_ANDROID_API_KEY',
    appId: 'YOUR_ANDROID_APP_ID',
    messagingSenderId: 'YOUR_MESSAGING_SENDER_ID',
    projectId: 'swiper-95482',
    databaseURL: 'https://swiper-95482.firebaseio.com',
    storageBucket: 'swiper-95482.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'YOUR_IOS_API_KEY',
    appId: 'YOUR_IOS_APP_ID',
    messagingSenderId: 'YOUR_MESSAGING_SENDER_ID',
    projectId: 'swiper-95482',
    databaseURL: 'https://swiper-95482.firebaseio.com',
    storageBucket: 'swiper-95482.appspot.com',
    iosBundleId: 'com.example.swiper',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'YOUR_MACOS_API_KEY',
    appId: 'YOUR_MACOS_APP_ID',
    messagingSenderId: 'YOUR_MESSAGING_SENDER_ID',
    projectId: 'swiper-95482',
    databaseURL: 'https://swiper-95482.firebaseio.com',
    storageBucket: 'swiper-95482.appspot.com',
    iosBundleId: 'com.example.swiper',
  );
}
