import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/helpers.dart';
import '../utils/pricing_calculator.dart';
import 'app_widgets.dart';

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

class _LiveOffersFlashBannerState extends State<LiveOffersFlashBanner>
    with TickerProviderStateMixin {
  late final Stream<List<Map<String, dynamic>>> _mealsStream;
  late final AnimationController _shimmer;
  late final AnimationController _pulse;
  late final AnimationController _blink;

  @override
  void initState() {
    super.initState();
    _mealsStream = Supabase.instance.client
        .from('meals')
        .stream(primaryKey: ['id'])
        .eq('status', 'Available');
    _shimmer = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
    _blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _shimmer.dispose();
    _pulse.dispose();
    _blink.dispose();
    super.dispose();
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
                    FadeTransition(
                      opacity: Tween(begin: 0.35, end: 1.0).animate(_blink),
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFF3D00),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'HOME OFFERS',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                        color: AppTheme.onSurfaceOf(context),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.auto_awesome, size: 14, color: AppTheme.accent),
                    if (offers.length > 1) ...[
                      const SizedBox(width: 8),
                      Text(
                        '${offers.length} live',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(
                height: 118,
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
                        shimmer: _shimmer,
                        pulse: _pulse,
                        onTap: () => widget.onOfferTap(meal),
                      ).entrance(index: index.clamp(0, 4)),
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
    required this.shimmer,
    required this.pulse,
    required this.onTap,
  });

  final Map<String, dynamic> meal;
  final Animation<double> shimmer;
  final Animation<double> pulse;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final image = meal['image_url']?.toString() ?? '';
    final headline = offerFlashHeadline(meal);
    final subhead = offerFlashSubhead(meal);
    final code = PricingCalculator.mealPromoCode(meal);
    final boosted = isMealBoosted(meal);

    return AnimatedBuilder(
      animation: Listenable.merge([shimmer, pulse]),
      builder: (context, child) {
        final glow = 0.18 + (pulse.value * 0.22);
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withValues(alpha: glow),
                blurRadius: 18 + (pulse.value * 10),
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: child,
        );
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                colors: [Color(0xFFD84315), Color(0xFFFF7043), Color(0xFFFFB300)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: shimmer,
                      builder: (context, _) {
                        final t = shimmer.value;
                        return IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment(-1.4 + (t * 2.8), -0.2),
                                end: Alignment(-0.4 + (t * 2.8), 0.4),
                                colors: [
                                  Colors.white.withValues(alpha: 0),
                                  Colors.white.withValues(alpha: 0.28),
                                  Colors.white.withValues(alpha: 0),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Row(
                      children: [
                        const AppLogo(size: 28, onDark: true),
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
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                subhead,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (boosted || code != null) ...[
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    if (boosted)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.22),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
                                        ),
                                        child: const Text(
                                          'PAID PROMO',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.8,
                                          ),
                                        ),
                                      ),
                                    if (code != null)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                                        ),
                                        child: Text(
                                          'CODE $code',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.8,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (image.isNotEmpty)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              image,
                              width: 64,
                              height: 64,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const SizedBox.shrink(),
                            ),
                          )
                        else
                          const Icon(Icons.local_offer_rounded, color: Colors.white, size: 28),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
