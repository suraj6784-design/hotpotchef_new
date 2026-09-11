import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_theme.dart';

class DinerOnboardingCoach extends StatefulWidget {
  const DinerOnboardingCoach({super.key, required this.onGoHome, required this.onGoOrders});

  final VoidCallback onGoHome;
  final VoidCallback onGoOrders;

  @override
  State<DinerOnboardingCoach> createState() => _DinerOnboardingCoachState();
}

class _DinerOnboardingCoachState extends State<DinerOnboardingCoach> {
  static const _key = 'diner_onboarding_v1';
  int _step = 0;
  bool _visible = false;

  static const _copy = [
    ('Find a kitchen', 'Home lists live plates near you. Open hours and FSSAI show on each card.'),
    ('Checkout in minutes', 'Add a plate, pick an address, and pay in-app. Coins apply at pay if you have them.'),
    ('Track and support', 'Orders shows status. Support tickets are under Profile if something is wrong.'),
  ];

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_key) == true) return;
    if (mounted) setState(() => _visible = true);
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
    if (mounted) setState(() => _visible = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    final item = _copy[_step];
    return Positioned.fill(
      child: Material(
        color: Colors.black54,
        child: SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppTheme.surfaceOf(context),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${_step + 1} of ${_copy.length}', style: AppTheme.caption),
                      const SizedBox(height: 6),
                      Text(item.$1, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                      const SizedBox(height: 6),
                      Text(item.$2),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          TextButton(onPressed: _finish, child: const Text('Skip')),
                          const Spacer(),
                          FilledButton(
                            onPressed: () {
                              if (_step >= _copy.length - 1) {
                                widget.onGoOrders();
                                _finish();
                              } else {
                                if (_step == 0) widget.onGoHome();
                                setState(() => _step++);
                              }
                            },
                            child: Text(_step >= _copy.length - 1 ? 'Done' : 'Next'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
