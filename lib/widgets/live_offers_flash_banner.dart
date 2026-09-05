import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/helpers.dart';
import '../utils/pricing_calculator.dart';
import 'app_widgets.dart';

class LiveOffersFlashBanner extends StatefulWidget {
  const LiveOffersFlashBanner({
    super.key,
    this.excludedChefIds = const {},
    required this.onOfferTap,
  });

  final Set<String> excludedChefIds;
  final ValueChanged<Map<String, dynamic>> onOfferTap;

  @override
  State<LiveOffersFlashBanner> createState() => _LiveOffersFlashBannerState();
}

class _LiveOffersFlashBannerState extends State<LiveOffersFlashBanner>
    with TickerProviderStateMixin {
  late final Stream<List<Map<String, dynamic>>> _mealsStream;
  late final PageController _pageController;
  late final AnimationController _shimmer;
  late final AnimationController _pulse;
  late final AnimationController _blink;
  Timer? _rotate;
  int _page = 0;
  int _offerCount = 0;

  @override
  void initState() {
    super.initState();
    _mealsStream = Supabase.instance.client
        .from('meals')
        .stream(primaryKey: ['id'])
        .eq('status', 'Available');
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

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _mealsStream,
      builder: (context, snapshot) {
        final offers = flashableOfferMeals(
          snapshot.data ?? const [],
          excludedChefIds: widget.excludedChefIds,
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
                      'LIVE OFFERS',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                        color: AppTheme.onSurfaceOf(context),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.auto_awesome, size: 14, color: AppTheme.accent),
                  ],
                ),
              ),
              SizedBox(
                height: 118,
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
                      onTap: () => widget.onOfferTap(meal),
                    );
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
                              if (code != null) ...[
                                const SizedBox(height: 8),
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
