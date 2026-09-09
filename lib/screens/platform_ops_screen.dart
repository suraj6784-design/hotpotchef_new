// lib/screens/platform_ops_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_session.dart';
import '../utils/helpers.dart';
import '../utils/kyc_checklist.dart';
import '../utils/network.dart';
import '../utils/platform_ops_access.dart';
import '../utils/support.dart';
import '../widgets/app_widgets.dart';
import '../widgets/customer_ui_components.dart';

part 'platform_ops_desk_tabs.dart';

/// In-app desk for packaging, FSSAI, brand ads, refunds, tickets, KYC, accounts, and helpers.
class PlatformOpsScreen extends StatefulWidget {
  const PlatformOpsScreen({super.key});

  @override
  State<PlatformOpsScreen> createState() => _PlatformOpsScreenState();
}

class _OpsTabSpec {
  const _OpsTabSpec(this.key, this.label, this.builder);
  final String key;
  final String label;
  final Widget Function() builder;
}

class _PlatformOpsScreenState extends State<PlatformOpsScreen> with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  TabController? _tabs;
  List<_OpsTabSpec> _tabSpecs = const [];
  bool _checking = true;
  bool _allowed = false;
  bool _isOwner = false;
  bool _busy = false;
  int _reloadToken = 0;
  String _opsEmail = '';

  @override
  void initState() {
    super.initState();
    _gate();
  }

  @override
  void dispose() {
    _tabs?.dispose();
    super.dispose();
  }

  Future<void> _gate() async {
    await AuthSession.syncOwnerAdminRole();
    final ok = await AuthSession.isPlatformOps();
    final owner = await AuthSession.isPlatformOwner();
    final perms = await AuthSession.opsPermissions();
    if (!mounted) return;

    final specs = <_OpsTabSpec>[];
    void add(String key, String label, Widget Function() builder) {
      if (owner || opsPermissionsContain(perms, key, owner: owner)) {
        specs.add(_OpsTabSpec(key, label, builder));
      }
    }

    add(kOpsPermissionDashboard, 'Dashboard', () => _OpsDashList(key: ValueKey('dash-$_reloadToken')));
    add(
      kOpsPermissionPackaging,
      'Packaging',
      () => _PackagingOpsList(key: ValueKey('pack-$_reloadToken'), busy: _busy, onStatus: _setPackagingStatus),
    );
    add(
      kOpsPermissionFssai,
      'FSSAI',
      () => _FssaiOpsList(key: ValueKey('fssai-$_reloadToken'), busy: _busy, onStatus: _setFssaiStatus),
    );
    add(
      kOpsPermissionBrands,
      'Brands',
      () => _BrandOpsList(
        key: ValueKey('brand-$_reloadToken'),
        busy: _busy,
        onEnd: (row) => _setBrandStatus(row, 'ended'),
        onReject: (row) => _setBrandStatus(row, 'draft', packageLabel: 'Returned to draft'),
        onPublish: _publishBrand,
      ),
    );
    add(
      kOpsPermissionRefunds,
      'Refunds',
      () => _RefundsOpsList(
        key: ValueKey('refund-$_reloadToken'),
        busy: _busy,
        onOpenDispute: _openRefundDispute,
        onDisputeStatus: _setDisputeStatus,
      ),
    );
    add(
      kOpsPermissionTickets,
      'Tickets',
      () => _TicketsOpsList(key: ValueKey('ticket-$_reloadToken'), busy: _busy, onStatus: _setTicketStatus),
    );
    add(kOpsPermissionKyc, 'KYC', () => _KycOpsList(key: ValueKey('kyc-$_reloadToken')));
    if (owner) {
      specs.add(
        _OpsTabSpec(
          kOpsPermissionProfile,
          'Profile',
          () => _AdminProfileList(
            key: ValueKey('profile-$_reloadToken'),
            email: _supabase.auth.currentUser?.email ?? '',
            onOpenTab: (key) {
              final index = specs.indexWhere((t) => t.key == key);
              if (index >= 0) _tabs?.animateTo(index);
            },
          ),
        ),
      );
      specs.add(
        _OpsTabSpec(
          kOpsPermissionAccounts,
          'Accounts',
          () => _OpsAccountsList(key: ValueKey('acct-$_reloadToken'), busy: _busy, onChanged: _bump),
        ),
      );
      specs.add(
        _OpsTabSpec(
          kOpsPermissionHelpers,
          'Helpers',
          () => _OpsHelpersList(key: ValueKey('help-$_reloadToken'), busy: _busy, onChanged: _bump),
        ),
      );
      specs.add(
        _OpsTabSpec(
          kOpsPermissionCatalog,
          'Catalog',
          () => _CatalogOpsList(
            key: ValueKey('cat-$_reloadToken'),
            busy: _busy,
            onStatus: _setMealStatus,
          ),
        ),
      );
    }

    _tabs?.dispose();
    _tabs = specs.isEmpty ? null : TabController(length: specs.length, vsync: this);
    setState(() {
      _tabSpecs = specs;
      _allowed = ok;
      _isOwner = owner;
      _opsEmail = _supabase.auth.currentUser?.email ?? '';
      _checking = false;
    });
  }

  void _bump() {
    if (mounted) setState(() => _reloadToken++);
  }

  Future<void> _setPackagingStatus(Map<String, dynamic> row, String status) async {
    final id = row['id']?.toString();
    if (id == null || id.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await _supabase.rpc(
        'ops_set_packaging_request_status',
        params: {
          'p_request_id': id,
          'p_status': status,
          'p_ops_note': null,
        },
      ).withTimeout(NetworkTimeouts.standard);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Marked $status'), backgroundColor: Colors.green),
      );
      _bump();
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Ops packaging status failed');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setFssaiStatus(Map<String, dynamic> row, String status) async {
    final id = row['id']?.toString();
    if (id == null || id.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await _supabase.rpc(
        'ops_set_fssai_status',
        params: {
          'p_chef_id': id,
          'p_status': status,
          'p_review_note': null,
        },
      ).withTimeout(NetworkTimeouts.standard);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('FSSAI marked $status'), backgroundColor: Colors.green),
      );
      _bump();
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Ops FSSAI status failed');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setBrandStatus(
    Map<String, dynamic> row,
    String status, {
    int? packageAmountPaise,
    String? packageLabel,
  }) async {
    final id = row['id']?.toString();
    if (id == null || id.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await _supabase.rpc(
        'platform_set_ad_campaign_status',
        params: {
          'p_campaign_id': id,
          'p_status': status,
          'p_review_note': null,
          'p_package_amount_paise': packageAmountPaise,
          'p_package_label': packageLabel,
          'p_starts_at': status == 'live' ? DateTime.now().toUtc().toIso8601String() : null,
          'p_ends_at': null,
        },
      ).withTimeout(NetworkTimeouts.standard);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Brand referral marked $status'), backgroundColor: Colors.green),
      );
      _bump();
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Ops brand campaign status failed');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setTicketStatus(Map<String, dynamic> row, String status) async {
    final id = row['id']?.toString();
    if (id == null || id.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await _supabase.rpc(
        'ops_set_ticket_status',
        params: {
          'p_ticket_id': id,
          'p_status': status,
          'p_note': null,
        },
      ).withTimeout(NetworkTimeouts.standard);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ticket marked $status'), backgroundColor: Colors.green),
      );
      _bump();
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Ops ticket status failed');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setDisputeStatus(Map<String, dynamic> row, String status) async {
    final id = row['id']?.toString();
    if (id == null || id.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await _supabase.rpc(
        'ops_set_dispute_status',
        params: {
          'p_dispute_id': id,
          'p_status': status,
          'p_resolution_note': null,
        },
      ).withTimeout(NetworkTimeouts.standard);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Dispute marked $status'), backgroundColor: Colors.green),
      );
      _bump();
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Ops dispute status failed');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setMealStatus(Map<String, dynamic> row, String status) async {
    final id = row['id']?.toString();
    if (id == null || id.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await _supabase.rpc(
        'ops_set_meal_status',
        params: {'p_meal_id': id, 'p_status': status},
      ).withTimeout(NetworkTimeouts.standard);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Meal marked $status'), backgroundColor: Colors.green),
      );
      _bump();
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Ops meal status failed');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openRefundDispute(Map<String, dynamic> row) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final orderUuid = row['id']?.toString();
      final orderNumber = row['order_id']?.toString();
      final ticket = await createSupportTicket(
        subject: supportContactSubject(orderNumber: orderNumber),
        body: supportContactMessage(orderNumber: orderNumber, orderUuid: orderUuid),
        orderId: orderUuid,
        orderNumber: orderNumber,
        category: 'refund',
        channel: 'in_app',
      ).withTimeout(NetworkTimeouts.standard);
      if (!mounted) return;
      final publicId = ticket?['public_id']?.toString() ?? '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            publicId.isEmpty ? 'Refund dispute opened' : 'Dispute ticket $publicId opened',
          ),
          backgroundColor: Colors.green,
        ),
      );
      _bump();
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Ops open refund dispute failed');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open dispute: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _publishBrand(Map<String, dynamic> row) async {
    final controller = TextEditingController(text: '4999');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Go live'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              row['advertiser_name']?.toString() ?? 'Brand',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Package price (₹)',
                helperText: 'Billed to the partner by HotPotChef',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Publish live')),
        ],
      ),
    );
    final rupees = int.tryParse(controller.text.trim()) ?? 0;
    controller.dispose();
    if (ok != true || !mounted) return;
    await _setBrandStatus(
      row,
      'live',
      packageAmountPaise: (rupees < 0 ? 0 : rupees) * 100,
      packageLabel: rupees > 0 ? 'Platform package ₹$rupees' : 'Platform package',
    );
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will leave the Admin desk and return to the customer feed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Log out')),
        ],
      ),
    );
    if (ok == true && mounted) {
      await AuthSession.logout(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_allowed) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Admin desk'),
          actions: [
            IconButton(
              tooltip: 'Log out',
              icon: const Icon(Icons.logout),
              onPressed: _confirmLogout,
            ),
          ],
        ),
        body: const EmptyState(
          icon: Icons.lock_outline,
          title: 'Ops access required',
          message:
              'Only the HotPotChef platform admin account can open this desk.',
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.canvasOf(context),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_isOwner ? 'Admin desk' : 'Platform ops'),
            if (_opsEmail.isNotEmpty)
              Text(
                _isOwner ? 'Owner · $_opsEmail' : _opsEmail,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppTheme.textMuted),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
            onPressed: _confirmLogout,
          ),
        ],
        bottom: _tabs == null || _tabSpecs.isEmpty
            ? null
            : TabBar(
                controller: _tabs,
                isScrollable: true,
                tabs: [for (final t in _tabSpecs) Tab(text: t.label)],
              ),
      ),
      body: _tabs == null || _tabSpecs.isEmpty
          ? const EmptyState(
              icon: Icons.lock_outline,
              title: 'No ops permissions',
              message: 'Ask the platform owner for a helper invite code.',
            )
          : TabBarView(
              controller: _tabs,
              children: [for (final t in _tabSpecs) t.builder()],
            ),
    );
  }
}

class _PackagingOpsList extends StatelessWidget {
  const _PackagingOpsList({super.key, required this.busy, required this.onStatus});

  final bool busy;
  final Future<void> Function(Map<String, dynamic> row, String status) onStatus;

  @override
  Widget build(BuildContext context) {
    final client = Supabase.instance.client;
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: () async {
        final rows = await client
            .from('customer_requests')
            .select()
            .order('created_at', ascending: false)
            .limit(80);
        return List<Map<String, dynamic>>.from(rows as List)
            .where(isPackagingSupplyRequest)
            .toList();
      }(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snap.data ?? const [];
        if (rows.isEmpty) {
          return const EmptyState(
            icon: Icons.inventory_2_outlined,
            title: 'No packaging requests',
            message: 'Chef supply requests appear here for confirmation and fulfillment.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            final status = packagingRequestStatusLabel(row['status']?.toString());
            final requestId = packagingRequestDisplayId(row);
            final total = parseMoney(row['quoted_total'] ?? row['budget']);
            return AppCard(
              margin: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          row['title']?.toString() ?? 'Packaging',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      Text(status, style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.primary)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${requestId.isEmpty ? 'SUP' : requestId} · Qty ${row['quantity'] ?? 1} · ₹${total.toStringAsFixed(0)}',
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${row['customer_name'] ?? 'Chef'} · ${row['customer_phone'] ?? ''}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  Text(
                    row['delivery_address']?.toString() ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final next in const ['Confirmed', 'Packed', 'Out for Delivery', 'Fulfilled', 'Rejected'])
                        OutlinedButton(
                          onPressed: busy || status.toLowerCase() == next.toLowerCase()
                              ? null
                              : () => onStatus(row, next),
                          child: Text(next, style: const TextStyle(fontSize: 12)),
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _FssaiOpsList extends StatelessWidget {
  const _FssaiOpsList({super.key, required this.busy, required this.onStatus});

  final bool busy;
  final Future<void> Function(Map<String, dynamic> row, String status) onStatus;

  @override
  Widget build(BuildContext context) {
    final client = Supabase.instance.client;
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: () async {
        final rows = await client
            .from('users')
            .select(
              'id, name, full_name, phone, email, fssai_number, fssai_proof_url, fssai_verification_status, fssai_review_note',
            )
            .neq('fssai_verification_status', 'unsubmitted')
            .order('updated_at', ascending: false)
            .limit(80);
        return List<Map<String, dynamic>>.from(rows as List);
      }(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return EmptyState(
            icon: Icons.error_outline,
            title: 'Could not load FSSAI queue',
            message: '${snap.error}',
          );
        }
        final rows = snap.data ?? const [];
        if (rows.isEmpty) {
          return const EmptyState(
            icon: Icons.verified_user_outlined,
            title: 'No FSSAI proofs pending',
            message: 'Chefs who upload licence photos appear here for verification.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            final status = normalizeFssaiVerificationStatus(row['fssai_verification_status']?.toString());
            final proof = row['fssai_proof_url']?.toString() ?? '';
            final name = row['name']?.toString() ?? row['full_name']?.toString() ?? 'Chef';
            return AppCard(
              margin: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
                      ),
                      Text(fssaiVerificationLabel(status), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'FSSAI ${row['fssai_number'] ?? '—'} · ${row['phone'] ?? ''}',
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                  ),
                  if (proof.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: proof,
                        height: 160,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: busy || status == 'verified' ? null : () => onStatus(row, 'verified'),
                          child: const Text('Verify'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: busy || status == 'rejected' ? null : () => onStatus(row, 'rejected'),
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade700),
                          child: const Text('Reject'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _BrandOpsList extends StatelessWidget {
  const _BrandOpsList({
    super.key,
    required this.busy,
    required this.onPublish,
    required this.onReject,
    required this.onEnd,
  });

  final bool busy;
  final Future<void> Function(Map<String, dynamic> row) onPublish;
  final Future<void> Function(Map<String, dynamic> row) onReject;
  final Future<void> Function(Map<String, dynamic> row) onEnd;

  @override
  Widget build(BuildContext context) {
    final client = Supabase.instance.client;
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: () async {
        final rows = await client
            .from('ad_campaigns')
            .select()
            .order('updated_at', ascending: false)
            .limit(80);
        return List<Map<String, dynamic>>.from(rows as List);
      }(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return EmptyState(
            icon: Icons.error_outline,
            title: 'Could not load brand referrals',
            message: '${snap.error}',
          );
        }
        final rows = snap.data ?? const [];
        if (rows.isEmpty) {
          return const EmptyState(
            icon: Icons.campaign_outlined,
            title: 'No brand referrals yet',
            message: 'When chefs submit Refer a brand, they appear here for review and go-live.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            final status = (row['status']?.toString() ?? 'draft').toLowerCase();
            final brand = row['advertiser_name']?.toString() ?? 'Brand';
            final title = row['title']?.toString() ?? '';
            final contact = row['contact_note']?.toString() ?? '';
            final url = row['cta_url']?.toString() ?? '';
            final reach = row['reach_mode']?.toString() ?? 'overall';
            return AppCard(
              margin: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(brand, style: const TextStyle(fontWeight: FontWeight.w800)),
                      ),
                      Text(
                        status == 'pending_review'
                            ? 'Pending review'
                            : status == 'live'
                                ? 'Live'
                                : status == 'ended'
                                    ? 'Ended'
                                    : 'Draft',
                        style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.primary, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  if ((row['body']?.toString() ?? '').isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      row['body'].toString(),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    [
                      reach == 'targeted' ? 'Targeted ${row['city'] ?? ''}'.trim() : 'Overall reach',
                      if (contact.isNotEmpty) contact,
                      if (url.isNotEmpty) url,
                    ].join(' · '),
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (status == 'pending_review' || status == 'draft')
                        ElevatedButton(
                          onPressed: busy ? null : () => onPublish(row),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Publish live'),
                        ),
                      if (status == 'pending_review')
                        OutlinedButton(
                          onPressed: busy ? null : () => onReject(row),
                          child: const Text('Return to draft'),
                        ),
                      if (status == 'live')
                        OutlinedButton(
                          onPressed: busy ? null : () => onEnd(row),
                          child: const Text('End campaign'),
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _RefundsOpsList extends StatelessWidget {
  const _RefundsOpsList({
    super.key,
    required this.busy,
    required this.onOpenDispute,
    required this.onDisputeStatus,
  });

  final bool busy;
  final Future<void> Function(Map<String, dynamic> row) onOpenDispute;
  final Future<void> Function(Map<String, dynamic> row, String status) onDisputeStatus;

  @override
  Widget build(BuildContext context) {
    final client = Supabase.instance.client;
    return FutureBuilder<({List<Map<String, dynamic>> orders, Map<String, Map<String, dynamic>> disputes})>(
      future: () async {
        final rows = await client
            .from('orders')
            .select()
            .inFilter('refund_status', ['failed', 'pending'])
            .order('updated_at', ascending: false)
            .limit(80)
            .withTimeout(NetworkTimeouts.standard);
        final orders = List<Map<String, dynamic>>.from(rows as List);
        final ids = orders.map((o) => o['id']?.toString() ?? '').where((id) => id.isNotEmpty).toList();
        final disputesByOrder = <String, Map<String, dynamic>>{};
        if (ids.isNotEmpty) {
          final disputes = await client
              .from('order_disputes')
              .select()
              .inFilter('order_id', ids)
              .order('created_at', ascending: false)
              .withTimeout(NetworkTimeouts.standard);
          for (final d in List<Map<String, dynamic>>.from(disputes as List)) {
            final oid = d['order_id']?.toString() ?? '';
            if (oid.isEmpty || disputesByOrder.containsKey(oid)) continue;
            disputesByOrder[oid] = d;
          }
        }
        return (orders: orders, disputes: disputesByOrder);
      }(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return EmptyState(
            icon: Icons.error_outline,
            title: 'Could not load refunds',
            message: '${snap.error}',
          );
        }
        final data = snap.data;
        final rows = data?.orders ?? const [];
        final disputes = data?.disputes ?? const {};
        if (rows.isEmpty) {
          return const EmptyState(
            icon: Icons.currency_rupee,
            title: 'No pending refunds',
            message: 'Orders with failed or pending refunds appear here for investigation.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            final refundStatus = (row['refund_status']?.toString() ?? '—').toLowerCase();
            final orderNumber = row['order_id']?.toString() ?? '';
            final orderUuid = row['id']?.toString() ?? '';
            final displayId = orderNumber.isNotEmpty ? orderNumber : orderUuid;
            final amount = parseMoney(row['total_price'] ?? row['total_amount'] ?? row['grand_total']);
            final status = row['status']?.toString() ?? '—';
            final dispute = disputes[orderUuid];
            final disputeStatus = dispute?['status']?.toString().toLowerCase() ?? '';
            return AppCard(
              margin: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          displayId.isEmpty ? 'Order' : displayId,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      Text(
                        refundStatus,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: refundStatus == 'failed' ? AppTheme.error : AppTheme.warning,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Status $status · ₹${amount.toStringAsFixed(0)}'
                    '${row['refund_id'] != null ? ' · refund ${row['refund_id']}' : ''}',
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                  ),
                  if (orderUuid.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'UUID $orderUuid',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                    ),
                  ],
                  if (dispute != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Dispute ${dispute['public_id'] ?? ''} · $disputeStatus',
                      style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: displayId.isEmpty
                            ? null
                            : () async {
                                await Clipboard.setData(ClipboardData(text: displayId));
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Order id copied')),
                                );
                              },
                        icon: const Icon(Icons.copy, size: 16),
                        label: const Text('Copy order id', style: TextStyle(fontSize: 12)),
                      ),
                      if (dispute == null)
                        ElevatedButton(
                          onPressed: busy ? null : () => onOpenDispute(row),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Open dispute', style: TextStyle(fontSize: 12)),
                        )
                      else ...[
                        OutlinedButton(
                          onPressed: busy || disputeStatus == 'investigating'
                              ? null
                              : () => onDisputeStatus(dispute, 'investigating'),
                          child: const Text('Mark investigating', style: TextStyle(fontSize: 12)),
                        ),
                        OutlinedButton(
                          onPressed: busy || disputeStatus == 'resolved'
                              ? null
                              : () => onDisputeStatus(dispute, 'resolved'),
                          child: const Text('Resolve dispute', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _TicketsOpsList extends StatelessWidget {
  const _TicketsOpsList({super.key, required this.busy, required this.onStatus});

  final bool busy;
  final Future<void> Function(Map<String, dynamic> row, String status) onStatus;

  bool _isOverdue(Map<String, dynamic> row) {
    final status = (row['status']?.toString() ?? '').toLowerCase();
    if (status != 'open' && status != 'pending_ops' && status != 'pending_customer') return false;
    final raw = row['sla_due_at']?.toString();
    if (raw == null || raw.isEmpty) return false;
    final due = DateTime.tryParse(raw);
    if (due == null) return false;
    return due.toUtc().isBefore(DateTime.now().toUtc()) &&
        (status == 'open' || status == 'pending_ops');
  }

  @override
  Widget build(BuildContext context) {
    final client = Supabase.instance.client;
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: () async {
        final rows = await client
            .from('support_tickets')
            .select()
            .order('created_at', ascending: false)
            .limit(80)
            .withTimeout(NetworkTimeouts.standard);
        return List<Map<String, dynamic>>.from(rows as List);
      }(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return EmptyState(
            icon: Icons.error_outline,
            title: 'Could not load tickets',
            message: '${snap.error}',
          );
        }
        final rows = snap.data ?? const [];
        if (rows.isEmpty) {
          return const EmptyState(
            icon: Icons.support_agent_outlined,
            title: 'No support tickets',
            message: 'In-app tickets from customers and chefs appear here.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            final status = (row['status']?.toString() ?? 'open').toLowerCase();
            final overdue = _isOverdue(row);
            final publicId = row['public_id']?.toString() ?? 'Ticket';
            final subject = row['subject']?.toString() ?? '';
            final orderNumber = row['order_number']?.toString() ?? '';
            final sla = row['sla_due_at']?.toString() ?? '';
            return AppCard(
              margin: const EdgeInsets.only(bottom: 12),
              child: Container(
                decoration: overdue
                    ? BoxDecoration(
                        border: Border.all(color: AppTheme.error.withValues(alpha: 0.45)),
                        borderRadius: BorderRadius.circular(12),
                      )
                    : null,
                padding: overdue ? const EdgeInsets.all(8) : EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(publicId, style: const TextStyle(fontWeight: FontWeight.w800)),
                        ),
                        Text(
                          overdue ? 'SLA overdue · $status' : status,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: overdue ? AppTheme.error : AppTheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(subject, style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (orderNumber.isNotEmpty) 'Order $orderNumber',
                        if (sla.isNotEmpty) 'SLA $sla',
                        row['category']?.toString() ?? '',
                      ].where((s) => s.trim().isNotEmpty).join(' · '),
                      style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: busy || status == 'resolved' ? null : () => onStatus(row, 'resolved'),
                          child: const Text('Resolve', style: TextStyle(fontSize: 12)),
                        ),
                        OutlinedButton(
                          onPressed: busy || status == 'pending_ops' ? null : () => onStatus(row, 'pending_ops'),
                          child: const Text('Pending ops', style: TextStyle(fontSize: 12)),
                        ),
                        OutlinedButton(
                          onPressed: busy || status == 'closed' ? null : () => onStatus(row, 'closed'),
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade700),
                          child: const Text('Close', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _KycOpsList extends StatelessWidget {
  const _KycOpsList({super.key});

  Future<List<Map<String, dynamic>>> _loadRows(SupabaseClient client) async {
    List<Map<String, dynamic>> list;
    try {
      final rows = await client
          .from('users')
          .select(
            'id, role, name, full_name, email, fssai_number, fssai_proof_url, '
            'fssai_verification_status, gstin, bank_account_number, bank_ifsc, '
            'pan_number, aadhaar_masked',
          )
          .inFilter('role', ['Chef', 'Driver'])
          .limit(120)
          .withTimeout(NetworkTimeouts.standard);
      list = List<Map<String, dynamic>>.from(rows as List);
    } catch (_) {
      // Older DBs may lack bank_* columns — still load KYC identity / FSSAI fields.
      final rows = await client
          .from('users')
          .select(
            'id, role, name, full_name, email, fssai_number, fssai_proof_url, '
            'fssai_verification_status, gstin, pan_number, aadhaar_masked',
          )
          .inFilter('role', ['Chef', 'Driver'])
          .limit(120)
          .withTimeout(NetworkTimeouts.standard);
      list = List<Map<String, dynamic>>.from(rows as List);
    }

    final chefIds = list
        .where((row) => (row['role']?.toString() ?? '').toLowerCase() == 'chef')
        .map((row) => row['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
    if (chefIds.isNotEmpty) {
      try {
        final profiles = await client
            .from('chef_profiles')
            .select('user_id, local_kitchen_name')
            .inFilter('user_id', chefIds)
            .withTimeout(NetworkTimeouts.standard);
        final byUser = <String, String>{};
        for (final profile in List<Map<String, dynamic>>.from(profiles as List)) {
          final id = profile['user_id']?.toString() ?? '';
          if (id.isEmpty) continue;
          byUser[id] = profile['local_kitchen_name']?.toString() ?? '';
        }
        for (final row in list) {
          final id = row['id']?.toString() ?? '';
          if (byUser.containsKey(id)) {
            row['local_kitchen_name'] = byUser[id];
          }
        }
      } catch (_) {
        // KYC still loads bank/FSSAI fields if chef_profiles is unavailable.
      }
    }

    list.sort((a, b) {
      final ca = kycChecklistFor(a);
      final cb = kycChecklistFor(b);
      if (ca.incomplete != cb.incomplete) return ca.incomplete ? -1 : 1;
      return ca.done.compareTo(cb.done);
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final client = Supabase.instance.client;
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _loadRows(client),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return EmptyState(
            icon: Icons.error_outline,
            title: 'Could not load KYC queue',
            message: '${snap.error}',
          );
        }
        final rows = snap.data ?? const [];
        if (rows.isEmpty) {
          return const EmptyState(
            icon: Icons.badge_outlined,
            title: 'No chef/driver KYC rows',
            message: 'Partner profiles with KYC fields appear here for completeness review.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            final checklist = kycChecklistFor(row);
            final name = row['name']?.toString() ?? row['full_name']?.toString() ?? 'Partner';
            final role = row['role']?.toString() ?? '';
            final kitchen = row['local_kitchen_name']?.toString() ?? '';
            return AppCard(
              margin: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
                      ),
                      Text(
                        '${checklist.done}/${checklist.total}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: checklist.incomplete ? AppTheme.warning : AppTheme.success,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      role,
                      if (kitchen.isNotEmpty) kitchen,
                      row['email']?.toString() ?? '',
                    ].where((s) => s.trim().isNotEmpty).join(' · '),
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                  ),
                  Builder(
                    builder: (_) {
                      final bankMasked = maskBankAccount(row['bank_account_number']?.toString());
                      final panMasked = maskPan(row['pan_number']?.toString());
                      final bits = <String>[
                        if (bankMasked.isNotEmpty) 'Bank $bankMasked',
                        if (panMasked.isNotEmpty) 'PAN $panMasked',
                      ];
                      if (bits.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          bits.join(' · '),
                          style: const TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      );
                    },
                  ),
                  if (checklist.missing.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Missing: ${checklist.missing.join(', ')}',
                      style: const TextStyle(fontSize: 12, color: AppTheme.error),
                    ),
                  ] else ...[
                    const SizedBox(height: 8),
                    const Text(
                      'KYC checklist complete',
                      style: TextStyle(fontSize: 12, color: AppTheme.success, fontWeight: FontWeight.w700),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}
