import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/app_theme.dart';
import '../utils/helpers.dart';
import '../utils/network.dart';
import 'customer_ui_components.dart';

class DriverPayoutCadenceCard extends StatefulWidget {
  const DriverPayoutCadenceCard({super.key});

  @override
  State<DriverPayoutCadenceCard> createState() => _DriverPayoutCadenceCardState();
}

class _DriverPayoutCadenceCardState extends State<DriverPayoutCadenceCard> {
  Map<String, dynamic>? _cadence;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await Supabase.instance.client.rpc('driver_payout_cadence').withTimeout(NetworkTimeouts.short);
      if (!mounted || raw is! Map) return;
      setState(() => _cadence = Map<String, dynamic>.from(raw));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final data = _cadence;
    if (data == null || data['success'] != true) return const SizedBox.shrink();
    final pending = parseMoney(data['pending_inr']);
    final nextRaw = data['next_payout_date']?.toString();
    final next = DateTime.tryParse(nextRaw ?? '');
    final nextLabel = next == null ? (nextRaw ?? '') : DateFormat('EEE d MMM').format(next);
    final note = data['cadence']?.toString() ??
        'Weekly bank transfer every Monday after KYC, arranged by ops from this wallet.';
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Next payout ${nextLabel.isEmpty ? 'Monday' : nextLabel}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              'Wallet ready: ₹${pending.toStringAsFixed(0)}',
              style: TextStyle(color: AppTheme.onSurfaceOf(context), fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(note, style: AppTheme.caption),
          ],
        ),
      ),
    );
  }
}
