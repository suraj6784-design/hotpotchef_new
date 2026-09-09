import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/app_theme.dart';
import '../utils/helpers.dart';
import 'shelf_items_banner.dart';
import 'sponsored_placement_banner.dart';

/// Puts the live sponsored card and Shelf from Home on one Home row when both exist.
class HomeSponsoredShelfRow extends StatefulWidget {
  const HomeSponsoredShelfRow({
    super.key,
    this.excludedChefIds = const {},
    this.destinationLat,
    this.destinationLng,
    this.cityHint,
    this.chefKitchenPins = const {},
    required this.onItemTap,
  });

  final Set<String> excludedChefIds;
  final double? destinationLat;
  final double? destinationLng;
  final String? cityHint;
  final Map<String, Map<String, dynamic>> chefKitchenPins;
  final ValueChanged<Map<String, dynamic>> onItemTap;

  @override
  State<HomeSponsoredShelfRow> createState() => _HomeSponsoredShelfRowState();
}

class _HomeSponsoredShelfRowState extends State<HomeSponsoredShelfRow> {
  late final Stream<List<Map<String, dynamic>>> _mealsStream;
  List<Map<String, dynamic>> _ads = const [];
  bool _adsReady = false;

  @override
  void initState() {
    super.initState();
    _mealsStream = Supabase.instance.client.from('meals').stream(primaryKey: ['id']).eq('status', 'Available');
    unawaited(_loadAds());
  }

  Future<void> _loadAds() async {
    try {
      final rows = await Supabase.instance.client
          .from('ad_campaigns')
          .select()
          .eq('status', 'live')
          .order('updated_at', ascending: false)
          .limit(20);
      if (!mounted) return;
      setState(() {
        _ads = liveSponsoredCampaigns(
          List<Map<String, dynamic>>.from(rows as List),
          cityHint: widget.cityHint,
        );
        _adsReady = true;
      });
    } catch (_) {
      if (mounted) setState(() => _adsReady = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sponsored = SponsoredPlacementBanner(
      destinationLat: widget.destinationLat,
      destinationLng: widget.destinationLng,
      cityHint: widget.cityHint,
      dense: true,
    );
    final shelf = ShelfItemsBanner(
      excludedChefIds: widget.excludedChefIds,
      destinationLat: widget.destinationLat,
      destinationLng: widget.destinationLng,
      chefKitchenPins: widget.chefKitchenPins,
      onItemTap: widget.onItemTap,
      dense: true,
    );

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
        final showAd = _adsReady && _ads.isNotEmpty;
        final showShelf = items.isNotEmpty;
        if (!showAd && !showShelf) return const SizedBox.shrink();
        if (!showAd) {
          return ShelfItemsBanner(
            excludedChefIds: widget.excludedChefIds,
            destinationLat: widget.destinationLat,
            destinationLng: widget.destinationLng,
            chefKitchenPins: widget.chefKitchenPins,
            onItemTap: widget.onItemTap,
          );
        }
        if (!showShelf) {
          return SponsoredPlacementBanner(
            destinationLat: widget.destinationLat,
            destinationLng: widget.destinationLng,
            cityHint: widget.cityHint,
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: SizedBox(
            height: 156,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: sponsored),
                const SizedBox(width: 8),
                Expanded(child: shelf),
              ],
            ),
          ),
        );
      },
    );
  }
}
