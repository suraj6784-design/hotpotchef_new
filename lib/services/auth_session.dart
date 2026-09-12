import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../models/app_role.dart';
import 'push_notification_service.dart';
import '../utils/app_flavor.dart';
import '../utils/network.dart';
import '../utils/platform_ops_access.dart';

/// Session helpers: resolve [AppRole], land on the right hub, and log out.
class AuthSession {
  AuthSession._();

  static SupabaseClient get _client => Supabase.instance.client;

  static User? get currentUser => _client.auth.currentUser;

  static bool get isSignedIn => currentUser != null;

  static List<String> _opsPermissionsCache = const [];
  static bool _opsOwnerCache = false;
  static bool _opsSeatCache = false;
  static String? _opsCacheUserId;
  static String? _roleCacheUserId;
  static AppRole? _tableRoleCache;

  static void clearOpsCache() {
    _opsPermissionsCache = const [];
    _opsOwnerCache = false;
    _opsSeatCache = false;
    _opsCacheUserId = null;
  }

  static void clearRoleCache() {
    _roleCacheUserId = null;
    _tableRoleCache = null;
  }

  /// Router and hubs prefer `public.users.role` over a stale JWT claim.
  static AppRole resolveRoleFromSources({
    String? email,
    String? jwtRole,
    String? tableRole,
  }) {
    if (isPlatformOwnerEmail(email)) return AppRole.admin;
    final table = tableRole?.trim() ?? '';
    if (table.isNotEmpty) return AppRole.parse(table);
    return AppRole.parse(jwtRole);
  }

  static AppRole roleFromSession({String? tableRole}) {
    final user = currentUser;
    return resolveRoleFromSources(
      email: user?.email,
      jwtRole: user?.userMetadata?['role']?.toString(),
      tableRole: tableRole ??
          (_roleCacheUserId == user?.id ? _tableRoleCache?.storageValue : null),
    );
  }

  static AppRole roleForUser(User? user, {String? tableRole}) {
    return resolveRoleFromSources(
      email: user?.email,
      jwtRole: user?.userMetadata?['role']?.toString(),
      tableRole: tableRole ??
          (_roleCacheUserId == user?.id ? _tableRoleCache?.storageValue : null),
    );
  }

  /// Keep JWT + public.users aligned when the owner still has a leftover Chef session.
  static Future<void> syncOwnerAdminRole() async {
    final user = currentUser;
    if (user == null || !isPlatformOwnerEmail(user.email)) return;
    try {
      await _client.from('users').update({'role': 'Admin'}).eq('id', user.id);
    } catch (e, st) {
      FirebaseCrashlytics.instance.recordError(e, st, reason: 'Owner Admin users.role sync failed');
    }
    final metaRole = user.userMetadata?['role']?.toString();
    if (AppRole.parse(metaRole) == AppRole.admin) return;
    try {
      await _client.auth.updateUser(UserAttributes(data: {'role': 'Admin'}));
    } catch (e, st) {
      FirebaseCrashlytics.instance.recordError(e, st, reason: 'Owner Admin JWT role sync failed');
    }
  }

  static Future<AppRole> resolveRole() async {
    final user = currentUser;
    if (user == null) return AppRole.customer;

    // Owner email is always the Admin hub, never Chef/Customer/Driver.
    if (isPlatformOwnerEmail(user.email)) {
      await syncOwnerAdminRole();
      return AppRole.admin;
    }

    try {
      final row = await _client
          .from('users')
          .select('role')
          .eq('id', user.id)
          .maybeSingle()
          .timeout(NetworkTimeouts.short);
      final tableRole = row?['role']?.toString();
      if (tableRole != null && tableRole.isNotEmpty) {
        final parsed = AppRole.parse(tableRole);
        _roleCacheUserId = user.id;
        _tableRoleCache = parsed;
        await _syncJwtRoleIfNeeded(parsed);
        return parsed;
      }
    } catch (e, st) {
      FirebaseCrashlytics.instance.recordError(e, st, reason: 'AuthSession role lookup failed');
    }

    return roleFromSession();
  }

  static Future<void> _syncJwtRoleIfNeeded(AppRole tableRole) async {
    final user = currentUser;
    if (user == null) return;
    final jwtRole = resolveRoleFromSources(
      email: user.email,
      jwtRole: user.userMetadata?['role']?.toString(),
    );
    if (jwtRole == tableRole) return;
    try {
      await _client.auth.updateUser(UserAttributes(data: {'role': tableRole.storageValue}));
    } catch (e, st) {
      FirebaseCrashlytics.instance.recordError(e, st, reason: 'AuthSession JWT role sync failed');
    }
  }

  static Future<Map<String, dynamic>?> _loadOpsSeat() async {
    final user = currentUser;
    if (user == null) return null;
    if (_opsCacheUserId == user.id && _opsSeatCache) {
      return {
        'seat_role': _opsOwnerCache ? 'owner' : 'helper',
        'permissions': _opsPermissionsCache,
      };
    }
    try {
      final row = await _client
          .from('platform_ops')
          .select('user_id, seat_role, permissions, revoked_at')
          .eq('user_id', user.id)
          .maybeSingle()
          .timeout(NetworkTimeouts.short);
      if (row == null || row['revoked_at'] != null) {
        clearOpsCache();
        _opsCacheUserId = user.id;
        return null;
      }
      final owner = (row['seat_role']?.toString() ?? '') == 'owner' &&
          isPlatformOwnerEmail(user.email);
      _opsCacheUserId = user.id;
      _opsSeatCache = true;
      _opsOwnerCache = owner;
      _opsPermissionsCache = normalizeOpsPermissions(row['permissions'], owner: owner);
      return row;
    } catch (e, st) {
      FirebaseCrashlytics.instance.recordError(e, st, reason: 'AuthSession platform ops lookup failed');
      return null;
    }
  }

  /// Active platform ops seat (owner or helper).
  static Future<bool> isPlatformOps() async {
    final user = currentUser;
    if (user == null) return false;
    final seat = await _loadOpsSeat();
    return seat != null;
  }

  static Future<bool> isPlatformOwner() async {
    final user = currentUser;
    if (user == null || !isPlatformOwnerEmail(user.email)) return false;
    final seat = await _loadOpsSeat();
    return seat != null && _opsOwnerCache;
  }

  static Future<List<String>> opsPermissions() async {
    await _loadOpsSeat();
    if (_opsOwnerCache) return List<String>.from(kOpsAllPermissions);
    return List<String>.from(_opsPermissionsCache);
  }

  static Future<bool> hasOpsPermission(String key) async {
    if (await isPlatformOwner()) return true;
    final perms = await opsPermissions();
    return opsPermissionsContain(perms, key);
  }

  /// Returns false and signs out when the account is suspended.
  static Future<bool> ensureAccountActive(BuildContext context) async {
    final user = currentUser;
    if (user == null) return true;
    try {
      final row = await _client
          .from('users')
          .select('account_status')
          .eq('id', user.id)
          .maybeSingle()
          .timeout(NetworkTimeouts.short);
      final status = (row?['account_status']?.toString() ?? 'active').toLowerCase();
      if (status != 'suspended') return true;
      if (!context.mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account suspended — contact Support.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      await logout(context);
      return false;
    } catch (e, st) {
      FirebaseCrashlytics.instance.recordError(e, st, reason: 'AuthSession account status check failed');
      return true;
    }
  }

  static Future<void> goToHub(BuildContext context, {AppRole? role}) async {
    if (!await ensureAccountActive(context)) return;
    if (await isPlatformOps()) {
      if (!context.mounted) return;
      context.go('/platform-ops');
      return;
    }
    final resolved = role ?? await resolveRole();
    if (!context.mounted) return;
    context.go(resolved.hubPath);
  }

  /// Bounce a signed-in user off a hub that does not match `users.role`.
  static Future<void> ensureHubRole(BuildContext context, AppRole expected) async {
    if (!await ensureAccountActive(context)) return;
    final resolved = await resolveRole();
    if (!context.mounted || resolved == expected) return;
    context.go(resolved.hubPath);
  }

  /// FCM token clear + Supabase signOut + return to the public guest feed
  /// (`/customer-hub`) so users can keep browsing meals after logging out.
  static Future<void> logout(
    BuildContext context, {
    Future<void> Function()? beforeNavigate,
  }) async {
    clearOpsCache();
    clearRoleCache();
    try {
      await PushNotificationService.clearTokenOnLogout();
    } catch (e, st) {
      FirebaseCrashlytics.instance.recordError(e, st, reason: 'AuthSession FCM clear failed');
    }

    try {
      await _client.auth.signOut().withTimeout(NetworkTimeouts.short);
    } catch (e, st) {
      FirebaseCrashlytics.instance.recordError(e, st, reason: 'AuthSession signOut failed');
    }

    if (beforeNavigate != null) {
      await beforeNavigate();
    }

    if (context.mounted) {
      context.go(kAppStorefront.isPartner ? '/auth' : '/customer-hub');
    }
  }
}

/// Notifies [GoRouter] when the Supabase session changes so redirects re-run.
class AuthRefreshNotifier extends ChangeNotifier {
  AuthRefreshNotifier() {
    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((event) async {
      AuthSession.clearOpsCache();
      if (event.session == null) {
        AuthSession.clearRoleCache();
        notifyListeners();
        return;
      }
      notifyListeners();
      await AuthSession.resolveRole();
      notifyListeners();
    });
    if (AuthSession.currentUser != null) {
      unawaited(AuthSession.resolveRole().then((_) => notifyListeners()));
    }
  }

  late final StreamSubscription<AuthState> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
