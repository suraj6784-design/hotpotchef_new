import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../utils/app_theme.dart';

/// Diner-facing sponsored strip (third-party advertising framework v1).
class SponsoredPlacementBanner extends StatefulWidget {
  const SponsoredPlacementBanner({
    super.key,
    this.destinationLat,
    this.destinationLng,
    this.cityHint,
    this.dense = false,
  });

  final double? destinationLat;
  final double? destinationLng;
  final String? cityHint;
  final bool dense;

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
    final uri = sponsoredCtaUri(ad['cta_url']?.toString());
    if (uri == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This ad has no working link yet.')),
      );
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open ${uri.host}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || _ads.isEmpty) return const SizedBox.shrink();
    final ad = _ads.first;
    final title = (ad['title'] ?? 'Sponsored').toString();
    final body = (ad['body'] ?? '').toString().trim();
    final cta = (ad['cta_label'] ?? 'Learn more').toString();
    final image = (ad['image_url'] ?? '').toString().trim();
    final video = (ad['video_url'] ?? '').toString().trim();
    final advertiser = (ad['advertiser_name'] ?? '').toString().trim();

    final card = Padding(
      padding: widget.dense ? EdgeInsets.zero : const EdgeInsets.fromLTRB(16, 2, 16, 6),
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
              padding: EdgeInsets.all(widget.dense ? 10 : 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SponsoredMedia(
                    imageUrl: image,
                    videoUrl: widget.dense ? '' : video,
                    size: widget.dense ? 52 : 72,
                  ),
                  SizedBox(width: widget.dense ? 8 : 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Sponsored', style: AppTheme.homeKickerOf(context)),
                        if (advertiser.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            advertiser,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.metaOf(context).copyWith(fontSize: 11),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          title,
                          maxLines: widget.dense ? 2 : 3,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.homeCardTitleOf(context),
                        ),
                        if (!widget.dense && body.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.metaOf(context).copyWith(fontSize: 12, fontWeight: FontWeight.w500),
                          ),
                        ],
                        if (widget.dense) const Spacer() else const SizedBox(height: 8),
                        Text(cta, style: AppTheme.homeKickerOf(context)),
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
    if (widget.dense) return SizedBox.expand(child: card);
    return card;
  }
}

class _SponsoredMedia extends StatefulWidget {
  const _SponsoredMedia({
    required this.imageUrl,
    required this.videoUrl,
    this.size = 72,
  });

  final String imageUrl;
  final String videoUrl;
  final double size;

  @override
  State<_SponsoredMedia> createState() => _SponsoredMediaState();
}

class _SponsoredMediaState extends State<_SponsoredMedia> {
  VideoPlayerController? _clip;

  @override
  void initState() {
    super.initState();
    unawaited(_boot());
  }

  @override
  void didUpdateWidget(covariant _SponsoredMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl) {
      unawaited(_boot());
    }
  }

  Future<void> _boot() async {
    await _clip?.dispose();
    _clip = null;
    final url = widget.videoUrl.trim();
    if (url.isEmpty) {
      if (mounted) setState(() {});
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final controller = VideoPlayerController.networkUrl(uri);
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _clip = controller);
    } catch (_) {
      await controller.dispose();
      if (mounted) setState(() => _clip = null);
    }
  }

  @override
  void dispose() {
    _clip?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clip = _clip;
    if (clip != null && clip.value.isInitialized) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: clip.value.size.width,
              height: clip.value.size.height,
              child: IgnorePointer(child: VideoPlayer(clip)),
            ),
          ),
        ),
      );
    }
    if (widget.imageUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          widget.imageUrl,
          width: widget.size,
          height: widget.size,
          fit: BoxFit.cover,
          errorBuilder: (_, error, stack) => _placeholderThumb(widget.size),
        ),
      );
    }
    return _placeholderThumb(widget.size);
  }
}

Widget _placeholderThumb([double size = 72]) {
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: AppTheme.primary.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
    ),
    child: const Icon(Icons.campaign_outlined, color: AppTheme.primary),
  );
}

/// Turns stored CTA text into a launchable https URL.
Uri? sponsoredCtaUri(String? raw) {
  var text = (raw ?? '').trim();
  if (text.isEmpty) return null;
  if (text.startsWith('//')) text = 'https:$text';
  if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(text)) {
    text = 'https://$text';
  }
  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  return uri;
}

bool campaignShowsInDaypart(Map<String, dynamic> ad, DateTime now) {
  final start = int.tryParse(ad['daily_start_minute']?.toString() ?? '');
  final end = int.tryParse(ad['daily_end_minute']?.toString() ?? '');
  if (start == null && end == null) return true;
  final local = now.toLocal();
  final mins = local.hour * 60 + local.minute;
  final from = (start ?? 0).clamp(0, 1439);
  final to = (end ?? 1440).clamp(0, 1440);
  if (from == to) return true;
  if (from < to) return mins >= from && mins < to;
  return mins >= from || mins < to;
}

/// Filters live campaigns for overall vs targeted reach.
List<Map<String, dynamic>> liveSponsoredCampaigns(
  Iterable<Map<String, dynamic>> rows, {
  String? cityHint,
  DateTime? now,
}) {
  final clock = now ?? DateTime.now();
  final utc = clock.toUtc();
  final city = (cityHint ?? '').trim().toLowerCase();
  final out = <Map<String, dynamic>>[];

  for (final raw in rows) {
    final ad = Map<String, dynamic>.from(raw);
    if ((ad['status']?.toString().toLowerCase() ?? '') != 'live') continue;
    final starts = DateTime.tryParse(ad['starts_at']?.toString() ?? '');
    final ends = DateTime.tryParse(ad['ends_at']?.toString() ?? '');
    if (starts != null && starts.toUtc().isAfter(utc)) continue;
    if (ends != null && !ends.toUtc().isAfter(utc)) continue;
    if (!campaignShowsInDaypart(ad, clock)) continue;

    final mode = (ad['reach_mode']?.toString().toLowerCase() ?? 'overall').trim();
    if (mode == 'targeted') {
      final adCity = (ad['city']?.toString() ?? '').trim().toLowerCase();
      if (adCity.isEmpty) continue;
      if (city.isNotEmpty && adCity != city) continue;
    }
    out.add(ad);
  }
  return out;
}
