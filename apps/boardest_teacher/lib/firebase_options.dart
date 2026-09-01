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
    apiKey: 'AIzaSyCebnepvovoZzuC2hm40GPESqKLXyMJ93A',
    appId: '1:540299822520:web:ca7c2f49d6b52866b9fb4d',
    messagingSenderId: '540299822520',
    projectId: 'boardest-cloud',
    authDomain: 'boardest-cloud.firebaseapp.com',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCebnepvovoZzuC2hm40GPESqKLXyMJ93A',
    appId: '1:540299822520:android:ca7c2f49d6b52866b9fb4d',
    messagingSenderId: '540299822520',
    projectId: 'boardest-cloud',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCebnepvovoZzuC2hm40GPESqKLXyMJ93A',
    appId: '1:540299822520:ios:ca7c2f49d6b52866b9fb4d',
    messagingSenderId: '540299822520',
    projectId: 'boardest-cloud',
    iosBundleId: 'com.boardest.cloud',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyCebnepvovoZzuC2hm40GPESqKLXyMJ93A',
    appId: '1:540299822520:ios:ca7c2f49d6b52866b9fb4d',
    messagingSenderId: '540299822520',
    projectId: 'boardest-cloud',
    iosBundleId: 'com.boardest.cloud',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyCebnepvovoZzuC2hm40GPESqKLXyMJ93A',
    appId: '1:540299822520:web:ca7c2f49d6b52866b9fb4d',
    messagingSenderId: '540299822520',
    projectId: 'boardest-cloud',
    authDomain: 'boardest-cloud.firebaseapp.com',
  );
}
