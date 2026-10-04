import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/models/driver_delivery_model.dart';
import 'package:hotpotchef_new/utils/delivery_fee.dart';
import 'package:hotpotchef_new/utils/helpers.dart';

void main() {
  test('DriverDeliveryModel uses the order id as the shared chat group', () {
    final delivery = DriverDeliveryModel.fromJson({
      'id': 'order-row',
      'chef_id': 'chef-1',
      'customer_id': 'cust-1',
      'delivery_address': 'Kothrud',
      'status': 'Out for Delivery',
      'created_at': '2026-09-04T10:00:00Z',
      'items': [
        {'source_meal_id': 'meal-77', 'id': 'line-1', 'title': 'Dal'},
      ],
    });

    expect(delivery.chatRoomId, 'order-row');
    expect(delivery.customerId, 'cust-1');
  });

  test('DriverDeliveryModel reads a chefs list embed without crashing', () {
    final delivery = DriverDeliveryModel.fromJson({
      'id': 'order-row',
      'chefs': [
        {'business_name': 'Home Kitchen', 'pickup_address': 'FC Road'},
      ],
      'status': 'Ready for Pickup',
    });
    expect(delivery.chefName, 'Home Kitchen');
    expect(delivery.pickupAddress, 'FC Road');
  });

  test('DriverDeliveryModel navigates kitchen first then customer after out for delivery', () {
    final assigned = DriverDeliveryModel.fromJson({
      'id': 'order-row',
      'chef_id': 'chef-1',
      'status': 'Driver Assigned',
      'delivery_address': 'Kothrud gate',
      'delivery_lat': 18.51,
      'delivery_lng': 73.82,
      '_chef_pin': {
        'name': 'Asha',
        'address': 'Wakad kitchen',
        'lat': 18.60,
        'lng': 73.76,
      },
    });
    expect(assigned.navigateToCustomer, isFalse);
    expect(assigned.navigateButtonLabel, 'Navigate to kitchen');
    expect(assigned.pickupAddress, contains('Wakad'));
    expect(assigned.pickupLat, 18.60);
    expect(assigned.deliveryLat, 18.51);
    expect(assigned.toTrackingOrderExtra()['navigate_leg'], 'pickup');

    final heading = DriverDeliveryModel.fromJson({
      'id': 'order-row',
      'chef_id': 'chef-1',
      'status': 'Heading to Kitchen',
      '_chef_pin': {'name': 'Asha', 'address': 'Wakad kitchen', 'lat': 18.60, 'lng': 73.76},
    });
    expect(heading.navigateToCustomer, isFalse);
    expect(heading.activeStepTitle, contains('Pickup'));
    expect(heading.status, DeliveryStatus.pickedUp);

    final out = DriverDeliveryModel.fromJson({
      'id': 'order-row',
      'status': 'Out for Delivery',
      'delivery_address': 'Kothrud gate',
      'delivery_lat': 18.51,
      'delivery_lng': 73.82,
    });
    expect(out.navigateToCustomer, isTrue);
    expect(out.navigateButtonLabel, 'Navigate to customer');
    expect(out.toTrackingOrderExtra()['navigate_leg'], 'dropoff');
  });

  test('googleMapsDirectionsUri prefers coordinates over address', () {
    expect(
      googleMapsDirectionsUri(lat: 18.6, lng: 73.7, address: 'ignored')!.toString(),
      contains('18.6,73.7'),
    );
    expect(
      googleMapsDirectionsUri(address: 'Wakad kitchen')!.toString(),
      contains('Wakad'),
    );
    expect(
      googleMapsDirectionsUri(
        lat: 18.6,
        lng: 73.7,
        address: 'Paid checkout street',
        preferAddress: true,
      )!.toString(),
      contains('Paid'),
    );
  });

  test('isPartnerDeliveryOrder excludes chef-self even when order_type is blank if items say so', () {
    expect(isPartnerDeliveryOrder({'order_type': 'Chef-Self'}), isFalse);
    expect(
      isPartnerDeliveryOrder({
        'order_type': '',
        'items': [
          {'selected_service_type': 'Chef-Self'},
        ],
      }),
      isFalse,
    );
    expect(isPartnerDeliveryOrder({'order_type': 'Delivery Partner'}), isTrue);
  });

  test('DriverDeliveryModel reads the meal time slot', () {
    final delivery = DriverDeliveryModel.fromJson({
      'id': 'order-row',
      'created_at': '2026-09-05T01:00:00Z',
      'items': [
        {'time_slot': '5 Sep at 02:00 AM', 'selected_date': '5 Sep'},
      ],
    });
    expect(delivery.timeSlot, '5 Sep at 02:00 AM');
    expect(formatDeliverySlotLabel(delivery.slotSource), contains('02:00'));
  });

  test('DriverDeliveryModel exposes brief order details for history cards', () {
    final delivery = DriverDeliveryModel.fromJson({
      'id': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      'order_id': 'OCB30688',
      'status': 'Delivered',
      'delivery_address': 'Flat 12, Kothrud Gate, Pune 411038',
      'created_at': '2026-09-05T03:36:00Z',
      'items': [
        {'title': 'Egg Dish', 'quantity': 2},
        {'title': 'Dal Tadka', 'quantity': 1},
      ],
      '_chef_pin': {'name': 'Asha Kitchen'},
    });

    expect(delivery.displayOrderNumber, 'OCB30688');
    expect(delivery.chefName, 'Asha Kitchen');
    expect(delivery.itemsSummary, contains('Egg Dish'));
    expect(delivery.itemsSummary, contains('3 items'));
    expect(delivery.driverHistoryDetail, contains('Egg Dish'));
    expect(delivery.driverHistoryDetail, contains('Kothrud'));
    expect(driverOrderItemsSummary(const [
      {'title': 'Dal', 'quantity': 1},
    ]), 'Dal');
    expect(briefDriverAddress('Customer address pending'), isEmpty);
  });

  test('driver payout uses the fee when the diner paid, and does not invent ₹40', () {
    expect(kFreeDeliveryDriverPayout, kPackagingFeeAtFreeDelivery);
    expect(kFreeDeliveryDriverPayout, inInclusiveRange(15, 20));
    expect(driverPayoutFromOrder({'delivery_fee': 0, 'driver_payout': 0}), 0);
    expect(driverPayoutFromOrder({'delivery_fee': 35}), 35);
    expect(driverPayoutFromOrder({'driver_payout': 55, 'delivery_fee': 35}), 55);
    expect(
      driverPayoutFromOrder({'driver_payout': 35, 'delivery_fee': 35, 'tip_amount': 20}),
      55,
    );
    expect(driverPayoutFromOrder({'delivery_fee': 30, 'tip_amount': 15}), 45);
  });

  test('free delivery above ₹199 stores the same payout the driver card shows', () {
    final open = <String, dynamic>{
      'order_type': 'Delivery Partner',
      'delivery_fee': 0,
      'driver_payout': 0,
      'tip_amount': 0,
      'packaging_fee': 20,
      'items': [
        {'title': 'Thali', 'quantity': 1, 'price': 220, 'line_net': 220},
      ],
    };

    final shown = driverPayoutFromOrder(open);
    final stored = driverPayoutStoredAtCompletion(open);
    final walletCredit = stored > 0 ? stored : 0.0;
    final chefDeduction = freeDeliveryDriverStipend(open);

    expect(shown, kFreeDeliveryDriverPayout);
    expect(stored, shown);
    expect(walletCredit, shown);
    expect(chefDeduction, shown);

    final completed = DriverDeliveryModel.fromJson({
      ...open,
      'driver_payout': stored,
      'id': 'free-delivery-order',
      'status': 'Delivered',
    });
    expect(completed.payout, stored);

    final underThreshold = <String, dynamic>{
      'order_type': 'Delivery Partner',
      'delivery_fee': 0,
      'driver_payout': 0,
      'items': [
        {'title': 'Breakfast', 'quantity': 1, 'price': 90, 'line_net': 90},
      ],
    };
    expect(driverPayoutFromOrder(underThreshold), 0);
    expect(driverPayoutStoredAtCompletion(underThreshold), 0);
    expect(freeDeliveryDriverStipend(underThreshold), 0);

    final paid = <String, dynamic>{
      'order_type': 'Delivery Partner',
      'delivery_fee': 30,
      'driver_payout': 0,
      'tip_amount': 0,
      'items': [
        {'title': 'Breakfast', 'quantity': 1, 'price': 90, 'line_net': 90},
      ],
    };
    expect(driverPayoutFromOrder(paid), 30);
    expect(driverPayoutStoredAtCompletion(paid), 30);
    expect(freeDeliveryDriverStipend(paid), 0);

    final withTip = <String, dynamic>{...open, 'tip_amount': 10};
    expect(driverPayoutFromOrder(withTip), 30);
    expect(driverPayoutStoredAtCompletion(withTip), 30);
    expect(freeDeliveryDriverStipend(withTip), kFreeDeliveryDriverPayout);

    expect(freeDeliveryDriverStipend({
      'order_type': 'Chef-Self',
      'delivery_fee': 0,
      'items': [
        {'title': 'Thali', 'quantity': 1, 'price': 220, 'line_net': 220},
      ],
    }), 0);
  });

  test('fleet earnings prefer a real wallet and otherwise sum run payouts', () {
    expect(fleetEarningsFrom(wallet: 0, lifetime: 0, deliveryPayouts: const [40]), 40);
    expect(fleetEarningsFrom(wallet: 120, lifetime: 0, deliveryPayouts: const [40]), 120);
    expect(fleetEarningsFrom(wallet: 0, lifetime: 200, deliveryPayouts: const [40]), 200);
  });

  test('formatSlotCountdown reports time left and late', () {
    final now = DateTime(2026, 9, 5, 1, 40);
    expect(formatSlotCountdown(now.add(const Duration(minutes: 12)), now: now), '12 min left');
    expect(formatSlotCountdown(now.subtract(const Duration(minutes: 8)), now: now), '8 min late');
    expect(formatSlotCountdown(now, now: now), 'Due now');
  });
}
