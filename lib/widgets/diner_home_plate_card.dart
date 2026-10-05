import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../utils/app_theme.dart';

/// One plate on the diner home. Photo, name, and price stay easy to scan.
class DinerHomePlateCard extends StatelessWidget {
  const DinerHomePlateCard({
    super.key,
    required this.title,
    required this.chefName,
    required this.priceLabel,
    this.prepMinutes = 0,
    this.portionsLabel,
    this.portionsUrgent = false,
    this.imageUrl,
    this.strikePriceLabel,
    this.offerBadge,
    this.footer,
    this.onTap,
  });

  final String title;
  final String chefName;
  final String priceLabel;
  final int prepMinutes;
  final String? portionsLabel;
  final bool portionsUrgent;
  final String? imageUrl;
  final String? strikePriceLabel;
  final String? offerBadge;
  final Widget? footer;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final photo = imageUrl?.trim() ?? '';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppTheme.radiusLg,
        child: Ink(
          decoration: AppTheme.cardDecoration(isDark: isDark),
          padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
          child: Row(
            children: [
              _photo(photo, offerBadge),
              const SizedBox(width: 14),
              Expanded(child: _copy(context)),
              const SizedBox(width: 10),
              _price(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _photo(String photo, String? badge) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        width: 92,
        height: 92,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (photo.isEmpty)
              ColoredBox(
                color: AppTheme.photoFallback,
                child: Icon(Icons.ramen_dining, color: AppTheme.textMuted),
              )
            else
              CachedNetworkImage(imageUrl: photo, fit: BoxFit.cover),
            if (badge != null && badge.isNotEmpty)
              Positioned(
                left: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    badge,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _copy(BuildContext context) {
    final portions = portionsLabel?.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.cardTitleOf(context),
        ),
        const SizedBox(height: 6),
        Text.rich(
          TextSpan(
            style: AppTheme.captionOf(context),
            children: [
              TextSpan(text: chefName),
              if (prepMinutes > 0) TextSpan(text: ' · $prepMinutes min'),
              if (portions.isNotEmpty)
                TextSpan(
                  text: ' · $portions',
                  style: portionsUrgent
                      ? AppTheme.captionOf(context).copyWith(
                          color: AppTheme.error,
                          fontWeight: FontWeight.w700,
                        )
                      : null,
                ),
            ],
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (footer != null) ...[const SizedBox(height: 6), footer!],
      ],
    );
  }

  Widget _price(BuildContext context) {
    final strike = strikePriceLabel?.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (strike.isNotEmpty)
          Text(
            strike,
            style: AppTheme.captionOf(context).copyWith(
              decoration: TextDecoration.lineThrough,
              fontWeight: FontWeight.w600,
            ),
          ),
        Text(
          priceLabel,
          style: AppTheme.priceOf(
            context,
          ).copyWith(fontSize: 18, color: AppTheme.linkOf(context)),
        ),
      ],
    );
  }
}
