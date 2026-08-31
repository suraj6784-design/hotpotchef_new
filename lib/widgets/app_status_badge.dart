// lib/widgets/app_status_badge.dart

import 'package:flutter/material.dart';

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
      baseColor = Colors.orange;
      iconData = Icons.hourglass_top_rounded;
    } else if (lowerStatus.contains('confirm') || lowerStatus.contains('preparing')) {
      baseColor = Colors.blue;
      iconData = Icons.soup_kitchen_rounded;
    } else if (lowerStatus.contains('ready') || lowerStatus.contains('out for delivery')) {
      baseColor = Colors.purple;
      iconData = Icons.local_shipping_rounded;
    } else if (lowerStatus.contains('deliver') || lowerStatus.contains('complet')) {
      baseColor = Colors.green;
      iconData = Icons.check_circle_rounded;
    } else if (lowerStatus.contains('cancel') || lowerStatus.contains('reject')) {
      baseColor = Colors.redAccent;
      iconData = Icons.cancel_rounded;
    } else {
      baseColor = Colors.grey;
      iconData = Icons.info_outline_rounded;
    }

    final bgColor = isDark ? baseColor.withValues(alpha: 0.2) : baseColor.withValues(alpha: 0.1);
    final textColor = isDark ? baseColor.shade200 : baseColor.shade800;

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
                fontWeight: FontWeight.bold,
                fontSize: 12,
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