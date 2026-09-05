import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/helpers.dart';

void main() {
  group('flashableOfferMeals', () {
    test('keeps live catalog offers and promo codes, skips sold-out and private rows', () {
      final offers = flashableOfferMeals([
        {
          'id': '1',
          'title': 'FESTIVE50',
          'price': 100,
          'quantity': 4,
          'status': 'Available',
          'offer_type': 'flashSale',
          'discount_value': 50,
          'promo_code': 'FESTIVE50',
        },
        {
          'id': '2',
          'title': 'Sold biryani',
          'price': 200,
          'quantity': 0,
          'status': 'sold out',
          'offer_type': 'percentage',
          'discount_value': 20,
        },
        {
          'id': '3',
          'title': 'Private plate',
          'customer_name': 'Asha',
          'price': 150,
          'quantity': 2,
          'status': 'Available',
          'promo_code': 'HOME20',
        },
      ]);

      expect(offers, hasLength(1));
      expect(offers.single['id'], '1');
      expect(offerFlashHeadline(offers.single), 'Use FESTIVE50');
      expect(offerFlashSubhead(offers.single), 'FESTIVE50');
    });

    test('hides a closed kitchen and labels an automatic flash sale', () {
      final meal = {
        'id': '4',
        'title': 'Dal Tadka',
        'chef_id': 'closed-chef',
        'price': 120,
        'quantity': 3,
        'status': 'Available',
        'offer_type': 'flashSale',
        'discount_value': 30,
      };
      expect(
        flashableOfferMeals([meal], excludedChefIds: {'closed-chef'}),
        isEmpty,
      );
      expect(offerFlashHeadline(meal), 'FLASH 30%');
    });
  });
}
