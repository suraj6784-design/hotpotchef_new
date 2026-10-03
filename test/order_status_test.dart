import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/models/driver_delivery_model.dart';
import 'package:hotpotchef_new/utils/order_status.dart';

void main() {
  group('OrderStatus.parse', () {
    test('accepts Title Case and snake_case for pickup and delivery', () {
      expect(OrderStatus.parse('Ready for Pickup'), OrderStatus.readyForPickup);
      expect(OrderStatus.parse('ready_for_pickup'), OrderStatus.readyForPickup);
      expect(OrderStatus.parse('Out for Delivery'), OrderStatus.outForDelivery);
      expect(OrderStatus.parse('out_for_delivery'), OrderStatus.outForDelivery);
    });

    test('accepts historical aliases used by chef and driver writes', () {
      expect(OrderStatus.parse('Pending Chef Approval'), OrderStatus.pendingChefApproval);
      expect(OrderStatus.parse('pending_chef_approval'), OrderStatus.pendingChefApproval);
      expect(OrderStatus.parse('Preparing'), OrderStatus.preparing);
      expect(OrderStatus.parse('Driver Assigned'), OrderStatus.driverAssigned);
      expect(OrderStatus.parse('accepted'), OrderStatus.accepted);
    });

    test('canonical writes are snake_case', () {
      expect(OrderStatus.toCanonical('Ready for Pickup'), 'ready_for_pickup');
      expect(OrderStatus.toCanonical('out_for_delivery'), 'out_for_delivery');
      expect(OrderStatus.readyForPickup.canonical, 'ready_for_pickup');
      expect(OrderStatus.outForDelivery.canonical, 'out_for_delivery');
    });

    test('display labels stay Title Case for both wire forms', () {
      expect(OrderStatus.toDisplay('ready_for_pickup'), 'Ready for Pickup');
      expect(OrderStatus.toDisplay('Out for Delivery'), 'Out for Delivery');
    });

    test('queue helpers match either wire form', () {
      expect(OrderStatus.parse('Ready for Pickup').isDispatchQueue, isTrue);
      expect(OrderStatus.parse('out_for_delivery').isDispatchQueue, isTrue);
      expect(OrderStatus.parse('Preparing').isKitchenQueue, isTrue);
      expect(OrderStatus.parse('delivered').isDeliveredLike, isTrue);
      expect(OrderStatus.parse('completed').isDeliveredLike, isTrue);
    });
  });

  group('DeliveryStatus.fromString', () {
    test('maps chef Title Case and driver snake_case to the same enum', () {
      expect(
        DeliveryStatus.fromString('Ready for Pickup'),
        DeliveryStatus.readyForPickup,
      );
      expect(
        DeliveryStatus.fromString('ready_for_pickup'),
        DeliveryStatus.readyForPickup,
      );
      expect(
        DeliveryStatus.fromString('Out for Delivery'),
        DeliveryStatus.outForDelivery,
      );
      expect(
        DeliveryStatus.fromString('out_for_delivery'),
        DeliveryStatus.outForDelivery,
      );
    });

    test('driver writes Title Case like cream chef, and still parse snake_case', () {
      expect(DeliveryStatus.readyForPickup.toDbValue(), 'Ready for Pickup');
      expect(DeliveryStatus.outForDelivery.toDbValue(), 'Out for Delivery');
      expect(
        DeliveryStatus.fromString(DeliveryStatus.readyForPickup.toDbValue()),
        DeliveryStatus.readyForPickup,
      );
      expect(
        DeliveryStatus.fromString('ready_for_pickup'),
        DeliveryStatus.readyForPickup,
      );
      expect(
        DeliveryStatus.fromString('out_for_delivery'),
        DeliveryStatus.outForDelivery,
      );
    });
  });

  group('OrderStatus driver gate', () {
    test('blocks platform delivery without a driver id', () {
      expect(
        OrderStatus.canMarkOutForDelivery({
          'service_type': 'Delivery (Platform)',
        }),
        isFalse,
      );
      expect(
        OrderStatus.canMarkOutForDelivery({
          'service_type': 'deliveryPlatform',
          'driver_id': 'drv-1',
        }),
        isTrue,
      );
      expect(
        OrderStatus.canMarkOutForDelivery({
          'service_type': 'Delivery (Platform)',
          'delivery_partner_id': 'drv-2',
        }),
        isTrue,
      );
    });

    test('allows self-delivery and pickup without a platform driver', () {
      expect(
        OrderStatus.canMarkOutForDelivery({'service_type': 'Delivery (Self)'}),
        isTrue,
      );
      expect(
        OrderStatus.canMarkOutForDelivery({'service_type': 'Pickup'}),
        isTrue,
      );
    });
  });
}
