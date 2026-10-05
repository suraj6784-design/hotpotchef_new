import 'package:flutter/material.dart';

import '../models/cart_enums.dart';
import '../utils/helpers.dart';

/// Diner details a kitchen uses on the In Progress card while preparing
/// and handing off. Name and the requested slot stay on the rest of the card.
/// Phone and chat stay on the existing contact icons.
///
/// Only fields the order actually has are shown. The diner delivery PIN and
/// the diner phone number are never printed on this card.
class ChefOrderHandoff {
  const ChefOrderHandoff({
    this.dropoff = '',
    this.note = '',
  });

  final String dropoff;
  final String note;

  bool get isEmpty => dropoff.isEmpty && note.isEmpty;
}

const _nonDropoffLabels = <String>{
  'store pickup / dine-in',
  'store pickup',
  'dine-in',
  'dine in',
  'customer address pending',
  'unknown location',
  'unknown address',
  'kitchen location',
};

String _cleanField(dynamic value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty || text.toLowerCase() == 'null') return '';
  return text;
}

bool _alreadyShown(String existing, String next) {
  final haystack = existing.toLowerCase();
  final needle = next.toLowerCase();
  if (needle.isEmpty) return true;
  return haystack.contains(needle);
}

String _gateLine(String raw) {
  final cleaned = kitchenFacingOrderNotes(raw);
  if (cleaned.isEmpty) return '';
  if (RegExp(r'^gate\b', caseSensitive: false).hasMatch(cleaned)) return cleaned;
  return 'Gate: $cleaned';
}

String _deliveryNote(Map<String, dynamic> order) {
  final lines = <String>[];
  void add(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return;
    final existing = lines.join('\n');
    if (_alreadyShown(existing, text)) return;
    lines.add(text);
  }

  add(kitchenFacingOrderNotes(order['special_instructions']?.toString()));
  add(_gateLine(_cleanField(order['gate_instructions'])));

  for (final item in parseOrderItemsList(order['items'] ?? order['cart_items'])) {
    final note = kitchenFacingOrderNotes(
      (item['specialInstructions'] ?? item['special_instructions'])?.toString(),
    );
    if (note.isEmpty || _alreadyShown(lines.join('\n'), note)) continue;
    final title = _cleanField(item['title'] ?? item['name']);
    add(title.isEmpty ? note : '$title: $note');
  }
  return lines.join('\n').trim();
}

/// Dropoff and delivery note copied from the order row.
/// Pickup and dine-in have no diner dropoff. An empty note stays empty.
ChefOrderHandoff chefOrderHandoff(Map<String, dynamic> order) {
  final service = ServiceType.fromString(
    order['order_type']?.toString() ?? order['service_type']?.toString(),
  );
  var dropoff = '';
  if (service.isDelivery) {
    final resolved = orderDropoffAddress(
      order,
      items: parseOrderItemsList(order['items'] ?? order['cart_items']),
    );
    if (!_nonDropoffLabels.contains(resolved.toLowerCase().trim())) {
      dropoff = resolved;
    }
  }
  return ChefOrderHandoff(
    dropoff: dropoff,
    note: _deliveryNote(order),
  );
}

/// "Occasion: Festivals" when the order remembers a diner tab. Empty for
/// orders placed before the occasion column existed.
String chefOrderOccasionCaption(Map<String, dynamic> order) {
  final label = occasionTabLabel(
    orderOccasionId(
      column: order['occasion'],
      items: parseOrderItemsList(order['items'] ?? order['cart_items']),
    ),
  );
  if (label.isEmpty) return '';
  return 'Occasion: $label';
}

/// One line on a chef order card. Hidden when the order has no occasion.
class ChefOrderOccasionLine extends StatelessWidget {
  const ChefOrderOccasionLine({
    super.key,
    required this.order,
    this.padding = const EdgeInsets.only(top: 6),
  });

  final Map<String, dynamic> order;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final caption = chefOrderOccasionCaption(order);
    if (caption.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: padding,
      child: Text(
        caption,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 13,
          color: AppTheme.link,
        ),
      ),
    );
  }
}

/// Address and note block under the slot banner on a chef order card.
class ChefOrderHandoffDetails extends StatelessWidget {
  const ChefOrderHandoffDetails({super.key, required this.order});

  final Map<String, dynamic> order;

  @override
  Widget build(BuildContext context) {
    final handoff = chefOrderHandoff(order);
    final occasion = chefOrderOccasionCaption(order);
    if (handoff.isEmpty && occasion.isEmpty) return const SizedBox.shrink();
    final onSurface = AppTheme.onSurfaceOf(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (occasion.isNotEmpty) ...[
            ChefOrderOccasionLine(order: order, padding: EdgeInsets.zero),
            if (handoff.dropoff.isNotEmpty || handoff.note.isNotEmpty) const SizedBox(height: 10),
          ],
          if (handoff.dropoff.isNotEmpty)
            _DetailRow(
              key: const Key('chef-order-dropoff'),
              icon: Icons.location_on,
              iconColor: Colors.redAccent,
              text: 'Dropoff: ${handoff.dropoff}',
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: onSurface,
              ),
            ),
          if (handoff.note.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              key: const Key('chef-order-note'),
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.warning.withValues(alpha: 0.12),
                borderRadius: AppTheme.radiusSm,
              ),
              child: Text(
                'Note: ${handoff.note}',
                style: TextStyle(
                  color: onSurface,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.text,
    required this.style,
  });

  final IconData icon;
  final Color iconColor;
  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: iconColor),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: style)),
      ],
    );
  }
}
