import 'package:flutter/material.dart';

import '../utils/app_theme.dart';
import 'app_widgets.dart';
import 'customer_ui_components.dart';

/// Compact diner Orders row. Collapsed it stays button-sized. Tap expands the
/// same details the oversized card used to show at once; tap again collapses.
class DinerOrderListCard extends StatefulWidget {
  const DinerOrderListCard({
    super.key,
    required this.orderIdLabel,
    required this.chefName,
    required this.lineLabel,
    required this.badgeLabel,
    this.badgeColor,
    required this.statusLine,
    required this.statusColor,
    required this.priceLabel,
    required this.orderType,
    required this.placedLabel,
    required this.slotLabel,
    this.occasionLabel = '',
    required this.addressLabel,
    required this.addressValue,
    required this.isPickup,
    this.moreItemsLabel,
    this.deliveryPin = '',
    this.dimmed = false,
    this.showReorder = false,
    this.showTrack = false,
    this.showHelp = false,
    this.helpTooltip = 'Help',
    this.onReorder,
    this.onTrack,
    this.onHelp,
    this.onOpenDetails,
  });

  final String orderIdLabel;
  final String chefName;
  final String lineLabel;
  final String? moreItemsLabel;
  final String badgeLabel;
  final Color? badgeColor;
  final String statusLine;
  final Color statusColor;
  final String priceLabel;
  final String orderType;
  final String placedLabel;
  final String slotLabel;
  final String occasionLabel;
  final String addressLabel;
  final String addressValue;
  final bool isPickup;
  final String deliveryPin;
  final bool dimmed;
  final bool showReorder;
  final bool showTrack;
  final bool showHelp;
  final String helpTooltip;
  final VoidCallback? onReorder;
  final VoidCallback? onTrack;
  final VoidCallback? onHelp;
  final VoidCallback? onOpenDetails;

  static const double collapsedHeight = 48;

  static Key toggleKey(String orderIdLabel) =>
      Key('diner-order-toggle-$orderIdLabel');

  @override
  State<DinerOrderListCard> createState() => _DinerOrderListCardState();
}

class _DinerOrderListCardState extends State<DinerOrderListCard> {
  bool _expanded = false;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final onSurface = AppTheme.onSurfaceOf(context);
    return AppCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: _expanded
          ? const EdgeInsets.all(16)
          : const EdgeInsets.symmetric(horizontal: 12),
      child: Opacity(
        opacity: widget.dimmed ? 0.6 : 1,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Material(
              color: Colors.transparent,
              child: Semantics(
                button: true,
                label: _expanded
                    ? 'Collapse order ${widget.orderIdLabel}'
                    : 'Expand order ${widget.orderIdLabel}',
                child: InkWell(
                  key: DinerOrderListCard.toggleKey(widget.orderIdLabel),
                  onTap: _toggle,
                  borderRadius: AppTheme.radiusSm,
                  child: SizedBox(
                    height: DinerOrderListCard.collapsedHeight,
                    child: Row(
                      children: [
                        Text(
                          widget.orderIdLabel,
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.lineLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 120),
                          child: _Badge(
                            label: widget.badgeLabel,
                            color: widget.badgeColor ?? AppTheme.primary,
                          ),
                        ),
                        Icon(
                          _expanded ? Icons.expand_less : Icons.expand_more,
                          color: AppTheme.textMuted,
                          size: 22,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_expanded) ...[
              const SizedBox(height: 12),
              Text(
                widget.chefName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: onSurface,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.lineLabel,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: onSurface,
                          ),
                        ),
                        if (widget.moreItemsLabel != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            widget.moreItemsLabel!,
                            style: const TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          widget.statusLine,
                          style: TextStyle(
                            color: widget.statusColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    widget.priceLabel,
                    style: TextStyle(
                      color: onSurface.withValues(alpha: 0.55),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(
                    Icons.local_shipping_outlined,
                    size: 14,
                    color: AppTheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text('Type: ', style: AppTheme.caption),
                  Text(
                    widget.orderType,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(
                    Icons.access_time,
                    size: 14,
                    color: AppTheme.textMuted,
                  ),
                  const SizedBox(width: 6),
                  Text('Placed: ', style: AppTheme.caption),
                  Flexible(
                    child: Text(
                      widget.placedLabel,
                      style: AppTheme.caption,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (widget.occasionLabel.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.celebration_outlined,
                      size: 14,
                      color: AppTheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text('Occasion: ', style: AppTheme.caption),
                    Flexible(
                      child: Text(
                        widget.occasionLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(
                    Icons.event_available,
                    size: 14,
                    color: Colors.green,
                  ),
                  const SizedBox(width: 6),
                  Text('Delivery Slot: ', style: AppTheme.caption),
                  Flexible(
                    child: Text(
                      widget.slotLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceOf(context),
                  borderRadius: AppTheme.radiusSm,
                  border: Border.all(color: AppTheme.hairlineOf(context)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      widget.isPickup ? Icons.storefront : Icons.location_on,
                      size: 14,
                      color: widget.isPickup ? Colors.blue : Colors.red,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${widget.addressLabel}${widget.addressValue}',
                        style: TextStyle(fontSize: 12, color: onSurface),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.deliveryPin.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.08),
                      borderRadius: AppTheme.radiusMd,
                      border: Border.all(
                        color: AppTheme.primary.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Text(
                      'Delivery PIN: ${widget.deliveryPin} — share with driver at the door',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: onSurface,
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
              if (widget.showTrack) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: widget.onTrack,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text('Track Live Order'),
                  ),
                ),
              ] else if (widget.showReorder) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: widget.onReorder,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primary,
                      side: const BorderSide(color: AppTheme.primary),
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'Reorder',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
              if (widget.showHelp) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    AppIconAction(
                      icon: Icons.support_agent_outlined,
                      tooltip: widget.helpTooltip,
                      onPressed: widget.onHelp,
                    ),
                  ],
                ),
              ],
              if (widget.onOpenDetails != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: widget.onOpenDetails,
                    child: const Text('Order details'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }
}
