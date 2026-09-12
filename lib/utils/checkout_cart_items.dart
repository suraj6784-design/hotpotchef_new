// Shared cart-JSON readers for checkout.
// CartItemModel.toJson() emits camelCase (`selectedServiceType`, `basePrice`,
// `mealDetails`). Older payloads and RPCs may use snake_case. Checkout must
// accept both so delivery, totals, and post-pay order rows stay consistent.

import '../models/cart_enums.dart';

Object? _firstNonEmpty(Iterable<Object?> values) {
  for (final value in values) {
    if (value == null) continue;
    final text = value.toString().trim();
    if (text.isNotEmpty && text.toLowerCase() != 'null') return value;
  }
  return null;
}

/// True when any cart line is platform or self delivery.
bool cartItemsHaveDelivery(Iterable<Map<String, dynamic>> items) =>
    items.any(cartItemHasDelivery);

bool cartItemHasDelivery(Map<String, dynamic> item) {
  final raw = _firstNonEmpty([
    item['selectedServiceType'],
    item['selected_service_type'],
    item['serviceType'],
    item['service_type'],
  ]);
  return ServiceType.fromString(raw?.toString()).isDelivery;
}

/// Nested meal blob. Cart persistence uses `mealDetails`; some UI maps keep
/// the live-model name `rawMealDetails`.
Map<String, dynamic>? cartItemMealDetails(Map<String, dynamic> item) {
  final raw = item['mealDetails'] ?? item['rawMealDetails'] ?? item['meal_details'];
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return null;
}

double cartItemUnitPrice(Map<String, dynamic> item) {
  final details = cartItemMealDetails(item);
  final raw = _firstNonEmpty([
    item['discountedPrice'],
    item['discounted_price'],
    item['basePrice'],
    item['price'],
    item['base_price'],
    details?['discounted_price'],
    details?['price'],
  ]);
  return double.tryParse(raw?.toString() ?? '0') ?? 0.0;
}

/// Email for `place_customer_order`. Never use `user.email!` after Razorpay
/// success — phone-only / unconfirmed accounts can have a null email.
String? resolveCustomerEmail({
  String? authEmail,
  String? metadataEmail,
  String? profileEmail,
}) {
  final resolved = _firstNonEmpty([authEmail, metadataEmail, profileEmail]);
  return resolved?.toString();
}
