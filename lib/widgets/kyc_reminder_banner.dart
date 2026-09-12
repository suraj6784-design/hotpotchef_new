import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/app_theme.dart';

/// Persistent in-app KYC nudge for chefs and drivers after ops sends a reminder.
class KycReminderBanner extends StatelessWidget {
  const KycReminderBanner({super.key, required this.profilePath});

  final String profilePath;

  Stream<List<Map<String, dynamic>>> _stream() {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return Stream.value(const []);
    return Supabase.instance.client
        .from('user_notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', uid)
        .map((rows) {
          final unread = rows.where((row) {
            final kind = row['kind']?.toString() ?? '';
            return (kind == 'kyc_pending' || kind == 'fssai_expired' || kind == 'fssai_review') &&
                row['read_at'] == null;
          }).toList()
            ..sort((a, b) => (b['created_at']?.toString() ?? '').compareTo(a['created_at']?.toString() ?? ''));
          return unread;
        });
  }

  Future<void> _open(BuildContext context, Map<String, dynamic> row) async {
    final id = row['id']?.toString();
    if (id != null && id.isNotEmpty) {
      try {
        await Supabase.instance.client.from('user_notifications').update({
          'read_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', id);
      } catch (_) {}
    }
    if (context.mounted) context.push(profilePath);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _stream(),
      builder: (context, snap) {
        if (snap.hasError) return const SizedBox.shrink();
        final rows = snap.data ?? const [];
        if (rows.isEmpty) return const SizedBox.shrink();
        final row = rows.first;
        final body = (row['body'] ?? 'Complete your KYC in Profile.').toString();
        return Material(
          color: const Color(0xFFFFF3E0),
          child: InkWell(
            onTap: () => _open(context, row),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                children: [
                  const Icon(Icons.badge_outlined, color: AppTheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      body,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.3),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Profile',
                    style: TextStyle(color: AppTheme.linkOf(context), fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
