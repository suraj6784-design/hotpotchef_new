import 'package:flutter/material.dart';

import '../services/order_lifecycle.dart';
import '../utils/app_theme.dart';

/// Accept → packed → rider → delivered, shown from the first kitchen status.
class DinerOrderProgress extends StatelessWidget {
  const DinerOrderProgress({super.key, required this.status, this.compact = false});

  final String? status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final step = OrderLifecycle.dinerProgressStep(status);
    if (step < 0) return const SizedBox.shrink();
    final labels = OrderLifecycle.dinerProgressLabels;
    final ink = AppTheme.onSurfaceOf(context);
    final muted = AppTheme.textMutedOf(context);
    return Semantics(
      label: 'Order status ${labels[step.clamp(0, labels.length - 1)]}',
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0)
              Expanded(
                child: Container(
                  height: 2,
                  color: i <= step ? AppTheme.primary : AppTheme.hairlineOf(context),
                ),
              ),
            Column(
              children: [
                Container(
                  width: compact ? 10 : 12,
                  height: compact ? 10 : 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < step
                        ? AppTheme.primary
                        : i == step
                            ? AppTheme.primary
                            : AppTheme.hairlineOf(context),
                    border: i == step
                        ? Border.all(color: AppTheme.primary, width: 3)
                        : null,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  labels[i],
                  style: TextStyle(
                    fontSize: compact ? 9 : 10,
                    fontWeight: i == step ? FontWeight.w800 : FontWeight.w600,
                    color: i <= step ? ink : muted,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
