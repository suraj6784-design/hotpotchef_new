import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/firebase_bootstrap.dart';
import 'package:hotpotchef_new/firebase_options.dart';

void main() {
  const projectId = 'hotpotchef-c53fa';
  const apiKey = 'AIzaSyCtic7MMrzyr8Tzx79ANA6ZRPhSZkkJiFg';
  const androidAppId = '1:379560909316:android:cae835b864441644cff351';
  const senderId = '379560909316';
  const storageBucket = 'hotpotchef-c53fa.firebasestorage.app';

  group('DefaultFirebaseOptions', () {
    test('android options match committed google-services.json', () {
      final options = DefaultFirebaseOptions.forPlatform(
        isWeb: false,
        platform: TargetPlatform.android,
      );

      expect(options.apiKey, apiKey);
      expect(options.appId, androidAppId);
      expect(options.messagingSenderId, senderId);
      expect(options.projectId, projectId);
      expect(options.storageBucket, storageBucket);
    });

    test('web options reuse in-repo project identifiers, not a new project', () {
      final options = DefaultFirebaseOptions.forPlatform(
        isWeb: true,
        platform: TargetPlatform.android,
      );

      expect(options.apiKey, apiKey);
      expect(options.projectId, projectId);
      expect(options.messagingSenderId, senderId);
      expect(options.storageBucket, storageBucket);
      expect(options.authDomain, 'hotpotchef-c53fa.firebaseapp.com');
      expect(options.appId, androidAppId);
      expect(options.appId.contains(':web:'), isFalse,
          reason: 'Repo has no Firebase web appId; do not invent one.');
    });

    test('currentPlatform matches the running target', () {
      final options = DefaultFirebaseOptions.currentPlatform;
      expect(options.projectId, projectId);
      expect(options.apiKey, apiKey);
      if (kIsWeb) {
        expect(options.authDomain, 'hotpotchef-c53fa.firebaseapp.com');
      } else {
        expect(options.appId, androidAppId);
      }
    });

    test('ios / macos / windows / linux throw until flutterfire configure', () {
      for (final platform in [
        TargetPlatform.iOS,
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        expect(
          () => DefaultFirebaseOptions.forPlatform(
            isWeb: false,
            platform: platform,
          ),
          throwsA(isA<UnsupportedError>()),
          reason: 'Expected missing options for $platform',
        );
      }
    });
  });

  group('FirebaseBootstrap strategy', () {
    test('web and android use reconstructed Dart options', () {
      expect(
        FirebaseBootstrap.strategyFor(
          isWeb: true,
          platform: TargetPlatform.android,
        ),
        FirebaseInitStrategy.useDartOptions,
      );
      expect(
        FirebaseBootstrap.strategyFor(
          isWeb: false,
          platform: TargetPlatform.android,
        ),
        FirebaseInitStrategy.useDartOptions,
      );
    });

    test('ios falls back to native GoogleService-Info.plist lookup', () {
      expect(
        FirebaseBootstrap.strategyFor(
          isWeb: false,
          platform: TargetPlatform.iOS,
        ),
        FirebaseInitStrategy.useNativeConfig,
      );
    });

    test('hasOptionsFor is true only for web and android', () {
      expect(
        FirebaseBootstrap.hasOptionsFor(
          isWeb: true,
          platform: TargetPlatform.linux,
        ),
        isTrue,
      );
      expect(
        FirebaseBootstrap.hasOptionsFor(
          isWeb: false,
          platform: TargetPlatform.android,
        ),
        isTrue,
      );
      expect(
        FirebaseBootstrap.hasOptionsFor(
          isWeb: false,
          platform: TargetPlatform.iOS,
        ),
        isFalse,
      );
    });
  });

  group('FirebaseBootstrap platform support gates', () {
    test('Crashlytics is skipped on web and desktop', () {
      expect(
        FirebaseBootstrap.isCrashlyticsSupported(
          isWeb: true,
          platform: TargetPlatform.android,
        ),
        isFalse,
      );
      expect(
        FirebaseBootstrap.isCrashlyticsSupported(
          isWeb: false,
          platform: TargetPlatform.linux,
        ),
        isFalse,
      );
      expect(
        FirebaseBootstrap.isCrashlyticsSupported(
          isWeb: false,
          platform: TargetPlatform.windows,
        ),
        isFalse,
      );
    });

    test('Crashlytics is supported on android, ios, and macos', () {
      expect(
        FirebaseBootstrap.isCrashlyticsSupported(
          isWeb: false,
          platform: TargetPlatform.android,
        ),
        isTrue,
      );
      expect(
        FirebaseBootstrap.isCrashlyticsSupported(
          isWeb: false,
          platform: TargetPlatform.iOS,
        ),
        isTrue,
      );
      expect(
        FirebaseBootstrap.isCrashlyticsSupported(
          isWeb: false,
          platform: TargetPlatform.macOS,
        ),
        isTrue,
      );
    });

    test('background messaging is not registered on web', () {
      expect(
        FirebaseBootstrap.isBackgroundMessagingSupported(isWeb: true),
        isFalse,
      );
      expect(
        FirebaseBootstrap.isBackgroundMessagingSupported(isWeb: false),
        isTrue,
      );
    });

    test('initializeApp times out instead of hanging forever', () {
      expect(FirebaseBootstrap.initializeTimeout, const Duration(seconds: 12));
    });
  });
}
