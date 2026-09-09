// Extra Platform Ops tabs: Dashboard, Accounts, Helpers.
part of 'platform_ops_screen.dart';

class _AdminProfileList extends StatefulWidget {
  const _AdminProfileList({super.key, required this.email, required this.onOpenTab});

  final String email;
  final void Function(String tabKey) onOpenTab;

  @override
  State<_AdminProfileList> createState() => _AdminProfileListState();
}

class _AdminProfileListState extends State<_AdminProfileList> {
  bool _syncing = false;
  String _dbRole = '…';
  String _sessionRole = '…';

  @override
  void initState() {
    super.initState();
    _refreshRoles();
  }

  Future<void> _refreshRoles() async {
    final user = Supabase.instance.client.auth.currentUser;
    var table = 'unknown';
    try {
      final row = await Supabase.instance.client
          .from('users')
          .select('role')
          .eq('id', user?.id ?? '')
          .maybeSingle()
          .withTimeout(NetworkTimeouts.short);
      table = row?['role']?.toString() ?? 'missing';
    } catch (_) {
      table = 'unavailable';
    }
    if (!mounted) return;
    setState(() {
      _dbRole = table;
      _sessionRole = user?.userMetadata?['role']?.toString() ?? 'none';
    });
  }

  Future<void> _syncRole() async {
    setState(() => _syncing = true);
    await AuthSession.syncOwnerAdminRole();
    await _refreshRoles();
    if (!mounted) return;
    setState(() => _syncing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Admin role re-synced. Sign out and back in if the old Chef label remains.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final actions = <(IconData, String, String, VoidCallback)>[
      (Icons.storefront_outlined, 'Catalog', 'Pause or restore live plates', () => widget.onOpenTab(kOpsPermissionCatalog)),
      (Icons.people_outline, 'Accounts', 'Roles, suspend, reinstate', () => widget.onOpenTab(kOpsPermissionAccounts)),
      (Icons.confirmation_number_outlined, 'Tickets', 'Customer and chef support', () => widget.onOpenTab(kOpsPermissionTickets)),
      (Icons.badge_outlined, 'KYC', 'Chef and driver completeness', () => widget.onOpenTab(kOpsPermissionKyc)),
      (Icons.insights_outlined, 'Dashboard', 'GMV and paid orders', () => widget.onOpenTab(kOpsPermissionDashboard)),
      (Icons.restaurant_outlined, 'Diner feed', 'See the customer home', () => context.go('/customer-hub')),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'ADMIN',
                  style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 0.6),
                ),
              ),
              const SizedBox(height: 10),
              Text(widget.email.isEmpty ? 'Platform owner' : widget.email, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(
                'Database role: $_dbRole · Session role: $_sessionRole',
                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _syncing ? null : _syncRole,
                icon: _syncing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.verified_user_outlined, size: 18),
                label: const Text('Re-sync Admin role'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('Controls', style: AppTheme.sectionTitleOf(context)),
        const SizedBox(height: 8),
        for (final action in actions)
          AppCard(
            margin: const EdgeInsets.only(bottom: 8),
            onTap: action.$4,
            child: Row(
              children: [
                Icon(action.$1, color: AppTheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(action.$2, style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text(action.$3, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        AppCard(
          margin: const EdgeInsets.only(bottom: 8),
          onTap: () => launchUrl(Uri.parse('https://hotpotchef.com'), mode: LaunchMode.externalApplication),
          child: const Row(
            children: [
              Icon(Icons.language, color: AppTheme.primary),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Website', style: TextStyle(fontWeight: FontWeight.w800)),
                    Text('hotpotchef.com catalog and policies', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right),
            ],
          ),
        ),
      ],
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
  String? _error;
  OpsTransactionSnapshot? _snap;
  int _openTickets = 0;
  int _liveMeals = 0;
  int _userCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      final raw = await client.rpc(
        'ops_transaction_snapshot',
        params: {'p_period': _period},
      ).withTimeout(NetworkTimeouts.standard);
      final map = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      var tickets = 0;
      var meals = 0;
      var users = 0;
      try {
        final countsRaw = await client.rpc('ops_desk_counts').withTimeout(NetworkTimeouts.standard);
        final counts = countsRaw is Map ? Map<String, dynamic>.from(countsRaw) : <String, dynamic>{};
        tickets = int.tryParse(counts['open_tickets']?.toString() ?? '') ?? 0;
        meals = int.tryParse(counts['live_meals']?.toString() ?? '') ?? 0;
        users = int.tryParse(counts['user_count']?.toString() ?? '') ?? 0;
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _snap = OpsTransactionSnapshot.fromJson(map);
        _openTickets = tickets;
        _liveMeals = meals;
        _userCount = users;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = opsFriendlyError(e);
        _loading = false;
      });
    }
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
              : _error != null
                  ? EmptyState(icon: Icons.error_outline, title: 'Could not load dashboard', message: _error!)
                  : _buildBody(context, _snap!),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, OpsTransactionSnapshot snap) {
    final cards = <(String, String)>[
      ('GMV', '₹${snap.gmv.toStringAsFixed(0)}'),
      ('Orders', '${snap.orderCount}'),
      ('Delivered', '${snap.deliveredCount}'),
      ('Cancelled', '${snap.cancelledCount}'),
      ('Avg ticket', '₹${snap.avgTicket.toStringAsFixed(0)}'),
      ('Delivery fees', '₹${snap.deliveryFeeSum.toStringAsFixed(0)}'),
      ('Margin earned', '₹${snap.platformMarginSum.toStringAsFixed(0)}'),
      ('Open tickets', '$_openTickets'),
      ('Live plates', '$_liveMeals'),
      ('Accounts', '$_userCount'),
    ];
    final maxGmv = snap.series.fold<double>(0, (m, b) => b.gmv > m ? b.gmv : m);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final c in cards)
              SizedBox(
                width: (MediaQuery.sizeOf(context).width - 52) / 2,
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.$1, style: const TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Text(c.$2, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
          ],
        ),
        if (snap.series.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Trend', style: AppTheme.sectionTitleOf(context)),
          const SizedBox(height: 8),
          AppCard(
            child: Column(
              children: [
                for (final b in snap.series) ...[
                  Row(
                    children: [
                      SizedBox(
                        width: 88,
                        child: Text(b.bucketDate, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                      ),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: maxGmv <= 0 ? 0 : (b.gmv / maxGmv).clamp(0.0, 1.0),
                            minHeight: 10,
                            backgroundColor: AppTheme.surfaceMutedOf(context),
                            color: AppTheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('₹${b.gmv.toStringAsFixed(0)} · ${b.orderCount}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text('Recent paid orders', style: AppTheme.sectionTitleOf(context)),
        const SizedBox(height: 8),
        if (snap.recent.isEmpty)
          const Text('No paid orders in this window.', style: TextStyle(color: AppTheme.textMuted))
        else
          ...snap.recent.map((row) {
            final label = formatOrderId(row['order_id']?.toString(), row['id']?.toString() ?? '');
            final total = parseMoney(row['total']);
            return AppCard(
              margin: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text(
                          '${row['status'] ?? ''} · ${row['created_at'] ?? ''}',
                          style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ),
                  Text('₹${total.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w800)),
                ],
              ),
            );
          }),
      ],
    );
  }
}

class _OpsAccountsList extends StatefulWidget {
  const _OpsAccountsList({super.key, required this.busy, required this.onChanged});

  final bool busy;
  final VoidCallback onChanged;

  @override
  State<_OpsAccountsList> createState() => _OpsAccountsListState();
}

class _OpsAccountsListState extends State<_OpsAccountsList> {
  final _search = TextEditingController();
  String _roleFilter = 'All';
  Future<List<Map<String, dynamic>>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final raw = await Supabase.instance.client.rpc('ops_list_accounts').withTimeout(NetworkTimeouts.standard);
    if (raw is List) {
      return [for (final row in raw) Map<String, dynamic>.from(row as Map)];
    }
    return const [];
  }

  Future<void> _setRole(Map<String, dynamic> row, String role) async {
    await Supabase.instance.client.rpc(
      'ops_set_user_role',
      params: {'p_user_id': row['id'], 'p_role': role},
    ).withTimeout(NetworkTimeouts.standard);
    widget.onChanged();
    setState(() => _future = _load());
  }

  Future<void> _setStatus(Map<String, dynamic> row, String status) async {
    await Supabase.instance.client.rpc(
      'ops_set_account_status',
      params: {'p_user_id': row['id'], 'p_status': status},
    ).withTimeout(NetworkTimeouts.standard);
    widget.onChanged();
    setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _search,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search name, email, phone',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              for (final role in const ['All', 'Admin', 'Chef', 'Customer', 'Driver', 'Suspended'])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(role),
                    selected: _roleFilter == role,
                    onSelected: (_) => setState(() => _roleFilter = role),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return EmptyState(icon: Icons.error_outline, title: 'Could not load accounts', message: opsFriendlyError(snap.error ?? 'unknown'));
              }
              final q = _search.text.trim().toLowerCase();
              var rows = snap.data ?? const <Map<String, dynamic>>[];
              rows = rows.where((row) {
                final role = row['role']?.toString() ?? '';
                final status = (row['account_status']?.toString() ?? 'active').toLowerCase();
                if (_roleFilter == 'Suspended') return status == 'suspended';
                if (_roleFilter != 'All' && role.toLowerCase() != _roleFilter.toLowerCase()) return false;
                if (q.isEmpty) return true;
                final hay = '${row['name']} ${row['full_name']} ${row['email']} ${row['phone']}'.toLowerCase();
                return hay.contains(q);
              }).toList();
              if (rows.isEmpty) {
                return const EmptyState(icon: Icons.people_outline, title: 'No matching accounts', message: 'Try another filter or search.');
              }
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: rows.length,
                itemBuilder: (context, index) {
                  final row = rows[index];
                  final name = row['name']?.toString() ?? row['full_name']?.toString() ?? 'User';
                  final status = (row['account_status']?.toString() ?? 'active').toLowerCase();
                  final role = row['role']?.toString() ?? '';
                  final email = row['email']?.toString() ?? '';
                  final isAdmin = role.toLowerCase() == 'admin' || isPlatformOwnerEmail(email);
                  return AppCard(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text(
                          '${isAdmin ? 'Admin' : role} · $email · $status',
                          style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                        ),
                        const SizedBox(height: 8),
                        if (isAdmin)
                          const Text(
                            'Owner account — role locked',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primary),
                          )
                        else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final nextRole in const ['Customer', 'Chef', 'Driver'])
                              OutlinedButton(
                                onPressed: widget.busy ? null : () => _setRole(row, nextRole),
                                child: Text(nextRole, style: const TextStyle(fontSize: 12)),
                              ),
                            OutlinedButton(
                              onPressed: widget.busy
                                  ? null
                                  : () => _setStatus(row, status == 'suspended' ? 'active' : 'suspended'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: status == 'suspended' ? AppTheme.success : Colors.red.shade700,
                              ),
                              child: Text(status == 'suspended' ? 'Reinstate' : 'Suspend', style: const TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _OpsHelpersList extends StatefulWidget {
  const _OpsHelpersList({super.key, required this.busy, required this.onChanged});

  final bool busy;
  final VoidCallback onChanged;

  @override
  State<_OpsHelpersList> createState() => _OpsHelpersListState();
}

class _OpsHelpersListState extends State<_OpsHelpersList> {
  Future<_HelpersBundle>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_HelpersBundle> _load() async {
    final client = Supabase.instance.client;
    final seats = await client
        .from('platform_ops')
        .select('user_id, seat_role, permissions, note, revoked_at, created_at')
        .order('created_at', ascending: false)
        .withTimeout(NetworkTimeouts.standard);
    final invites = await client
        .from('platform_ops_invites')
        .select('id, code, permissions, label, expires_at, max_uses, use_count, revoked_at, created_at')
        .order('created_at', ascending: false)
        .limit(40)
        .withTimeout(NetworkTimeouts.standard);
    return _HelpersBundle(
      seats: List<Map<String, dynamic>>.from(seats as List),
      invites: List<Map<String, dynamic>>.from(invites as List),
    );
  }

  Future<void> _createInvite() async {
    final selected = <String>{kOpsPermissionFssai};
    final label = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              shape: AppTheme.dialogShape,
              title: const Text('Create helper invite'),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: label,
                      decoration: const InputDecoration(labelText: 'Label (optional)'),
                    ),
                    const SizedBox(height: 8),
                    ...kOpsInviteablePermissions.map(
                      (key) => CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(opsPermissionLabel(key)),
                        value: selected.contains(key),
                        onChanged: (v) => setLocal(() {
                          if (v == true) {
                            selected.add(key);
                          } else {
                            selected.remove(key);
                          }
                        }),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
              ],
            );
          },
        );
      },
    );
    if (ok != true || !mounted) return;
    try {
      final raw = await Supabase.instance.client.rpc(
        'ops_create_helper_invite',
        params: {
          'p_permissions': selected.toList(),
          'p_label': label.text.trim().isEmpty ? null : label.text.trim(),
          'p_expires_hours': 72,
          'p_max_uses': 1,
        },
      ).withTimeout(NetworkTimeouts.standard);
      final map = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      final code = map['code']?.toString() ?? '';
      final path = map['deep_link_path']?.toString() ?? '/ops-invite?code=$code';
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: AppTheme.dialogShape,
          title: const Text('Invite ready'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText('Code: $code', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              const SizedBox(height: 8),
              SelectableText(path),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: '$code\n$path'));
                Navigator.pop(ctx);
              },
              child: const Text('Copy'),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
          ],
        ),
      );
      setState(() => _future = _load());
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      label.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_HelpersBundle>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return EmptyState(icon: Icons.error_outline, title: 'Could not load helpers', message: opsFriendlyError(snap.error ?? 'unknown'));
        }
        final data = snap.data!;
        final helpers = data.seats.where((s) => (s['seat_role']?.toString() ?? '') == 'helper' && s['revoked_at'] == null).toList();
        final openInvites = data.invites.where((i) => i['revoked_at'] == null).toList();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            GradientButton(
              label: 'Create helper invite',
              icon: Icons.person_add_alt_1_outlined,
              onPressed: widget.busy ? null : _createInvite,
            ),
            const SizedBox(height: 16),
            Text('Open invites', style: AppTheme.sectionTitleOf(context)),
            const SizedBox(height: 8),
            if (openInvites.isEmpty)
              const Text('No open invites.', style: TextStyle(color: AppTheme.textMuted))
            else
              ...openInvites.map((inv) {
                final perms = normalizeOpsPermissions(inv['permissions']);
                return AppCard(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(inv['code']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w800)),
                            Text(
                              '${perms.map(opsPermissionLabel).join(', ')} · uses ${inv['use_count']}/${inv['max_uses']}',
                              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: widget.busy
                            ? null
                            : () async {
                                await Supabase.instance.client.rpc(
                                  'ops_revoke_invite',
                                  params: {'p_invite_id': inv['id']},
                                );
                                setState(() => _future = _load());
                              },
                        child: const Text('Revoke'),
                      ),
                    ],
                  ),
                );
              }),
            const SizedBox(height: 16),
            Text('Active helpers', style: AppTheme.sectionTitleOf(context)),
            const SizedBox(height: 8),
            if (helpers.isEmpty)
              const Text('No active helpers yet.', style: TextStyle(color: AppTheme.textMuted))
            else
              ...helpers.map((seat) {
                final perms = normalizeOpsPermissions(seat['permissions']);
                return AppCard(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(seat['user_id']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                            Text(perms.map(opsPermissionLabel).join(', '), style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: widget.busy
                            ? null
                            : () async {
                                await Supabase.instance.client.rpc(
                                  'ops_revoke_helper',
                                  params: {'p_user_id': seat['user_id']},
                                );
                                setState(() => _future = _load());
                              },
                        child: const Text('Revoke'),
                      ),
                    ],
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}

class _HelpersBundle {
  const _HelpersBundle({required this.seats, required this.invites});
  final List<Map<String, dynamic>> seats;
  final List<Map<String, dynamic>> invites;
}

class _CatalogOpsList extends StatelessWidget {
  const _CatalogOpsList({super.key, required this.busy, required this.onStatus});

  final bool busy;
  final Future<void> Function(Map<String, dynamic> row, String status) onStatus;

  @override
  Widget build(BuildContext context) {
    final client = Supabase.instance.client;
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: () async {
        final rows = await client
            .from('meals')
            .select('id, title, chef_name, chef_id, price, status, quantity, offer_type')
            .order('created_at', ascending: false)
            .limit(120)
            .withTimeout(NetworkTimeouts.standard);
        return List<Map<String, dynamic>>.from(rows as List);
      }(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return EmptyState(icon: Icons.error_outline, title: 'Could not load catalog', message: opsFriendlyError(snap.error ?? 'unknown'));
        }
        final rows = snap.data ?? const [];
        if (rows.isEmpty) {
          return const EmptyState(
            icon: Icons.restaurant_outlined,
            title: 'No meals yet',
            message: 'Published plates appear here so you can pause or restore them.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            final status = row['status']?.toString() ?? '';
            final available = status.toLowerCase() == 'available';
            return AppCard(
              margin: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(mealDisplayTitle(row), style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text(
                          '${row['chef_name'] ?? 'Kitchen'} · $status · ₹${parseMoney(row['price']).toStringAsFixed(0)}',
                          style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: busy ? null : () => onStatus(row, available ? 'Paused' : 'Available'),
                    child: Text(available ? 'Pause' : 'Make live'),
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

class _OpsAuditList extends StatelessWidget {
  const _OpsAuditList({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<dynamic>(
      future: Supabase.instance.client
          .rpc('ops_list_audit', params: {'p_limit': 80})
          .withTimeout(NetworkTimeouts.standard),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return EmptyState(
            icon: Icons.policy_outlined,
            title: 'Could not load audit log',
            message: opsFriendlyError(snap.error ?? 'unknown'),
          );
        }
        final raw = snap.data;
        final rows = raw is List
            ? [for (final row in raw) Map<String, dynamic>.from(row as Map)]
            : const <Map<String, dynamic>>[];
        if (rows.isEmpty) {
          return const EmptyState(
            icon: Icons.policy_outlined,
            title: 'No audit rows yet',
            message: 'Role, FSSAI, ticket, and catalog changes by ops appear here.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            return AppCard(
              margin: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row['action']?.toString() ?? 'update',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      row['target_table']?.toString() ?? '',
                      row['target_id']?.toString() ?? '',
                      row['created_at']?.toString() ?? '',
                    ].where((s) => s.trim().isNotEmpty).join(' · '),
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
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
