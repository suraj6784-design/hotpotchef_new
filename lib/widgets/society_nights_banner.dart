import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/app_theme.dart';
import '../utils/helpers.dart';
import '../utils/pricing_calculator.dart';

class SocietyNightsBanner extends StatefulWidget {
  const SocietyNightsBanner({
    super.key,
    this.excludedChefIds = const {},
    this.destinationLat,
    this.destinationLng,
    this.destinationAddress,
    this.chefKitchenPins = const {},
    required this.onNightTap,
  });

  final Set<String> excludedChefIds;
  final double? destinationLat;
  final double? destinationLng;
  final Map<String, dynamic>? destinationAddress;
  final Map<String, Map<String, dynamic>> chefKitchenPins;
  final ValueChanged<Map<String, dynamic>> onNightTap;

  @override
  State<SocietyNightsBanner> createState() => _SocietyNightsBannerState();
}

class _SocietyNightsBannerState extends State<SocietyNightsBanner> {
  late final Stream<List<Map<String, dynamic>>> _mealsStream;

  @override
  void initState() {
    super.initState();
    _mealsStream = Supabase.instance.client
        .from('meals')
        .stream(primaryKey: ['id'])
        .eq('status', 'Available');
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _mealsStream,
      builder: (context, snapshot) {
        final nights = societyNightMeals(
          snapshot.data ?? const [],
          excludedChefIds: widget.excludedChefIds,
          destinationLat: widget.destinationLat,
          destinationLng: widget.destinationLng,
          destinationAddress: widget.destinationAddress,
          chefKitchenPins: widget.chefKitchenPins,
        );
        if (nights.isEmpty) {
          final anySociety = (snapshot.data ?? const []).any(isSocietyNight);
          final hasPin = widget.destinationAddress != null ||
              (widget.destinationLat != null && widget.destinationLng != null);
          if (anySociety && hasPin && widget.destinationAddress != null) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: Text(
                'Society nights nearby are hidden — they are not listed for your society / wing.',
                style: AppTheme.caption,
              ),
            );
          }
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(0, 4, 0, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Row(
                  children: [
                    Icon(Icons.apartment_outlined, size: 16, color: AppTheme.primary),
                    const SizedBox(width: 8),
                    Text('Society nights', style: AppTheme.homeSectionLabelOf(context)),
                  ],
                ),
              ),
              SizedBox(
                height: 112,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  scrollDirection: Axis.horizontal,
                  itemCount: nights.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final meal = nights[index];
                    final price = PricingCalculator.effectiveUnitPrice(meal, 1);
                    return InkWell(
                      onTap: () => widget.onNightTap(meal),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: 220,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppTheme.primary.withValues(alpha: 0.14),
                              AppTheme.accent.withValues(alpha: 0.10),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.30)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              societyNightHeadline(meal),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.primary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              societyNightSubhead(meal),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.onSurfaceOf(context),
                                height: 1.25,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              price > 0 ? 'From ₹${price.toStringAsFixed(0)}' : 'Tap to join',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textMuted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
