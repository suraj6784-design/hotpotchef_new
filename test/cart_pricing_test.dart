// test/cart_pricing_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/models/cart_state.dart';
import 'package:hotpotchef_new/models/cart_enums.dart';
import 'package:hotpotchef_new/utils/helpers.dart';

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

    test('Calculates BOGO for even quantities using chef enum names', () {
      final item = _buildItem(
        quantity: 2,
        mealDetails: {'price': 150, 'offer_type': 'bogo'},
      );
      expect(CartState(items: [item]).getEffectiveItemTotal(item), 150.0);
    });

    test('Calculates flat discount per portion', () {
      final item = _buildItem(
        quantity: 3,
        mealDetails: {
          'price': 200,
          'offer_type': 'flat',
          'discount_value': 40,
        },
      );
      expect(CartState(items: [item]).getEffectiveItemTotal(item), 480.0);
    });

    test('Calculates flash sale as a percentage', () {
      final item = _buildItem(
        quantity: 2,
        mealDetails: {
          'price': 250,
          'offer_type': 'flashSale',
          'discount_value': 20,
        },
      );
      expect(CartState(items: [item]).getEffectiveItemTotal(item), 400.0);
    });

    test('Caps a percentage discount at max_discount_cap', () {
      final item = _buildItem(
        quantity: 2,
        mealDetails: {
          'price': 500,
          'offer_type': 'percentage',
          'discount_value': 50,
          'max_discount_cap': 100,
        },
      );
      // 50% of 1000 = 500, capped at ₹100 → 900
      expect(CartState(items: [item]).getEffectiveItemTotal(item), 900.0);
    });
  });

  test('toCheckoutPayload snapshots the paid unit for place_customer_order', () {
    final item = _buildItem(
      quantity: 3,
      mealDetails: {
        'price': 150,
        'offer_type': 'bogo',
        'discount_value': 0,
      },
    );
    final payload = item.toCheckoutPayload();
    expect(payload['base_price'], 150.0);
    expect(payload['price'], 100.0);
    expect(payload['discounted_price'], 100.0);
    expect(payload['line_net'], 300.0);
    expect(payload['offer_applied'], isTrue);
  });

  test('checkoutCartPayload keeps offer math after JSON sanitizing', () {
    final item = _buildItem(
      quantity: 2,
      mealDetails: {
        'price': 200,
        'offer_type': 'percentage',
        'discount_value': 20,
        'max_discount_cap': 0,
      },
    );
    final lines = checkoutCartPayload([item.toCheckoutPayload()]);
    expect(lines.single['base_price'], 200.0);
    expect(lines.single['price'], 160.0);
    expect(lines.single['discounted_price'], 160.0);
    expect(lines.single['line_net'], 320.0);
    expect(lines.single['offer_type'], 'percentage');
  });

  test('FESTIVE50 with a blank flash-sale percent is 50% off, not the 20% default', () {
    final item = _buildItem(
      quantity: 1,
      mealDetails: {
        'price': 100,
        'offer_type': 'Flash Sale',
        'discount_value': 0,
        'promo_code': 'FESTIVE50',
      },
    );
    expect(CartState(items: [item]).getEffectiveItemTotal(item), 100.0);

    final unlocked = checkoutCartPayload(
      [item.toCheckoutPayload()],
      appliedPromoCode: 'FESTIVE50',
    );
    expect(unlocked.single['line_net'], 50.0);
    expect(unlocked.single['price'], 50.0);
  });

  test('an explicit flash-sale percent is not overwritten by the code digits', () {
    final item = _buildItem(
      quantity: 1,
      mealDetails: {
        'price': 100,
        'offer_type': 'flashSale',
        'discount_value': 15,
        'promo_code': 'FESTIVE50',
      },
    );
    final unlocked = checkoutCartPayload(
      [item.toCheckoutPayload()],
      appliedPromoCode: 'FESTIVE50',
    );
    expect(unlocked.single['line_net'], 85.0);
  });

  test('a promo code unlocks a gated meal offer at checkout', () {
    final item = _buildItem(
      quantity: 2,
      mealDetails: {
        'price': 200,
        'offer_type': 'percentage',
        'discount_value': 20,
        'promo_code': 'HOME20',
      },
    );
    expect(CartState(items: [item]).getEffectiveItemTotal(item), 400.0);
    expect(item.toCheckoutPayload()['price'], 200.0);

    final unlocked = checkoutCartPayload([item.toCheckoutPayload()], appliedPromoCode: 'home20');
    expect(unlocked.single['price'], 160.0);
    expect(unlocked.single['line_net'], 320.0);
    expect(unlocked.single['applied_promo_code'], 'HOME20');
  });

  test('a matching promo extra stacks on top of the automatic offer', () {
    final item = _buildItem(
      quantity: 1,
      mealDetails: {
        'price': 200,
        'offer_type': 'percentage',
        'discount_value': 20,
        'promo_code': 'STACK10',
        'promo_discount_type': 'percentage',
        'promo_discount_value': 10,
      },
    );
    expect(CartState(items: [item]).getEffectiveItemTotal(item), 160.0);

    final stacked = checkoutCartPayload([item.toCheckoutPayload()], appliedPromoCode: 'STACK10');
    expect(stacked.single['line_net'], 144.0);
    expect(stacked.single['offer_description'], contains('Promo 10%'));
  });

  test('a stacked flat promo comes off the already-discounted line', () {
    final item = _buildItem(
      quantity: 2,
      mealDetails: {
        'price': 200,
        'offer_type': 'flashSale',
        'discount_value': 20,
        'promo_code': 'FLAT40',
        'promo_discount_type': 'flat',
        'promo_discount_value': 40,
      },
    );
    expect(CartState(items: [item]).getEffectiveItemTotal(item), 320.0);
    final stacked = checkoutCartPayload([item.toCheckoutPayload()], appliedPromoCode: 'FLAT40');
    expect(stacked.single['line_net'], 280.0);
  });

  test('a wrong promo code does not change the automatic offer', () {
    final item = _buildItem(
      quantity: 1,
      mealDetails: {
        'price': 200,
        'offer_type': 'flat',
        'discount_value': 40,
        'promo_code': 'SAVE40',
        'promo_discount_type': 'percentage',
        'promo_discount_value': 10,
      },
    );
    final lines = checkoutCartPayload([item.toCheckoutPayload()], appliedPromoCode: 'NOPE');
    expect(lines.single['line_net'], 160.0);
    expect(lines.single['applied_promo_code'], isNull);
  });

  test('expired offers are snapshotted at list price', () {
    final item = _buildItem(
      quantity: 1,
      mealDetails: {
        'price': 100,
        'offer_type': 'flat',
        'discount_value': 50,
        'offer_valid_until': DateTime.now().subtract(const Duration(hours: 1)).toIso8601String(),
      },
    );
    final lines = checkoutCartPayload([item.toCheckoutPayload()]);
    expect(lines.single['price'], 100.0);
    expect(lines.single['discounted_price'], isNull);
    expect(lines.single['offer_applied'], isFalse);
  });

  test('toMealMap keeps chef, meal id, and price for a group-order join', () {
    final item = CartItemModel(
      id: 'line-1',
      mealId: 'meal-9',
      chefId: 'chef-3',
      title: 'Dal fry',
      basePrice: 180,
      quantity: 2,
      scheduledDate: DateTime.now(),
      serviceType: ServiceType.deliveryPlatform,
      rawMealDetails: const {'title': 'Old title', 'price': 160},
    );
    final meal = item.toMealMap();
    expect(meal['id'], 'meal-9');
    expect(meal['chef_id'], 'chef-3');
    expect(meal['title'], 'Dal fry');
    expect(meal['price'], 160);
  });

  test('checkout snapshot folds add-ons into the paid unit', () {
    final item = CartItemModel(
      id: '1',
      mealId: 'm1',
      chefId: 'c1',
      title: 'Test Meal',
      basePrice: 200,
      quantity: 2,
      scheduledDate: DateTime.now(),
      serviceType: ServiceType.deliveryPlatform,
      selectedAddOns: const [CartItemAddOn(id: 'a1', title: 'Raita', price: 40)],
      rawMealDetails: const {'price': 200, 'offer_type': 'none'},
    );
    expect(CartState(items: [item]).getEffectiveItemTotal(item), 480.0);
    final payload = item.toCheckoutPayload();
    expect(payload['addons_unit'], 40.0);
    expect(payload['price'], 240.0);
    expect(payload['line_net'], 480.0);
    expect(lineItemUnitPrice(payload), 240.0);

    final lines = checkoutCartPayload([payload]);
    expect(lines.single['price'], 240.0);
    expect(lines.single['line_net'], 480.0);
    expect(lines.single['addons_unit'], 40.0);
  });

  test('cart estimated total includes packaging and a delivery estimate', () {
    final item = _buildItem(quantity: 1, mealDetails: {'price': 200, 'offer_type': 'none'});
    final state = CartState(items: [item]);
    expect(state.packagingFee, 20);
    expect(state.estimatedDeliveryFee, 30);
    expect(state.grandTotal, 250);
    expect(state.deliveryFeeIsEstimate, isTrue);
  });

  test('coins cannot apply when a chef refuses HotPot Coins', () {
    final item = _buildItem(
      quantity: 1,
      mealDetails: {'price': 200, 'accepts_hotpot_coins': false},
    );
    final state = CartState(items: [item], applyCoins: true, userCoinBalance: 50);
    expect(state.coinsAcceptedByVendors, isFalse);
    expect(state.coinsDiscountAmount, 0);
    expect(state.grandTotal, 250);
  });

  test('isMealAvailableForCart refuses sold-out and empty stock', () {
    expect(
      isMealAvailableForCart({'id': '1', 'quantity': 3, 'status': 'Available'}),
      isTrue,
    );
    expect(
      isMealAvailableForCart({'id': '1', 'quantity': 0, 'status': 'Available'}),
      isFalse,
    );
    expect(
      isMealAvailableForCart({'id': '1', 'quantity': 4, 'status': 'Sold Out'}),
      isFalse,
    );
    expect(
      isMealAvailableForCart({'id': '1', 'quantity': 2, 'status': 'Paused'}),
      isFalse,
    );
  });
}
