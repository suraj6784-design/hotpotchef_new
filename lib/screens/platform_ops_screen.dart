// lib/screens/platform_ops_screen.dart
//
// Minimal Admin desk on main: dashboard (RPC with fallback), FSSAI queue,
// and chef-only FSSAI KYC. RouteAuthz already keeps non-admins off /platform-ops.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/push_notification_service.dart';
import '../utils/auth_role_sync.dart';
import '../utils/helpers.dart';
import '../utils/kyc_checklist.dart';
import '../utils/platform_ops_access.dart';
import '../widgets/app_empty_state.dart';

/// In-app desk for dashboard, FSSAI review, and partner KYC completeness.
class PlatformOpsScreen extends StatefulWidget {
  const PlatformOpsScreen({super.key});

  @override
  State<PlatformOpsScreen> createState() => _PlatformOpsScreenState();
}

class _PlatformOpsScreenState extends State<PlatformOpsScreen> with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  late final TabController _tabs;
  bool _busy = false;
  int _reloadToken = 0;
  String _opsEmail = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _opsEmail = _supabase.auth.currentUser?.email ?? '';
    AuthRoleSync.syncOwnerAdminRole(_supabase);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _bump() {
    if (mounted) setState(() => _reloadToken++);
  }

  Future<void> _logout() async {
    try {
      await PushNotificationService.clearTokenOnLogout();
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Admin desk FCM clear failed');
    }
    try {
      await _supabase.auth.signOut();
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Admin desk signOut failed');
    }
    if (!mounted) return;
    context.go('/customer-hub');
  }

  Future<void> _setFssaiStatus(Map<String, dynamic> row, String status) async {
    final id = row['id']?.toString();
    if (id == null || id.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      try {
        await _supabase.rpc(
          'ops_set_fssai_status',
          params: {
            'p_chef_id': id,
            'p_status': status,
            'p_review_note': null,
          },
        );
      } catch (_) {
        // RPC may be missing on mainline DBs — write the column directly.
        await _supabase.from('users').update({
          'fssai_verification_status': status,
        }).eq('id', id);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('FSSAI marked $status'), backgroundColor: Colors.green),
      );
      _bump();
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Ops FSSAI status failed');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update FSSAI. Need ops_set_fssai_status RPC or users UPDATE: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppTheme.backgroundDark : AppTheme.background,
      appBar: AppBar(
        title: const Text('Admin desk'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _busy ? null : _bump,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Log out',
            onPressed: _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Dashboard'),
            Tab(text: 'FSSAI'),
            Tab(text: 'KYC'),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_opsEmail.isNotEmpty)
            Material(
              color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFFFF3E0),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.admin_panel_settings_outlined, size: 18, color: AppTheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _opsEmail,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : AppTheme.textMain,
                        ),
                      ),
                    ),
                    Text(
                      isPlatformOwnerEmail(_opsEmail) ? 'Owner' : 'Admin',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.primary),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _OpsDashList(key: ValueKey('dash-$_reloadToken')),
                _FssaiOpsList(
                  key: ValueKey('fssai-$_reloadToken'),
                  busy: _busy,
                  onStatus: _setFssaiStatus,
                ),
                _KycOpsList(key: ValueKey('kyc-$_reloadToken')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OpsCard extends StatelessWidget {
  const _OpsCard({required this.child, this.margin});

  final Widget child;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: margin ?? EdgeInsets.zero,
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.cardDecoration(isDark: isDark),
      child: child,
    );
  }
}

class _OpsDashList extends StatefulWidget {
  const _OpsDashList({super.key});

  @override
  State<_OpsDashList> createState() => _OpsDashListState();
}

class _OpsDashListState extends State<_OpsDashList> {
  String _period = 'day';
  bool _loading = true;
  String? _rpcNote;
  OpsTransactionSnapshot _snap = OpsTransactionSnapshot.fromJson(null);
  int _openTickets = 0;
  int _liveMeals = 0;
  int _userCount = 0;
  int _chefCount = 0;
  int _driverCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final client = Supabase.instance.client;
    var rpcNote = '';
    var snap = OpsTransactionSnapshot.fromJson(null);
    try {
      final raw = await client.rpc('ops_transaction_snapshot', params: {'p_period': _period});
      final map = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      snap = OpsTransactionSnapshot.fromJson(map);
    } catch (_) {
      rpcNote =
          'ops_transaction_snapshot is not installed on this project. GMV stays at 0 until that RPC (or PR #12 extras) lands.';
    }

    var tickets = 0;
    var meals = 0;
    var users = 0;
    var chefs = 0;
    var drivers = 0;
    try {
      final extras = await Future.wait([
        client.from('support_tickets').select('id').limit(200),
        client.from('meals').select('id').limit(200),
        client.from('users').select('id, role').limit(400),
      ]);
      tickets = (extras[0] as List).length;
      meals = (extras[1] as List).length;
      final userRows = List<Map<String, dynamic>>.from(extras[2] as List);
      users = userRows.length;
      for (final row in userRows) {
        final role = (row['role']?.toString() ?? '').toLowerCase();
        if (role == 'chef') chefs++;
        if (role == 'driver') drivers++;
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _snap = snap;
      _rpcNote = rpcNote.isEmpty ? null : rpcNote;
      _openTickets = tickets;
      _liveMeals = meals;
      _userCount = users;
      _chefCount = chefs;
      _driverCount = drivers;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              for (final entry in const [
                ('day', 'Today'),
                ('week', '7 days'),
                ('month', 'Month'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(entry.$2),
                    selected: _period == entry.$1,
                    onSelected: (_) {
                      setState(() => _period = entry.$1);
                      _load();
                    },
                  ),
                ),
              const Spacer(),
              IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_rpcNote != null) ...[
                      _OpsCard(
                        child: Text(_rpcNote!, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final c in <(String, String)>[
                          ('GMV', '₹${_snap.gmv.toStringAsFixed(0)}'),
                          ('Orders', '${_snap.orderCount}'),
                          ('Delivered', '${_snap.deliveredCount}'),
                          ('Cancelled', '${_snap.cancelledCount}'),
                          ('Avg ticket', '₹${_snap.avgTicket.toStringAsFixed(0)}'),
                          ('Delivery fees', '₹${_snap.deliveryFeeSum.toStringAsFixed(0)}'),
                          ('Tickets (sample)', '$_openTickets'),
                          ('Meals (sample)', '$_liveMeals'),
                          ('Accounts (sample)', '$_userCount'),
                          ('Chefs (sample)', '$_chefCount'),
                          ('Drivers (sample)', '$_driverCount'),
                        ])
                          SizedBox(
                            width: (MediaQuery.sizeOf(context).width - 52) / 2,
                            child: _OpsCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c.$1,
                                    style: const TextStyle(
                                      color: AppTheme.textMuted,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(c.$2, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('Grant Admin', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 8),
                    _OpsCard(
                      child: Text(
                        '1. Set public.users.role = Admin for the operator (and JWT user_metadata.role = Admin).\n'
                        '2. The owner allowlist $kPlatformOwnerEmail is always treated as Admin on login.\n'
                        '3. Do not offer Admin at signup — grant it in the database only.',
                        style: const TextStyle(fontSize: 12, height: 1.45, color: AppTheme.textMuted),
                      ),
                    ),
                    if (_snap.recent.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text('Recent paid orders', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      const SizedBox(height: 8),
                      for (final row in _snap.recent)
                        _OpsCard(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  formatOrderId(row['order_id']?.toString(), row['id']?.toString() ?? ''),
                                  style: const TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                              Text('₹${row['total'] ?? 0}', style: const TextStyle(fontWeight: FontWeight.w800)),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _FssaiOpsList extends StatelessWidget {
  const _FssaiOpsList({super.key, required this.busy, required this.onStatus});

  final bool busy;
  final Future<void> Function(Map<String, dynamic> row, String status) onStatus;

  Future<List<Map<String, dynamic>>> _load(SupabaseClient client) async {
    try {
      final rows = await client
          .from('users')
          .select(
            'id, name, full_name, phone, email, role, fssai_number, fssai_proof_url, fssai_verification_status, fssai_review_note',
          )
          .neq('fssai_verification_status', 'unsubmitted')
          .limit(80);
      return List<Map<String, dynamic>>.from(rows as List)
          .where((row) => (row['role']?.toString() ?? '').toLowerCase() == 'chef')
          .toList();
    } catch (_) {
      final rows = await client
          .from('users')
          .select('id, name, full_name, phone, email, role, fssai_number, fssai_proof_url, fssai_verification_status')
          .limit(80);
      return List<Map<String, dynamic>>.from(rows as List).where((row) {
        final role = (row['role']?.toString() ?? '').toLowerCase();
        final status = normalizeFssaiVerificationStatus(row['fssai_verification_status']?.toString());
        return role == 'chef' && status != 'unsubmitted';
      }).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = Supabase.instance.client;
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _load(client),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return AppEmptyState(
            icon: Icons.error_outline,
            title: 'Could not load FSSAI queue',
            subtitle: '${snap.error}',
          );
        }
        final rows = snap.data ?? const [];
        if (rows.isEmpty) {
          return const AppEmptyState(
            icon: Icons.verified_user_outlined,
            title: 'No FSSAI proofs pending',
            subtitle: 'Chefs who upload licence photos appear here for verification. Drivers are not in this queue.',
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
            return _OpsCard(
              margin: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w800))),
                      Text(
                        fssaiVerificationLabel(status),
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                      ),
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

class _KycOpsList extends StatelessWidget {
  const _KycOpsList({super.key});

  Future<List<Map<String, dynamic>>> _loadRows(SupabaseClient client) async {
    List<Map<String, dynamic>> list;
    try {
      final rows = await client
          .from('users')
          .select(
            'id, role, name, full_name, email, fssai_number, fssai_proof_url, '
            'fssai_verification_status, gstin, bank_account_number, bank_ifsc, ifsc_code, '
            'pan_number, aadhaar_masked',
          )
          .limit(200);
      list = List<Map<String, dynamic>>.from(rows as List);
    } catch (_) {
      final rows = await client
          .from('users')
          .select(
            'id, role, name, full_name, email, fssai_number, fssai_proof_url, '
            'fssai_verification_status, gstin, pan_number, aadhaar_masked',
          )
          .limit(200);
      list = List<Map<String, dynamic>>.from(rows as List);
    }

    list = list.where((row) {
      final role = (row['role']?.toString() ?? '').toLowerCase();
      return role == 'chef' || role == 'driver';
    }).toList();

    final chefIds = list
        .where((row) => (row['role']?.toString() ?? '').toLowerCase() == 'chef')
        .map((row) => row['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
    if (chefIds.isNotEmpty) {
      try {
        final profiles = await client.from('chef_profiles').select('user_id, local_kitchen_name').inFilter('user_id', chefIds);
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
          return AppEmptyState(
            icon: Icons.error_outline,
            title: 'Could not load KYC queue',
            subtitle: '${snap.error}',
          );
        }
        final rows = snap.data ?? const [];
        if (rows.isEmpty) {
          return const AppEmptyState(
            icon: Icons.badge_outlined,
            title: 'No chef/driver KYC rows',
            subtitle: 'Partner profiles with KYC fields appear here for completeness review.',
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
            return _OpsCard(
              margin: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w800))),
                      Text(
                        '${checklist.done}/${checklist.total}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: checklist.incomplete ? Colors.orange.shade800 : Colors.green.shade700,
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
                      style: TextStyle(fontSize: 12, color: Colors.red.shade700),
                    ),
                  ] else ...[
                    const SizedBox(height: 8),
                    Text(
                      'KYC checklist complete',
                      style: TextStyle(fontSize: 12, color: Colors.green.shade700, fontWeight: FontWeight.w700),
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
