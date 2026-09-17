import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/alert_service.dart';
import '../services/auth_session.dart';
import '../utils/diner_locale.dart';
import '../utils/helpers.dart';
import '../utils/network.dart';
import '../widgets/app_widgets.dart';
import '../widgets/diner_storefront.dart';

class NotificationsInboxScreen extends StatefulWidget {
  const NotificationsInboxScreen({
    super.key,
    this.embedded = false,
    this.partnerInbox = false,
  });

  final bool embedded;
  final bool partnerInbox;

  @override
  State<NotificationsInboxScreen> createState() => _NotificationsInboxScreenState();
}

class _NotificationsInboxScreenState extends State<NotificationsInboxScreen> {
  bool _loading = true;
  String? _error;
  String _filter = 'all';
  List<Map<String, dynamic>> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool _isOrderKind(Map<String, dynamic> row) {
    final kind = '${row['kind'] ?? ''} ${row['title'] ?? ''} ${row['body'] ?? ''}'.toLowerCase();
    return kind.contains('order') ||
        kind.contains('delivery') ||
        kind.contains('kitchen') ||
        kind.contains('otp') ||
        kind.contains('live');
  }

  bool _isPromoKind(Map<String, dynamic> row) {
    final kind = '${row['kind'] ?? ''} ${row['title'] ?? ''} ${row['body'] ?? ''}'.toLowerCase();
    return kind.contains('promo') ||
        kind.contains('offer') ||
        kind.contains('coupon') ||
        kind.contains('off') ||
        kind.contains('%');
  }

  bool _isSystemKind(Map<String, dynamic> row) {
    final kind = '${row['kind'] ?? ''} ${row['title'] ?? ''} ${row['body'] ?? ''}'.toLowerCase();
    return kind.contains('kyc') ||
        kind.contains('fssai') ||
        kind.contains('payout') ||
        kind.contains('system') ||
        kind.contains('hours') ||
        kind.contains('licence') ||
        kind.contains('license');
  }

  List<Map<String, dynamic>> get _visibleRows {
    if (_filter == 'orders') return _rows.where(_isOrderKind).toList();
    if (_filter == 'promos') return _rows.where(_isPromoKind).toList();
    if (_filter == 'system') return _rows.where(_isSystemKind).toList();
    return _rows;
  }

  Color _accentFor(Map<String, dynamic> row) {
    if (_isPromoKind(row)) return AppTheme.primary;
    if (_isOrderKind(row)) return AppTheme.live;
    return AppTheme.primary;
  }

  String _relativeTime(DateTime? created) {
    if (created == null) return '';
    final local = created.toLocal();
    final diff = DateTime.now().difference(local);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} mins ago';
    if (diff.inHours < 24) return '${diff.inHours} hours ago';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return formatAppDateTime(local);
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

  Future<void> _openRow(Map<String, dynamic> row) async {
    await _markRead(row);
    if (!mounted) return;
    final path = alertOpenPath(
      alertDataFromNotificationRow(row),
      role: AuthSession.roleFromSession().storageValue,
    );
    if (path == null || path.isEmpty) return;
    AlertService.openAlertRoute(path);
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

  Future<void> _markAllRead() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await Supabase.instance.client.from('user_notifications').update({
        'read_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('user_id', uid);
      if (!mounted) return;
      final stamp = DateTime.now().toUtc().toIso8601String();
      setState(() {
        _rows = _rows.map((item) => {...item, 'read_at': item['read_at'] ?? stamp}).toList();
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final unread = _rows.where((row) => row['read_at'] == null).length;
    final visible = _visibleRows;
    return Scaffold(
      backgroundColor: AppTheme.canvasOf(context),
      appBar: AppBar(
        title: const Text('Notifications'),
        automaticallyImplyLeading: !widget.embedded,
        leading: widget.embedded
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/customer-hub');
                  }
                },
              ),
        actions: [
          if (_rows.isNotEmpty)
            TextButton(
              onPressed: unread == 0 ? null : _markAllRead,
              child: const Text('Mark all as read', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
        ],
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
                          title: DinerLocaleController.instance.copy.notifications,
                          message: _error,
                          actionLabel: 'Retry',
                          onAction: _load,
                        ),
                      ),
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      Row(
                        children: [
                          _filterChip('All ($unread)', 'all'),
                          const SizedBox(width: 8),
                          _filterChip('Orders', 'orders'),
                          const SizedBox(width: 8),
                          _filterChip(widget.partnerInbox ? 'System' : 'Promotions', widget.partnerInbox ? 'system' : 'promos'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (visible.isEmpty)
                        EmptyState(
                          icon: Icons.notifications_none_outlined,
                          title: 'You are up to date',
                          message: 'Kitchen, delivery, and support notes land here.',
                        )
                      else
                        ...visible.map((row) {
                          final unreadRow = row['read_at'] == null;
                          final created = DateTime.tryParse(row['created_at']?.toString() ?? '');
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: DinerAccentCard(
                              accent: _accentFor(row),
                              unread: unreadRow,
                              onTap: () => _openRow(row),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    row['title']?.toString() ?? 'Update',
                                    style: TextStyle(
                                      fontWeight: unreadRow ? FontWeight.w800 : FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(row['body']?.toString() ?? '', style: AppTheme.caption),
                                  const SizedBox(height: 6),
                                  Text(_relativeTime(created), style: AppTheme.captionOf(context)),
                                ],
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final selected = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : AppTheme.surfaceOf(context),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? AppTheme.primary : AppTheme.hairlineOf(context)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 12,
            color: selected ? Colors.white : AppTheme.onSurfaceOf(context),
          ),
        ),
      ),
    );
  }
}
