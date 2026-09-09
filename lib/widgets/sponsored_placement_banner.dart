import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../utils/app_theme.dart';

class SponsoredFlashSlide {
  const SponsoredFlashSlide({
    required this.ad,
    required this.stillUrl,
    required this.clipUrl,
  });

  final Map<String, dynamic> ad;
  final String stillUrl;
  final String clipUrl;
}

/// Diner-facing sponsored strip. Live campaigns rotate like kitchen offers.
/// A campaign with both a still and a clip gets two slides so the still is not hidden.
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

class _SponsoredPlacementBannerState extends State<SponsoredPlacementBanner>
    with TickerProviderStateMixin {
  List<SponsoredFlashSlide> _slides = const [];
  bool _ready = false;
  late final PageController _pageController;
  late final AnimationController _blink;
  Timer? _rotate;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.92);
    _blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant SponsoredPlacementBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cityHint != widget.cityHint) {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _rotate?.cancel();
    _pageController.dispose();
    _blink.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await Supabase.instance.client
          .from('ad_campaigns')
          .select()
          .eq('status', 'live')
          .order('updated_at', ascending: false)
          .limit(40);
      if (!mounted) return;
      final ads = liveSponsoredCampaigns(
        List<Map<String, dynamic>>.from(rows as List),
        cityHint: widget.cityHint,
      );
      setState(() {
        _slides = sponsoredFlashSlides(ads);
        _ready = true;
      });
      _syncRotation(_slides.length);
    } catch (_) {
      if (mounted) setState(() => _ready = true);
    }
  }

  void _syncRotation(int count) {
    _rotate?.cancel();
    _rotate = null;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (count < 2 || reduce) return;
    _rotate = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_pageController.hasClients || _slides.length < 2) return;
      final next = (_page + 1) % _slides.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeOutCubic,
      );
    });
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
    if (!_ready || _slides.isEmpty) return const SizedBox.shrink();
    final current = _page % _slides.length;

    if (widget.dense) {
      return SizedBox.expand(
        child: _SponsoredFlashCard(
          slide: _slides[current],
          playing: true,
          dense: true,
          onTap: () => _open(_slides[current].ad),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 2, 0, 6),
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
                      color: AppTheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('Sponsored', style: AppTheme.homeSectionLabelOf(context)),
              ],
            ),
          ),
          SizedBox(
            height: 132,
            child: PageView.builder(
              controller: _pageController,
              itemCount: _slides.length,
              onPageChanged: (index) => setState(() => _page = index),
              itemBuilder: (context, index) {
                final slide = _slides[index];
                return _SponsoredFlashCard(
                  slide: slide,
                  playing: index == current,
                  dense: false,
                  onTap: () => _open(slide.ad),
                );
              },
            ),
          ),
          if (_slides.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _slides.length; i++)
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

class _SponsoredFlashCard extends StatelessWidget {
  const _SponsoredFlashCard({
    required this.slide,
    required this.playing,
    required this.dense,
    required this.onTap,
  });

  final SponsoredFlashSlide slide;
  final bool playing;
  final bool dense;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ad = slide.ad;
    final title = (ad['title'] ?? 'Sponsored').toString();
    final body = (ad['body'] ?? '').toString().trim();
    final cta = (ad['cta_label'] ?? 'Learn more').toString();
    final advertiser = (ad['advertiser_name'] ?? '').toString().trim();

    return Container(
      margin: dense ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [
                  AppTheme.primary.withValues(alpha: 0.18),
                  AppTheme.accent.withValues(alpha: 0.12),
                ],
              ),
              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.22)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _SponsoredMedia(
                    imageUrl: slide.stillUrl,
                    videoUrl: slide.clipUrl,
                    playing: playing,
                    fill: true,
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Colors.black.withValues(alpha: 0.62),
                          Colors.black.withValues(alpha: 0.28),
                          Colors.black.withValues(alpha: 0.08),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.all(dense ? 10 : 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (advertiser.isNotEmpty)
                          Text(
                            advertiser.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.86),
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.7,
                            ),
                          ),
                        const SizedBox(height: 4),
                        Text(
                          title,
                          maxLines: dense ? 2 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            height: 1.15,
                          ),
                        ),
                        if (!dense && body.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                        const Spacer(),
                        Text(
                          cta,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
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
}

class _SponsoredMedia extends StatefulWidget {
  const _SponsoredMedia({
    required this.imageUrl,
    required this.videoUrl,
    this.size = 72,
    this.playing = true,
    this.fill = false,
  });

  final String imageUrl;
  final String videoUrl;
  final double size;
  final bool playing;
  final bool fill;

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
      return;
    }
    unawaited(_syncPlayback());
  }

  Future<void> _syncPlayback() async {
    final clip = _clip;
    if (clip == null || !clip.value.isInitialized) return;
    if (widget.playing) {
      await clip.play();
    } else {
      await clip.pause();
    }
  }

  Future<void> _boot() async {
    await _clip?.dispose();
    _clip = null;
    final url = widget.videoUrl.trim();
    if (url.isEmpty || looksLikeImageUrl(url)) {
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
      if (widget.playing) await controller.play();
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

  Widget _frame(Widget child) {
    if (widget.fill) return SizedBox.expand(child: child);
    return SizedBox(width: widget.size, height: widget.size, child: child);
  }

  @override
  Widget build(BuildContext context) {
    final clip = _clip;
    if (clip != null && clip.value.isInitialized && widget.imageUrl.trim().isEmpty) {
      return _frame(
        FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: clip.value.size.width,
            height: clip.value.size.height,
            child: IgnorePointer(child: VideoPlayer(clip)),
          ),
        ),
      );
    }
    if (widget.imageUrl.isNotEmpty) {
      return _frame(
        CachedNetworkImage(
          imageUrl: widget.imageUrl,
          fit: BoxFit.cover,
          width: widget.fill ? double.infinity : widget.size,
          height: widget.fill ? double.infinity : widget.size,
          errorWidget: (_, error, stack) => _placeholderThumb(widget.fill ? 72 : widget.size),
          placeholder: (_, url) => _placeholderThumb(widget.fill ? 72 : widget.size),
        ),
      );
    }
    return _frame(_placeholderThumb(widget.fill ? 72 : widget.size));
  }
}

Widget _placeholderThumb([double size = 72]) {
  return ColoredBox(
    color: AppTheme.primary.withValues(alpha: 0.18),
    child: SizedBox(
      width: size,
      height: size,
      child: const Icon(Icons.campaign_outlined, color: Colors.white),
    ),
  );
}

final _kVideoExt = RegExp(r'\.(mp4|webm|mov|m4v|avi)(\?|#|$)', caseSensitive: false);
final _kImageExt = RegExp(r'\.(png|jpe?g|webp|gif|heic|heif|bmp)(\?|#|$)', caseSensitive: false);

bool looksLikeVideoUrl(String raw) => _kVideoExt.hasMatch(raw.trim());

bool looksLikeImageUrl(String raw) => _kImageExt.hasMatch(raw.trim());

/// Splits stored still/clip fields when an image was saved into `video_url` (or vice versa).
({String still, String clip}) sponsoredCreativeUrls({
  String? imageUrl,
  String? videoUrl,
}) {
  var still = (imageUrl ?? '').trim();
  var clip = (videoUrl ?? '').trim();

  if (clip.isNotEmpty && looksLikeImageUrl(clip) && !looksLikeVideoUrl(clip)) {
    if (still.isEmpty) still = clip;
    clip = '';
  }
  if (still.isNotEmpty && looksLikeVideoUrl(still) && !looksLikeImageUrl(still)) {
    if (clip.isEmpty) clip = still;
    still = '';
  }
  return (still: still, clip: clip);
}

/// One diner slide per still, plus a separate slide for a clip so stills stay visible.
List<SponsoredFlashSlide> sponsoredFlashSlides(Iterable<Map<String, dynamic>> ads) {
  final out = <SponsoredFlashSlide>[];
  for (final raw in ads) {
    final ad = Map<String, dynamic>.from(raw);
    final creative = sponsoredCreativeUrls(
      imageUrl: ad['image_url']?.toString(),
      videoUrl: ad['video_url']?.toString(),
    );
    if (creative.still.isNotEmpty) {
      out.add(SponsoredFlashSlide(ad: ad, stillUrl: creative.still, clipUrl: ''));
    }
    if (creative.clip.isNotEmpty) {
      out.add(SponsoredFlashSlide(ad: ad, stillUrl: '', clipUrl: creative.clip));
    }
    if (creative.still.isEmpty && creative.clip.isEmpty) {
      out.add(SponsoredFlashSlide(ad: ad, stillUrl: '', clipUrl: ''));
    }
  }
  return out;
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
