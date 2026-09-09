import 'dart:async';

import 'package:flutter/material.dart';

import '../utils/helpers.dart';

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
    final slot = formatDeliverySlotLabel(widget.order);
    final start = orderSlotStart(widget.order);
    final left = formatSlotCountdown(start);
    final late = dinerSlotIsLate(widget.order);
    final hint = (widget.hint ?? '').trim();
    final title = widget.diner
        ? (slot == 'ASAP' ? 'Promised ASAP' : 'Promised $slot')
        : (slot == 'ASAP' ? 'Requested ASAP' : 'Requested $slot');

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
