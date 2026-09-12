part of 'platform_ops_screen.dart';

Future<OpsAdminHq> _fetchOpsAdminHq(String period) async {
  final client = Supabase.instance.client;
  final raw = await client.rpc(
    'ops_admin_hq',
    params: {'p_period': period},
  ).withTimeout(NetworkTimeouts.standard);
  final map = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  try {
    final sig = await client.rpc(
      'ops_readiness_signals',
      params: {'p_period': period},
    ).withTimeout(NetworkTimeouts.standard);
    if (sig is Map) map.addAll(Map<String, dynamic>.from(sig));
  } catch (_) {}
  return OpsAdminHq.fromJson(map);
}

String _opsShortDate(String raw) {
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return raw.length >= 10 ? raw.substring(0, 10) : raw;
  return DateFormat('d MMM').format(parsed.toLocal());
}

String _opsPct(double value) => '${(value * 100).clamp(0, 100).toStringAsFixed(0)}%';

class _OpsDashList extends StatefulWidget {
  const _OpsDashList({super.key, this.onOpenTab});

  final void Function(String tabKey)? onOpenTab;

  @override
  State<_OpsDashList> createState() => _OpsDashListState();
}

class _OpsDashListState extends State<_OpsDashList> {
  String _period = 'day';
  bool _loading = true;
  String? _error;
  OpsAdminHq? _hq;

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
      final hq = await _fetchOpsAdminHq(_period);
      if (!mounted) return;
      setState(() {
        _hq = hq;
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

  void _open(String key) => widget.onOpenTab?.call(key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _OpsPeriodBar(period: _period, loading: _loading, onRefresh: _load, onPeriod: (p) {
          setState(() => _period = p);
          _load();
        }),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? EmptyState(icon: Icons.error_outline, title: 'Could not load dashboard', message: _error!)
                  : _buildBody(context, _hq!),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, OpsAdminHq hq) {
    final snap = hq.snapshot;
    final kpis = <(String, String, Color)>[
      ('GMV', '₹${snap.gmv.toStringAsFixed(0)}', AppTheme.primary),
      ('Orders', '${snap.orderCount}', AppTheme.info),
      ('Margin', '₹${snap.platformMarginSum.toStringAsFixed(0)}', AppTheme.success),
      ('Avg ticket', '₹${snap.avgTicket.toStringAsFixed(0)}', AppTheme.accent),
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Command center', style: AppTheme.homeSectionLabelOf(context)),
        const SizedBox(height: 4),
        Text(
          'Paid volume, fulfillment, and queues that need a person.',
          style: AppTheme.caption,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final c in kpis)
              SizedBox(
                width: (MediaQuery.sizeOf(context).width - 52) / 2,
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.$1, style: AppTheme.caption),
                      const SizedBox(height: 6),
                      Text(
                        c.$2,
                        style: AppTheme.listTitleOf(context).copyWith(fontSize: 20, color: c.$3),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _OpsGmvChart(series: snap.series),
        const SizedBox(height: 16),
        Text('Health', style: AppTheme.homeSectionLabelOf(context)),
        const SizedBox(height: 8),
        AppCard(
          child: Column(
            children: [
              _OpsMeterRow(label: 'Delivered', value: _opsPct(hq.fulfillmentRate), ratio: hq.fulfillmentRate),
              const SizedBox(height: 10),
              _OpsMeterRow(label: 'Cancelled', value: _opsPct(hq.cancelRate), ratio: hq.cancelRate, color: AppTheme.error),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('Work queues', style: AppTheme.homeSectionLabelOf(context)),
        const SizedBox(height: 8),
        _OpsQueueTile(
          icon: Icons.confirmation_number_outlined,
          title: 'Open tickets',
          value: '${hq.openTickets}',
          onTap: () => _open(kOpsPermissionTickets),
        ),
        _OpsQueueTile(
          icon: Icons.timer_off_outlined,
          title: 'SLA breached',
          value: '${hq.slaBreached}',
          onTap: () => _open(kOpsPermissionTickets),
        ),
        _OpsQueueTile(
          icon: Icons.gavel_outlined,
          title: 'Open disputes',
          value: '${hq.openDisputes}',
          onTap: () => _open(kOpsPermissionRefunds),
        ),
        _OpsQueueTile(
          icon: Icons.report_gmailerrorred_outlined,
          title: 'Failed refunds',
          value: '${hq.failedRefunds}',
          onTap: () => _open(kOpsPermissionRefunds),
        ),
        _OpsQueueTile(
          icon: Icons.badge_outlined,
          title: 'Chef / driver KYC pending',
          value: '${hq.pendingKyc}',
          onTap: () => _open(kOpsPermissionKyc),
        ),
        _OpsQueueTile(
          icon: Icons.group_outlined,
          title: 'People directory',
          value: '${hq.userCount} accounts · ${hq.newUsers} new',
          onTap: () => _open(kOpsPermissionCrm),
        ),
        const SizedBox(height: 8),
        Text('Marketplace', style: AppTheme.homeSectionLabelOf(context)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _OpsMiniStat(label: 'Chefs', value: '${hq.chefCount}'),
            _OpsMiniStat(label: 'Diners', value: '${hq.dinerCount}'),
            _OpsMiniStat(label: 'Drivers', value: '${hq.driverCount}'),
            _OpsMiniStat(label: 'Live plates', value: '${hq.liveMeals}'),
          ],
        ),
        const SizedBox(height: 16),
        Text('Recent paid orders', style: AppTheme.homeSectionLabelOf(context)),
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
                          '${row['status'] ?? ''} · ${_opsShortDate(row['created_at']?.toString() ?? '')}',
                          style: AppTheme.micro,
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

class _OpsAnalyticsList extends StatefulWidget {
  const _OpsAnalyticsList({super.key});

  @override
  State<_OpsAnalyticsList> createState() => _OpsAnalyticsListState();
}

class _OpsAnalyticsListState extends State<_OpsAnalyticsList> {
  String _period = 'week';
  bool _loading = true;
  String? _error;
  OpsAdminHq? _hq;

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
      final hq = await _fetchOpsAdminHq(_period);
      if (!mounted) return;
      setState(() {
        _hq = hq;
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
        _OpsPeriodBar(period: _period, loading: _loading, onRefresh: _load, onPeriod: (p) {
          setState(() => _period = p);
          _load();
        }),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? EmptyState(icon: Icons.error_outline, title: 'Could not load analytics', message: _error!)
                  : _buildBody(context, _hq!),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, OpsAdminHq hq) {
    final snap = hq.snapshot;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Platform analytics', style: AppTheme.homeSectionLabelOf(context)),
        const SizedBox(height: 4),
        Text('GMV, conversion, kitchens, and account mix.', style: AppTheme.caption),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _OpsMiniStat(label: 'GMV', value: '₹${snap.gmv.toStringAsFixed(0)}'),
            _OpsMiniStat(label: 'Orders', value: '${snap.orderCount}'),
            _OpsMiniStat(label: 'Delivered', value: '${snap.deliveredCount}'),
            _OpsMiniStat(label: 'Cancelled', value: '${snap.cancelledCount}'),
            _OpsMiniStat(label: 'Margin', value: '₹${snap.platformMarginSum.toStringAsFixed(0)}'),
            _OpsMiniStat(label: 'Delivery fees', value: '₹${snap.deliveryFeeSum.toStringAsFixed(0)}'),
            _OpsMiniStat(label: 'New accounts', value: '${hq.newUsers}'),
            _OpsMiniStat(label: 'Fill rate', value: _opsPct(hq.fulfillmentRate)),
            _OpsMiniStat(label: '7d GMV forecast', value: '₹${hq.forecastGmv7d.toStringAsFixed(0)}'),
            _OpsMiniStat(label: 'Repeat 30d', value: '${hq.repeat30d}'),
            _OpsMiniStat(label: 'Churn 21d', value: '${hq.churn21d}'),
            _OpsMiniStat(label: 'Fraud flags', value: '${hq.fraudFlags}'),
            _OpsMiniStat(label: 'Avg CSAT', value: hq.avgCsat <= 0 ? '—' : hq.avgCsat.toStringAsFixed(1)),
          ],
        ),
        const SizedBox(height: 16),
        _OpsGmvChart(series: snap.series, title: 'GMV by day'),
        const SizedBox(height: 16),
        Text('Account mix', style: AppTheme.homeSectionLabelOf(context)),
        const SizedBox(height: 8),
        AppCard(
          child: hq.usersByRole.isEmpty
              ? const Text('No accounts yet.', style: TextStyle(color: AppTheme.textMuted))
              : Column(
                  children: [
                    for (final row in hq.usersByRole) ...[
                      _OpsMeterRow(
                        label: row.label,
                        value: '${row.count}',
                        ratio: hq.userCount <= 0 ? 0 : row.count / hq.userCount,
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 16),
        Text('Acquisition mix', style: AppTheme.homeSectionLabelOf(context)),
        const SizedBox(height: 8),
        AppCard(
          child: Column(
            children: [
              _OpsMeterRow(
                label: 'Referred',
                value: '${hq.referredAccounts}',
                ratio: (hq.referredAccounts + hq.organicAccounts) <= 0
                    ? 0
                    : hq.referredAccounts / (hq.referredAccounts + hq.organicAccounts),
              ),
              const SizedBox(height: 8),
              _OpsMeterRow(
                label: 'Organic diners',
                value: '${hq.organicAccounts}',
                ratio: (hq.referredAccounts + hq.organicAccounts) <= 0
                    ? 0
                    : hq.organicAccounts / (hq.referredAccounts + hq.organicAccounts),
              ),
              const SizedBox(height: 8),
              Text('Refunds last 7 days: ${hq.refundVelocity}', style: AppTheme.caption),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('Tickets', style: AppTheme.homeSectionLabelOf(context)),
        const SizedBox(height: 8),
        AppCard(
          child: hq.ticketsByStatus.isEmpty
              ? const Text('No tickets in the log.', style: TextStyle(color: AppTheme.textMuted))
              : Column(
                  children: [
                    for (final row in hq.ticketsByStatus)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(child: Text(row.label, style: const TextStyle(fontWeight: FontWeight.w700))),
                            Text('${row.count}'),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        Text('Top kitchens', style: AppTheme.homeSectionLabelOf(context)),
        const SizedBox(height: 8),
        if (hq.topKitchens.isEmpty)
          const Text('No paid kitchen volume in this window.', style: TextStyle(color: AppTheme.textMuted))
        else
          ...hq.topKitchens.map(
            (k) => AppCard(
              margin: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(k.name.isEmpty ? 'Kitchen' : k.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text('${k.orderCount} paid orders', style: AppTheme.caption),
                      ],
                    ),
                  ),
                  Text('₹${k.gmv.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _OpsCrmList extends StatefulWidget {
  const _OpsCrmList({super.key});

  @override
  State<_OpsCrmList> createState() => _OpsCrmListState();
}

class _OpsCrmListState extends State<_OpsCrmList> {
  final _search = TextEditingController();
  String _role = 'all';
  bool _loading = true;
  String? _error;
  List<OpsCrmContact> _rows = const [];
  OpsAdminHq? _hq;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      final raw = await client.rpc(
        'ops_crm_directory',
        params: {
          'p_role': _role,
          'p_search': _search.text.trim(),
          'p_limit': 80,
        },
      ).withTimeout(NetworkTimeouts.standard);
      OpsAdminHq? hq;
      try {
        hq = await _fetchOpsAdminHq('week');
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _rows = parseOpsCrmDirectory(raw);
        _hq = hq;
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

  Future<void> _openContact(OpsCrmContact row) async {
    final note = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Text(row.name, style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(opsCrmSheetSubtitle(row), style: AppTheme.caption),
              const SizedBox(height: 12),
              Text(opsCrmSpendLabel(row), style: const TextStyle(fontWeight: FontWeight.w700)),
              if (row.lastOrderAt.isNotEmpty && AppRole.parse(row.role) != AppRole.driver)
                Text('Last order ${_opsShortDate(row.lastOrderAt)}', style: AppTheme.caption),
              if (opsCrmComplianceLine(row) case final compliance?)
                Text(compliance, style: AppTheme.caption),
              if (row.openTickets > 0) Text('${row.openTickets} open tickets', style: AppTheme.caption),
              if (row.lastNote.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Latest note', style: AppTheme.caption),
                Text(row.lastNote),
              ],
              const SizedBox(height: 16),
              if (row.phone.isNotEmpty)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.call_outlined),
                  title: Text(row.phone),
                  onTap: () => launchUrl(Uri.parse('tel:${row.phone}')),
                ),
              if (row.email.isNotEmpty)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.mail_outline),
                  title: Text(row.email),
                  onTap: () => launchUrl(Uri.parse('mailto:${row.email}')),
                ),
              TextField(
                controller: note,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Add CRM note'),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () async {
                  try {
                    await Supabase.instance.client.rpc(
                      'ops_crm_add_note',
                      params: {'p_user_id': row.id, 'p_body': note.text},
                    ).withTimeout(NetworkTimeouts.standard);
                    if (ctx.mounted) Navigator.pop(ctx);
                    await _load();
                  } catch (e) {
                    if (!ctx.mounted) return;
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(opsFriendlyError(e))));
                  }
                },
                child: const Text('Save note'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final hq = _hq;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            children: [
              TextField(
                controller: _search,
                decoration: InputDecoration(
                  hintText: 'Search name, email, phone, kitchen',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
                ),
                onSubmitted: (_) => _load(),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final entry in const [
                      ('all', 'All'),
                      ('chef', 'Chefs'),
                      ('customer', 'Diners'),
                      ('driver', 'Drivers'),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(entry.$2),
                          selected: _role == entry.$1,
                          onSelected: (_) {
                            setState(() => _role = entry.$1);
                            _load();
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? EmptyState(icon: Icons.error_outline, title: 'Could not load CRM', message: _error!)
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (hq != null) ...[
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _OpsMiniStat(label: 'Pipeline tickets', value: '${hq.openTickets}'),
                              _OpsMiniStat(label: 'Chef/driver KYC', value: '${hq.pendingKyc}'),
                              _OpsMiniStat(label: 'New this week', value: '${hq.newUsers}'),
                              _OpsMiniStat(label: 'Disputes', value: '${hq.openDisputes}'),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                        Text('Directory', style: AppTheme.homeSectionLabelOf(context)),
                        const SizedBox(height: 8),
                        if (_rows.isEmpty)
                          const Text('No matching accounts.', style: TextStyle(color: AppTheme.textMuted))
                        else
                          ..._rows.map((row) {
                            return AppCard(
                              margin: const EdgeInsets.only(bottom: 8),
                              onTap: () => _openContact(row),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                                    child: Text(
                                      row.name.isEmpty ? '?' : row.name[0].toUpperCase(),
                                      style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w800),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(row.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                                        Text(
                                          opsCrmDirectoryMeta(row),
                                          style: AppTheme.caption,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text('₹${row.gmv.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                                ],
                              ),
                            );
                          }),
                      ],
                    ),
        ),
      ],
    );
  }
}

class _OpsPeriodBar extends StatelessWidget {
  const _OpsPeriodBar({
    required this.period,
    required this.loading,
    required this.onPeriod,
    required this.onRefresh,
  });

  final String period;
  final bool loading;
  final ValueChanged<String> onPeriod;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Padding(
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
                selected: period == entry.$1,
                onSelected: (_) => onPeriod(entry.$1),
              ),
            ),
          const Spacer(),
          IconButton(onPressed: loading ? null : onRefresh, icon: const Icon(Icons.refresh)),
        ],
      ),
    );
  }
}

class _OpsMiniStat extends StatelessWidget {
  const _OpsMiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: (MediaQuery.sizeOf(context).width - 52) / 2,
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTheme.caption),
            const SizedBox(height: 6),
            Text(value, style: AppTheme.listTitleOf(context).copyWith(fontSize: 18)),
          ],
        ),
      ),
    );
  }
}

class _OpsQueueTile extends StatelessWidget {
  const _OpsQueueTile({
    required this.icon,
    required this.title,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      margin: const EdgeInsets.only(bottom: 8),
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: AppTheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
          if (onTap != null) const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}

class _OpsMeterRow extends StatelessWidget {
  const _OpsMeterRow({
    required this.label,
    required this.value,
    required this.ratio,
    this.color,
  });

  final String label;
  final String value;
  final double ratio;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 88, child: Text(label, style: AppTheme.micro)),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio.clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: AppTheme.surfaceMutedOf(context),
              color: color ?? AppTheme.primary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _OpsGmvChart extends StatelessWidget {
  const _OpsGmvChart({required this.series, this.title = 'Trend'});

  final List<OpsSnapshotBucket> series;
  final String title;

  @override
  Widget build(BuildContext context) {
    if (series.isEmpty) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text('No paid volume in this window.', style: TextStyle(color: AppTheme.textMuted)),
          ],
        ),
      );
    }
    final maxY = series.fold<double>(0, (m, b) => b.gmv > m ? b.gmv : m);
    final chartMax = maxY <= 0 ? 1.0 : maxY * 1.2;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: chartMax,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      if (group.x < 0 || group.x >= series.length) {
                        return BarTooltipItem('', const TextStyle(color: Colors.white));
                      }
                      final item = series[group.x.toInt()];
                      return BarTooltipItem(
                        '${_opsShortDate(item.bucketDate)}\n₹${item.gmv.toStringAsFixed(0)} · ${item.orderCount}',
                        const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      getTitlesWidget: (value, meta) => Text(
                        value >= 1000 ? '${(value / 1000).toStringAsFixed(0)}k' : value.toStringAsFixed(0),
                        style: AppTheme.micro,
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        if (i < 0 || i >= series.length) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(_opsShortDate(series[i].bucketDate), style: AppTheme.micro),
                        );
                      },
                    ),
                  ),
                ),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                barGroups: [
                  for (var i = 0; i < series.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: series[i].gmv <= 0 ? 0.01 : series[i].gmv,
                          width: 14,
                          borderRadius: BorderRadius.circular(6),
                          color: AppTheme.primary,
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
