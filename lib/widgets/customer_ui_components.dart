// lib/widgets/customer_ui_components.dart

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/kitchen_live_badge.dart';

import '../utils/helpers.dart';
import '../utils/app_page.dart';
import '../utils/app_theme.dart';
import '../utils/pricing_calculator.dart';
import '../models/cart_enums.dart';
import '../providers/cart_provider.dart';
import '../providers/kitchen_follows_provider.dart';
import '../services/chef_directory.dart';
import '../services/reorder_service.dart';
import 'weekly_plan_sheet.dart';
import '../screens/auth_screen.dart';
import 'app_widgets.dart';

Future<void> shareMealOnWhatsApp(Map<String, dynamic> meal) async {
  final text = mealShareText(meal);
  final opened = await launchUrl(mealWhatsAppShareUri(text), mode: LaunchMode.externalApplication);
  if (!opened) {
    await SharePlus.instance.share(ShareParams(text: text));
  }
}

Future<void> shareTextOnWhatsApp(String text) async {
  final opened = await launchUrl(mealWhatsAppShareUri(text), mode: LaunchMode.externalApplication);
  if (!opened) {
    await SharePlus.instance.share(ShareParams(text: text));
  }
}

Future<void> shareTextWithApps(String text) {
  return SharePlus.instance.share(ShareParams(text: text));
}

/// Preview with a tappable HTTPS meal link (opens in-app meal screen).
Widget shareCardPreview(BuildContext context, String text) {
  final match = RegExp(r'https://[^\s]+').firstMatch(text);
  if (match == null) {
    return SelectableText(
      text,
      style: const TextStyle(fontSize: 13, height: 1.35, color: AppTheme.textMuted),
    );
  }
  final before = text.substring(0, match.start);
  final link = match.group(0)!;
  final after = text.substring(match.end);
  return SelectableText.rich(
    TextSpan(
      style: const TextStyle(fontSize: 13, height: 1.35, color: AppTheme.textMuted),
      children: [
        TextSpan(text: before),
        TextSpan(
          text: link,
          style: const TextStyle(
            color: AppTheme.primary,
            decoration: TextDecoration.underline,
            fontWeight: FontWeight.w600,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              final uri = Uri.tryParse(link);
              if (uri == null) return;
              final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
              final mealIdx = segments.indexOf('meal');
              final mealId = mealIdx >= 0 && mealIdx + 1 < segments.length
                  ? segments[mealIdx + 1]
                  : (segments.isNotEmpty ? segments.last : '');
              if (mealId.isEmpty) return;
              context.push('/meal/$mealId');
            },
        ),
        TextSpan(text: after),
      ],
    ),
  );
}

Future<void> showMealShareSheet(BuildContext context, Map<String, dynamic> meal) {
  final text = mealShareText(meal);
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      decoration: AppTheme.bottomSheetDecoration(isDark: isDark),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Share this dish', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppTheme.onSurfaceOf(ctx))),
              const SizedBox(height: 8),
              shareCardPreview(ctx, text),
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  shareTextWithApps(text);
                },
                icon: const Icon(Icons.ios_share_rounded),
                label: const Text('Share · WhatsApp, Instagram…', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: text));
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                icon: const Icon(Icons.copy_outlined),
                label: const Text('Copy card', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> showPlateShareSheet(
  BuildContext context, {
  required List<Map<String, dynamic>> items,
  String? chefId,
  String? chefNameHint,
}) async {
  if (items.isEmpty) return;
  final hint = items.first;
  final chefIdResolved = (chefId ?? hint['chef_id'] ?? hint['chefId'])?.toString();
  final chefName = await lookupChefDisplayName(chefIdResolved, hint: {
    ...hint,
    if (chefNameHint != null && chefNameHint.trim().isNotEmpty) 'chef_name': chefNameHint,
  });
  final fssai = plateShareFssaiFromItems(items) ?? await lookupChefFssai(chefIdResolved);
  if (!context.mounted) return;
  final text = plateShareText(chefName: chefName, items: items, fssai: fssai);

  final isDark = Theme.of(context).brightness == Brightness.dark;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      decoration: AppTheme.bottomSheetDecoration(isDark: isDark),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Share your plate',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppTheme.onSurfaceOf(ctx)),
              ),
              const SizedBox(height: 4),
              const Text(
                'Share who cooked it — and the FSSAI number when the kitchen has listed one. The link opens this dish in HotPotChef.',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 10),
              shareCardPreview(ctx, text),
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  shareTextWithApps(text);
                },
                icon: const Icon(Icons.ios_share_rounded),
                label: const Text('Share · WhatsApp, Instagram…', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: text));
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                icon: const Icon(Icons.copy_outlined),
                label: const Text('Copy card', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class DispatchPackedPhoto extends StatelessWidget {
  const DispatchPackedPhoto({
    super.key,
    required this.url,
    this.height = 160,
    this.caption = 'Your box is packed',
  });

  final String url;
  final double height;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppTheme.radiusMd,
      child: Stack(
        children: [
          CachedNetworkImage(
            imageUrl: url,
            width: double.infinity,
            height: height,
            fit: BoxFit.cover,
            errorWidget: (_, _, _) => SizedBox(
              height: height,
              child: const Center(child: Icon(Icons.inventory_2_outlined)),
            ),
          ),
          Positioned(
            left: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: AppTheme.radiusSm,
              ),
              child: Text(
                caption,
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 1. High-Performance Watermarked Image Widget
class WatermarkedMealImage extends StatelessWidget {
  final String? imageUrl;
  final double width;
  final double height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  const WatermarkedMealImage({
    super.key,
    required this.imageUrl,
    this.width = double.infinity,
    this.height = 120,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: Container(
        width: width,
        height: height,
        color: isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade200,
        child: Stack(
          fit: StackFit.expand,
          children: [
            imageUrl != null && imageUrl!.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: imageUrl!,
                    fit: fit,
                    placeholder: (context, url) => Container(
                      color: isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade100,
                      child: const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
                        ),
                      ),
                    ),
                    errorWidget: (_, _, _) => const Icon(Icons.restaurant, color: Colors.grey),
                  )
                : const Icon(Icons.restaurant, color: Colors.grey),
            const Positioned(
              bottom: 6,
              right: 6,
              child: Opacity(
                opacity: 0.7,
                child: AppLogo(size: 22),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 2. Status Badge Helper
Widget buildStatusBadge(String status) {
  Color color = Colors.orange;
  final s = status.toLowerCase();
  if (s.contains('deliver') || s.contains('complet') || s.contains('confirm')) {
    color = Colors.green;
  } else if (s.contains('cancel') || s.contains('reject')) {
    color = Colors.redAccent;
  } else if (s.contains('out') || s.contains('ready')) {
    color = Colors.teal;
  }
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: AppTheme.radiusSm,
    ),
    child: Text(
      status.toUpperCase(),
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
    ),
  );
}

// 3. Unread Chat Indicator Widget
class UnreadChatIndicator extends StatelessWidget {
  final String mealId;
  final bool hasUnread;

  const UnreadChatIndicator({super.key, required this.mealId, this.hasUnread = false});

  @override
  Widget build(BuildContext context) {
    if (!hasUnread) return const SizedBox.shrink();
    return Container(
      width: 8,
      height: 8,
      decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
    );
  }
}

// 4. Promised slot countdown on diner orders
class DeliveryCountdownSticker extends StatefulWidget {
  final Map<String, dynamic>? order;
  final String? timeSlot;
  final String? status;
  final String? createdAt;
  final String? orderId;

  const DeliveryCountdownSticker({
    super.key,
    this.order,
    this.timeSlot,
    this.status,
    this.createdAt,
    this.orderId,
  });

  @override
  State<DeliveryCountdownSticker> createState() => _DeliveryCountdownStickerState();
}

class _DeliveryCountdownStickerState extends State<DeliveryCountdownSticker> {
  Timer? _tick;

  Map<String, dynamic> get _order => widget.order ??
      {
        'time_slot': widget.timeSlot,
        'status': widget.status,
        'created_at': widget.createdAt,
        'order_id': widget.orderId,
      };

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status ?? _order['status']?.toString();
    if (!dinerSlotCountdownActive(status)) return const SizedBox.shrink();

    final label = dinerPromisedSlotCopy(_order, status: status);
    if (label.isEmpty) return const SizedBox.shrink();
    final late = dinerSlotIsLate(_order);
    final color = late ? AppTheme.error : AppTheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer, size: 12, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// 5. Chef Profile Dialog
void showChefProfileDialog(BuildContext context, String chefId, String chefName, String fssai) {
  showDialog(
    context: context,
    builder: (ctx) => ChefProfilePeekDialog(
      chefId: chefId,
      chefName: chefName,
      fssai: fssai,
    ),
  );
}

class ChefProfilePeekDialog extends ConsumerStatefulWidget {
  const ChefProfilePeekDialog({
    super.key,
    required this.chefId,
    required this.chefName,
    required this.fssai,
  });

  final String chefId;
  final String chefName;
  final String fssai;

  @override
  ConsumerState<ChefProfilePeekDialog> createState() => _ChefProfilePeekDialogState();
}

final Map<String, ChefRatingSummary> _chefRatingCache = {};

class _ChefProfilePeekDialogState extends ConsumerState<ChefProfilePeekDialog> {

  bool _loading = true;
  String _name = '';
  String _fssai = '';
  String _fssaiStatus = '';
  String _city = '';
  String _memberSince = '';
  String _story = '';
  String _hygiene = '';
  String _cookedLabel = 'New kitchen';
  String _cardLocale = 'en';
  String _liveUrl = '';
  String _liveLabel = '';
  List<String> _photos = const [];
  ChefRatingSummary _rating = const ChefRatingSummary();
  List<Map<String, dynamic>> _recentReviews = const [];
  ChefCardCopy get _copy => chefCardCopy(_cardLocale);

  @override
  void initState() {
    super.initState();
    _name = widget.chefName;
    _fssai = widget.fssai;
    _loadChef();
  }

  Future<void> _loadChef() async {
    final chefId = widget.chefId.trim();
    if (chefId.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final cached = _chefRatingCache[chefId];
    if (cached != null) _rating = cached;

    try {
      final client = Supabase.instance.client;
      Map<String, dynamic>? profile;
      try {
        final row = await client
            .from('users')
            .select('name, full_name, fssai_number, fssai_verification_status, city, address, created_at')
            .eq('id', chefId)
            .maybeSingle();
        if (row != null) profile = Map<String, dynamic>.from(row);
      } catch (e, stack) {
        FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to load chef peek user row');
        try {
          final row = await client
              .from('users')
              .select('name, full_name, fssai_number, fssai_verification_status, created_at')
              .eq('id', chefId)
              .maybeSingle();
          if (row != null) profile = Map<String, dynamic>.from(row);
        } catch (_) {}
      }

      List<dynamic> reviewRows = const [];
      try {
        reviewRows = await client
            .from('reviews')
            .select('rating, comment, created_at')
            .eq('chef_id', chefId)
            .order('created_at', ascending: false)
            .limit(20);
      } catch (e, stack) {
        FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to load chef peek reviews');
      }

      Map<String, dynamic>? kitchen;
      try {
        final row = await client
            .from('chef_profiles')
            .select('kitchen_story, hygiene_note, kitchen_photos, live_photo_url, live_photo_at, card_locale, local_kitchen_name')
            .eq('user_id', chefId)
            .maybeSingle();
        if (row != null) kitchen = Map<String, dynamic>.from(row);
      } catch (e, stack) {
        FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to load kitchen story');
        try {
          final row = await client
              .from('chef_profiles')
              .select('kitchen_story, hygiene_note, kitchen_photos, live_photo_url, live_photo_at, card_locale, local_kitchen_name')
              .eq('user_id', chefId)
              .maybeSingle();
          if (row != null) kitchen = Map<String, dynamic>.from(row);
        } catch (_) {}
      }

      var cooked = 0;
      try {
        final orders = await client.from('orders').select('status').eq('chef_id', chefId);
        cooked = cookedMealCountFromOrders(orders);
      } catch (e, stack) {
        FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to count cooked meals');
      }
      if (!mounted) return;

      final rating = chefRatingSummaryFromRows(reviewRows);
      _chefRatingCache[chefId] = rating;

      final cardLocale = normalizeChefCardLocale(kitchen?['card_locale']?.toString());
      final copy = chefCardCopy(cardLocale);
      final resolvedName = chefCardDisplayName({
        if (profile != null) ...profile,
        'name': widget.chefName,
        'local_kitchen_name': kitchen?['local_kitchen_name'],
        'card_locale': cardLocale,
      }, locale: cardLocale);
      final listedFssai = profile?['fssai_number']?.toString().trim() ?? '';
      final fssaiStatus = normalizeFssaiVerificationStatus(
        profile?['fssai_verification_status']?.toString(),
      );
      final city = kitchenStoryArea(
        city: profile?['city']?.toString(),
        address: profile?['address']?.toString(),
      );
      final joined = parseFlexibleDate(profile?['created_at']?.toString());
      final liveAt = DateTime.tryParse(kitchen?['live_photo_at']?.toString() ?? '');
      final liveUrl = kitchen?['live_photo_url']?.toString() ?? '';

      setState(() {
        _name = resolvedName;
        _cardLocale = cardLocale;
        if (listedFssai.isNotEmpty) _fssai = listedFssai;
        _fssaiStatus = fssaiStatus;
        _city = city;
        _memberSince = joined == null ? '' : formatAppDate(joined);
        _story = kitchen?['kitchen_story']?.toString().trim() ?? '';
        _hygiene = kitchen?['hygiene_note']?.toString().trim() ?? '';
        _photos = kitchenPhotosFrom(kitchen?['kitchen_photos']);
        _liveUrl = isKitchenLivePhotoFresh(liveAt) ? liveUrl : '';
        _liveLabel = kitchenLivePhotoLabel(liveAt);
        _cookedLabel = copy.cookedMeals(cooked);
        _rating = rating;
        _recentReviews = reviewRows
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .where((row) => (row['comment']?.toString().trim() ?? '').isNotEmpty)
            .take(2)
            .toList();
        _loading = false;
      });
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to load chef peek profile');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? AppTheme.textMainDark : AppTheme.textMain;
    final muted = isDark ? Colors.grey.shade400 : AppTheme.textMuted;

    return AlertDialog(
      shape: AppTheme.dialogShape,
      backgroundColor: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
      title: Row(
        children: [
          const CircleAvatar(backgroundColor: AppTheme.primary, child: Icon(Icons.person, color: Colors.white)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _name.isEmpty ? widget.chefName : _name,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: ink),
                ),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _liveUrl.isNotEmpty ? 'Live from the kitchen' : _copy.homeKitchen,
                        style: TextStyle(
                          fontSize: 12,
                          color: _liveUrl.isNotEmpty ? Colors.red.shade700 : muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (_cardLocale != 'en') ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.12),
                          borderRadius: AppTheme.radiusSm,
                        ),
                        child: Text(
                          chefCardLocaleLabel(_cardLocale),
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppTheme.primary),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (_liveUrl.isNotEmpty) const KitchenLiveBadge(compact: false),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Builder(
              builder: (context) {
                final verified = dinerFssaiIsVerified(_fssaiStatus);
                final status = normalizeFssaiVerificationStatus(_fssaiStatus);
                final trustLabel = verified
                    ? 'FSSAI verified home kitchen'
                    : dinerFssaiTrustLabel(
                        fssaiNumber: _fssai,
                        verificationStatus: _fssaiStatus,
                      );
                final Color trustColor;
                if (verified) {
                  trustColor = Colors.green;
                } else if (status == 'pending') {
                  trustColor = Colors.orange;
                } else {
                  trustColor = muted;
                }
                return Text(
                  trustLabel,
                  style: TextStyle(color: trustColor, fontWeight: FontWeight.bold, fontSize: 13),
                );
              },
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(minHeight: 2, color: AppTheme.primary),
              )
            else ...[
              Row(
                children: [
                  ...List.generate(5, (index) {
                    final filled = _rating.hasReviews && index < _rating.average.round();
                    return Icon(
                      filled ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                      size: 18,
                    );
                  }),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _rating.label,
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: ink),
                    ),
                  ),
                ],
              ),
              if (!_rating.hasReviews)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Be the first to rate this kitchen after an order.', style: TextStyle(fontSize: 12, color: muted)),
                ),
            ],
            if (_liveUrl.isNotEmpty) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: AppTheme.radiusMd,
                child: Stack(
                  children: [
                    CachedNetworkImage(
                      imageUrl: _liveUrl,
                      width: double.infinity,
                      height: 160,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => const SizedBox(height: 80, child: Center(child: Icon(Icons.kitchen))),
                    ),
                    Positioned(
                      left: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: AppTheme.radiusSm,
                        ),
                        child: Text(
                          _liveLabel.isEmpty ? 'Live from the kitchen' : _liveLabel,
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_photos.isNotEmpty) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 72,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _photos.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) => ClipRRect(
                    borderRadius: AppTheme.radiusSm,
                    child: CachedNetworkImage(
                      imageUrl: _photos[index],
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => const SizedBox(width: 72, height: 72, child: Icon(Icons.image)),
                    ),
                  ),
                ),
              ),
            ],
            if (_story.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(_story, style: TextStyle(fontSize: 13, height: 1.4, color: ink)),
            ],
            const SizedBox(height: 12),
            _infoRow(
              Icons.verified,
              _fssai.isNotEmpty ? '${_copy.fssaiListed}: $_fssai' : _copy.fssaiMissing,
              muted,
            ),
            const SizedBox(height: 8),
            _infoRow(Icons.soup_kitchen_outlined, _cookedLabel, muted),
            if (_hygiene.isNotEmpty) ...[
              const SizedBox(height: 8),
              _infoRow(Icons.clean_hands_outlined, _hygiene, muted),
            ],
            if (_city.isNotEmpty) ...[
              const SizedBox(height: 8),
              _infoRow(Icons.place_outlined, _city, muted),
            ],
            if (_memberSince.isNotEmpty) ...[
              const SizedBox(height: 8),
              _infoRow(Icons.calendar_month_outlined, '${_copy.partnerSince} $_memberSince', muted),
            ],
            if (_recentReviews.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(_copy.recentReviews, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: ink)),
              const SizedBox(height: 8),
              ..._recentReviews.map((review) {
                final stars = int.tryParse(review['rating']?.toString() ?? '') ?? 0;
                final comment = review['comment']?.toString().trim() ?? '';
                final when = formatOrderDate(review['created_at']?.toString());
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          ...List.generate(
                            5,
                            (index) => Icon(
                              index < stars ? Icons.star : Icons.star_border,
                              color: Colors.amber,
                              size: 12,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(when, style: TextStyle(fontSize: 10, color: muted)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text('"$comment"', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: ink)),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
        ),
      ),
      actions: [
        KitchenFollowButton(
          chefId: widget.chefId,
          chefName: _name.isEmpty ? widget.chefName : _name,
          locale: _cardLocale,
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _infoRow(IconData icon, String text, Color muted) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.blueAccent),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: muted))),
      ],
    );
  }
}

// 6. Fully Upgraded Decision-Making Meal Details Modal
Future<bool> confirmReplaceKitchenCart(BuildContext context) async {
  final replace = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.surfaceOf(ctx),
      shape: AppTheme.dialogShape,
      title: Text(
        'Different kitchen',
        style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.onSurfaceOf(ctx)),
      ),
      content: Text(
        'Your cart has dishes from another kitchen. Clear the cart and add this dish instead?',
        style: TextStyle(color: AppTheme.onSurfaceOf(ctx).withValues(alpha: 0.75)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Keep cart', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Clear & add'),
        ),
      ],
    ),
  );
  return replace == true;
}

/// Adds a dish, asking before mixing kitchens. Never reports success if the add failed.
Future<bool> addMealToCartWithConflict({
  required BuildContext context,
  required WidgetRef ref,
  required Map<String, dynamic> meal,
  int quantity = 1,
  List<CartItemAddOn> addOns = const [],
}) async {
  if (!isMealAvailableForCart(meal)) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This dish is no longer available.'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
    }
    return false;
  }

  try {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      final prefs = await Supabase.instance.client
          .from('users')
          .select('dietary_preference, allergies')
          .eq('id', user.id)
          .maybeSingle();
      final reason = dietSkipReason(
        meal,
        preference: prefs?['dietary_preference']?.toString(),
        allergies: prefs?['allergies']?.toString(),
      );
      if (reason != null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(reason), backgroundColor: Colors.orangeAccent),
          );
        }
        return false;
      }
    }
  } catch (_) {}

  try {
    final chefId = meal['chef_id']?.toString() ?? meal['chefId']?.toString() ?? '';
    if (chefId.isNotEmpty) {
      final kitchen = await Supabase.instance.client
          .from('chef_profiles')
          .select('is_open')
          .eq('user_id', chefId)
          .maybeSingle();
      if (!isChefKitchenOpen(kitchen)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('This kitchen is closed right now.'),
              backgroundColor: Colors.orangeAccent,
            ),
          );
        }
        return false;
      }
    }
  } catch (_) {}

  final cart = ref.read(cartProvider.notifier);
  final existingChef = ref.read(cartProvider).primaryChefId;
  final chefId = meal['chef_id']?.toString() ?? '';
  final added = cart.addToCart(meal, quantity, addOns: addOns, clearIfVendorConflict: false);
  if (added) return true;

  final isConflict = existingChef != null && existingChef.isNotEmpty && chefId.isNotEmpty && existingChef != chefId;
  if (!isConflict || !context.mounted) return false;

  final replace = await confirmReplaceKitchenCart(context);
  if (!replace || !context.mounted) return false;
  return cart.addToCart(meal, quantity, addOns: addOns, clearIfVendorConflict: true);
}

void showMealDetailsDialog(
  BuildContext context,
  Map<String, dynamic> meal,
  WidgetRef ref, {
  VoidCallback? onGoToCart,
}) {
  Navigator.push(
    context,
    appMaterialRoute(
      Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: MealDetailsBody(meal: meal, ref: ref, onGoToCart: onGoToCart),
      ),
    ),
  );
}

/// Consistent post-add snack that points diners to Cart.
void showAddedToCartSnack(
  BuildContext context, {
  String message = 'Added to cart',
  VoidCallback? onViewCart,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  SemanticsService.sendAnnouncement(
    View.of(context),
    message,
    TextDirection.ltr,
  );
  messenger.showSnackBar(
    SnackBar(
      content: Semantics(
        liveRegion: true,
        child: Text(message),
      ),
      backgroundColor: AppTheme.primary,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
      action: onViewCart == null
          ? null
          : SnackBarAction(
              label: 'View cart',
              textColor: Colors.white,
              onPressed: () {
                messenger.clearSnackBars();
                onViewCart();
              },
            ),
    ),
  );
}

/// Drop lingering “Added to cart” (and other) snacks when entering Cart / Checkout / Pay.
void dismissAppSnackBars(BuildContext context) {
  ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
}

Widget _mealInfoChip({
  required IconData icon,
  required String label,
  required String value,
  required Color background,
  required Color iconColor,
  required Color textColor,
}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: background,
      borderRadius: AppTheme.radiusMd,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textColor.withValues(alpha: 0.8)),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textColor, height: 1.3),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class MealDetailsBody extends StatefulWidget {
  final Map<String, dynamic> meal;
  final WidgetRef ref;
  final VoidCallback? onGoToCart;

  const MealDetailsBody({
    super.key,
    required this.meal,
    required this.ref,
    this.onGoToCart,
  });

  @override
  State<MealDetailsBody> createState() => _MealDetailsBodyState();
}

class _MealDetailsBodyState extends State<MealDetailsBody> {
  int _quantity = 1;
  final Set<String> _selectedAddOnIds = {};

  List<CartItemAddOn> get _availableAddOns => ReorderService.parseMealAddOns(
        widget.meal['add_ons'] ?? widget.meal['addons'] ?? widget.meal['selectedAddOns'],
      );

  List<CartItemAddOn> get _chosenAddOns =>
      _availableAddOns.where((addon) => _selectedAddOnIds.contains(addon.id)).toList();

  double get _addOnsUnitTotal =>
      _chosenAddOns.fold<double>(0, (sum, addon) => sum + addon.price);

  double get _lineFoodTotal =>
      PricingCalculator.effectiveItemTotal(widget.meal, _quantity) +
      (_addOnsUnitTotal * _quantity);

  @override
  Widget build(BuildContext context) {
    final meal = widget.meal;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final maxStock = int.tryParse(meal['quantity']?.toString() ?? '10') ?? 10;
    final offerSummary = PricingCalculator.calculateItemSummary(meal, _quantity);
    final price = offerSummary.effectiveUnitPrice;
    final chefName = chefDisplayName(meal);
    final chefId = meal['chef_id']?.toString() ?? '';
    final fssai = meal['fssai_number']?.toString() ?? '';
    final fssaiStatus = meal['fssai_verification_status']?.toString();
    final fssaiVerified = dinerFssaiIsVerified(fssaiStatus);
    final fssaiTrustLine = dinerFssaiTrustLabel(
      fssaiNumber: fssai,
      verificationStatus: fssaiStatus,
    );
    final serviceType = meal['service_type']?.toString() ?? 'Delivery, Pickup';
    final timeSlot = meal['time_slot']?.toString() ?? 'Available Today';

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Stack(
                  children: [
                    Hero(
                      tag: 'meal-image-${meal['id']}',
                      child: WatermarkedMealImage(
                        imageUrl: meal['image_url'],
                        height: 300,
                        borderRadius: BorderRadius.zero,
                      ),
                    ),
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 8,
                      left: 16,
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                          child: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              meal['title']?.toString() ?? 'Home Meal',
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                                color: isDark ? AppTheme.textMainDark : AppTheme.textMain,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              border: Border.all(color: meal['is_veg'] == true ? Colors.green : Colors.redAccent),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Icon(Icons.circle,
                                color: meal['is_veg'] == true ? Colors.green : Colors.redAccent, size: 10),
                          ),
                        ],
                      ),
                      if (isFestivalHamper(meal)) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withValues(alpha: 0.18),
                            borderRadius: AppTheme.radiusXl,
                            border: Border.all(color: AppTheme.accent.withValues(alpha: 0.45)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.card_giftcard_outlined, size: 14, color: AppTheme.primary),
                              SizedBox(width: 6),
                              Text(
                                'Festival hamper',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.primary),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (isSocietyNight(meal)) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.12),
                            borderRadius: AppTheme.radiusXl,
                            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.35)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.apartment_outlined, size: 14, color: AppTheme.primary),
                              const SizedBox(width: 6),
                              Text(
                                societyNightLabel(meal),
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
                      if (isShelfItem(meal)) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withValues(alpha: 0.14),
                            borderRadius: AppTheme.radiusXl,
                            border: Border.all(color: AppTheme.accent.withValues(alpha: 0.40)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.kitchen_outlined, size: 14, color: AppTheme.primary),
                              const SizedBox(width: 6),
                              Text(
                                shelfItemKind(meal),
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
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (offerSummary.isOfferApplied) ...[
                                Text(
                                  '₹${offerSummary.baseUnitPrice.toInt()}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: AppTheme.textMuted,
                                    decoration: TextDecoration.lineThrough,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                              ],
                              Text('₹${price.toInt()}',
                                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppTheme.primary)),
                              if (offerSummary.isOfferApplied &&
                                  (offerSummary.offerDescription ?? '').isNotEmpty)
                                Text(
                                  offerSummary.offerDescription!,
                                  style: TextStyle(
                                    color: Colors.red.shade700,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              if (PricingCalculator.mealPromoCode(meal) != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    PricingCalculator.hasPromoExtra(meal)
                                        ? 'Promo ${PricingCalculator.mealPromoCode(meal)} stacks extra off at checkout'
                                        : 'Enter promo ${PricingCalculator.mealPromoCode(meal)} at checkout to unlock this offer',
                                    style: const TextStyle(
                                      color: AppTheme.textMuted,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          MealRatingBadge(meal: meal),
                        ],
                      ),
                      const SizedBox(height: 24),
                      InkWell(
                        onTap: () => showChefProfileDialog(context, chefId, chefName, fssai),
                        borderRadius: AppTheme.radiusMd,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
                            borderRadius: AppTheme.radiusLg,
                            border: Border.all(color: AppTheme.hairlineOf(context)),
                            boxShadow: isDark ? [] : AppTheme.softShadow,
                          ),
                          child: Row(
                            children: [
                              const CircleAvatar(
                                  backgroundColor: AppTheme.primary,
                                  radius: 22,
                                  child: Icon(Icons.storefront, color: Colors.white, size: 22)),
                              const SizedBox(width: 16),
                              Expanded(
                                child: FutureBuilder<Map<String, dynamic>?>(
                                  future: chefId.isEmpty
                                      ? Future.value(null)
                                      : Supabase.instance.client
                                          .from('chef_profiles')
                                          .select('card_locale, local_kitchen_name')
                                          .eq('user_id', chefId)
                                          .maybeSingle(),
                                  builder: (context, snap) {
                                    final locale = normalizeChefCardLocale(snap.data?['card_locale']?.toString());
                                    final copy = chefCardCopy(locale);
                                    final shownName = chefCardDisplayName({
                                      'chef_name': chefName,
                                      'local_kitchen_name': snap.data?['local_kitchen_name'],
                                      'card_locale': locale,
                                    }, locale: locale);
                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                '${copy.preparedBy} $shownName',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                  color: isDark ? AppTheme.textMainDark : AppTheme.textMain,
                                                ),
                                              ),
                                            ),
                                            if (locale != 'en')
                                              Text(
                                                chefCardLocaleLabel(locale),
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w800,
                                                  color: AppTheme.primary,
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          fssai.isNotEmpty
                                              ? '$fssaiTrustLine • ${copy.tapForInfo}'
                                              : '${copy.fssaiMissing} • ${copy.tapForInfo}',
                                          style: TextStyle(
                                            color: fssaiVerified
                                                ? Colors.green
                                                : (isDark ? Colors.grey.shade400 : AppTheme.textMuted),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                              KitchenFollowButton(
                                chefId: chefId,
                                chefName: chefName,
                                compact: true,
                              ),
                              const Icon(Icons.chevron_right, color: Colors.grey),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _mealInfoChip(
                        icon: Icons.delivery_dining,
                        label: 'Delivery option',
                        value: serviceType,
                        background: isDark ? Colors.blue.shade900.withValues(alpha: 0.3) : Colors.blue.shade50,
                        iconColor: Colors.blueAccent,
                        textColor: isDark ? Colors.blue.shade200 : Colors.blue.shade800,
                      ),
                      const SizedBox(height: 10),
                      _mealInfoChip(
                        icon: Icons.access_time,
                        label: 'Time slots',
                        value: timeSlot,
                        background: isDark ? Colors.orange.shade900.withValues(alpha: 0.3) : Colors.orange.shade50,
                        iconColor: Colors.orangeAccent,
                        textColor: isDark ? Colors.orange.shade200 : Colors.orange.shade800,
                      ),
                      if (_availableAddOns.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Text('Customise',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: isDark ? AppTheme.textMainDark : AppTheme.textMain)),
                        const SizedBox(height: 10),
                        ..._availableAddOns.map((addon) {
                          final selected = _selectedAddOnIds.contains(addon.id);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: InkWell(
                              onTap: () => setState(() {
                                if (selected) {
                                  _selectedAddOnIds.remove(addon.id);
                                } else {
                                  _selectedAddOnIds.add(addon.id);
                                }
                              }),
                              borderRadius: AppTheme.radiusMd,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? AppTheme.primary.withValues(alpha: 0.1)
                                      : (isDark ? AppTheme.surfaceDark : AppTheme.surfaceMutedLight),
                                  borderRadius: AppTheme.radiusMd,
                                  border: Border.all(color: selected ? AppTheme.primary : AppTheme.hairlineOf(context)),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      selected ? Icons.check_circle : Icons.circle_outlined,
                                      color: selected ? AppTheme.primary : AppTheme.textMuted,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        addon.title,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: isDark ? AppTheme.textMainDark : AppTheme.textMain,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      addon.price > 0 ? '+₹${addon.price.toInt()}' : 'Free',
                                      style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.primary),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                      const SizedBox(height: 24),
                      Text('About this meal',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: isDark ? AppTheme.textMainDark : AppTheme.textMain)),
                      const SizedBox(height: 8),
                      Text(
                        meal['description']?.toString() ??
                            'Delicious home-cooked meal prepared with love and high hygiene standards.',
                        style: TextStyle(
                            color: isDark ? Colors.grey.shade400 : AppTheme.textMuted, fontSize: 14, height: 1.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Container(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 16,
            bottom: MediaQuery.of(context).padding.bottom > 0 ? MediaQuery.of(context).padding.bottom : 24,
          ),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
            boxShadow: AppTheme.heavyShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: AppTheme.hairlineOf(context)),
                      borderRadius: AppTheme.radiusLg,
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Decrease quantity',
                          icon: const Icon(Icons.remove, size: 20, color: AppTheme.primary),
                          onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
                        ),
                        Semantics(
                          liveRegion: true,
                          label: 'Quantity $_quantity',
                          child: Text('$_quantity',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: isDark ? AppTheme.textMainDark : AppTheme.textMain)),
                        ),
                        IconButton(
                          tooltip: 'Increase quantity',
                          icon: const Icon(Icons.add, size: 20, color: AppTheme.primary),
                          onPressed: _quantity < maxStock
                              ? () => setState(() => _quantity++)
                              : () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text('Only $maxStock portions available.'),
                                        backgroundColor: Colors.orangeAccent,
                                        behavior: SnackBarBehavior.floating),
                                  );
                                },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Semantics(
                      button: true,
                      enabled: isMealAvailableForCart(meal),
                      label: isMealAvailableForCart(meal)
                          ? 'Add $_quantity portions to cart'
                          : 'Meal sold out',
                      child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey.shade400,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        minimumSize: const Size(0, 48),
                        shape: const RoundedRectangleBorder(borderRadius: AppTheme.radiusLg),
                        elevation: 0,
                      ),
                      onPressed: !isMealAvailableForCart(meal)
                          ? null
                          : () async {
                              final added = await addMealToCartWithConflict(
                                context: context,
                                ref: widget.ref,
                                meal: meal,
                                quantity: _quantity,
                                addOns: _chosenAddOns,
                              );
                              if (!added || !context.mounted) return;
                              Navigator.pop(context);
                              showAddedToCartSnack(
                                context,
                                message: 'Added $_quantity portion(s) to cart',
                                onViewCart: widget.onGoToCart,
                              );
                            },
                      child: Text(
                        isMealAvailableForCart(meal)
                            ? 'Add to Cart • ₹${_lineFoodTotal.toInt()}'
                            : 'Sold out',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ).successPulse(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => showMealShareSheet(context, meal),
                  icon: const Icon(Icons.chat, size: 18),
                  label: const Text('WhatsApp card', style: TextStyle(fontWeight: FontWeight.w800)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF25D366),
                    side: const BorderSide(color: Color(0xFF25D366)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: const RoundedRectangleBorder(borderRadius: AppTheme.radiusLg),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => showWeeklyPlanSheet(
                    context: context,
                    ref: widget.ref,
                    meal: meal,
                    quantity: _quantity,
                  ),
                  icon: const Icon(Icons.event_repeat, size: 18),
                  label: const Text('Weekly plan', style: TextStyle(fontWeight: FontWeight.w800)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    side: const BorderSide(color: AppTheme.primary),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: const RoundedRectangleBorder(borderRadius: AppTheme.radiusLg),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class KitchenFollowButton extends ConsumerWidget {
  const KitchenFollowButton({
    super.key,
    required this.chefId,
    required this.chefName,
    this.compact = false,
    this.locale,
  });

  final String chefId;
  final String chefName;
  final bool compact;
  final String? locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (!canFollowKitchen(viewerId: userId, chefId: chefId) && userId != null) {
      return const SizedBox.shrink();
    }

    final following = ref.watch(kitchenFollowsProvider).contains(chefId);
    final copy = chefCardCopy(locale);

    Future<void> toggle() async {
      if (userId == null) {
        showAuthBottomSheet(
          context,
          () => ref.read(kitchenFollowsProvider.notifier).fetchFollows(),
          title: 'Sign in to follow kitchens',
          subtitle: 'We will ping you when this chef goes live.',
        );
        return;
      }
      final ok = await ref.read(kitchenFollowsProvider.notifier).toggleFollow(chefId);
      if (!context.mounted || !ok) return;
      final nowFollowing = ref.read(kitchenFollowsProvider).contains(chefId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nowFollowing
                ? 'Following $chefName. We will ping you when their kitchen opens.'
                : 'Unfollowed $chefName.',
          ),
        ),
      );
    }

    if (compact) {
      return IconButton(
        tooltip: following ? 'Following kitchen' : 'Follow kitchen',
        onPressed: toggle,
        icon: Icon(
          following ? Icons.notifications_active : Icons.notifications_none,
          color: following ? AppTheme.primary : Colors.grey,
        ),
      );
    }

    return TextButton.icon(
      onPressed: toggle,
      icon: Icon(following ? Icons.notifications_active : Icons.notifications_outlined, size: 18),
      label: Text(following ? copy.following : copy.followKitchen),
      style: TextButton.styleFrom(
        foregroundColor: AppTheme.primary,
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }
}

// 7. Streamlined Auth Flow
void showAuthBottomSheet(
  BuildContext context,
  VoidCallback onSuccess, {
  String? title,
  String? subtitle,
}) {
  showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (ctx) => AuthScreen(
      asSheet: true,
      sheetTitle: title,
      sheetSubtitle: subtitle,
    ),
  ).then((ok) {
    if (ok == true) onSuccess();
  });
}

// 8. Dynamic Meal Rating Badge
class MealRatingBadge extends StatefulWidget {
  final Map<String, dynamic> meal;
  const MealRatingBadge({super.key, required this.meal});

  @override
  State<MealRatingBadge> createState() => _MealRatingBadgeState();
}

class _MealRatingBadgeState extends State<MealRatingBadge> {
  ChefRatingSummary _summary = const ChefRatingSummary();

  @override
  void initState() {
    super.initState();
    _fetchRealRatings();
  }

  Future<void> _fetchRealRatings() async {
    final chefId = widget.meal['chef_id']?.toString() ?? '';
    if (chefId.isEmpty) return;

    final cached = _chefRatingCache[chefId];
    if (cached != null && mounted) {
      setState(() => _summary = cached);
      return;
    }

    try {
      final res = await Supabase.instance.client
          .from('reviews')
          .select('rating')
          .eq('chef_id', chefId);

      if (!mounted) return;
      final summary = chefRatingSummaryFromRows(res);
      _chefRatingCache[chefId] = summary;
      setState(() => _summary = summary);
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to fetch chef ratings');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.star, color: Colors.amber, size: 16),
        const SizedBox(width: 4),
        Text(
          _summary.hasReviews ? _summary.average.toStringAsFixed(1) : 'New',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: isDark ? AppTheme.textMainDark : AppTheme.textMain,
          ),
        ),
        if (_summary.hasReviews)
          Text(' (${_summary.count})',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey.shade400)),
      ],
    );
  }
}

// 9. Standardized Universal App Card (with tactile press feedback)
class AppCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? backgroundColor;
  final VoidCallback? onTap;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.only(bottom: 16),
    this.backgroundColor,
    this.onTap,
  });

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onTap == null) return;
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final card = AnimatedScale(
      scale: _pressed ? 0.97 : 1.0,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: Container(
        margin: widget.margin,
        padding: widget.padding,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: widget.backgroundColor ?? AppTheme.surfaceOf(context),
          borderRadius: AppTheme.radiusLg,
          boxShadow: isDark ? const [] : AppTheme.softShadow,
          border: Border.all(color: AppTheme.hairlineOf(context)),
        ),
        child: widget.child,
      ),
    );

    if (widget.onTap == null) return card;

    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      behavior: HitTestBehavior.opaque,
      child: card,
    );
  }
}