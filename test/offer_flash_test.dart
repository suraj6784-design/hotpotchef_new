import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/helpers.dart';

Map<String, dynamic> _live(Map<String, dynamic> extra) {
  return {
    'price': 100,
    'quantity': 4,
    'status': 'Available',
    'service_type': 'Delivery',
    'hosting_address': 'Pune',
    'pickup_lat': 18.52,
    'pickup_lng': 73.85,
    'time_slot': 'Daily (6:30 PM to 9:30 PM)',
    ...extra,
  };
}

void main() {
  group('flashableOfferMeals', () {
    test('keeps live catalog offers and promo codes, skips sold-out and private rows', () {
      final now = DateTime(2026, 9, 12, 19, 0);
      final offers = flashableOfferMeals([
        _live({
          'id': '1',
          'title': 'FESTIVE50',
          'offer_type': 'flashSale',
          'discount_value': 50,
          'promo_code': 'FESTIVE50',
        }),
        _live({
          'id': '2',
          'title': 'Sold biryani',
          'price': 200,
          'quantity': 0,
          'status': 'sold out',
          'offer_type': 'percentage',
          'discount_value': 20,
        }),
        _live({
          'id': '3',
          'title': 'Private plate',
          'customer_name': 'Asha',
          'price': 150,
          'quantity': 2,
          'promo_code': 'HOME20',
        }),
      ], now: now);

      expect(offers, hasLength(1));
      expect(offers.single['id'], '1');
      expect(offerFlashHeadline(offers.single), 'Flash Sale');
      expect(offerFlashSubhead(offers.single), 'Flash Sale · tap to browse');
    });

    test('shows gated BOGO and Flash families beside Flat, hides expired %', () {
      final now = DateTime(2026, 9, 9, 6, 30);
      final offers = flashableOfferMeals([
        _live({
          'id': 'bogo',
          'title': 'PromoSales',
          'quantity': 2,
          'offer_type': 'BOGO (Buy 1 Get 1)',
          'promo_code': 'BOGO',
          'time_slot': 'Daily (6:30 PM to 9:30 PM)',
        }),
        _live({
          'id': 'flash',
          'title': 'FESTIVE50',
          'quantity': 8,
          'offer_type': 'flashSale',
          'promo_code': 'FESTIVE50',
        }),
        _live({
          'id': 'flat',
          'title': 'Veg Jumbo Thali',
          'quantity': 8,
          'offer_type': 'flat',
          'offer_valid_until': DateTime(2026, 9, 10).toIso8601String(),
        }),
        _live({
          'id': 'pct',
          'title': 'DiscountTest',
          'quantity': 18,
          'offer_type': 'Percentage Discount (%)',
          'offer_valid_until': DateTime(2026, 8, 16).toIso8601String(),
        }),
      ], now: now);

      expect(
        offers.map((meal) => meal['_offer_group']),
        ['flashSale', 'bogo', 'flat'],
      );
      expect(offerFlashHeadline(offers[0]), 'Flash Sale');
      expect(offerFlashHeadline(offers[1]), 'BOGO');
      expect(offerFlashHeadline(offers[2]), 'Flat Discount');
    });

    test('hides a closed kitchen and labels an automatic flash sale', () {
      final meal = _live({
        'id': '4',
        'title': 'Dal Tadka',
        'chef_id': 'closed-chef',
        'price': 120,
        'quantity': 3,
        'offer_type': 'flashSale',
        'discount_value': 30,
      });
      expect(
        flashableOfferMeals([meal], excludedChefIds: {'closed-chef'}),
        isEmpty,
      );
      expect(offerFlashHeadline(meal), 'FLASH 30%');
    });

    test('boosted dishes still appear beside offer families', () {
      final now = DateTime(2026, 9, 6, 15);
      final boosted = _live({
        'id': 'boosted',
        'title': 'Ragi dosa',
        'boosted_until': DateTime(2026, 9, 7).toIso8601String(),
      });
      final promo = _live({
        'id': 'promo',
        'title': 'FESTIVE50',
        'promo_code': 'FESTIVE50',
        'offer_type': 'flashSale',
        'discount_value': 50,
      });
      final expiredBoost = _live({
        'id': 'old',
        'title': 'Yesterday',
        'boosted_until': DateTime(2026, 9, 6).toIso8601String(),
      });
      final offers = flashableOfferMeals([promo, expiredBoost, boosted], now: now);
      expect(offers.map((meal) => meal['id']), ['promo', 'boosted']);
      expect(offerFlashHeadline(boosted, now: now), 'Boosted today');
      expect(isMealBoosted(expiredBoost, now: now), isFalse);
      expect(kChefBoostRupees, 99);
    });

    test('hides tonight offers when no plate can be booked today', () {
      final fridayNight = DateTime(2026, 9, 11, 2, 40);
      final weekendOnly = _live({
        'id': 'festive50',
        'title': 'FESTIVE50',
        'quantity': 8,
        'offer_type': 'flashSale',
        'promo_code': 'FESTIVE50',
        'time_slot': 'Sat, Sun (11:00 AM to 6:00 PM)',
      });
      expect(flashableOfferMeals([weekendOnly], now: fridayNight), isEmpty);

      final windowOver = _live({
        'id': 'lunch',
        'title': 'Flash thali',
        'offer_type': 'flashSale',
        'time_slot': 'Daily (11:00 AM to 12:00 PM)',
      });
      expect(
        flashableOfferMeals([windowOver], now: DateTime(2026, 9, 11, 14, 0)),
        isEmpty,
      );

      final liveTonight = {
        ...weekendOnly,
        'id': 'live',
        'time_slot': 'Daily (6:30 PM to 9:30 PM)',
      };
      expect(
        flashableOfferMeals([liveTonight], now: DateTime(2026, 9, 11, 14, 0)).single['id'],
        'live',
      );
    });
  });

  test('incomplete leftover plates fail current catalog requirements', () {
    expect(
      mealFailsCurrentCatalogRequirements({
        'title': 'NewChef19',
        'price': 0,
        'status': 'Available',
        'time_slot': 'Flexible',
      }),
      isTrue,
    );
    expect(
      mealFailsCurrentCatalogRequirements(_live({
        'title': 'Veg Thali',
        'price': 150,
      })),
      isFalse,
    );
    expect(mealHasPlaceholderOrMissingSlot({'time_slot': 'Flexible'}), isTrue);
    expect(mealHasPlaceholderOrMissingSlot({'time_slot': 'Daily (6:30 PM to 9:30 PM)'}), isFalse);
  });
}
