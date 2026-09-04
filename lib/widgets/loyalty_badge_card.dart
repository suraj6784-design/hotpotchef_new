// lib/widgets/loyalty_badge_card.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../utils/app_theme.dart';

class LoyaltyBadgeCard extends StatefulWidget {
  const LoyaltyBadgeCard({super.key});

  @override
  State<LoyaltyBadgeCard> createState() => _LoyaltyBadgeCardState();
}

class _LoyaltyBadgeCardState extends State<LoyaltyBadgeCard> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  String _tier = 'Bronze Foodie 🥉';
  int _completedOrders = 0;
  int _streak = 0;

  @override
  void initState() {
    super.initState();
    _fetchGamificationData();
  }

  Future<void> _fetchGamificationData() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final results = await Future.wait([
        _supabase.from('user_gamification').select().eq('user_id', user.id).maybeSingle(),
        _supabase.from('orders').select('status').eq('customer_id', user.id),
      ]);

      if (!mounted) return;

      final res = results[0] as Map<String, dynamic>?;
      final orders = List<Map<String, dynamic>>.from((results[1] as List?) ?? const []);
      final delivered = orders.where((order) {
        final status = order['status']?.toString().toLowerCase() ?? '';
        return status.contains('delivered') || status.contains('completed');
      }).length;

      setState(() {
        _tier = res?['loyalty_tier']?.toString() ?? 'Bronze Foodie 🥉';
        _completedOrders = delivered;
        _streak = (res?['current_streak'] as num?)?.toInt() ?? 0;
        _isLoading = false;
      });
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to fetch gamification tier data');
      if (mounted) setState(() => _isLoading =false);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primary.withValues(alpha: isDark ? 0.4 : 0.2)),
        boxShadow: isDark ? [] : AppTheme.softShadow,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.workspace_premium, color: AppTheme.primary, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Customer Loyalty Tier',
                  style: TextStyle(
                    color: isDark ? Colors.grey.shade400 : AppTheme.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _tier,
                  style: TextStyle(
                    color: isDark ? AppTheme.textMainDark : AppTheme.textMain,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      '$_completedOrders Orders Completed',
                      style: TextStyle(
                        color: isDark ? Colors.grey.shade300 : AppTheme.textMuted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '🔥 $_streak Streak',
                      style: const TextStyle(
                        color: Colors.orangeAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}