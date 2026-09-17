// lib/widgets/loyalty_badge_card.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../screens/checkout_screen.dart';
import '../utils/app_theme.dart';
import '../utils/helpers.dart';
import '../utils/membership.dart';
import '../utils/network.dart';

class LoyaltyBadgeCard extends StatefulWidget {
  const LoyaltyBadgeCard({
    super.key,
    this.coins = 0,
    this.onOpenWallet,
  });

  final double coins;
  final VoidCallback? onOpenWallet;

  @override
  State<LoyaltyBadgeCard> createState() => _LoyaltyBadgeCardState();
}

class _LoyaltyBadgeCardState extends State<LoyaltyBadgeCard> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  String _tier = 'Bronze Foodie 🥉';
  bool _isFamilyMember = false;
  DateTime? _memberUntil;
  int _memberPlanDays = 90;
  int _completedOrders = 0;
  int _streak = 0;
  String _referralCode = '';
  int _referralsShared = 0;
  double _referralCoins = 0;

  @override
  void initState() {
    super.initState();
    _fetchRewards();
  }

  Future<void> _fetchRewards() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final results = await Future.wait<dynamic>([
        _supabase.from('user_gamification').select().eq('user_id', user.id).maybeSingle(),
        _supabase.from('orders').select('status').eq('customer_id', user.id),
        _supabase.from('users').select('referral_code, role').eq('id', user.id).maybeSingle(),
        _supabase
            .from('diner_memberships')
            .select('ends_at, status, membership_plans(duration_days, member_title)')
            .eq('user_id', user.id)
            .eq('status', 'active')
            .order('ends_at', ascending: false)
            .limit(1),
      ]).withTimeout(NetworkTimeouts.standard);

      if (!mounted) return;

      final res = results[0] as Map<String, dynamic>?;
      final orders = List<Map<String, dynamic>>.from((results[1] as List?) ?? const []);
      final profile = results[2] as Map<String, dynamic>?;
      final membershipRows = List<Map<String, dynamic>>.from((results[3] as List?) ?? const []);
      final membership = membershipRows.isEmpty ? null : membershipRows.first;
      final plan = membership?['membership_plans'];
      final planMap = plan is Map
          ? Map<String, dynamic>.from(plan)
          : (plan is List && plan.isNotEmpty && plan.first is Map)
              ? Map<String, dynamic>.from(plan.first as Map)
              : const <String, dynamic>{};
      final planDays = int.tryParse(planMap['duration_days']?.toString() ?? '') ?? 90;
      final delivered = orders.where((order) {
        final status = order['status']?.toString().toLowerCase() ?? '';
        return status.contains('delivered') || status.contains('completed');
      }).length;

      var code = '';
      if (roleUsesReferral(profile?['role']?.toString())) {
        code = normalizeReferralCode(profile?['referral_code']?.toString()) ?? '';
        if (code.isEmpty) {
          code = generateReferralCode();
          try {
            await _supabase.from('users').update({'referral_code': code}).eq('id', user.id);
          } catch (_) {}
        }
      }

      var shared = 0;
      var rewarded = 0;
      if (code.isNotEmpty) {
        try {
          shared = await _supabase.from('users').count(CountOption.exact).ilike('referred_by', code);
        } catch (_) {
          try {
            shared = await _supabase.from('users').count(CountOption.exact).eq('referred_by', code);
          } catch (_) {}
        }
        try {
          rewarded = await _supabase
              .from('users')
              .count(CountOption.exact)
              .ilike('referred_by', code)
              .not('referral_rewarded_at', 'is', null);
        } catch (_) {
          try {
            rewarded = await _supabase
                .from('users')
                .count(CountOption.exact)
                .eq('referred_by', code)
                .not('referral_rewarded_at', 'is', null);
          } catch (_) {}
        }
      }

      if (!mounted) return;
      final ends = DateTime.tryParse(membership?['ends_at']?.toString() ?? '');
      final family = ends != null && ends.isAfter(DateTime.now());
      setState(() {
        _isFamilyMember = family;
        _memberUntil = family ? ends : null;
        _memberPlanDays = planDays;
        _tier = family ? kFamilyMemberTitle : (res?['loyalty_tier']?.toString() ?? 'Bronze Foodie 🥉');
        _completedOrders = delivered;
        _streak = (res?['current_streak'] as num?)?.toInt() ?? 0;
        _referralCode = code;
        _referralsShared = shared;
        _referralCoins = referralCoinsFromRewardedFriends(rewarded);
        _isLoading = false;
      });
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to fetch diner rewards card');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _copyReferral() async {
    if (_referralCode.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _referralCode));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied $_referralCode')),
    );
  }

  void _shareReferral() {
    if (_referralCode.isEmpty) return;
    SharePlus.instance.share(
      ShareParams(
        text: referralInviteText(_referralCode),
        subject: 'Join HotPotChef with my code $_referralCode',
      ),
    );
  }

  Future<void> _buyMembership() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CheckoutScreen(
          cartItems: const [],
          membershipOnly: true,
          onOrderPlacedSuccess: () => unawaited(_fetchRewards()),
        ),
      ),
    );
    if (mounted) unawaited(_fetchRewards());
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final coins = widget.coins.toInt();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primary.withValues(alpha: isDark ? 0.4 : 0.2)),
        boxShadow: isDark ? [] : AppTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _tier,
            style: TextStyle(
              color: isDark ? AppTheme.textMainDark : AppTheme.textMain,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _isFamilyMember
                ? membershipDaysLeftLabel(endsAt: _memberUntil, durationDays: _memberPlanDays)
                : '$_completedOrders orders completed · rewards in one place',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _RewardCell(
                  icon: Icons.local_fire_department_outlined,
                  label: 'Streak',
                  value: _streak > 0 ? '$_streak days' : 'Start today',
                ),
              ),
              Expanded(
                child: _RewardCell(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Coins',
                  value: '$coins',
                  onTap: widget.onOpenWallet,
                ),
              ),
              Expanded(
                child: _RewardCell(
                  icon: Icons.card_giftcard_outlined,
                  label: 'Referral',
                  value: referralCardStatsLabel(
                    sharedCount: _referralsShared,
                    coinsCredited: _referralCoins,
                  ),
                  onTap: _referralCode.isEmpty ? null : _copyReferral,
                  onLongPress: _referralCode.isEmpty ? null : _shareReferral,
                ),
              ),
            ],
          ),
          if (_referralCode.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _shareReferral,
                icon: const Icon(Icons.ios_share, size: 16),
                label: const Text('Share code'),
              ),
            ),
          ],
          const SizedBox(height: 4),
          if (!_isFamilyMember)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _buyMembership,
                child: const Text('Become a Family member'),
              ),
            ),
        ],
      ),
    );
  }
}

class _RewardCell extends StatelessWidget {
  const _RewardCell({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
    this.onLongPress,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Column(
        children: [
          Icon(icon, color: AppTheme.primary, size: 22),
          const SizedBox(height: 6),
          Text(label, style: AppTheme.caption),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
        ],
      ),
    );
    if (onTap == null && onLongPress == null) return child;
    return InkWell(onTap: onTap, onLongPress: onLongPress, borderRadius: BorderRadius.circular(12), child: child);
  }
}
