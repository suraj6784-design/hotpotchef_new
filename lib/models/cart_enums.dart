// lib/models/cart_enums.dart

enum ServiceType {
  deliveryPlatform,
  deliverySelf,
  pickup,
  dineIn;

  static ServiceType fromString(String? value) {
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