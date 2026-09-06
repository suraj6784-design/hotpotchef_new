import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/app_theme.dart';

/// Diner-facing sponsored strip (third-party advertising framework v1).
class SponsoredPlacementBanner extends StatefulWidget {
  const SponsoredPlacementBanner({
    super.key,
    this.destinationLat,
    this.destinationLng,
    this.cityHint,
  });

  final double? destinationLat;
  final double? destinationLng;
  final String? cityHint;

  @override
  State<SponsoredPlacementBanner> createState() => _SponsoredPlacementBannerState();
}

class _SponsoredPlacementBannerState extends State<SponsoredPlacementBanner> {
  List<Map<String, dynamic>> _ads = const [];
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
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
        _ready = true;
      });
    } catch (_) {
      if (mounted) setState(() => _ready = true);
    }
  }

  Future<void> _open(Map<String, dynamic> ad) async {
    final url = (ad['cta_url'] ?? '').toString().trim();
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || _ads.isEmpty) return const SizedBox.shrink();
    final ad = _ads.first;
    final title = (ad['title'] ?? 'Sponsored').toString();
    final body = (ad['body'] ?? '').toString().trim();
    final cta = (ad['cta_label'] ?? 'Learn more').toString();
    final image = (ad['image_url'] ?? '').toString().trim();
    final advertiser = (ad['advertiser_name'] ?? '').toString().trim();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _open(ad),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [
                  AppTheme.primary.withValues(alpha: 0.14),
                  AppTheme.accent.withValues(alpha: 0.10),
                ],
              ),
              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.22)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (image.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        image,
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                        errorBuilder: (_, error, stack) => _placeholderThumb(),
                      ),
                    )
                  else
                    _placeholderThumb(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: const Text(
                                'Sponsored · Brand',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.primary,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                            if (advertiser.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  advertiser,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.onSurfaceOf(context),
                          ),
                        ),
                        if (body.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted, height: 1.35),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          cta,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.primary,
                          ),
                        ),
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

  Widget _placeholderThumb() {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.campaign_outlined, color: AppTheme.primary),
    );
  }
}

/// Filters live campaigns for overall vs targeted reach.
List<Map<String, dynamic>> liveSponsoredCampaigns(
  Iterable<Map<String, dynamic>> rows, {
  String? cityHint,
  DateTime? now,
}) {
  final clock = now ?? DateTime.now().toUtc();
  final city = (cityHint ?? '').trim().toLowerCase();
  final out = <Map<String, dynamic>>[];

  for (final raw in rows) {
    final ad = Map<String, dynamic>.from(raw);
    if ((ad['status']?.toString().toLowerCase() ?? '') != 'live') continue;
    final starts = DateTime.tryParse(ad['starts_at']?.toString() ?? '');
    final ends = DateTime.tryParse(ad['ends_at']?.toString() ?? '');
    if (starts != null && starts.toUtc().isAfter(clock)) continue;
    if (ends != null && ends.toUtc().isBefore(clock)) continue;

    final mode = (ad['reach_mode']?.toString().toLowerCase() ?? 'overall').trim();
    if (mode == 'targeted') {
      final adCity = (ad['city']?.toString() ?? '').trim().toLowerCase();
      if (adCity.isEmpty) continue;
      if (city.isNotEmpty && adCity != city) continue;
      // If diner city is unknown, still show city-targeted ads (soft match for v1).
    }
    out.add(ad);
  }
  return out;
}
