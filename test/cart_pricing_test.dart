// test/cart_pricing_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/models/cart_state.dart';
import 'package:hotpotchef_new/models/cart_enums.dart';

CartItemModel _buildItem({
  required int quantity,
  required Map<String, dynamic> mealDetails,
}) {
  return CartItemModel(
    id: '1',
    mealId: 'm1',
    chefId: 'c1',
    title: 'Test Meal',
    basePrice: (mealDetails['price'] as num?)?.toDouble() ?? 0.0,
    quantity: quantity,
    scheduledDate: DateTime.now(),
    serviceType: ServiceType.deliveryPlatform,
    rawMealDetails: mealDetails,
  );
}

void main() {
  group('CartState Discount & Offer Tests', () {
    test('Calculates standard price when no offer is active', () {
      final item = _buildItem(
        quantity: 2,
        mealDetails: {'price': 100, 'offer_type': 'None'},
      );

      final state = CartState(items: [item]);
      expect(state.getEffectiveItemTotal(item), 200.0);
    });

    test('Calculates BOGO (Buy 1 Get 1) correctly for odd quantities', () {
      final item = _buildItem(
        quantity: 3, // Buy 2, Get 1 free (Pay for 2)
        mealDetails: {'price': 150, 'offer_type': 'BOGO (Buy 1 Get 1)'},
      );

      final state = CartState(items: [item]);
      // 3 items -> paidQty = (3 ~/ 2) + (3 % 2) = 1 + 1 = 2 items paid -> 150 * 2 = 300
      expect(state.getEffectiveItemTotal(item), 300.0);
    });

    test('Calculates Percentage Discount correctly', () {
      final item = _buildItem(
        quantity: 2,
        mealDetails: {
          'price': 200,
          'offer_type': 'Percentage Discount (%)',
          'discount_value': 20, // 20% off -> 160 per unit
        },
      );

      final state = CartState(items: [item]);
      expect(state.getEffectiveItemTotal(item), 320.0);
    });

    test('Respects offer expiration correctly', () {
      final expiredDate =
          DateTime.now().subtract(const Duration(hours: 1)).toIso8601String();
      final item = _buildItem(
        quantity: 1,
        mealDetails: {
          'price': 100,
          'offer_type': 'Flat Discount (₹)',
          'discount_value': 50,
          'offer_valid_until': expiredDate, // Already expired
        },
      );

      final state = CartState(items: [item]);
      // Should ignore discount because offer is expired -> returns full price 100
      expect(state.getEffectiveItemTotal(item), 100.0);
    });
  });
}
