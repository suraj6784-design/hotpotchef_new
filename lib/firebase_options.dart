// Reconstructed FlutterFire options from committed platform config.
// Source: android/app/google-services.json (project hotpotchef-c53fa).
// No GoogleService-Info.plist or Firebase web app registration exists in-repo.
// Do not invent a new Firebase project. To generate a canonical file with a
// real `:web:` appId (and iOS options), run:
//   dart pub global activate flutterfire_cli
//   flutterfire configure
//
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    return forPlatform(isWeb: kIsWeb, platform: defaultTargetPlatform);
  }

  /// Platform lookup used by boot code and unit tests.
  static FirebaseOptions forPlatform({
    required bool isWeb,
    required TargetPlatform platform,
  }) {
    if (isWeb) {
      return web;
    }
    switch (platform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for ios. '
          'Add ios/Runner/GoogleService-Info.plist and run `flutterfire configure`.',
        );
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos. '
          'Run `flutterfire configure`.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows. '
          'Run `flutterfire configure`.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux. '
          'Run `flutterfire configure`.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  /// Web options reconstructed from the Android google-services.json project
  /// identifiers. [appId] reuses the only mobilesdk_app_id in-repo (Android).
  /// Replace with a real `1:<project>:web:<hash>` after `flutterfire configure`.
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCtic7MMrzyr8Tzx79ANA6ZRPhSZkkJiFg',
    appId: '1:379560909316:android:cae835b864441644cff351',
    messagingSenderId: '379560909316',
    projectId: 'hotpotchef-c53fa',
    authDomain: 'hotpotchef-c53fa.firebaseapp.com',
    storageBucket: 'hotpotchef-c53fa.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCtic7MMrzyr8Tzx79ANA6ZRPhSZkkJiFg',
    appId: '1:379560909316:android:cae835b864441644cff351',
    messagingSenderId: '379560909316',
    projectId: 'hotpotchef-c53fa',
    storageBucket: 'hotpotchef-c53fa.firebasestorage.app',
  );
}
