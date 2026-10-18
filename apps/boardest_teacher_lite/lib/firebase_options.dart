import 'dart:convert';
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static final String _k = utf8.decode(base64.decode('QUl6YVN5Q2VibmVwdm92b1p6dUMyaG00MEdQRVNxS0xYeU1KOTNB'));

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

  static final FirebaseOptions web = FirebaseOptions(
    apiKey: _k,
    appId: '1:540299822520:web:ca7c2f49d6b52866b9fb4d',
    messagingSenderId: '540299822520',
    projectId: 'boardest-cloud',
    authDomain: 'boardest-cloud.firebaseapp.com',
  );

  static final FirebaseOptions android = FirebaseOptions(
    apiKey: _k,
    appId: '1:540299822520:android:ca7c2f49d6b52866b9fb4d',
    messagingSenderId: '540299822520',
    projectId: 'boardest-cloud',
  );

  static final FirebaseOptions ios = FirebaseOptions(
    apiKey: _k,
    appId: '1:540299822520:ios:ca7c2f49d6b52866b9fb4d',
    messagingSenderId: '540299822520',
    projectId: 'boardest-cloud',
    iosBundleId: 'com.boardest.cloud',
  );

  static final FirebaseOptions macos = FirebaseOptions(
    apiKey: _k,
    appId: '1:540299822520:ios:ca7c2f49d6b52866b9fb4d',
    messagingSenderId: '540299822520',
    projectId: 'boardest-cloud',
    iosBundleId: 'com.boardest.cloud',
  );

  static final FirebaseOptions windows = FirebaseOptions(
    apiKey: _k,
    appId: '1:540299822520:web:ca7c2f49d6b52866b9fb4d',
    messagingSenderId: '540299822520',
    projectId: 'boardest-cloud',
    authDomain: 'boardest-cloud.firebaseapp.com',
  );
}
