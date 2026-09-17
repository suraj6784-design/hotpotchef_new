import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/helpers.dart';
import 'customer_ui_components.dart';

class RescuedMealsBanner extends StatefulWidget {
  const RescuedMealsBanner({super.key});

  @override
  State<RescuedMealsBanner> createState() => _RescuedMealsBannerState();
}

class _RescuedMealsBannerState extends State<RescuedMealsBanner> {
  Map<String, dynamic>? _week;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await Supabase.instance.client.rpc('get_rescued_meals_week');
      if (!mounted) return;
      if (raw is Map) setState(() => _week = Map<String, dynamic>.from(raw));
    } catch (_) {
      if (mounted) setState(() => _week = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final week = _week;
    if (week == null) return const SizedBox.shrink();
    final rescued = int.tryParse(week['rescued_plates']?.toString() ?? '') ?? 0;
    final offer = int.tryParse(week['on_offer_plates']?.toString() ?? '') ?? 0;
    if (rescued <= 0 && offer <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: AppCard(
        child: Row(
          children: [
            const Icon(Icons.compost_outlined, color: AppTheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rescuedMealsHeadline(rescuedPlates: rescued, onOfferPlates: offer),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    rescuedMealsSubhead(rescuedPlates: rescued, onOfferPlates: offer),
                    style: AppTheme.caption,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
