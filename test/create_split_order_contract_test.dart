import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/services/create_split_order_contract.dart';
import 'package:hotpotchef_new/utils/helpers.dart';

void main() {
  group('CreateSplitOrderRequest contract', () {
    test('builds the pending-checkout body checkout sends to create-split-order', () {
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
        customerPhone: '9999999999',
        deliveryAddress: 'Kothrud',
        instructions: 'Gate 2',
        dropoffLat: 18.5,
        dropoffLng: 73.8,
        tipAmount: 20,
        applyCoins: true,
        addMembership: true,
        membershipPlanId: 'plan-90',
      );

      expect(CreateSplitOrderRequest.functionName, 'create-split-order');
      expect(body.keys, containsAll([
        'cart_items',
        'customer_email',
        'customer_phone',
        'delivery_address',
        'instructions',
        'dropoff_lat',
        'dropoff_lng',
        'tip_amount',
        'apply_coins',
        'add_membership',
        'membership_plan_id',
      ]));
      expect(body.containsKey('total_amount'), isFalse);
      expect(body.containsKey('delivery_fee'), isFalse);
      expect(body.containsKey('meal_id'), isFalse);
      expect(body.containsKey('chef_transfer'), isFalse);
      expect(body['cart_items'], cartItems);
      expect(body['customer_email'], 'diner@example.com');
      expect(body['tip_amount'], 20);
      expect(body['apply_coins'], isTrue);
      expect(body['add_membership'], isTrue);
      expect(body['membership_plan_id'], 'plan-90');
    });

    test('allows a multi-item cart without forcing a single meal_id', () {
      final body = CreateSplitOrderRequest.toBody(
        cartItems: [
          {'mealId': 'a', 'quantity': 1},
          {'mealId': 'b', 'quantity': 3},
        ],
        customerEmail: null,
        tipAmount: 0,
        applyCoins: false,
      );

      final items = body['cart_items'] as List;
      expect(items.length, 2);
      expect(body['meal_id'], isNull);
    });
  });

  group('checkout init errors from edge JSON', () {
    test('maps sold_out HTTP 400 payload to diner copy', () {
      expect(
        checkoutInitErrorMessage(null, {
          'success': false,
          'code': 'sold_out',
          'error': 'This meal just sold out. Nothing was charged.',
        }),
        contains('Nothing was charged'),
      );
    });

    test('maps kitchen_closed and unauthorized payloads', () {
      expect(
        checkoutInitErrorMessage({'success': false, 'code': 'kitchen_closed'}),
        contains('kitchen is closed'),
      );
      expect(
        checkoutInitErrorMessage({'success': false, 'error': 'Unauthorized'}),
        'Please sign in to continue.',
      );
    });
  });
}
