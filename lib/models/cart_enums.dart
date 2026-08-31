// lib/models/cart_enums.dart

enum ServiceType {
  deliveryPlatform,
  deliverySelf,
  pickup,
  dineIn;

  static ServiceType fromString(String? value) {
    switch (value?.toLowerCase().trim()) {
      case 'delivery (platform)':
      case 'delivery_platform':
      case 'delivery':
        return ServiceType.deliveryPlatform;
      case 'delivery (self)':
      case 'delivery_self':
        return ServiceType.deliverySelf;
      case 'pickup':
        return ServiceType.pickup;
      case 'dinein':
      case 'dine_in':
        return ServiceType.dineIn;
      default:
        return ServiceType.deliveryPlatform;
    }
  }

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