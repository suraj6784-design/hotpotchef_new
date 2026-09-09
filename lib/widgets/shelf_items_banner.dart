import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/app_theme.dart';
import '../utils/helpers.dart';
import '../utils/pricing_calculator.dart';

class ShelfItemsBanner extends StatefulWidget {
  const ShelfItemsBanner({
    super.key,
    this.excludedChefIds = const {},
    this.destinationLat,
    this.destinationLng,
    this.chefKitchenPins = const {},
    required this.onItemTap,
    this.dense = false,
  });

  final Set<String> excludedChefIds;
  final double? destinationLat;
  final double? destinationLng;
  final Map<String, Map<String, dynamic>> chefKitchenPins;
  final ValueChanged<Map<String, dynamic>> onItemTap;
  final bool dense;

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
          destinationLat: widget.destinationLat,
          destinationLng: widget.destinationLng,
          chefKitchenPins: widget.chefKitchenPins,
        );
        if (items.isEmpty) return const SizedBox.shrink();

        Widget itemList({required EdgeInsets padding}) {
          return ListView.separated(
            padding: padding,
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
                  width: widget.dense ? 168 : 220,
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
                        style: AppTheme.homeKickerOf(context),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        shelfItemSubhead(meal),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.homeCardTitleOf(context),
                      ),
                      const Spacer(),
                      Text(
                        price > 0 ? 'From ₹${price.toStringAsFixed(0)}' : 'Tap to shop',
                        style: AppTheme.metaOf(context).copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        }

        final header = Padding(
          padding: EdgeInsets.fromLTRB(widget.dense ? 0 : 20, 0, widget.dense ? 0 : 20, 8),
          child: Row(
            children: [
              Icon(Icons.kitchen_outlined, size: 16, color: AppTheme.primary),
              const SizedBox(width: 8),
              Text('Shelf from home', style: AppTheme.homeSectionLabelOf(context)),
            ],
          ),
        );

        if (widget.dense) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              header,
              Expanded(child: itemList(padding: EdgeInsets.zero)),
            ],
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(0, 2, 0, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              header,
              SizedBox(height: 112, child: itemList(padding: const EdgeInsets.symmetric(horizontal: 20))),
            ],
          ),
        );
      },
    );
  }
}
