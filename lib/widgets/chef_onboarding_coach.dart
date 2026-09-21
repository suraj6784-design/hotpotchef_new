import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_theme.dart';
import '../utils/fssai_certificate_scan.dart';
import '../utils/helpers.dart';
import '../utils/kyc_checklist.dart';

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

bool chefKycCoachShouldShow(Map<String, dynamic> profile) {
  return kycChecklistFor({'role': 'chef', ...profile}).incomplete;
}

class ChefOnboardingCoach extends StatefulWidget {
  const ChefOnboardingCoach({
    super.key,
    required this.profile,
    required this.onOpenProfile,
  });

  final Map<String, dynamic> profile;
  final VoidCallback onOpenProfile;

  @override
  State<ChefOnboardingCoach> createState() => _ChefOnboardingCoachState();
}

class _ChefOnboardingCoachState extends State<ChefOnboardingCoach> {
  static const _key = 'chef_onboarding_v1';
  bool _visible = false;
  bool _dismissed = false;

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
    if (mounted) setState(() {
      _visible = false;
      _dismissed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed || !_visible || !chefKycCoachShouldShow(widget.profile)) {
      return const SizedBox.shrink();
    }
    final kyc = kycChecklistFor({'role': 'chef', ...widget.profile});
    final missing = kyc.missing;
    return Positioned.fill(
      child: Material(
        color: Colors.black45,
        child: SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppTheme.surfaceOf(context),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: AppTheme.brandGlow(opacity: 0.08),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.badge_outlined, color: AppTheme.primary),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Finish kitchen verification',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Diners only see a live kitchen after these Profile items are in. Takes a couple of minutes.',
                        style: AppTheme.caption.copyWith(height: 1.35, fontSize: 13),
                      ),
                      if (missing.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: missing
                              .take(6)
                              .map(
                                (item) => Chip(
                                  visualDensity: VisualDensity.compact,
                                  label: Text(item, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                                  backgroundColor: AppTheme.primary.withValues(alpha: 0.08),
                                  side: BorderSide.none,
                                ),
                              )
                              .toList(),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          TextButton(onPressed: _finish, child: const Text('Later')),
                          const Spacer(),
                          FilledButton(
                            onPressed: () {
                              widget.onOpenProfile();
                              _finish();
                            },
                            child: const Text('Open Profile'),
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
