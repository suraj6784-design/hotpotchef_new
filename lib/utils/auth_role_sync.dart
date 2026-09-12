// lib/utils/auth_role_sync.dart
//
// Login routes from `public.users.role`. GoRouter guards JWT
// `user_metadata.role`. Keep those two in sync whenever a profile writes a role.

import 'package:supabase_flutter/supabase_flutter.dart';

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
}
