// lib/services/push_notification_service.dart
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../firebase_bootstrap.dart';

// Top-level background message handler (Required by FCM)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (!kIsWeb) {
    debugPrint("Handling a background message: ${message.messageId}");
  }
}

class PushNotificationService {
  static FirebaseMessaging get _messaging => FirebaseMessaging.instance;
  static final _supabase = Supabase.instance.client;

  static Future<void> initialize() async {
    if (Firebase.apps.isEmpty) {
      debugPrint('⚠️ Skipping push notifications because Firebase is not initialized.');
      return;
    }

    try {
      // 1. Request Permission for iOS / Web / Android 13+
      NotificationSettings settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        debugPrint('User granted notification permissions.');
      } else {
        debugPrint('User declined or accepted provisional permissions.');
      }

      // 2. Set background message handler (not supported on web)
      if (FirebaseBootstrap.isBackgroundMessagingSupported(isWeb: kIsWeb)) {
        FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
      }

      // 3. Fetch and save the FCM Token to Supabase for the current user
      await _syncFCMTokenToDatabase();

      // 4. Listen for token refreshes
      _messaging.onTokenRefresh.listen((newToken) {
        _updateTokenInDatabase(newToken);
      });

      // 5. Handle foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('Received foreground message: ${message.notification?.title}');
      });

    } catch (e, stack) {
      _recordNonFatal(e, stack, 'Error initializing PushNotifications service');
      debugPrint('Error initializing PushNotifications: $e');
    }
  }

  static void _recordNonFatal(Object error, StackTrace stack, String reason) {
    if (!FirebaseBootstrap.isCrashlyticsSupported(
      isWeb: kIsWeb,
      platform: defaultTargetPlatform,
    )) {
      return;
    }
    try {
      FirebaseCrashlytics.instance.recordError(error, stack, reason: reason);
    } catch (crashlyticsError) {
      debugPrint('⚠️ Failed to report to Crashlytics: $crashlyticsError');
    }
  }

  static Future<void> _syncFCMTokenToDatabase() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      String? token = await _messaging.getToken();
      if (token != null) {
        await _updateTokenInDatabase(token);
      }
    } catch (e, stack) {
      _recordNonFatal(e, stack, 'Error syncing FCM token to database');
      debugPrint('Error syncing FCM token: $e');
    }
  }

  static Future<void> _updateTokenInDatabase(String token) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      // Save token inside the users table column 'fcm_token'
      await _supabase.from('users').update({
        'fcm_token': token,
      }).eq('id', user.id);

      debugPrint('FCM Token successfully updated in Supabase.');
    } catch (e, stack) {
      _recordNonFatal(e, stack, 'Failed to update token in database');
      debugPrint('Failed to update token in database: $e');
    }
  }

  // Clear token on logout so notifications don't go to a signed-out device
  static Future<void> clearTokenOnLogout() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user != null) {
        await _supabase.from('users').update({
          'fcm_token': null,
        }).eq('id', user.id);
      }
      await _messaging.deleteToken();
    } catch (e, stack) {
      _recordNonFatal(e, stack, 'Error clearing FCM token on logout');
      debugPrint('Error clearing FCM token on logout: $e');
    }
  }
}