import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/models/driver_delivery_model.dart';
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

  test('driver payout ignores a stored zero and uses the default', () {
    expect(driverPayoutFromOrder({'delivery_fee': 0, 'driver_payout': 0}), 40);
    expect(driverPayoutFromOrder({'delivery_fee': 35}), 35);
    expect(driverPayoutFromOrder({'driver_payout': 55, 'delivery_fee': 35}), 55);
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
