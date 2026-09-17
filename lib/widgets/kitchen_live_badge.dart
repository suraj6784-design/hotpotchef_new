import 'package:flutter/material.dart';

import 'app_widgets.dart';

/// Small chip for a fresh kitchen photo (not real-time video).
class KitchenLiveBadge extends StatelessWidget {
  const KitchenLiveBadge({super.key, this.compact = true});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Fresh kitchen photo',
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 10, vertical: compact ? 3 : 6),
        decoration: BoxDecoration(
          color: Colors.red.shade700,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
            Text(
              'FRESH',
              style: TextStyle(
                color: Colors.white,
                fontSize: compact ? 9 : 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ).successPulse(),
    );
  }
}
