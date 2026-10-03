import 'chef_order_realtime.dart';
import 'helpers.dart';

/// Active Orders sections. Meal cards come before catering so a confirmed
/// scheduled plate is on screen; catering used to fill the viewport first.
enum DinerOrdersSection { reorder, meals, empty, broadcasts }

bool isDinerActiveOrderStatus(String? status) {
  final value = status?.toString().toLowerCase() ?? '';
  return !value.contains('delivered') &&
      !value.contains('completed') &&
      !value.contains('cancelled') &&
      !value.contains('rejected');
}

/// Orders stream rows are not always filtered server-side. Keep the signed-in
/// diner's rows whether the owner column is `customer_id` or legacy `user_id`.
bool dinerOrderOwnedBy(Map<String, dynamic> order, String userId) {
  if (userId.isEmpty) return false;
  final owner =
      order['customer_id']?.toString() ?? order['user_id']?.toString() ?? '';
  return owner == userId;
}

List<Map<String, dynamic>> _orderMaps(Iterable<dynamic> rows) {
  return rows
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList();
}

List<Map<String, dynamic>> dinerActiveOrders(Iterable<dynamic> rows) {
  return _orderMaps(rows)
      .where((row) => isDinerActiveOrderStatus(row['status']?.toString()))
      .toList();
}

List<Map<String, dynamic>> dinerPastOrders(
  Iterable<dynamic> rows, {
  int limit = 24,
}) {
  return _orderMaps(rows)
      .where((row) => !isDinerActiveOrderStatus(row['status']?.toString()))
      .take(limit)
      .toList();
}

/// `1x Breakfast` from orders.items, including when that column is JSON text.
String dinerOrderLineLabel(Map<String, dynamic> order) {
  final items = parseOrderItemsList(
    order['items'] ?? order['cart_items'] ?? order['order_items'],
  );
  if (items.isEmpty) {
    final title = order['title']?.toString().trim() ?? '';
    final qty = order['quantity'] ?? 1;
    return '${qty}x ${title.isEmpty ? 'Custom Order' : title}';
  }
  final first = items.first;
  final title = (first['title'] ?? first['name'] ?? 'Custom Order').toString();
  final qty = first['quantity'] ?? 1;
  return '${qty}x $title';
}

/// Overlay a realtime orders snapshot onto rows already on screen.
/// Accept updates only `status`. Postgres omits unchanged toasted `items`,
/// and `.stream()` replaces the row, which would drop "Breakfast" and the slot.
List<Map<String, dynamic>> mergeDinerOrderSnapshot(
  Iterable<Map<String, dynamic>> previous,
  Iterable<dynamic> incoming,
) {
  final priorById = <String, Map<String, dynamic>>{};
  for (final row in previous) {
    final id = row['id']?.toString() ?? '';
    if (id.isEmpty) continue;
    priorById[id] = row;
  }
  final merged = <Map<String, dynamic>>[];
  for (final raw in incoming) {
    if (raw is! Map) continue;
    final next = Map<String, dynamic>.from(raw);
    final id = next['id']?.toString() ?? '';
    merged.add(
      mergeChefOrderRealtimeRow(id.isEmpty ? null : priorById[id], next),
    );
  }
  return merged;
}

/// Section order for the Orders tab.
///
/// When the diner has meal orders, those cards are listed before broadcasts.
/// With no meal orders, broadcasts stay above the empty state.
List<DinerOrdersSection> dinerOrdersSections({
  required bool showPast,
  required bool hasMealOrders,
  required bool hasBroadcasts,
}) {
  if (showPast) {
    return [
      if (hasMealOrders) DinerOrdersSection.meals else DinerOrdersSection.empty,
    ];
  }
  if (!hasMealOrders) {
    return [
      DinerOrdersSection.reorder,
      if (hasBroadcasts) DinerOrdersSection.broadcasts,
      DinerOrdersSection.empty,
    ];
  }
  return [
    DinerOrdersSection.reorder,
    DinerOrdersSection.meals,
    if (hasBroadcasts) DinerOrdersSection.broadcasts,
  ];
}
