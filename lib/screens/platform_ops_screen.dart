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
import '../utils/network.dart';
import '../utils/platform_ops_access.dart';
import '../utils/support.dart';
import '../widgets/app_widgets.dart';
import '../widgets/customer_ui_components.dart';
import 'brand_campaign_editor_sheet.dart';

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

class _PlatformOpsScreenState extends State<PlatformOpsScreen> {
  final _supabase = Supabase.instance.client;
  List<_OpsTabSpec> _tabSpecs = const [];
  String _selectedKey = kOpsPermissionDashboard;
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
        onSchedule: _scheduleBrand,
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
      () => _TicketsOpsList(
        key: ValueKey('ticket-$_reloadToken'),
        busy: _busy,
        onStatus: _setTicketStatus,
        onOpenThread: (row) async {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => _OpsTicketThreadScreen(ticket: row),
            ),
          );
          if (mounted) _bump();
        },
      ),
    );
    add(kOpsPermissionKyc, 'KYC', () => _KycOpsList(key: ValueKey('kyc-$_reloadToken')));
    add(kOpsPermissionAudit, 'Audit', () => _OpsAuditList(key: ValueKey('audit-$_reloadToken')));
    if (owner) {
      specs.add(
        _OpsTabSpec(
          kOpsPermissionProfile,
          'Profile',
          () => _AdminProfileList(
            key: ValueKey('profile-$_reloadToken'),
            email: _supabase.auth.currentUser?.email ?? '',
            onOpenTab: _openTab,
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

    setState(() {
      _tabSpecs = specs;
      _allowed = ok;
      _isOwner = owner;
      _opsEmail = _supabase.auth.currentUser?.email ?? '';
      _checking = false;
      if (!specs.any((t) => t.key == _selectedKey)) {
        _selectedKey = specs.isEmpty ? kOpsPermissionDashboard : specs.first.key;
      }
    });
  }

  void _openTab(String key) {
    if (!_tabSpecs.any((t) => t.key == key)) return;
    setState(() => _selectedKey = key);
  }

  _OpsTabSpec? get _currentSpec {
    for (final spec in _tabSpecs) {
      if (spec.key == _selectedKey) return spec;
    }
    return _tabSpecs.isEmpty ? null : _tabSpecs.first;
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
        SnackBar(content: Text(opsFriendlyError(e)), backgroundColor: Colors.redAccent),
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
        SnackBar(content: Text(opsFriendlyError(e)), backgroundColor: Colors.redAccent),
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
        SnackBar(content: Text(opsFriendlyError(e)), backgroundColor: Colors.redAccent),
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
        SnackBar(content: Text(opsFriendlyError(e)), backgroundColor: Colors.redAccent),
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
        SnackBar(content: Text(opsFriendlyError(e)), backgroundColor: Colors.redAccent),
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
        SnackBar(content: Text(opsFriendlyError(e)), backgroundColor: Colors.redAccent),
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
        SnackBar(content: Text(opsFriendlyError(e)), backgroundColor: Colors.redAccent),
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

  Future<void> _scheduleBrand(Map<String, dynamic> row) async {
    final saved = await showBrandCampaignEditorSheet(context, row: row);
    if (saved && mounted) _bump();
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

    final wide = MediaQuery.sizeOf(context).width >= 900;
    final nav = _OpsDeskNav(
      isOwner: _isOwner,
      email: _opsEmail,
      selectedKey: _selectedKey,
      groups: opsNavGroupsFor(_tabSpecs.map((t) => t.key)),
      popOnSelect: !wide,
      onSelect: _openTab,
    );

    return Scaffold(
      backgroundColor: AppTheme.canvasOf(context),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_currentSpec?.label ?? (_isOwner ? 'Admin desk' : 'Platform ops')),
            if (opsNavGroupTitleFor(_selectedKey) != null || _opsEmail.isNotEmpty)
              Text(
                [
                  if (opsNavGroupTitleFor(_selectedKey) != null) opsNavGroupTitleFor(_selectedKey)!,
                  if (_opsEmail.isNotEmpty) (_isOwner ? 'Owner · $_opsEmail' : _opsEmail),
                ].join(' · '),
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
      ),
      drawer: wide ? null : Drawer(child: nav),
      body: _tabSpecs.isEmpty
          ? const EmptyState(
              icon: Icons.lock_outline,
              title: 'No ops permissions',
              message: 'Ask the platform owner for a helper invite code.',
            )
          : wide
              ? Row(
                  children: [
                    SizedBox(width: 268, child: nav),
                    VerticalDivider(width: 1, color: AppTheme.surfaceMutedLight.withValues(alpha: 0.9)),
                    Expanded(child: _currentSpec!.builder()),
                  ],
                )
              : _currentSpec!.builder(),
    );
  }
}

IconData _opsNavIcon(String key) {
  switch (key) {
    case kOpsPermissionDashboard:
      return Icons.insights_outlined;
    case kOpsPermissionProfile:
      return Icons.person_outline;
    case kOpsPermissionCatalog:
      return Icons.storefront_outlined;
    case kOpsPermissionPackaging:
      return Icons.inventory_2_outlined;
    case kOpsPermissionKyc:
      return Icons.badge_outlined;
    case kOpsPermissionFssai:
      return Icons.verified_outlined;
    case kOpsPermissionBrands:
      return Icons.campaign_outlined;
    case kOpsPermissionTickets:
      return Icons.confirmation_number_outlined;
    case kOpsPermissionRefunds:
      return Icons.currency_rupee;
    case kOpsPermissionAccounts:
      return Icons.people_outline;
    case kOpsPermissionHelpers:
      return Icons.support_agent_outlined;
    case kOpsPermissionAudit:
      return Icons.policy_outlined;
    default:
      return Icons.tune;
  }
}

class _OpsDeskNav extends StatelessWidget {
  const _OpsDeskNav({
    required this.isOwner,
    required this.email,
    required this.selectedKey,
    required this.groups,
    required this.popOnSelect,
    required this.onSelect,
  });

  final bool isOwner;
  final String email;
  final String selectedKey;
  final List<OpsNavGroup> groups;
  final bool popOnSelect;
  final void Function(String key) onSelect;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppTheme.surfaceOf(context),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isOwner ? 'Admin desk' : 'Platform ops',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                  ),
                  if (email.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      email,
                      style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            for (final group in groups) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
                child: Text(
                  group.title.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: AppTheme.textMuted,
                  ),
                ),
              ),
              for (final key in group.keys)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: ListTile(
                    selected: key == selectedKey,
                    selectedTileColor: AppTheme.primary.withValues(alpha: 0.12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    leading: Icon(_opsNavIcon(key), size: 22),
                    title: Text(
                      opsPermissionLabel(key),
                      style: TextStyle(
                        fontWeight: key == selectedKey ? FontWeight.w800 : FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    onTap: () {
                      onSelect(key);
                      if (popOnSelect && Navigator.of(context).canPop()) {
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                ),
            ],
          ],
        ),
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
            message: opsFriendlyError(snap.error ?? 'unknown'),
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
    required this.onSchedule,
  });

  final bool busy;
  final Future<void> Function(Map<String, dynamic> row) onPublish;
  final Future<void> Function(Map<String, dynamic> row) onReject;
  final Future<void> Function(Map<String, dynamic> row) onEnd;
  final Future<void> Function(Map<String, dynamic> row) onSchedule;

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
            message: opsFriendlyError(snap.error ?? 'unknown'),
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
                      OutlinedButton(
                        onPressed: busy ? null : () => onSchedule(row),
                        child: const Text('Schedule & media'),
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
            message: opsFriendlyError(snap.error ?? 'unknown'),
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
                      IconButton(
                        tooltip: 'Copy order id',
                        onPressed: displayId.isEmpty
                            ? null
                            : () async {
                                await Clipboard.setData(ClipboardData(text: displayId));
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Order id copied')),
                                );
                              },
                        icon: const Icon(Icons.copy, size: 18),
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
  const _TicketsOpsList({
    super.key,
    required this.busy,
    required this.onStatus,
    required this.onOpenThread,
  });

  final bool busy;
  final Future<void> Function(Map<String, dynamic> row, String status) onStatus;
  final void Function(Map<String, dynamic> row) onOpenThread;

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
            message: opsFriendlyError(snap.error ?? 'unknown'),
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
            final sla = formatTicketSlaDue(row['sla_due_at']?.toString());
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
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => onOpenThread(row),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 6),
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
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton(
                          onPressed: () => onOpenThread(row),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text('Reply', style: TextStyle(fontSize: 12)),
                        ),
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

class _KycChecklist {
  const _KycChecklist({required this.done, required this.total, required this.missing});

  final int done;
  final int total;
  final List<String> missing;

  bool get incomplete => done < total;
}

_KycChecklist _kycChecklistFor(Map<String, dynamic> row) {
  final role = (row['role']?.toString() ?? '').toLowerCase();
  final isDriver = role == 'driver';
  final checks = <String, String>{
    'Name': row['name']?.toString() ?? row['full_name']?.toString() ?? '',
    'Email': row['email']?.toString() ?? '',
    'Phone': row['phone']?.toString() ?? '',
    'Bank account': row['bank_account_number']?.toString() ?? '',
    'IFSC': row['ifsc_code']?.toString() ?? row['bank_ifsc']?.toString() ?? '',
    'PAN': row['pan_number']?.toString() ?? '',
    'Aadhaar': row['aadhaar_masked']?.toString() ?? '',
  };
  if (isDriver) {
    checks['Vehicle type'] = row['vehicle_type']?.toString() ?? '';
    checks['Vehicle number'] = row['vehicle_reg_no']?.toString() ?? row['vehicle_number']?.toString() ?? '';
  } else {
    checks['FSSAI number'] = row['fssai_number']?.toString() ?? '';
    checks['FSSAI proof'] = row['fssai_proof_url']?.toString() ?? '';
    checks['FSSAI verified'] =
        normalizeFssaiVerificationStatus(row['fssai_verification_status']?.toString()) == 'verified' ? 'yes' : '';
    checks['GSTIN'] = row['gstin']?.toString() ?? '';
    if (role == 'chef') {
      checks['Kitchen name'] = row['local_kitchen_name']?.toString() ?? '';
    }
  }
  final missing = <String>[];
  var done = 0;
  for (final entry in checks.entries) {
    if (entry.value.trim().isEmpty) {
      missing.add(entry.key);
    } else {
      done++;
    }
  }
  return _KycChecklist(done: done, total: checks.length, missing: missing);
}

class _KycOpsList extends StatelessWidget {
  const _KycOpsList({super.key});

  bool _isRole(Map<String, dynamic> row, String role) =>
      (row['role']?.toString() ?? '').trim().toLowerCase() == role;

  Future<List<Map<String, dynamic>>> _loadRows(SupabaseClient client) async {
    final raw = await client.rpc('ops_list_kyc_queue').withTimeout(NetworkTimeouts.standard);
    final list = raw is List
        ? [for (final row in raw) Map<String, dynamic>.from(row as Map)]
        : <Map<String, dynamic>>[];
    list.sort((a, b) {
      final ca = _kycChecklistFor(a);
      final cb = _kycChecklistFor(b);
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
            message: opsFriendlyError(snap.error ?? 'unknown'),
          );
        }
        final rows = snap.data ?? const [];
        final chefs = rows.where((row) => _isRole(row, 'chef')).toList();
        final drivers = rows.where((row) => _isRole(row, 'driver')).toList();
        return DefaultTabController(
          length: 2,
          child: Column(
            children: [
              Material(
                color: AppTheme.surfaceOf(context),
                child: const TabBar(
                  tabs: [
                    Tab(text: 'Chef Profile'),
                    Tab(text: 'Driver Profile'),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _KycRoleQueue(
                      rows: chefs,
                      emptyTitle: 'No chef profiles',
                      emptyMessage: 'Chef KYC rows appear here for completeness review.',
                    ),
                    _KycRoleQueue(
                      rows: drivers,
                      emptyTitle: 'No driver profiles',
                      emptyMessage: 'Driver KYC rows appear here for completeness review.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _KycRoleQueue extends StatelessWidget {
  const _KycRoleQueue({
    required this.rows,
    required this.emptyTitle,
    required this.emptyMessage,
  });

  final List<Map<String, dynamic>> rows;
  final String emptyTitle;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return EmptyState(
        icon: Icons.badge_outlined,
        title: emptyTitle,
        message: emptyMessage,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: rows.length,
      itemBuilder: (context, index) => _KycPartnerTile(row: rows[index]),
    );
  }
}

class _KycPartnerTile extends StatelessWidget {
  const _KycPartnerTile({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final checklist = _kycChecklistFor(row);
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
  }
}

class _OpsTicketThreadScreen extends StatefulWidget {
  const _OpsTicketThreadScreen({required this.ticket});

  final Map<String, dynamic> ticket;

  @override
  State<_OpsTicketThreadScreen> createState() => _OpsTicketThreadScreenState();
}

class _OpsTicketThreadScreenState extends State<_OpsTicketThreadScreen> {
  final _supabase = Supabase.instance.client;
  final _replyController = TextEditingController();
  bool _loading = true;
  bool _sending = false;
  bool _internalNote = false;
  String? _error;
  List<Map<String, dynamic>> _messages = const [];
  late String _status;

  String get _ticketId => widget.ticket['id']?.toString() ?? '';

  @override
  void initState() {
    super.initState();
    _status = (widget.ticket['status']?.toString() ?? 'open').toLowerCase();
    _loadMessages();
  }

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages({bool silent = false}) async {
    if (_ticketId.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Invalid ticket.';
      });
      return;
    }
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final rows = await _supabase
          .from('support_ticket_messages')
          .select('id, author_id, body, is_internal, created_at')
          .eq('ticket_id', _ticketId)
          .order('created_at', ascending: true)
          .withTimeout(NetworkTimeouts.standard);
      if (!mounted) return;
      setState(() {
        _messages = List<Map<String, dynamic>>.from(rows as List);
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _send() async {
    final body = _replyController.text.trim();
    final user = _supabase.auth.currentUser;
    if (body.isEmpty || user == null || _sending || _ticketId.isEmpty) return;

    setState(() => _sending = true);
    try {
      await _supabase.from('support_ticket_messages').insert({
        'ticket_id': _ticketId,
        'author_id': user.id,
        'body': body,
        'is_internal': _internalNote,
      }).withTimeout(NetworkTimeouts.standard);

      if (!_internalNote && shouldMarkPendingCustomerAfterOpsPublicReply(_status)) {
        await _supabase.rpc(
          'ops_set_ticket_status',
          params: {
            'p_ticket_id': _ticketId,
            'p_status': 'pending_customer',
            'p_note': null,
          },
        ).withTimeout(NetworkTimeouts.standard);
        _status = 'pending_customer';
      }

      _replyController.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_internalNote ? 'Internal note saved' : 'Reply sent to diner'),
          backgroundColor: Colors.green,
        ),
      );
      await _loadMessages(silent: true);
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Ops ticket reply failed');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(opsFriendlyError(e)), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final publicId = widget.ticket['public_id']?.toString() ?? 'Ticket';
    final subject = widget.ticket['subject']?.toString() ?? '';
    final me = _supabase.auth.currentUser?.id;
    final onSurface = AppTheme.onSurfaceOf(context);

    return Scaffold(
      backgroundColor: AppTheme.canvasOf(context),
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
                    'Status: ${_status.replaceAll('_', ' ')}',
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Public replies are visible on My support tickets. Internal notes stay on this desk.',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 12, height: 1.35),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                : _error != null
                    ? Center(child: Text(_error!, style: const TextStyle(color: AppTheme.textMuted)))
                    : _messages.isEmpty
                        ? const Center(
                            child: Text('No messages yet.', style: TextStyle(color: AppTheme.textMuted)),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                            itemCount: _messages.length,
                            itemBuilder: (context, index) {
                              final msg = _messages[index];
                              final isMe = msg['author_id']?.toString() == me;
                              final internal = msg['is_internal'] == true;
                              final body = msg['body']?.toString() ?? '';
                              String timeStr = '';
                              final raw = msg['created_at']?.toString();
                              if (raw != null) {
                                final dt = DateTime.tryParse(raw);
                                if (dt != null) {
                                  timeStr = '${formatFriendlyDate(dt)} · ${formatAppTime(dt)}';
                                }
                              }
                              return Align(
                                alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  constraints: BoxConstraints(
                                    maxWidth: MediaQuery.sizeOf(context).width * 0.82,
                                  ),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: internal
                                        ? AppTheme.primary.withValues(alpha: 0.08)
                                        : (isMe ? AppTheme.primary : AppTheme.surfaceOf(context)),
                                    borderRadius: BorderRadius.circular(14),
                                    border: internal
                                        ? Border.all(color: AppTheme.primary.withValues(alpha: 0.35))
                                        : Border.all(color: AppTheme.hairlineOf(context)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        internal ? 'Internal note' : (isMe ? 'You · diner can see this' : 'Requester'),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: internal
                                              ? AppTheme.primary
                                              : (isMe ? Colors.white70 : AppTheme.textMuted),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        body,
                                        style: TextStyle(
                                          color: internal || !isMe ? onSurface : Colors.white,
                                          fontSize: 14,
                                          height: 1.35,
                                        ),
                                      ),
                                      if (timeStr.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          timeStr,
                                          style: TextStyle(
                                            color: internal || !isMe ? AppTheme.textMuted : Colors.white70,
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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceOf(context),
              border: Border(top: BorderSide(color: AppTheme.hairlineOf(context))),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: _internalNote,
                    onChanged: _sending ? null : (v) => setState(() => _internalNote = v),
                    title: const Text(
                      'Internal note',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    subtitle: const Text(
                      'Not shown to the diner',
                      style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _replyController,
                          minLines: 1,
                          maxLines: 4,
                          enabled: !_sending,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            hintText: _internalNote ? 'Note for ops only…' : 'Write a public reply…',
                          ),
                          onSubmitted: (_) => _send(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _sending ? null : _send,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(88, 44),
                        ),
                        child: _sending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Text(_internalNote ? 'Save' : 'Send'),
                      ),
                    ],
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
