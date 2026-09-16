import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/helpers.dart';
import '../utils/membership.dart';
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
      if (raw is Map && membershipOfferEligible(Map<String, dynamic>.from(raw))) {
        setState(() => _offer = Map<String, dynamic>.from(raw));
      } else {
        setState(() => _offer = null);
      }
    } catch (_) {
      if (mounted) setState(() => _offer = null);
    }
  }

  Future<void> _interest() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await rememberAddMembershipAtCheckout();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('We will add Family member on your next checkout. Toggle it on the bill.')),
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
    final period = membershipPlanPeriodLabel(days);
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
                    flashing && label.isNotEmpty ? label : 'Become a Family member',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Unlimited free delivery for $period. '
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
