import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/services/create_split_order_contract.dart';

void main() {
  group('CreateSplitOrderRequest contract', () {
    test('builds the body checkout sends to create-split-order', () {
      final cartItems = [
        {
          'mealId': 'meal-1',
          'chefId': 'chef-a',
          'quantity': 2,
          'selectedAddOns': [
            {'id': 'addon-1', 'title': 'Raita', 'price': 15.0},
          ],
        },
        {
          'mealId': 'meal-2',
          'chefId': 'chef-b',
          'quantity': 1,
        },
      ];

      final body = CreateSplitOrderRequest.toBody(
        cartItems: cartItems,
        customerEmail: 'diner@example.com',
        deliveryFee: 40.0,
        tipAmount: 20,
        applyCoins: true,
      );

      expect(CreateSplitOrderRequest.functionName, 'create-split-order');
      expect(body.keys, containsAll([
        'cart_items',
        'customer_email',
        'delivery_fee',
        'tip_amount',
        'apply_coins',
      ]));
      expect(body.containsKey('total_amount'), isFalse);
      expect(body.containsKey('meal_id'), isFalse);
      expect(body['cart_items'], cartItems);
      expect(body['customer_email'], 'diner@example.com');
      expect(body['delivery_fee'], 40.0);
      expect(body['tip_amount'], 20);
      expect(body['apply_coins'], isTrue);
    });

    test('allows a multi-item cart without forcing a single meal_id', () {
      final body = CreateSplitOrderRequest.toBody(
        cartItems: [
          {'mealId': 'a', 'quantity': 1},
          {'mealId': 'b', 'quantity': 3},
        ],
        customerEmail: null,
        deliveryFee: 0,
        tipAmount: 0,
        applyCoins: false,
      );

      final items = body['cart_items'] as List;
      expect(items.length, 2);
      expect(body['meal_id'], isNull);
    });
  });
}
