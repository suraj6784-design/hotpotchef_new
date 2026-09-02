// lib/widgets/app_status_badge.dart

import 'package:flutter/material.dart';

import '../utils/app_theme.dart';

class AppStatusBadge extends StatelessWidget {
  final String status;

  const AppStatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lowerStatus = status.toLowerCase();

    Color baseColor;
    IconData iconData;

    if (lowerStatus.contains('pending')) {
      baseColor = AppTheme.warning;
      iconData = Icons.hourglass_top_rounded;
    } else if (lowerStatus.contains('confirm') || lowerStatus.contains('preparing')) {
      baseColor = AppTheme.info;
      iconData = Icons.soup_kitchen_rounded;
    } else if (lowerStatus.contains('ready') || lowerStatus.contains('out for delivery')) {
      baseColor = AppTheme.primary;
      iconData = Icons.local_shipping_rounded;
    } else if (lowerStatus.contains('deliver') || lowerStatus.contains('complet')) {
      baseColor = AppTheme.success;
      iconData = Icons.check_circle_rounded;
    } else if (lowerStatus.contains('cancel') || lowerStatus.contains('reject')) {
      baseColor = AppTheme.error;
      iconData = Icons.cancel_rounded;
    } else {
      baseColor = AppTheme.textMuted;
      iconData = Icons.info_outline_rounded;
    }

    final bgColor = isDark ? baseColor.withValues(alpha: 0.2) : baseColor.withValues(alpha: 0.12);
    final hsl = HSLColor.fromColor(baseColor);
    final textColor = isDark
        ? hsl.withLightness((hsl.lightness + 0.32).clamp(0.0, 1.0)).toColor()
        : hsl.withLightness((hsl.lightness - 0.28).clamp(0.0, 1.0)).toColor();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: baseColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconData, size: 14, color: textColor),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              status,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w700,
                fontSize: 11.5,
                letterSpacing: 0.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}