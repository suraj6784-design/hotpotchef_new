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
        return ServiceType.deliveryPlatform;
      case 'deliveryself':
        return ServiceType.deliverySelf;
      case 'pickup':
        return ServiceType.pickup;
      case 'dinein':
        return ServiceType.dineIn;
      default:
        return ServiceType.deliveryPlatform;
    }
  }

  /// Stable wire / persistence value (`deliveryPlatform`), not `toString()`.
  String toWireValue() => name;

  String toDisplayString() {
    switch (this) {
      case ServiceType.deliveryPlatform:
        return 'Delivery (Platform)';
      case ServiceType.deliverySelf:
        return 'Delivery (Self)';
      case ServiceType.pickup:
        return 'Pickup';
      case ServiceType.dineIn:
        return 'Dine-In';
    }
  }

  bool get isDelivery =>
      this == ServiceType.deliveryPlatform || this == ServiceType.deliverySelf;

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
    return CartItemAddOn(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
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
