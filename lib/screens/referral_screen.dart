// lib/screens/referral_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../utils/helpers.dart';
import '../widgets/app_widgets.dart';

class ReferralScreen extends StatefulWidget {
  const ReferralScreen({super.key});

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  String _referralCode = '';
  double _earnedCoins = 0.0;
  int _friendsReferred = 0;

  @override
  void initState() {
    super.initState();
    _loadReferralData();
  }

  Future<void> _loadReferralData() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final userData = await _supabase
          .from('users')
          .select('referral_code, hotpot_coins, role')
          .eq('id', user.id)
          .maybeSingle();

      if (userData != null && !roleUsesReferral(userData['role']?.toString())) {
        if (mounted) Navigator.pop(context);
        return;
      }

      if (!mounted) return;

      if (userData != null) {
        String code = normalizeReferralCode(userData['referral_code']?.toString()) ?? '';

        if (code.isEmpty) {
          code = generateReferralCode();
          await _supabase.from('users').update({'referral_code': code}).eq('id', user.id);
          if (!mounted) return;
        }

        final countResponse = await _supabase
            .from('users')
            .count(CountOption.exact)
            .eq('referred_by', code);

        var rewardedFriends = 0;
        try {
          rewardedFriends = await _supabase
              .from('users')
              .count(CountOption.exact)
              .eq('referred_by', code)
              .not('referral_rewarded_at', 'is', null);
        } catch (_) {
          rewardedFriends = 0;
        }

        if (!mounted) return;

        setState(() {
          _referralCode = code;
          _earnedCoins = referralCoinsFromRewardedFriends(rewardedFriends);
          _friendsReferred = countResponse;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed loading referral metrics');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _shareCode() {
    Share.share(
      referralInviteText(_referralCode),
      subject: 'Claim your HotPotChef Bonus!',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const BrandMark(title: 'Refer & Earn'),
        backgroundColor: isDark ? AppTheme.surfaceDark : Colors.white,
        elevation: 0,
        iconTheme: IconThemeData(color: isDark ? AppTheme.textMainDark : AppTheme.textMain),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.primary, Color(0xFFFF9800)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: AppTheme.softShadow,
                  ),
                  child: Column(
                    children: const [
                      AppLogo(size: 56, onDark: true),
                      SizedBox(height: 16),
                      Text(
                        'Give ₹50, Get ₹50!',
                        style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Invite your friends to HotPotChef. They enter your code when they sign up. When they place their first order, you both get 50 HotPot Coins!',
                        style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: isDark ? [] : AppTheme.softShadow,
                    border: Border.all(color: isDark ? Colors.white12 : Colors.transparent),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Your Exclusive Referral Code',
                        style: TextStyle(
                          color: isDark ? Colors.grey.shade400 : AppTheme.textMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark ? Colors.white24 : Colors.grey.shade300,
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _referralCode,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2.0,
                                color: isDark ? Colors.orange.shade200 : AppTheme.primary,
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.copy,
                                color: isDark ? AppTheme.textMainDark : AppTheme.textMain,
                              ),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: _referralCode));
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Referral code copied to clipboard!'),
                                    backgroundColor: Colors.green,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              },
                              tooltip: 'Copy Code',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF25D366),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          icon: const Icon(Icons.share, size: 18),
                          label: const Text('Share Referral Invite',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          onPressed: _shareCode,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: isDark ? [] : AppTheme.softShadow,
                          border: Border.all(color: isDark ? Colors.white12 : Colors.transparent),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Friends Joined',
                              style: TextStyle(
                                color: isDark ? Colors.grey.shade400 : AppTheme.textMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '$_friendsReferred',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: isDark ? AppTheme.textMainDark : AppTheme.textMain,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: isDark ? [] : AppTheme.softShadow,
                          border: Border.all(color: isDark ? Colors.white12 : Colors.transparent),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Coins Earned',
                              style: TextStyle(
                                color: isDark ? Colors.grey.shade400 : AppTheme.textMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '₹${_earnedCoins.toInt()}',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}