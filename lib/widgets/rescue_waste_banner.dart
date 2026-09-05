import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/app_theme.dart';
import '../utils/helpers.dart';

/// Publicity strip: pre-order cook-to-demand — less waste than cooking on hope.
class RescueWasteBanner extends StatefulWidget {
  const RescueWasteBanner({super.key});

  @override
  State<RescueWasteBanner> createState() => _RescueWasteBannerState();
}

class _RescueWasteBannerState extends State<RescueWasteBanner> {
  int _preordered = 0;
  int _preorderable = 0;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await Supabase.instance.client.rpc('get_rescued_meals_week');
      if (!mounted) return;
      final map = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      setState(() {
        _preordered = (map['preordered_plates'] as num?)?.toInt() ??
            (map['rescued_plates'] as num?)?.toInt() ??
            0;
        _preorderable = (map['preorderable_plates'] as num?)?.toInt() ??
            (map['on_offer_plates'] as num?)?.toInt() ??
            0;
        _ready = true;
      });
    } catch (_) {
      if (mounted) setState(() => _ready = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox.shrink();
    if (_preordered <= 0 && _preorderable <= 0) return const SizedBox.shrink();

    final headline = rescuedMealsHeadline(
      rescuedPlates: _preordered,
      onOfferPlates: _preorderable,
    );
    final subhead = rescuedMealsSubhead(
      rescuedPlates: _preordered,
      onOfferPlates: _preorderable,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.success.withValues(alpha: 0.12),
              AppTheme.accent.withValues(alpha: 0.10),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.success.withValues(alpha: 0.28)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.success.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.event_available_outlined, color: AppTheme.success, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    headline,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.onSurfaceOf(context),
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subhead,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textMuted,
                      height: 1.3,
                    ),
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
