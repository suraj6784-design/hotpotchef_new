import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/helpers.dart';
import '../utils/pricing_calculator.dart';
import 'app_widgets.dart';

class LiveOffersFlashBanner extends StatefulWidget {
  const LiveOffersFlashBanner({
    super.key,
    this.meals = const [],
    this.excludedChefIds = const {},
    this.destinationLat,
    this.destinationLng,
    this.chefKitchenPins = const {},
    required this.onOfferTap,
  });

  /// Home catalog rows. Avoids a Realtime `select *` that greys guest Home.
  final List<Map<String, dynamic>> meals;
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
  late final PageController _pageController;
  late final AnimationController _shimmer;
  late final AnimationController _pulse;
  late final AnimationController _blink;
  Timer? _rotate;
  int _page = 0;
  int _offerCount = 0;
  final Set<String> _resolvedChefIds = {};
  final Set<String> _closedChefIds = {};
  bool _hydratingKitchens = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.92);
    _shimmer = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
    _blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _rotate?.cancel();
    _pageController.dispose();
    _shimmer.dispose();
    _pulse.dispose();
    _blink.dispose();
    super.dispose();
  }

  void _syncRotation(int count) {
    _offerCount = count;
    if (count < 2) {
      _rotate?.cancel();
      _rotate = null;
      return;
    }
    _rotate ??= Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_pageController.hasClients || _offerCount < 2) return;
      final next = (_page + 1) % _offerCount;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _hydrateKitchenHours(List<Map<String, dynamic>> meals) async {
    final missing = <String>{};
    for (final meal in meals) {
      final chefId = meal['chef_id']?.toString() ?? '';
      if (chefId.isEmpty || _resolvedChefIds.contains(chefId)) continue;
      missing.add(chefId);
    }
    if (missing.isEmpty || _hydratingKitchens) return;
    _hydratingKitchens = true;
    try {
      final rows = await Supabase.instance.client
          .from('chef_profiles')
          .select('user_id, is_open')
          .inFilter('user_id', missing.toList());
      for (final row in rows) {
        final id = row['user_id']?.toString();
        if (id == null || id.isEmpty) continue;
        _resolvedChefIds.add(id);
        if (!isChefKitchenAcceptingOrders(Map<String, dynamic>.from(row))) {
          _closedChefIds.add(id);
        }
      }
      _resolvedChefIds.addAll(missing);
      if (mounted) setState(() {});
    } catch (_) {
      _resolvedChefIds.addAll(missing);
    } finally {
      _hydratingKitchens = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.meals;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _hydrateKitchenHours(rows);
    });
    final unresolvedChefs = <String>{};
    for (final meal in rows) {
      final chefId = meal['chef_id']?.toString() ?? '';
      if (chefId.isNotEmpty && !_resolvedChefIds.contains(chefId)) {
        unresolvedChefs.add(chefId);
      }
    }
    final offers = flashableOfferMeals(
      rows,
      excludedChefIds: {
        ...widget.excludedChefIds,
        ..._closedChefIds,
        ...unresolvedChefs,
      },
      destinationLat: widget.destinationLat,
      destinationLng: widget.destinationLng,
      chefKitchenPins: widget.chefKitchenPins,
      excludeFestivalHampers: true,
    );
    if (offers.isEmpty) return const SizedBox.shrink();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncRotation(offers.length);
    });
    final current = _page % offers.length;

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
                      'Exclusive offers',
                      style: AppTheme.homeSectionLabelOf(context),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.auto_awesome, size: 14, color: AppTheme.accent),
                  ],
                ),
              ),
              SizedBox(
                height: 164,
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: offers.length,
                  onPageChanged: (index) => setState(() => _page = index),
                  itemBuilder: (context, index) {
                    final meal = offers[index];
                    return _OfferFlashCard(
                      meal: meal,
                      shimmer: _shimmer,
                      pulse: _pulse,
                      blink: _blink,
                      onExpired: () {
                        if (mounted) setState(() {});
                      },
                      onTap: () => widget.onOfferTap(meal),
                    ).entrance(index: index.clamp(0, 4));
                  },
                ),
              ),
              if (offers.length > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < offers.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: i == current ? 16 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: i == current ? AppTheme.primary : AppTheme.hairlineOf(context),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
  }
}

class _OfferFlashCard extends StatefulWidget {
  const _OfferFlashCard({
    required this.meal,
    required this.shimmer,
    required this.pulse,
    required this.blink,
    required this.onTap,
    required this.onExpired,
  });

  final Map<String, dynamic> meal;
  final Animation<double> shimmer;
  final Animation<double> pulse;
  final Animation<double> blink;
  final VoidCallback onTap;
  final VoidCallback onExpired;

  @override
  State<_OfferFlashCard> createState() => _OfferFlashCardState();
}

class _OfferFlashCardState extends State<_OfferFlashCard> {
  Timer? _clock;
  bool _expired = false;

  @override
  void initState() {
    super.initState();
    _armClock();
  }

  @override
  void didUpdateWidget(covariant _OfferFlashCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.meal['offer_valid_until'] != widget.meal['offer_valid_until']) {
      _expired = false;
      _armClock();
    }
  }

  void _armClock() {
    _clock?.cancel();
    _clock = null;
    final until = PricingCalculator.parseOfferDate(widget.meal['offer_valid_until']);
    if (until == null || !until.isAfter(DateTime.now())) return;
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    final until = PricingCalculator.parseOfferDate(widget.meal['offer_valid_until']);
    final label = offerExpiryCountdownLabel(until);
    if (until != null && label.isEmpty && !_expired) {
      _expired = true;
      widget.onExpired();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final meal = widget.meal;
    final image = meal['image_url']?.toString() ?? '';
    final price = offerFlashPriceBreakup(meal);
    final title = price.title.isEmpty ? offerFlashHeadline(meal) : price.title;
    final code = PricingCalculator.mealPromoCode(meal);
    final boosted = isMealBoosted(meal);
    final countdown = offerExpiryCountdownLabel(
      PricingCalculator.parseOfferDate(meal['offer_valid_until']),
    );

    return AnimatedBuilder(
      animation: Listenable.merge([widget.shimmer, widget.pulse]),
      builder: (context, child) {
        final glow = 0.18 + (widget.pulse.value * 0.22);
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withValues(alpha: glow),
                blurRadius: 18 + (widget.pulse.value * 10),
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
          onTap: widget.onTap,
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
                      animation: widget.shimmer,
                      builder: (context, _) {
                        final t = widget.shimmer.value;
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
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              const SizedBox(height: 4),
                              _OfferPriceBreakup(price: price),
                              if (price.plateCount > 1) ...[
                                const SizedBox(height: 2),
                                Text(
                                  '${price.plateCount} plates · tap to see all',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                              if (countdown.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                FadeTransition(
                                  opacity: Tween(begin: 0.35, end: 1.0).animate(widget.blink),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.timer_outlined, color: Colors.white, size: 14),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          countdown,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            fontFeatures: [FontFeature.tabularFigures()],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
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

class _OfferPriceBreakup extends StatelessWidget {
  const _OfferPriceBreakup({required this.price});

  final OfferFlashPriceBreakup price;

  @override
  Widget build(BuildContext context) {
    const payStyle = TextStyle(
      color: Colors.white,
      fontSize: 16,
      fontWeight: FontWeight.w800,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    if (!price.showsSplit) {
      if (price.listRupees == null) return const SizedBox.shrink();
      return Text('₹${price.listRupees}', style: payStyle);
    }
    final struck = TextStyle(
      color: Colors.white.withValues(alpha: 0.75),
      fontSize: 13,
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.lineThrough,
      decorationColor: Colors.white.withValues(alpha: 0.75),
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Row(
      children: [
        Text('₹${price.listRupees}', style: struck),
        const SizedBox(width: 6),
        Text('₹${price.payRupees}', style: payStyle),
        if (price.badge.isNotEmpty) ...[
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              price.badge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Blinking remaining time for a chef-published offer end.
class FlashingOfferCountdown extends StatefulWidget {
  const FlashingOfferCountdown({
    super.key,
    required this.until,
    this.onDark = false,
  });

  final DateTime? until;
  final bool onDark;

  @override
  State<FlashingOfferCountdown> createState() => _FlashingOfferCountdownState();
}

class _FlashingOfferCountdownState extends State<FlashingOfferCountdown>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true);
    final until = widget.until;
    if (until != null && until.isAfter(DateTime.now())) {
      _clock = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = offerExpiryCountdownLabel(widget.until);
    if (label.isEmpty) return const SizedBox.shrink();
    final color = widget.onDark ? Colors.white : Colors.red.shade700;
    return FadeTransition(
      opacity: Tween(begin: 0.25, end: 1.0).animate(_blink),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
