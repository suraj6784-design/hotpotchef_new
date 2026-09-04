// lib/widgets/daily_streak_banner.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../utils/app_theme.dart';

class DailyStreakBanner extends StatefulWidget {
  const DailyStreakBanner({super.key});

  @override
  State<DailyStreakBanner> createState() => _DailyStreakBannerState();
}

class _DailyStreakBannerState extends State<DailyStreakBanner> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  int _currentStreak = 0;
  bool _claimedToday = false;

  @override
  void initState() {
    super.initState();
    _fetchStreakData();
  }

  Future<void> _fetchStreakData() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final res = await _supabase
          .from('user_gamification')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();

      if (!mounted) return;

      if (res != null) {
        final lastDateStr = res['last_check_in_date']?.toString();
        final lastDate = lastDateStr != null ? DateTime.tryParse(lastDateStr) : null;
        final today = DateTime.now();

        bool alreadyClaimed = false;
        if (lastDate != null) {
          alreadyClaimed = lastDate.year == today.year &&
              lastDate.month == today.month &&
              lastDate.day == today.day;
        }

        setState(() {
          _currentStreak = (res['current_streak'] as num?)?.toInt() ?? 0;
          _claimedToday = alreadyClaimed;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to fetch streak data');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _claimStreak() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final response = await _supabase.rpc('claim_daily_streak', params: {'p_user_id': user.id});

      if (!mounted) return;

      if (response != null && response['success'] == true) {
        final newStreak = (response['streak'] as num?)?.toInt() ?? _currentStreak + 1;
        final reward = response['reward'] ?? 15;

        setState(() {
          _currentStreak = newStreak;
          _claimedToday = true;
        });

        _showSnackBar('Streak Claimed! +$reward HotPot Coins Added! 🎉', isError: false);
      } else {
        final message = response?['message']?.toString() ??
            'Already claimed today. Coins stay in your wallet until you spend them at checkout.';
        _showSnackBar(message, isError: true);
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Error claiming daily streak');
      _showSnackBar('Error claiming streak: $e', isError: true);
    }
  }

  void _showSnackBar(String text, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: isError ? Colors.orangeAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF5722), Color(0xFFFF9800)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Icon(Icons.local_fire_department, color: Colors.white, size: 24),
                  SizedBox(width: 8),
                  Text('Daily Streak Rewards',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
                child: Text('🔥 $_currentStreak Day Streak',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Check in daily to earn free HotPot Coins and unlock high-tier foodie rewards!',
              style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.3)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _claimedToday ? Colors.white24 : Colors.white,
                foregroundColor: _claimedToday ? Colors.white : AppTheme.primary,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _claimedToday ? null : _claimStreak,
              child: Text(
                _claimedToday ? 'Claimed for Today ✓' : 'Claim Daily Bonus',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}