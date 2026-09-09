import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/models/cart_enums.dart';
import 'package:hotpotchef_new/models/cart_state.dart';

CartItemModel _itemWith(ServiceType serviceType) {
  return CartItemModel(
    id: '1',
    mealId: 'm1',
    chefId: 'c1',
    title: 'Test Meal',
    basePrice: 100,
    quantity: 1,
    scheduledDate: DateTime.utc(2026, 1, 1),
    serviceType: serviceType,
  );
}

void main() {
  group('ServiceType.fromString', () {
    test('parses display strings', () {
      expect(
        ServiceType.fromString('Delivery (Platform)'),
        ServiceType.deliveryPlatform,
      );
      expect(
        ServiceType.fromString('Delivery (Self)'),
        ServiceType.deliverySelf,
      );
      expect(ServiceType.fromString('Pickup'), ServiceType.pickup);
      expect(ServiceType.fromString('Dine-In'), ServiceType.dineIn);
    });

    test('parses snake_case and common aliases', () {
      expect(
        ServiceType.fromString('delivery_platform'),
        ServiceType.deliveryPlatform,
      );
      expect(
        ServiceType.fromString('delivery'),
        ServiceType.deliveryPlatform,
      );
      expect(
        ServiceType.fromString('delivery_self'),
        ServiceType.deliverySelf,
      );
      expect(ServiceType.fromString('pickup'), ServiceType.pickup);
      expect(ServiceType.fromString('dine_in'), ServiceType.dineIn);
      expect(ServiceType.fromString('dinein'), ServiceType.dineIn);
    });

    test('parses enum.toString() and .name forms', () {
      for (final value in ServiceType.values) {
        expect(ServiceType.fromString(value.toString()), value);
        expect(ServiceType.fromString(value.name), value);
        expect(ServiceType.fromString(value.toWireValue()), value);
      }
    });

    test('is case-insensitive and ignores surrounding whitespace', () {
      expect(
        ServiceType.fromString('  SERVICETYPE.PICKUP  '),
        ServiceType.pickup,
      );
      expect(
        ServiceType.fromString('Delivery (self)'),
        ServiceType.deliverySelf,
      );
    });

    test('defaults unknown and empty values to deliveryPlatform', () {
      expect(ServiceType.fromString(null), ServiceType.deliveryPlatform);
      expect(ServiceType.fromString(''), ServiceType.deliveryPlatform);
      expect(ServiceType.fromString('unknown'), ServiceType.deliveryPlatform);
    });
  });

  group('ServiceType round-trip contract', () {
    test('display, wire, name, and toString all round-trip', () {
      for (final value in ServiceType.values) {
        expect(ServiceType.fromString(value.toDisplayString()), value);
        expect(ServiceType.fromString(value.toWireValue()), value);
        expect(ServiceType.fromString(value.name), value);
        expect(ServiceType.fromString(value.toString()), value);
      }
    });

    test('CartItemModel JSON write/read preserves service type', () {
      for (final value in ServiceType.values) {
        final restored = CartItemModel.fromJson(_itemWith(value).toJson());
        expect(restored.serviceType, value);
        expect(restored.toJson()['selectedServiceType'], value.toWireValue());
      }
    });

    test('legacy display-string JSON still reads correctly', () {
      final json = _itemWith(ServiceType.pickup).toJson();
      json['selectedServiceType'] = ServiceType.pickup.toDisplayString();
      expect(CartItemModel.fromJson(json).serviceType, ServiceType.pickup);
    });

    test('legacy enum.toString() JSON still reads correctly', () {
      final json = _itemWith(ServiceType.dineIn).toJson();
      json['selectedServiceType'] = ServiceType.dineIn.toString();
      expect(CartItemModel.fromJson(json).serviceType, ServiceType.dineIn);
    });
  });
}
