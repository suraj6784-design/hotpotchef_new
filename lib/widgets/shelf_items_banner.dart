import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/app_theme.dart';
import '../utils/helpers.dart';
import '../utils/pricing_calculator.dart';

class ShelfItemsBanner extends StatefulWidget {
  const ShelfItemsBanner({
    super.key,
    this.excludedChefIds = const {},
    required this.onItemTap,
  });

  final Set<String> excludedChefIds;
  final ValueChanged<Map<String, dynamic>> onItemTap;

  @override
  State<ShelfItemsBanner> createState() => _ShelfItemsBannerState();
}

class _ShelfItemsBannerState extends State<ShelfItemsBanner> {
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
        final items = shelfItems(
          snapshot.data ?? const [],
          excludedChefIds: widget.excludedChefIds,
        );
        if (items.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.fromLTRB(0, 4, 0, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Row(
                  children: [
                    Icon(Icons.kitchen_outlined, size: 16, color: AppTheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'SHELF FROM HOME',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.1,
                        color: AppTheme.onSurfaceOf(context),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 112,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  scrollDirection: Axis.horizontal,
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final meal = items[index];
                    final price = PricingCalculator.effectiveUnitPrice(meal, 1);
                    return InkWell(
                      onTap: () => widget.onItemTap(meal),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: 220,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppTheme.accent.withValues(alpha: 0.12),
                              AppTheme.primary.withValues(alpha: 0.08),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppTheme.accent.withValues(alpha: 0.28)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              shelfItemHeadline(meal),
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
                              shelfItemSubhead(meal),
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
                              price > 0 ? 'From ₹${price.toStringAsFixed(0)}' : 'Tap to shop',
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
