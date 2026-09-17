import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/app_theme.dart';
import '../utils/diner_locale.dart';
import '../utils/network.dart';
import '../widgets/app_widgets.dart';
import '../widgets/customer_ui_components.dart';

class NotificationsInboxScreen extends StatefulWidget {
  const NotificationsInboxScreen({super.key});

  @override
  State<NotificationsInboxScreen> createState() => _NotificationsInboxScreenState();
}

class _NotificationsInboxScreenState extends State<NotificationsInboxScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Sign in to see notifications.';
          _rows = const [];
        });
      }
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await Supabase.instance.client
          .from('user_notifications')
          .select()
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(80)
          .withTimeout(NetworkTimeouts.standard);
      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(raw as List);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load notifications.';
        _loading = false;
      });
    }
  }

  Future<void> _markRead(Map<String, dynamic> row) async {
    final id = row['id']?.toString();
    if (id == null || id.isEmpty || row['read_at'] != null) return;
    try {
      await Supabase.instance.client.from('user_notifications').update({
        'read_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', id);
      if (!mounted) return;
      setState(() {
        _rows = _rows
            .map((item) => item['id']?.toString() == id
                ? {...item, 'read_at': DateTime.now().toUtc().toIso8601String()}
                : item)
            .toList();
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final copy = DinerLocaleController.instance.copy;
    return Scaffold(
      backgroundColor: AppTheme.canvasOf(context),
      appBar: AppBar(
        title: Text(copy.notifications),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/customer-hub');
            }
          },
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? ListView(children: const [SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))])
            : _error != null
                ? ListView(
                    children: [
                      SizedBox(
                        height: 280,
                        child: EmptyState(
                          icon: Icons.notifications_off_outlined,
                          title: copy.notifications,
                          message: _error,
                          actionLabel: 'Retry',
                          onAction: _load,
                        ),
                      ),
                    ],
                  )
                : _rows.isEmpty
                    ? ListView(
                        children: [
                          SizedBox(
                            height: 280,
                            child: EmptyState(
                              icon: Icons.notifications_none_outlined,
                              title: 'You are up to date',
                              message: 'Kitchen, delivery, and support notes land here.',
                            ),
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                        itemCount: _rows.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final row = _rows[index];
                          final unread = row['read_at'] == null;
                          final created = DateTime.tryParse(row['created_at']?.toString() ?? '');
                          final when = created == null
                              ? ''
                              : DateFormat('d MMM, h:mm a').format(created.toLocal());
                          return AppCard(
                            onTap: () => _markRead(row),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  unread ? Icons.notifications_active_outlined : Icons.notifications_none,
                                  color: unread ? AppTheme.primary : AppTheme.textMuted,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        row['title']?.toString() ?? 'Update',
                                        style: TextStyle(
                                          fontWeight: unread ? FontWeight.w800 : FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        row['body']?.toString() ?? '',
                                        style: AppTheme.caption,
                                      ),
                                      if (when.isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Text(when, style: AppTheme.micro),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}
