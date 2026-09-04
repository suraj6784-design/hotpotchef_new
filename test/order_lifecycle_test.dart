import 'package:flutter_test/flutter_test.dart';

import 'package:hotpotchef_new/models/app_role.dart';
import 'package:hotpotchef_new/models/cart_enums.dart';
import 'package:hotpotchef_new/models/order_status.dart';
import 'package:hotpotchef_new/services/order_lifecycle.dart';

void main() {
  group('AppRole', () {
    test('parses chef, driver, and customer aliases', () {
      expect(AppRole.parse('Chef'), AppRole.chef);
      expect(AppRole.parse('driver'), AppRole.driver);
      expect(AppRole.parse(null), AppRole.customer);
      expect(AppRole.chef.hubPath, '/chef-hub');
    });
  });

  group('ServiceType', () {
    test('maps chef fulfillment labels', () {
      expect(ServiceType.fromString('Delivery Partner').usesDeliveryPartner, isTrue);
      expect(ServiceType.fromString('Delivery (Platform)'), ServiceType.deliveryPlatform);
      expect(ServiceType.fromString('Chef-Self'), ServiceType.deliverySelf);
      expect(ServiceType.fromString('Customer Pickup'), ServiceType.pickup);
      expect(ServiceType.fromString('Dine In'), ServiceType.dineIn);
    });
  });

  group('OrderLifecycle', () {
    test('kitchen Confirm → Preparing → Ready for Pickup', () {
      expect(OrderLifecycle.nextKitchenStatus('Pending Chef Approval'), OrderStatus.confirmed);
      expect(OrderLifecycle.nextKitchenStatus('Confirmed'), OrderStatus.preparing);
      expect(OrderLifecycle.nextKitchenStatus('Preparing'), OrderStatus.readyForPickup);
    });

    test('dispatch depends on delivery option', () {
      expect(
        OrderLifecycle.nextDispatchStatus('Ready for Pickup', ServiceType.deliveryPlatform),
        isNull,
      );
      expect(
        OrderLifecycle.nextDispatchStatus('Ready for Pickup', ServiceType.deliverySelf),
        OrderStatus.outForDelivery,
      );
      expect(
        OrderLifecycle.nextDispatchStatus('Ready for Pickup', ServiceType.pickup),
        OrderStatus.delivered,
      );
      expect(
        OrderLifecycle.nextDriverStatus('Driver Assigned'),
        OrderStatus.outForDelivery,
      );
      expect(
        OrderLifecycle.nextDriverStatus('Out for Delivery'),
        OrderStatus.delivered,
      );
    });

    test('customer cannot cancel once cooking starts', () {
      expect(OrderLifecycle.canCustomerCancel('Pending Chef Approval'), isTrue);
      expect(OrderLifecycle.canCustomerCancel('Preparing'), isFalse);
    });

    test('customer can cancel a processing order before the slot starts', () {
      final placed = DateTime(2026, 9, 3, 7, 28);
      final now = DateTime(2026, 9, 3, 7, 31);
      expect(
        OrderLifecycle.canCustomerCancelOrder({
          'status': 'Pending Chef Approval',
          'created_at': placed.toIso8601String(),
          'time_slot': '03/09/2026 | 12:00 PM to 1:00 PM',
        }, now: now),
        isTrue,
      );
    });

    test('customer cannot cancel after the delivery slot begins', () {
      final placed = DateTime(2026, 9, 3, 7, 28);
      final now = DateTime(2026, 9, 3, 12, 5);
      expect(
        OrderLifecycle.canCustomerCancelOrder({
          'status': 'Pending Chef Approval',
          'created_at': placed.toIso8601String(),
          'time_slot': '03/09/2026 | 12:00 PM to 1:00 PM',
        }, now: now),
        isFalse,
      );
    });

    test('trackable after kitchen is ready or driver is assigned', () {
      expect(OrderLifecycle.isTrackable('Ready for Pickup'), isTrue);
      expect(OrderLifecycle.isTrackable('Driver Assigned'), isTrue);
      expect(OrderLifecycle.isTrackable('Preparing'), isFalse);
    });
  });
}
