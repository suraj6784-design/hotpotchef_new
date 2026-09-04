import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/helpers.dart';
import 'package:hotpotchef_new/utils/network.dart';

void main() {
  group('orderBillBreakdown', () {
    test('reconstructs a ₹30 delivery fee from the paid total', () {
      final bill = orderBillBreakdown(
        items: [
          {'title': 'Veg Biryani', 'price': 150, 'quantity': 1},
        ],
        order: {'total_price': 200, 'order_type': 'Delivery Partner'},
        hasDelivery: true,
      );
      expect(bill.itemsTotal, 150);
      expect(bill.packagingFee, 20);
      expect(bill.deliveryFee, 30);
      expect(bill.grandTotal, 200);
    });

    test('uses a stored delivery_fee when present', () {
      final bill = orderBillBreakdown(
        items: [
          {'price': 150, 'quantity': 1},
        ],
        order: {'total_price': 200, 'delivery_fee': 30},
        hasDelivery: true,
      );
      expect(bill.deliveryFee, 30);
      expect(bill.grandTotal, 200);
    });

    test('does not invent a delivery fee for pickup', () {
      final bill = orderBillBreakdown(
        items: [
          {'price': 150, 'quantity': 1},
        ],
        order: {'total_price': 170, 'order_type': 'Pickup'},
        hasDelivery: false,
      );
      expect(bill.deliveryFee, 0);
      expect(bill.grandTotal, 170);
    });
  });

  group('friendlyAuthError', () {
    test('explains invalid login credentials', () {
      expect(
        friendlyAuthError(Exception('Invalid login credentials')),
        'Wrong email or password. Please try again.',
      );
    });

    test('explains a timeout', () {
      expect(
        friendlyAuthError(const NetworkException(NetworkException.timedOutMessage, timedOut: true)),
        NetworkException.timedOutMessage,
      );
    });
  });
}
