import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../models/app_role.dart';
import 'push_notification_service.dart';

/// Session helpers: resolve [AppRole], land on the right hub, and log out.
class AuthSession {
  AuthSession._();

  static SupabaseClient get _client => Supabase.instance.client;

  static User? get currentUser => _client.auth.currentUser;

  static bool get isSignedIn => currentUser != null;

  static AppRole roleFromSession({String? tableRole}) {
    final metadataRole = currentUser?.userMetadata?['role']?.toString();
    return AppRole.parse(tableRole ?? metadataRole);
  }

  static Future<AppRole> resolveRole() async {
    final user = currentUser;
    if (user == null) return AppRole.customer;

    try {
      final row = await _client
          .from('users')
          .select('role')
          .eq('id', user.id)
          .maybeSingle()
          .timeout(const Duration(seconds: 5));
      final tableRole = row?['role']?.toString();
      if (tableRole != null && tableRole.isNotEmpty) {
        return AppRole.parse(tableRole);
      }
    } catch (e, st) {
      FirebaseCrashlytics.instance.recordError(e, st, reason: 'AuthSession role lookup failed');
    }

    return roleFromSession();
  }

  static Future<void> goToHub(BuildContext context, {AppRole? role}) async {
    final resolved = role ?? await resolveRole();
    if (!context.mounted) return;
    context.go(resolved.hubPath);
  }

  /// FCM token clear + Supabase signOut + return to the public guest feed
  /// (`/customer-hub`) so users can keep browsing meals after logging out.
  static Future<void> logout(
    BuildContext context, {
    Future<void> Function()? beforeNavigate,
  }) async {
    try {
      await PushNotificationService.clearTokenOnLogout();
    } catch (e, st) {
      FirebaseCrashlytics.instance.recordError(e, st, reason: 'AuthSession FCM clear failed');
    }

    try {
      await _client.auth.signOut();
    } catch (e, st) {
      FirebaseCrashlytics.instance.recordError(e, st, reason: 'AuthSession signOut failed');
    }

    if (beforeNavigate != null) {
      await beforeNavigate();
    }

    if (context.mounted) {
      context.go('/customer-hub');
    }
  }
}

/// Notifies [GoRouter] when the Supabase session changes so redirects re-run.
class AuthRefreshNotifier extends ChangeNotifier {
  AuthRefreshNotifier() {
    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      notifyListeners();
    });
  }

  late final StreamSubscription<AuthState> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
