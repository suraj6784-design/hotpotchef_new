import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/helpers.dart';
import 'app_widgets.dart';

/// Home flash for admin-controlled membership pricing (e.g. ₹1 for 3 months).
class MembershipFlashBanner extends StatefulWidget {
  const MembershipFlashBanner({super.key});

  @override
  State<MembershipFlashBanner> createState() => _MembershipFlashBannerState();
}

class _MembershipFlashBannerState extends State<MembershipFlashBanner> {
  Map<String, dynamic>? _offer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (Supabase.instance.client.auth.currentUser == null) {
      if (mounted) setState(() => _offer = null);
      return;
    }
    try {
      final raw = await Supabase.instance.client.rpc('diner_flash_membership_offer');
      if (!mounted) return;
      if (raw is Map && raw['active_member'] != true && raw['plan_id'] != null) {
        setState(() => _offer = Map<String, dynamic>.from(raw));
      } else {
        setState(() => _offer = null);
      }
    } catch (_) {
      if (mounted) setState(() => _offer = null);
    }
  }

  Future<void> _interest() async {
    final planId = _offer?['plan_id']?.toString();
    if (planId == null || _busy) return;
    setState(() => _busy = true);
    try {
      await Supabase.instance.client.rpc('diner_interest_in_membership', params: {'p_plan_id': planId});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Interest saved. We will activate this membership from ops.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save interest')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final offer = _offer;
    if (offer == null) return const SizedBox.shrink();
    final list = parseMoney(offer['list_price_inr']);
    final flash = parseMoney(offer['offer_price_inr']);
    final days = int.tryParse(offer['duration_days']?.toString() ?? '') ?? 90;
    final label = (offer['flash_label']?.toString() ?? '').trim();
    final flashing = offer['flash_enabled'] == true;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: AppCard(
        onTap: _busy ? null : _interest,
        child: Row(
          children: [
            const Icon(Icons.workspace_premium_outlined, color: AppTheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    flashing && label.isNotEmpty ? label : 'Become a HotPotChef member',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Unlimited free delivery for $days days. '
                    '${flashing ? 'Flash ₹${flash.toStringAsFixed(0)}' : '₹${list.toStringAsFixed(0)}'}'
                    '${flashing && list > flash ? ' (usually ₹${list.toStringAsFixed(0)})' : ''}.',
                    style: AppTheme.caption,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
