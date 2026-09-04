import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/models/driver_delivery_model.dart';

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
}
