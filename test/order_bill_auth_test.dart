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

    test('keeps grand total at the paid amount even if discounted_price is higher', () {
      final bill = orderBillBreakdown(
        items: [
          {'title': 'AnyDish', 'price': 151, 'discounted_price': 201, 'quantity': 1},
        ],
        order: {'total_price': 211, 'order_type': 'Delivery Partner'},
        hasDelivery: true,
      );
      expect(bill.itemsTotal, 151);
      expect(bill.packagingFee, 20);
      expect(bill.deliveryFee, 40);
      expect(bill.grandTotal, 211);
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

  group('chefDisplayName', () {
    test('uses the profile name instead of Home Chef', () {
      expect(
        chefDisplayName({'chef_name': 'Home Chef', 'name': 'newchef16'}),
        'newchef16',
      );
    });

    test('falls back to the email local-part', () {
      expect(
        chefDisplayName({'chef_name': 'Home Kitchen', 'email': 'newchef16@example.com'}),
        'newchef16',
      );
    });
  });

  group('chefPayoutBreakdown', () {
    test('pays the chef food plus packaging minus 15% after delivery', () {
      final payout = chefPayoutBreakdown(itemsTotal: 151, packagingFee: 20);
      expect(payout.foodAndPackaging, 171);
      expect(payout.margin, 25.65);
      expect(payout.chefPayout, 145.35);
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
