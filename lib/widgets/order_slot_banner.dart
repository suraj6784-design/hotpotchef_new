import 'dart:async';

import 'package:flutter/material.dart';

import '../utils/helpers.dart';

/// Slot row for a kitchen order card.
///
/// Confirmed orders that are still inside the prepare window already explain
/// that on this banner. Callers must not print [chefPrepGateHint] again under
/// Start Preparing.
List<Widget> chefKitchenOrderTiming({
  required Map<String, dynamic> order,
  required bool isPending,
  required bool isPreparing,
  DateTime? now,
}) {
  final hint = isPending || isPreparing ? '' : chefPrepGateHint(order, now: now);
  return [
    OrderSlotBanner(
      order: order,
      hint: hint.isEmpty ? null : hint,
    ),
  ];
}

/// Requested delivery date/time plus a live countdown.
class OrderSlotBanner extends StatefulWidget {
  const OrderSlotBanner({super.key, required this.order, this.hint, this.diner = false});

  final Map<String, dynamic> order;
  final String? hint;
  final bool diner;

  @override
  State<OrderSlotBanner> createState() => _OrderSlotBannerState();
}

class _OrderSlotBannerState extends State<OrderSlotBanner> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(Duration(seconds: widget.diner ? 15 : 30), (_) {
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
    final start = orderPromisedAt(widget.order) ?? orderSlotStart(widget.order);
    final left = formatSlotCountdown(start);
    final late = dinerSlotIsLate(widget.order);
    final hint = (widget.hint ?? '').trim();
    final title = orderSlotBannerTitle(widget.order, diner: widget.diner);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: (late ? AppTheme.error : AppTheme.primary).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.schedule, size: 18, color: late ? AppTheme.error : AppTheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.onSurfaceOf(context)),
                ),
                if (left.isNotEmpty && left != title) ...[
                  const SizedBox(height: 2),
                  Text(
                    left,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: late ? AppTheme.error : AppTheme.linkOf(context),
                    ),
                  ),
                ],
                if (widget.diner && dinerLateOrderCopy(widget.order).isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    dinerLateOrderCopy(widget.order),
                    style: const TextStyle(fontSize: 11, color: AppTheme.error, fontWeight: FontWeight.w700),
                  ),
                ],
                if (hint.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(hint, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w600)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
