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
}
