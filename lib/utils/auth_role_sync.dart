// lib/utils/auth_role_sync.dart
//
// Login routes from `public.users.role`. GoRouter guards JWT
// `user_metadata.role`. Keep those two in sync whenever a profile writes a role.

import 'package:supabase_flutter/supabase_flutter.dart';

import 'platform_ops_access.dart';

abstract final class AuthRoleSync {
  /// Writes [role] into JWT user_metadata when it differs (case-insensitive).
  static Future<void> ensureJwtRole(SupabaseClient client, String role) async {
    final trimmed = role.trim();
    if (trimmed.isEmpty) return;

    final user = client.auth.currentUser;
    if (user == null) return;

    final current = user.userMetadata?['role']?.toString();
    if (current != null && current.trim().toLowerCase() == trimmed.toLowerCase()) {
      return;
    }

    final merged = <String, dynamic>{
      ...?user.userMetadata,
      'role': trimmed,
    };
    await client.auth.updateUser(UserAttributes(data: merged));
  }

  /// Owner allowlist is always Admin. Writes `public.users.role` and JWT metadata
  /// so leftover Chef/Customer sessions still land on `/platform-ops`.
  static Future<void> syncOwnerAdminRole(SupabaseClient client) async {
    final user = client.auth.currentUser;
    if (user == null || !isPlatformOwnerEmail(user.email)) return;
    try {
      await client.from('users').update({'role': 'Admin'}).eq('id', user.id);
    } catch (_) {
      // Role check constraints or missing column should not block the desk.
    }
    await ensureJwtRole(client, 'Admin');
  }
}
