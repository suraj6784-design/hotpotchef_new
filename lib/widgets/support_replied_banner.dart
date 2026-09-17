import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/ticket_reply_seen_store.dart';
import '../utils/helpers.dart';
import '../utils/network.dart';
import '../utils/support.dart';

class SupportRepliedBanner extends StatefulWidget {
  const SupportRepliedBanner({super.key});

  @override
  State<SupportRepliedBanner> createState() => _SupportRepliedBannerState();
}

class _SupportRepliedBannerState extends State<SupportRepliedBanner> {
  Map<String, dynamic>? _ticket;
  int _extraCount = 0;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _ready = true);
      return;
    }
    try {
      final rows = await Supabase.instance.client
          .from('support_tickets')
          .select('id, public_id, status, last_message_at')
          .eq('created_by', user.id)
          .eq('status', 'pending_customer')
          .order('last_message_at', ascending: false)
          .limit(8)
          .withTimeout(NetworkTimeouts.standard);
      final tickets = List<Map<String, dynamic>>.from(rows as List);
      final seen = await TicketReplySeenStore.lastSeenByTicket(
        tickets.map((row) => row['id']?.toString() ?? ''),
      );
      final waiting = tickets.where((row) {
        final id = row['id']?.toString() ?? '';
        return dinerHasSupportReplyWaiting(
          status: row['status']?.toString(),
          lastMessageAt: row['last_message_at']?.toString(),
          lastSeenMessageAt: seen[id],
        );
      }).toList();
      if (!mounted) return;
      setState(() {
        _ticket = waiting.isEmpty ? null : waiting.first;
        _extraCount = waiting.length > 1 ? waiting.length - 1 : 0;
        _ready = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _ready = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || _ticket == null) return const SizedBox.shrink();
    final publicId = _ticket!['public_id']?.toString();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Material(
        color: AppTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.push('/support-tickets'),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                const Icon(Icons.support_agent_outlined, color: AppTheme.primary, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    supportRepliedNoticeCopy(publicId: publicId, extraCount: _extraCount),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: AppTheme.onSurfaceOf(context),
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppTheme.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
