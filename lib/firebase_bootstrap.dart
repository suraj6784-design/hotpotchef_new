import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'firebase_options.dart';

/// How [FirebaseBootstrap.initializeApp] should obtain Firebase options.
enum FirebaseInitStrategy {
  /// Use reconstructed / generated [DefaultFirebaseOptions].
  useDartOptions,

  /// Fall back to native google-services.json / GoogleService-Info.plist.
  useNativeConfig,

  /// Do not call [Firebase.initializeApp] (would crash on web with no options).
  skip,
}

/// Safe Firebase boot: explicit options when we have them, native config on
/// mobile when we do not, and a logged skip on web instead of a hard crash.
class FirebaseBootstrap {
  static bool hasOptionsFor({
    required bool isWeb,
    required TargetPlatform platform,
  }) {
    try {
      DefaultFirebaseOptions.forPlatform(isWeb: isWeb, platform: platform);
      return true;
    } on UnsupportedError {
      return false;
    }
  }

  static FirebaseInitStrategy strategyFor({
    required bool isWeb,
    required TargetPlatform platform,
  }) {
    if (hasOptionsFor(isWeb: isWeb, platform: platform)) {
      return FirebaseInitStrategy.useDartOptions;
    }
    if (!isWeb) {
      return FirebaseInitStrategy.useNativeConfig;
    }
    return FirebaseInitStrategy.skip;
  }

  /// Crashlytics is Android / iOS / macOS only. Calling it on web throws.
  static bool isCrashlyticsSupported({
    required bool isWeb,
    required TargetPlatform platform,
  }) {
    if (isWeb) {
      return false;
    }
    return platform == TargetPlatform.android ||
        platform == TargetPlatform.iOS ||
        platform == TargetPlatform.macOS;
  }

  /// [FirebaseMessaging.onBackgroundMessage] is not supported on web.
  static bool isBackgroundMessagingSupported({required bool isWeb}) => !isWeb;

  /// Initializes the default Firebase app. Returns `true` when an app exists
  /// afterwards. Failures are logged and do not rethrow.
  static Future<bool> initializeApp() async {
    if (Firebase.apps.isNotEmpty) {
      return true;
    }

    final strategy = strategyFor(
      isWeb: kIsWeb,
      platform: defaultTargetPlatform,
    );

    try {
      switch (strategy) {
        case FirebaseInitStrategy.useDartOptions:
          await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          );
          return true;
        case FirebaseInitStrategy.useNativeConfig:
          await Firebase.initializeApp();
          return true;
        case FirebaseInitStrategy.skip:
          debugPrint(
            '⚠️ Firebase skipped on web: no DefaultFirebaseOptions. '
            'Run `dart pub global activate flutterfire_cli && flutterfire configure` '
            'and add a Web app in the Firebase console.',
          );
          return false;
      }
    } catch (error, stack) {
      debugPrint('⚠️ Firebase.initializeApp failed: $error');
      debugPrint('$stack');
      return false;
    }
  }
}
