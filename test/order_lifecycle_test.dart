import 'package:flutter_test/flutter_test.dart';

import 'package:hotpotchef_new/models/app_role.dart';
import 'package:hotpotchef_new/models/cart_enums.dart';
import 'package:hotpotchef_new/services/auth_session.dart';
import 'package:hotpotchef_new/services/order_lifecycle.dart';

void main() {
  group('AppRole', () {
    test('parses chef, driver, admin, and customer aliases', () {
      expect(AppRole.parse('Chef'), AppRole.chef);
      expect(AppRole.parse('driver'), AppRole.driver);
      expect(AppRole.parse('Delivery'), AppRole.driver);
      expect(AppRole.parse('Delivery Partner'), AppRole.driver);
      expect(AppRole.parse('Admin'), AppRole.admin);
      expect(AppRole.parse('customer'), AppRole.customer);
      expect(AppRole.parse('Food Lover'), AppRole.customer);
      expect(AppRole.parse(null), AppRole.customer);
      expect(AppRole.chef.hubPath, '/chef-hub');
      expect(AppRole.admin.hubPath, '/platform-ops');
      expect(AppRole.driver.signupLabel, 'Delivery Partner');
      expect(AppRole.chef.signupLabel, 'Chef');
    });
  });

  group('AuthSession role sources', () {
    test('prefers public.users.role over a stale JWT claim', () {
      expect(
        AuthSession.resolveRoleFromSources(jwtRole: 'Customer', tableRole: 'Chef'),
        AppRole.chef,
      );
      expect(
        AuthSession.resolveRoleFromSources(jwtRole: 'Chef', tableRole: 'Driver'),
        AppRole.driver,
      );
      expect(
        AuthSession.resolveRoleFromSources(jwtRole: 'Chef', tableRole: null),
        AppRole.chef,
      );
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

    test('open driver jobs start only after the kitchen is ready', () {
      expect(OrderLifecycle.isOpenDriverJob('Pending Chef Approval'), isFalse);
      expect(OrderLifecycle.isOpenDriverJob('Confirmed'), isFalse);
      expect(OrderLifecycle.isOpenDriverJob('Preparing'), isFalse);
      expect(OrderLifecycle.isOpenDriverJob('Ready for Pickup'), isTrue);
      expect(OrderLifecycle.isOpenDriverJob('Driver Assigned'), isTrue);
      expect(OrderLifecycle.isOpenDriverJob('Out for Delivery'), isTrue);
      expect(OrderLifecycle.isOpenDriverJob('Delivered'), isFalse);
      expect(OrderLifecycle.isOpenDriverJob('Cancelled'), isFalse);
    });

    test('drivers cannot start or finish a run before the kitchen is ready', () {
      expect(OrderLifecycle.nextDriverStatus('Pending Chef Approval'), isNull);
      expect(OrderLifecycle.nextDriverStatus('Confirmed'), isNull);
      expect(OrderLifecycle.nextDriverStatus('Preparing'), isNull);
      expect(OrderLifecycle.nextDriverStatus('Ready for Pickup'), OrderStatus.headingToKitchen);
      expect(OrderLifecycle.nextDriverStatus('Driver Assigned'), OrderStatus.headingToKitchen);
      expect(OrderLifecycle.nextDriverStatus('Heading to Kitchen'), OrderStatus.outForDelivery);
      expect(OrderLifecycle.nextDriverStatus('Out for Delivery'), OrderStatus.delivered);
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
        OrderStatus.headingToKitchen,
      );
      expect(
        OrderLifecycle.nextDriverStatus('Heading to Kitchen'),
        OrderStatus.outForDelivery,
      );
      expect(
        OrderLifecycle.nextDriverStatus('Out for Delivery'),
        OrderStatus.delivered,
      );
      expect(
        OrderLifecycle.nextDispatchStatus('Out for Delivery', ServiceType.deliveryPlatform),
        isNull,
      );
      expect(
        OrderLifecycle.nextDispatchStatus('Out for Delivery', ServiceType.deliverySelf),
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

    test('offline kitchens still owe accepted and dispatch orders', () {
      expect(OrderLifecycle.isUnfulfilledKitchenWork('Confirmed'), isTrue);
      expect(OrderLifecycle.isUnfulfilledKitchenWork('Preparing'), isTrue);
      expect(OrderLifecycle.isUnfulfilledKitchenWork('Driver Assigned'), isTrue);
      expect(OrderLifecycle.isUnfulfilledKitchenWork('Out for Delivery'), isTrue);
      expect(OrderLifecycle.isUnfulfilledKitchenWork('Delivered'), isFalse);
      expect(OrderLifecycle.isFulfilled('Out for Delivery'), isFalse);
      expect(OrderLifecycle.isFulfilled('Delivered'), isTrue);
      expect(
        OrderLifecycle.chefHasUnfulfilledOrders([
          {'status': 'Confirmed'},
          {'status': 'Delivered'},
        ]),
        isTrue,
      );
    });

    test('live tracking only once the order is out for delivery', () {
      expect(OrderLifecycle.isTrackable('Pending Chef Approval'), isFalse);
      expect(OrderLifecycle.isTrackable('Confirmed'), isFalse);
      expect(OrderLifecycle.isTrackable('Preparing'), isFalse);
      expect(OrderLifecycle.isTrackable('Ready for Pickup'), isFalse);
      expect(OrderLifecycle.isTrackable('Driver Assigned'), isFalse);
      expect(OrderLifecycle.isTrackable('Heading to Kitchen'), isFalse);
      expect(OrderLifecycle.isTrackable('Out for Delivery'), isTrue);
      expect(OrderLifecycle.isTrackable('Delivered'), isFalse);
      expect(OrderLifecycle.isTrackable('Cancelled'), isFalse);
      expect(OrderLifecycle.dinerOrderCardBadge('Pending Chef Approval'), 'Waiting for the kitchen');
      expect(OrderLifecycle.dinerOrderCardBadge('Confirmed'), 'Kitchen confirmed');
      expect(OrderLifecycle.dinerOrderCardBadge('Ready for Pickup'), 'Packed');
      expect(OrderLifecycle.dinerOrderCardBadge('Driver Assigned'), 'Partner assigned');
      expect(OrderLifecycle.dinerOrderCardBadge('Heading to Kitchen'), 'Partner is heading to the kitchen');
      expect(OrderLifecycle.dinerOrderCardBadge('Out for Delivery'), 'Out for delivery');
    });

    test('driver hub shows pickup-run badge and actions', () {
      expect(OrderLifecycle.driverHubBadge('Driver Assigned'), 'On the way to pickup');
      expect(OrderLifecycle.driverHubActionLabel('Driver Assigned'), 'On the way to pickup');
      expect(OrderLifecycle.driverHubBadge('Heading to Kitchen'), 'On the way to pickup');
      expect(OrderLifecycle.driverHubActionLabel('Heading to Kitchen'), 'Picked up');
      expect(OrderLifecycle.driverHubActionLabel('Out for Delivery'), 'Mark Delivered');
    });

    test('older status labels map onto the statuses we write', () {
      expect(OrderStatus.canonical('placed'), OrderStatus.pendingChefApproval);
      expect(OrderStatus.canonical('packed'), OrderStatus.readyForPickup);
      expect(OrderStatus.canonical('completed'), OrderStatus.delivered);
      expect(OrderStatus.canonical('out_for_delivery'), OrderStatus.outForDelivery);
      expect(OrderStatus.canonical('Pending Chef Approval'), OrderStatus.pendingChefApproval);
      expect(OrderLifecycle.isTrackable('packed'), isFalse);
      expect(OrderLifecycle.isTrackable('out_for_delivery'), isTrue);
      expect(OrderLifecycle.isTrackable('completed'), isFalse);
      expect(OrderLifecycle.nextKitchenStatus('placed'), OrderStatus.confirmed);
    });

    test('diner progress is Kitchen → Packed → On the way → Delivered', () {
      expect(OrderLifecycle.dinerProgressStep('Confirmed'), 0);
      expect(OrderLifecycle.dinerProgressStep('Preparing'), 0);
      expect(OrderLifecycle.dinerProgressStep('Ready for Pickup'), 1);
      expect(OrderLifecycle.dinerProgressStep('Driver Assigned'), 2);
      expect(OrderLifecycle.dinerProgressStep('Heading to Kitchen'), 2);
      expect(OrderLifecycle.dinerProgressStep('Out for Delivery'), 2);
      expect(OrderLifecycle.dinerProgressStep('Delivered'), 3);
      expect(OrderLifecycle.dinerProgressStep('Cancelled'), -1);
    });
  });
}
