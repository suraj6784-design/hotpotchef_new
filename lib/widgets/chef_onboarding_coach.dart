import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_theme.dart';
import '../utils/fssai_certificate_scan.dart';
import '../utils/helpers.dart';

class ChefSetupStrip extends StatelessWidget {
  const ChefSetupStrip({
    super.key,
    required this.profile,
    required this.isKitchenOpen,
    required this.hasActiveDish,
    required this.onOpenProfile,
    required this.onPublish,
    required this.onGoOnline,
  });

  final Map<String, dynamic> profile;
  final bool isKitchenOpen;
  final bool hasActiveDish;
  final VoidCallback onOpenProfile;
  final VoidCallback onPublish;
  final VoidCallback onGoOnline;

  @override
  Widget build(BuildContext context) {
    final next = chefSetupNextAction(
      profile: profile,
      isKitchenOpen: isKitchenOpen,
      hasActiveDish: hasActiveDish,
    );
    if (next == null) return const SizedBox.shrink();
    return Material(
      color: const Color(0xFFFFF4E5),
      child: InkWell(
        onTap: () {
          if (next.$3 == ChefSetupTarget.profile) {
            onOpenProfile();
          } else if (next.$3 == ChefSetupTarget.publish) {
            onPublish();
          } else {
            onGoOnline();
          }
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              const Icon(Icons.flag_outlined, color: Color(0xFFB45309)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(next.$1, style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text(next.$2, style: AppTheme.caption),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

enum ChefSetupTarget { profile, publish, online }

/// Title, body, tap target for the first incomplete kitchen-launch step.
(String, String, ChefSetupTarget)? chefSetupNextAction({
  required Map<String, dynamic> profile,
  required bool isKitchenOpen,
  required bool hasActiveDish,
}) {
  final number = normalizeFssaiNumber(profile['fssai_number']?.toString()) ?? '';
  final proof = (profile['fssai_proof_url']?.toString() ?? '').trim();
  final status = normalizeFssaiVerificationStatus(profile['fssai_verification_status']?.toString());
  if (number.length != 14 || proof.isEmpty) {
    return (
      'Finish kitchen KYC',
      'Add your 14-digit FSSAI number and licence photo in Profile.',
      ChefSetupTarget.profile,
    );
  }
  if (fssaiLicenceIsExpired(parseStoredFssaiValidUntil(profile['fssai_valid_until']))) {
    return (
      'FSSAI licence expired',
      'Scan a current certificate in Profile. Publishing stays locked until HotPotChef verifies the new card.',
      ChefSetupTarget.profile,
    );
  }
  if (status == 'rejected') {
    return (
      'FSSAI proof was rejected',
      'Upload a clear licence photo in Profile, then wait for HotPotChef to verify.',
      ChefSetupTarget.profile,
    );
  }
  if (status != 'verified') {
    return (
      'FSSAI under review',
      'Publishing unlocks after HotPotChef verifies — typically 1 business day.',
      ChefSetupTarget.profile,
    );
  }
  if (!hasKitchenPin(profile)) {
    return (
      'Pin your kitchen',
      'Drivers collect from this map pin. Add it in Profile before you publish.',
      ChefSetupTarget.profile,
    );
  }
  if (!isKitchenOpen) {
    return (
      'Go online',
      'Turn Online so diners can see your dishes on Home.',
      ChefSetupTarget.online,
    );
  }
  if (!hasActiveDish) {
    return (
      'Publish your first dish',
      'Name, price, portions, a clocked slot, and a service type are required.',
      ChefSetupTarget.publish,
    );
  }
  return null;
}

class ChefOnboardingCoach extends StatefulWidget {
  const ChefOnboardingCoach({
    super.key,
    required this.onOpenProfile,
    required this.onPublish,
  });

  final VoidCallback onOpenProfile;
  final VoidCallback onPublish;

  @override
  State<ChefOnboardingCoach> createState() => _ChefOnboardingCoachState();
}

class _ChefOnboardingCoachState extends State<ChefOnboardingCoach> {
  static const _key = 'chef_onboarding_v1';
  int _step = 0;
  bool _visible = false;

  static const _copy = [
    (
      'Licence and pin',
      'Profile needs a 14-digit FSSAI number, a licence photo, and your kitchen map pin. Ops verifies FSSAI before you can publish.',
    ),
    (
      'Go online, then publish',
      'Turn Online on the dashboard. Then publish a dish with a real clock window, price, portions, and at least one service type.',
    ),
    (
      'Offers, boosts, and payouts',
      'Meal offers and ₹99 Home boosts are self-serve. Brand Sponsored ads go through HotPotChef. Bank details save here; Route payouts start after a live acc_ account is linked.',
    ),
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
                                widget.onPublish();
                                _finish();
                              } else {
                                if (_step == 0) widget.onOpenProfile();
                                setState(() => _step++);
                              }
                            },
                            child: Text(_step >= _copy.length - 1 ? 'Publish' : 'Next'),
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
