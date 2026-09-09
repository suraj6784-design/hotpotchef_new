import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/helpers.dart';
import '../utils/network.dart';
import '../utils/support.dart';
import '../services/ticket_reply_seen_store.dart';
import '../widgets/app_widgets.dart';
import '../widgets/customer_ui_components.dart';

class CustomerSupportTicketsScreen extends StatefulWidget {
  const CustomerSupportTicketsScreen({super.key});

  @override
  State<CustomerSupportTicketsScreen> createState() => _CustomerSupportTicketsScreenState();
}

class _CustomerSupportTicketsScreenState extends State<CustomerSupportTicketsScreen> {
  final _supabase = Supabase.instance.client;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _tickets = const [];
  Map<String, String> _seenByTicket = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      setState(() {
        _loading = false;
        _error = 'Sign in to view support tickets.';
        _tickets = const [];
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rows = await _supabase
          .from('support_tickets')
          .select('id, public_id, subject, status, sla_due_at, last_message_at, order_number, created_at')
          .eq('created_by', user.id)
          .order('created_at', ascending: false)
          .withTimeout(NetworkTimeouts.standard);
      if (!mounted) return;
      final tickets = List<Map<String, dynamic>>.from(rows as List);
      final seen = await TicketReplySeenStore.lastSeenByTicket(
        tickets.map((row) => row['id']?.toString() ?? ''),
      );
      if (!mounted) return;
      setState(() {
        _tickets = tickets;
        _seenByTicket = seen;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _formatSla(String? raw) => formatTicketSlaDue(raw);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppTheme.backgroundDark : AppTheme.background;
    final onSurface = AppTheme.onSurfaceOf(context);
    final muted = isDark ? AppTheme.textMuted : AppTheme.textMuted;

    return Scaffold(
      backgroundColor: bg,
      appBar: const HubAppBar(title: 'My support tickets'),
      body: RefreshIndicator(
        color: AppTheme.primary,
        onRefresh: _load,
        child: _loading
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  Center(child: CircularProgressIndicator(color: AppTheme.primary)),
                ],
              )
            : _error != null
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(24),
                    children: [
                      EmptyState(
                        icon: Icons.error_outline,
                        title: 'Could not load tickets',
                        message: _error!,
                      ),
                    ],
                  )
                : _tickets.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(24),
                        children: const [
                          EmptyState(
                            icon: Icons.support_agent_outlined,
                            title: 'No tickets yet',
                            message: 'Open Contact Us to create a support ticket. Ops replies within 1 business day.',
                          ),
                        ],
                      )
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                        itemCount: _tickets.length,
                        itemBuilder: (context, index) {
                          final row = _tickets[index];
                          final publicId = row['public_id']?.toString() ?? 'Ticket';
                          final subject = row['subject']?.toString() ?? '';
                          final status = (row['status']?.toString() ?? 'open').replaceAll('_', ' ');
                          final orderNumber = row['order_number']?.toString() ?? '';
                          final sla = _formatSla(row['sla_due_at']?.toString());
                          final ticketId = row['id']?.toString() ?? '';
                          final waiting = dinerHasSupportReplyWaiting(
                            status: row['status']?.toString(),
                            lastMessageAt: row['last_message_at']?.toString(),
                            lastSeenMessageAt: _seenByTicket[ticketId],
                          );

                          return AppCard(
                            margin: const EdgeInsets.only(bottom: 12),
                            onTap: () async {
                              await TicketReplySeenStore.markSeen(
                                ticketId,
                                row['last_message_at']?.toString(),
                              );
                              if (!context.mounted) return;
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => _SupportTicketDetailScreen(ticket: row),
                                ),
                              );
                              if (mounted) _load();
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        publicId,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: onSurface,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      waiting ? 'Support replied' : status,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                        color: AppTheme.primary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  subject,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    color: onSurface,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  [
                                    if (orderNumber.isNotEmpty) 'Order $orderNumber',
                                    if (sla.isNotEmpty) 'SLA $sla',
                                  ].join(' · '),
                                  style: TextStyle(color: muted, fontSize: 12),
                                ),
                              ],
                            ),
                          ).entrance(index: index);
                        },
                      ),
      ),
    );
  }
}

class _SupportTicketDetailScreen extends StatefulWidget {
  const _SupportTicketDetailScreen({required this.ticket});

  final Map<String, dynamic> ticket;

  @override
  State<_SupportTicketDetailScreen> createState() => _SupportTicketDetailScreenState();
}

class _SupportTicketDetailScreenState extends State<_SupportTicketDetailScreen> {
  final _supabase = Supabase.instance.client;
  final _replyController = TextEditingController();
  bool _loading = true;
  bool _sending = false;
  String? _error;
  List<Map<String, dynamic>> _messages = const [];

  String get _ticketId => widget.ticket['id']?.toString() ?? '';

  @override
  void initState() {
    super.initState();
    TicketReplySeenStore.markSeen(
      widget.ticket['id']?.toString() ?? '',
      widget.ticket['last_message_at']?.toString(),
    );
    _loadMessages();
  }

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    if (_ticketId.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Invalid ticket.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rows = await _supabase
          .from('support_ticket_messages')
          .select('id, author_id, body, is_internal, created_at')
          .eq('ticket_id', _ticketId)
          .eq('is_internal', false)
          .order('created_at', ascending: true)
          .withTimeout(NetworkTimeouts.standard);
      if (!mounted) return;
      setState(() {
        _messages = List<Map<String, dynamic>>.from(rows as List);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _sendReply() async {
    final body = _replyController.text.trim();
    final user = _supabase.auth.currentUser;
    if (body.isEmpty || user == null || _sending || _ticketId.isEmpty) return;

    setState(() => _sending = true);
    try {
      await _supabase.from('support_ticket_messages').insert({
        'ticket_id': _ticketId,
        'author_id': user.id,
        'body': body,
        'is_internal': false,
      }).withTimeout(NetworkTimeouts.standard);
      _replyController.clear();
      await _loadMessages();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send reply: $e'), backgroundColor: AppTheme.error),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppTheme.backgroundDark : AppTheme.background;
    final surface = isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight;
    final onSurface = AppTheme.onSurfaceOf(context);
    final muted = isDark ? AppTheme.textMuted : AppTheme.textMuted;
    final publicId = widget.ticket['public_id']?.toString() ?? 'Ticket';
    final subject = widget.ticket['subject']?.toString() ?? '';
    final status = (widget.ticket['status']?.toString() ?? 'open').replaceAll('_', ' ');
    final me = _supabase.auth.currentUser?.id;

    return Scaffold(
      backgroundColor: bg,
      appBar: HubAppBar(title: publicId),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: AppCard(
              margin: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(subject, style: TextStyle(fontWeight: FontWeight.w800, color: onSurface)),
                  const SizedBox(height: 6),
                  Text(
                    'Status: $status',
                    style: TextStyle(color: muted, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                : _error != null
                    ? Center(child: Text(_error!, style: TextStyle(color: muted)))
                    : _messages.isEmpty
                        ? Center(
                            child: Text(
                              'No messages yet.',
                              style: TextStyle(color: muted),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                            itemCount: _messages.length,
                            itemBuilder: (context, index) {
                              final msg = _messages[index];
                              final isMe = msg['author_id']?.toString() == me;
                              final body = msg['body']?.toString() ?? '';
                              String timeStr = '';
                              final raw = msg['created_at']?.toString();
                              if (raw != null) {
                                final dt = DateTime.tryParse(raw);
                                if (dt != null) {
                                  timeStr = DateFormat('dd MMM, hh:mm a').format(dt.toLocal());
                                }
                              }
                              return Align(
                                alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  constraints: BoxConstraints(
                                    maxWidth: MediaQuery.of(context).size.width * 0.78,
                                  ),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: isMe
                                        ? AppTheme.primary
                                        : (isDark ? AppTheme.surfaceMutedDark : AppTheme.surfaceMutedLight),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        body,
                                        style: TextStyle(
                                          color: isMe ? Colors.white : onSurface,
                                          fontSize: 14,
                                          height: 1.35,
                                        ),
                                      ),
                                      if (timeStr.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          timeStr,
                                          style: TextStyle(
                                            color: isMe ? Colors.white70 : muted,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            decoration: BoxDecoration(
              color: surface,
              border: Border(top: BorderSide(color: isDark ? Colors.black26 : Colors.black12)),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _replyController,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      style: TextStyle(color: onSurface),
                      decoration: InputDecoration(
                        hintText: 'Write a reply…',
                        hintStyle: TextStyle(color: muted),
                        filled: true,
                        fillColor: isDark ? AppTheme.surfaceMutedDark : AppTheme.surfaceMutedLight,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _sendReply(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    style: IconButton.styleFrom(backgroundColor: AppTheme.primary),
                    onPressed: _sending ? null : _sendReply,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send, color: Colors.white, size: 20),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
