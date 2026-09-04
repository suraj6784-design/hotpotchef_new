// lib/services/push_notification_service.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'alert_service.dart';
import '../utils/network.dart';

// Top-level background message handler (Required by FCM)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (!kIsWeb) {
    debugPrint("Handling a background message: ${message.messageId}");
  }
}

class PushNotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final _supabase = Supabase.instance.client;
  static Map<String, dynamic>? _pendingData;

  static Future<void> initialize() async {
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

      // 2. Set background message handler
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // 3. Fetch and save the FCM Token to Supabase for the current user
      await syncTokenForCurrentUser();

      // 4. Listen for token refreshes
      _messaging.onTokenRefresh.listen((newToken) {
        _updateTokenInDatabase(newToken);
      });

      // 5. Handle foreground messages with an in-app banner
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        final title = message.notification?.title ?? 'HotPotChef';
        final body = message.notification?.body ?? '';
        final id = message.data['alert_id'] ??
            message.data['message_id'] ??
            message.data['order_id'] ??
            message.messageId ??
            title;
        AlertService.showBanner(id, title, body, data: message.data);
      });

      FirebaseMessaging.onMessageOpenedApp.listen(openFromMessage);
      final initial = await _messaging.getInitialMessage();
      if (initial != null) {
        _pendingData = Map<String, dynamic>.from(initial.data);
      }

      _supabase.auth.onAuthStateChange.listen((data) {
        if (data.session != null) {
          AlertService.start();
        } else {
          AlertService.stop();
        }
      });
      await AlertService.start();

    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Error initializing PushNotifications service');
      debugPrint('Error initializing PushNotifications: $e');
    }
  }

  static Future<void> syncTokenForCurrentUser() async {
    await _syncFCMTokenToDatabase();
  }

  static Future<void> _syncFCMTokenToDatabase() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      String? token = await _messaging.getToken().withTimeout(NetworkTimeouts.short);
      if (token != null) {
        await _updateTokenInDatabase(token);
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Error syncing FCM token to database');
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
      }).eq('id', user.id).withTimeout(NetworkTimeouts.short);

      debugPrint('FCM Token successfully updated in Supabase.');
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to update token in database');
      debugPrint('Failed to update token in database: $e');
    }
  }

  static void openFromMessage(RemoteMessage message) {
    unawaited(AlertService.openFromData(Map<String, dynamic>.from(message.data)));
  }

  static void openPendingAlert() {
    final data = _pendingData;
    _pendingData = null;
    if (data == null || data.isEmpty) return;
    unawaited(AlertService.openFromData(data));
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
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Error clearing FCM token on logout');
      debugPrint('Error clearing FCM token on logout: $e');
    }
  }
}