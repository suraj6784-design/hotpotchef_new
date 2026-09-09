import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/helpers.dart';
import '../utils/pricing_calculator.dart';

class LiveOffersFlashBanner extends StatefulWidget {
  const LiveOffersFlashBanner({
    super.key,
    this.excludedChefIds = const {},
    this.destinationLat,
    this.destinationLng,
    this.chefKitchenPins = const {},
    required this.onOfferTap,
  });

  final Set<String> excludedChefIds;
  final double? destinationLat;
  final double? destinationLng;
  final Map<String, Map<String, dynamic>> chefKitchenPins;
  final ValueChanged<Map<String, dynamic>> onOfferTap;

  @override
  State<LiveOffersFlashBanner> createState() => _LiveOffersFlashBannerState();
}

class _LiveOffersFlashBannerState extends State<LiveOffersFlashBanner> {
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
        final offers = flashableOfferMeals(
          snapshot.data ?? const [],
          excludedChefIds: widget.excludedChefIds,
          destinationLat: widget.destinationLat,
          destinationLng: widget.destinationLng,
          chefKitchenPins: widget.chefKitchenPins,
        );
        if (offers.isEmpty) return const SizedBox.shrink();
        final cardWidth = (MediaQuery.sizeOf(context).width * 0.78).clamp(260.0, 340.0);

        return Padding(
          padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Row(
                  children: [
                    Text(
                      "Tonight's kitchen offers",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.onSurfaceOf(context),
                      ),
                    ),
                    if (offers.length > 1) ...[
                      const SizedBox(width: 8),
                      Text(
                        '${offers.length}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(
                height: 108,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  itemCount: offers.length,
                  itemBuilder: (context, index) {
                    final meal = offers[index];
                    return SizedBox(
                      width: cardWidth,
                      child: _OfferFlashCard(
                        meal: meal,
                        onTap: () => widget.onOfferTap(meal),
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

class _OfferFlashCard extends StatelessWidget {
  const _OfferFlashCard({
    required this.meal,
    required this.onTap,
  });

  final Map<String, dynamic> meal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final image = meal['image_url']?.toString() ?? '';
    final headline = offerFlashHeadline(meal);
    final subhead = offerFlashSubhead(meal);
    final code = PricingCalculator.mealPromoCode(meal);
    final boosted = isMealBoosted(meal);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.softShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: AppTheme.surfaceOf(context),
              border: Border.all(color: AppTheme.hairlineOf(context)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          headline,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppTheme.onSurfaceOf(context),
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subhead,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (boosted || code != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            [
                              if (boosted) 'Featured',
                              if (code != null) code,
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (image.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        image,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Icon(Icons.local_offer_outlined, color: AppTheme.textMuted),
                      ),
                    )
                  else
                    const Icon(Icons.local_offer_outlined, color: AppTheme.textMuted, size: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
