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
  final Set<String> _selected = <String>{};
  String? _editingId;
  String? _draftRole;
  String? _draftStatus;

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

  String _rowId(Map<String, dynamic> row) => row['id']?.toString() ?? '';

  bool _isLocked(Map<String, dynamic> row) {
    final role = row['role']?.toString() ?? '';
    final email = row['email']?.toString() ?? '';
    return role.toLowerCase() == 'admin' || isPlatformOwnerEmail(email);
  }

  void _startEdit(Map<String, dynamic> row) {
    final id = _rowId(row);
    if (id.isEmpty || _isLocked(row)) return;
    setState(() {
      _editingId = id;
      _draftRole = row['role']?.toString() ?? 'Customer';
      _draftStatus = (row['account_status']?.toString() ?? 'active').toLowerCase();
    });
  }

  void _cancelEdit() {
    setState(() {
      _editingId = null;
      _draftRole = null;
      _draftStatus = null;
    });
  }

  Future<void> _reload() async {
    widget.onChanged();
    if (!mounted) return;
    setState(() => _future = _load());
  }

  Future<bool> _applyRole(String userId, String role) async {
    await Supabase.instance.client.rpc(
      'ops_set_user_role',
      params: {'p_user_id': userId, 'p_role': role},
    ).withTimeout(NetworkTimeouts.standard);
    return true;
  }

  Future<bool> _applyStatus(String userId, String status) async {
    await Supabase.instance.client.rpc(
      'ops_set_account_status',
      params: {'p_user_id': userId, 'p_status': status},
    ).withTimeout(NetworkTimeouts.standard);
    return true;
  }

  Future<void> _saveEdit(Map<String, dynamic> row) async {
    if (widget.busy) return;
    final id = _rowId(row);
    final currentRole = row['role']?.toString() ?? '';
    final currentStatus = (row['account_status']?.toString() ?? 'active').toLowerCase();
    try {
      if (_draftRole != null && _draftRole!.trim().isNotEmpty && _draftRole != currentRole) {
        await _applyRole(id, _draftRole!);
      }
      if (_draftStatus != null && _draftStatus != currentStatus) {
        await _applyStatus(id, _draftStatus!);
      }
      _cancelEdit();
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(opsFriendlyError(e)), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _applyToSelected({String? role, String? status}) async {
    if (widget.busy || _selected.isEmpty) return;
    try {
      for (final id in _selected.toList()) {
        if (role != null) await _applyRole(id, role);
        if (status != null) await _applyStatus(id, status);
      }
      setState(() => _selected.clear());
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(opsFriendlyError(e)), backgroundColor: Colors.redAccent),
      );
    }
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
              final selectable = rows.where((row) => !_isLocked(row) && _rowId(row).isNotEmpty).toList();
              final allSelected = selectable.isNotEmpty && selectable.every((row) => _selected.contains(_rowId(row)));
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                    child: Row(
                      children: [
                        Checkbox(
                          value: allSelected,
                          visualDensity: VisualDensity.compact,
                          onChanged: selectable.isEmpty
                              ? null
                              : (on) {
                                  setState(() {
                                    if (on == true) {
                                      _selected.addAll(selectable.map(_rowId));
                                    } else {
                                      for (final row in selectable) {
                                        _selected.remove(_rowId(row));
                                      }
                                    }
                                  });
                                },
                        ),
                        Text(
                          allSelected ? 'Clear all' : 'Select all',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
                        if (_selected.isNotEmpty)
                          Text(
                            '${_selected.length} selected',
                            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted, fontWeight: FontWeight.w700),
                          ),
                      ],
                    ),
                  ),
                  if (_selected.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final role in const ['Customer', 'Chef', 'Driver'])
                            OutlinedButton(
                              onPressed: widget.busy ? null : () => _applyToSelected(role: role),
                              child: Text('Save as $role', style: const TextStyle(fontSize: 12)),
                            ),
                          OutlinedButton(
                            onPressed: widget.busy ? null : () => _applyToSelected(status: 'suspended'),
                            style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade700),
                            child: const Text('Suspend', style: TextStyle(fontSize: 12)),
                          ),
                          OutlinedButton(
                            onPressed: widget.busy ? null : () => _applyToSelected(status: 'active'),
                            style: OutlinedButton.styleFrom(foregroundColor: AppTheme.success),
                            child: const Text('Reinstate', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        final id = _rowId(row);
                        final name = row['name']?.toString() ?? row['full_name']?.toString() ?? 'User';
                        final status = (row['account_status']?.toString() ?? 'active').toLowerCase();
                        final role = row['role']?.toString() ?? '';
                        final email = row['email']?.toString() ?? '';
                        final locked = _isLocked(row);
                        final editing = !locked && _editingId == id;
                        final shownRole = editing ? (_draftRole ?? role) : role;
                        final shownStatus = editing ? (_draftStatus ?? status) : status;
                        return AppCard(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Checkbox(
                                    value: !locked && id.isNotEmpty && _selected.contains(id),
                                    visualDensity: VisualDensity.compact,
                                    onChanged: locked || id.isEmpty
                                        ? null
                                        : (on) {
                                            setState(() {
                                              if (on == true) {
                                                _selected.add(id);
                                              } else {
                                                _selected.remove(id);
                                              }
                                            });
                                          },
                                  ),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 10),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
                                          Text(
                                            '${locked ? 'Admin' : shownRole} · $email · $shownStatus',
                                            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (locked)
                                    const Padding(
                                      padding: EdgeInsets.only(top: 8),
                                      child: Text(
                                        'Locked',
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primary),
                                      ),
                                    )
                                  else if (editing) ...[
                                    IconButton(
                                      tooltip: 'Cancel',
                                      onPressed: widget.busy ? null : _cancelEdit,
                                      icon: const Icon(Icons.close, size: 20),
                                    ),
                                    IconButton(
                                      tooltip: 'Save',
                                      onPressed: widget.busy ? null : () => _saveEdit(row),
                                      icon: const Icon(Icons.check, size: 20, color: AppTheme.primary),
                                    ),
                                  ] else
                                    IconButton(
                                      tooltip: 'Edit',
                                      onPressed: widget.busy ? null : () => _startEdit(row),
                                      icon: const Icon(Icons.edit_outlined, size: 20, color: AppTheme.primary),
                                    ),
                                ],
                              ),
                              if (editing) ...[
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final nextRole in const ['Customer', 'Chef', 'Driver'])
                                      ChoiceChip(
                                        label: Text(nextRole, style: const TextStyle(fontSize: 12)),
                                        selected: shownRole.toLowerCase() == nextRole.toLowerCase(),
                                        onSelected: widget.busy
                                            ? null
                                            : (_) => setState(() => _draftRole = nextRole),
                                      ),
                                    ChoiceChip(
                                      label: const Text('Active', style: TextStyle(fontSize: 12)),
                                      selected: shownStatus != 'suspended',
                                      onSelected: widget.busy ? null : (_) => setState(() => _draftStatus = 'active'),
                                    ),
                                    ChoiceChip(
                                      label: const Text('Suspended', style: TextStyle(fontSize: 12)),
                                      selected: shownStatus == 'suspended',
                                      onSelected: widget.busy ? null : (_) => setState(() => _draftStatus = 'suspended'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Tap Save to apply role or suspend changes.',
                                  style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
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
  Future<List<Map<String, dynamic>>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    try {
      final raw = await Supabase.instance.client.rpc('ops_list_helpers').withTimeout(NetworkTimeouts.standard);
      if (raw is List) {
        return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (_) {}

    final client = Supabase.instance.client;
    final seats = await client
        .from('platform_ops')
        .select('user_id, seat_role, permissions, note, revoked_at, created_at')
        .eq('seat_role', 'helper')
        .order('created_at', ascending: false)
        .withTimeout(NetworkTimeouts.standard);
    Map<String, Map<String, dynamic>> byId = {};
    try {
      final accounts = await client.rpc('ops_list_accounts').withTimeout(NetworkTimeouts.standard);
      if (accounts is List) {
        for (final row in accounts.whereType<Map>()) {
          final map = Map<String, dynamic>.from(row);
          final id = map['id']?.toString() ?? '';
          if (id.isNotEmpty) byId[id] = map;
        }
      }
    } catch (_) {}
    return List<Map<String, dynamic>>.from(seats as List).map((seat) {
      final id = seat['user_id']?.toString() ?? '';
      final profile = byId[id] ?? const <String, dynamic>{};
      return {
        ...seat,
        'email': profile['email'],
        'name': profile['name'] ?? profile['full_name'] ?? seat['note'],
        'full_name': profile['full_name'],
        'account_status': profile['account_status'] ?? 'active',
      };
    }).toList();
  }

  Future<Map<String, dynamic>> _manage({
    required String action,
    Map<String, dynamic> extra = const {},
  }) async {
    final response = await Supabase.instance.client.functions.invoke(
      'manage-helper-account',
      body: {'action': action, ...extra},
    ).withTimeout(NetworkTimeouts.standard);
    final data = response.data is Map ? Map<String, dynamic>.from(response.data as Map) : <String, dynamic>{};
    if (response.status != 200 || data['ok'] != true) {
      throw Exception(data['error']?.toString() ?? 'Could not update helper');
    }
    return data;
  }

  Future<void> _createHelper() async {
    final selected = <String>{kOpsPermissionFssai};
    final username = TextEditingController();
    final password = TextEditingController(text: generateOpsHelperPassword());
    final label = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              shape: AppTheme.dialogShape,
              title: const Text('Create helper account'),
              content: SizedBox(
                width: 360,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'This creates a login. Share the username and password with the helper. They sign in on the same app and open only the tabs you grant.',
                        style: TextStyle(fontSize: 13, height: 1.35, color: AppTheme.textMuted),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: username,
                        textCapitalization: TextCapitalization.none,
                        decoration: const InputDecoration(
                          labelText: 'Username or email',
                          hintText: 'fssai.reviewer',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: password,
                        decoration: const InputDecoration(labelText: 'Password'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: label,
                        decoration: const InputDecoration(labelText: 'Display name (optional)'),
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
    final login = username.text.trim();
    final pass = password.text.trim();
    final name = label.text.trim();
    username.dispose();
    password.dispose();
    label.dispose();
    if (ok != true || !mounted) return;
    try {
      final data = await _manage(
        action: 'create',
        extra: {
          'username': login,
          'password': pass,
          'label': name,
          'permissions': selected.toList(),
        },
      );
      if (!mounted) return;
      final shownUser = data['username']?.toString() ?? login;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: AppTheme.dialogShape,
          title: const Text('Helper login ready'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Send this once. They sign in with Email or helper username, then land on Platform ops.',
                style: TextStyle(fontSize: 13, height: 1.35),
              ),
              const SizedBox(height: 12),
              SelectableText('Username: $shownUser', style: const TextStyle(fontWeight: FontWeight.w800)),
              SelectableText('Password: $pass', style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Copy',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: 'Username: $shownUser\nPassword: $pass'));
                Navigator.pop(ctx);
              },
              icon: const Icon(Icons.copy),
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
        SnackBar(content: Text(opsFriendlyError(e)), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _runAction(String action, Map<String, dynamic> seat) async {
    final id = seat['user_id']?.toString() ?? '';
    if (id.isEmpty) return;
    if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: AppTheme.dialogShape,
          title: const Text('Delete helper?'),
          content: const Text('This removes the login. They will not be able to sign in again.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    try {
      await _manage(action: action, extra: {'user_id': id});
      if (!mounted) return;
      setState(() => _future = _load());
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(opsFriendlyError(e)), backgroundColor: Colors.redAccent),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return EmptyState(icon: Icons.error_outline, title: 'Could not load helpers', message: opsFriendlyError(snap.error ?? 'unknown'));
        }
        final seats = snap.data ?? const [];
        final helpers = seats.where((s) => s['revoked_at'] == null).toList();
        final revoked = seats.where((s) => s['revoked_at'] != null).toList();
        Widget helperCard(Map<String, dynamic> seat, {required bool active}) {
          final perms = normalizeOpsPermissions(seat['permissions']);
          final email = seat['email']?.toString() ?? '';
          final login = opsHelperUsernameFromEmail(email);
          final name = (seat['name'] ?? seat['full_name'] ?? seat['note'] ?? '').toString();
          final status = (seat['account_status']?.toString() ?? 'active').toLowerCase();
          return AppCard(
            margin: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name.isEmpty ? login : name, style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(
                  [
                    login,
                    if (perms.isNotEmpty) perms.map(opsPermissionLabel).join(', '),
                    if (!active) 'revoked',
                    if (status == 'suspended') 'suspended',
                  ].join(' · '),
                  style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: active
                      ? [
                          TextButton(
                            onPressed: widget.busy ? null : () => _runAction('revoke', seat),
                            child: const Text('Revoke'),
                          ),
                          TextButton(
                            onPressed: widget.busy
                                ? null
                                : () => _runAction(status == 'suspended' ? 'unsuspend' : 'suspend', seat),
                            child: Text(status == 'suspended' ? 'Unsuspend' : 'Suspend'),
                          ),
                          TextButton(
                            onPressed: widget.busy ? null : () => _runAction('delete', seat),
                            child: const Text('Delete', style: TextStyle(color: AppTheme.error)),
                          ),
                        ]
                      : [
                          TextButton(
                            onPressed: widget.busy ? null : () => _runAction('restore', seat),
                            child: const Text('Restore'),
                          ),
                          TextButton(
                            onPressed: widget.busy ? null : () => _runAction('delete', seat),
                            child: const Text('Delete', style: TextStyle(color: AppTheme.error)),
                          ),
                        ],
                ),
              ],
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            GradientButton(
              label: 'Create helper account',
              icon: Icons.person_add_alt_1_outlined,
              onPressed: widget.busy ? null : _createHelper,
            ),
            const SizedBox(height: 16),
            Text('Active helpers', style: AppTheme.sectionTitleOf(context)),
            const SizedBox(height: 8),
            if (helpers.isEmpty)
              const Text('No active helpers yet.', style: TextStyle(color: AppTheme.textMuted))
            else
              ...helpers.map((seat) => helperCard(seat, active: true)),
            if (revoked.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Revoked', style: AppTheme.sectionTitleOf(context)),
              const SizedBox(height: 8),
              ...revoked.map((seat) => helperCard(seat, active: false)),
            ],
          ],
        );
      },
    );
  }
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
