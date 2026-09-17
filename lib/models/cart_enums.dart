// lib/models/cart_enums.dart

enum ServiceType {
  deliveryPlatform,
  deliverySelf,
  pickup,
  dineIn;

  /// Parses display strings, snake_case, aliases, [name], and [toString] forms
  /// (e.g. `ServiceType.pickup`). Unknown / empty values default to
  /// [ServiceType.deliveryPlatform] to match historical cart behavior.
  static ServiceType fromString(String? value) {
    final normalized = _normalize(value);
    if (normalized.isEmpty) {
      return ServiceType.deliveryPlatform;
    }

    switch (normalized) {
      case 'deliveryplatform':
      case 'delivery':
      case 'partner':
      case 'platform':
        return ServiceType.deliveryPlatform;
      case 'deliveryself':
      case 'self':
      case 'chefself':
        return ServiceType.deliverySelf;
      case 'pickup':
      case 'pick up':
        return ServiceType.pickup;
      case 'dinein':
      case 'dine':
        return ServiceType.dineIn;
    }

    final raw = value?.toLowerCase().trim() ?? '';
    final token = raw.split(',').first.trim();

    if (token.contains('partner') ||
        token.contains('platform') ||
        token == 'delivery' ||
        token == 'delivery_platform') {
      return ServiceType.deliveryPlatform;
    }
    if (token.contains('self') || token.contains('chef-self') || token == 'delivery_self') {
      return ServiceType.deliverySelf;
    }
    if (token.contains('pickup') || token.contains('pick up')) {
      return ServiceType.pickup;
    }
    if (token.contains('dine')) {
      return ServiceType.dineIn;
    }
    return ServiceType.deliveryPlatform;
  }

  /// Stable wire / persistence value (`deliveryPlatform`), not `toString()`.
  String toWireValue() => name;

  String toDisplayString() {
    switch (this) {
      case ServiceType.deliveryPlatform:
        return 'Delivery Partner';
      case ServiceType.deliverySelf:
        return 'Chef-Self';
      case ServiceType.pickup:
        return 'Customer Pickup';
      case ServiceType.dineIn:
        return 'Dine In';
    }
  }

  bool get isDelivery =>
      this == ServiceType.deliveryPlatform || this == ServiceType.deliverySelf;

  bool get usesDeliveryPartner => this == ServiceType.deliveryPlatform;

  String get chefHelpText {
    switch (this) {
      case ServiceType.deliveryPlatform:
        return 'A HotPotChef driver collects and delivers.';
      case ServiceType.deliverySelf:
        return 'You deliver the order to the customer.';
      case ServiceType.pickup:
        return 'Customer collects from your kitchen.';
      case ServiceType.dineIn:
        return 'Customer eats at your kitchen.';
    }
  }

  /// Lowercases, strips a `ServiceType.` prefix, and drops non-alphanumerics
  /// so `ServiceType.dineIn`, `dine_in`, `Dine-In`, and `dinein` all match.
  static String _normalize(String? value) {
    var s = value?.toLowerCase().trim() ?? '';
    const prefix = 'servicetype.';
    if (s.startsWith(prefix)) {
      s = s.substring(prefix.length);
    }
    return s.replaceAll(RegExp(r'[^a-z0-9]'), '');
  }
}

/// Strongly typed add-ons/customizations for production scalability
class CartItemAddOn {
  final String id;
  final String title;
  final double price;

  const CartItemAddOn({
    required this.id,
    required this.title,
    required this.price,
  });

  factory CartItemAddOn.fromJson(Map<String, dynamic> json) {
    final rawPrice = json['price'];
    final price = rawPrice is num
        ? rawPrice.toDouble()
        : double.tryParse(rawPrice?.toString() ?? '') ?? 0.0;
    return CartItemAddOn(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      price: price,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'price': price,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CartItemAddOn &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          price == other.price;

  @override
  int get hashCode => id.hashCode ^ price.hashCode;
}
