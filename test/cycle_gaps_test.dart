import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/helpers.dart';

void main() {
  group('mergedOrderInstructions', () {
    test('joins per-item notes with the checkout field', () {
      expect(
        mergedOrderInstructions(
          [
            {'title': 'Dal', 'specialInstructions': 'Less spice'},
            {'title': 'Rice', 'special_instructions': 'No ghee'},
          ],
          'Leave at gate',
        ),
        'Dal: Less spice\nRice: No ghee\nLeave at gate',
      );
    });
  });

  group('claimedStreakOnIstDate', () {
    test('compares the stored date to Asia/Kolkata, not the device local day', () {
      final utcEvening = DateTime.utc(2026, 9, 4, 20, 0); // 01:30 IST on 5 Sep
      expect(istCalendarDate(utcEvening), DateTime(2026, 9, 5));
      expect(claimedStreakOnIstDate('2026-09-05', now: utcEvening), isTrue);
      expect(claimedStreakOnIstDate('2026-09-04', now: utcEvening), isFalse);
    });
  });

  group('packagingFeeForLoyaltyTier', () {
    test('Gold is free, Silver is ₹10, Bronze is ₹20', () {
      expect(packagingFeeForLoyaltyTier('Gold Foodie'), 0);
      expect(packagingFeeForLoyaltyTier('Silver Foodie'), 10);
      expect(packagingFeeForLoyaltyTier('Bronze Foodie'), 20);
      expect(packagingFeeForLoyaltyTier(null), 20);
    });
  });

  group('kitchen closed checkout', () {
    test('reads the kitchen_closed code and copy', () {
      expect(isKitchenClosedCheckoutError(null, {'code': 'kitchen_closed'}), isTrue);
      expect(isKitchenClosedCheckoutError('This kitchen is closed right now'), isTrue);
      expect(isKitchenClosedCheckoutError('sold out'), isFalse);
      expect(kitchenClosedCheckoutMessage(charged: false), contains('Nothing was charged'));
    });
  });

  group('chefPayoutStatusLabel', () {
    test('labels settlement states chefs can act on', () {
      expect(chefPayoutStatusLabel('released'), 'Payout released');
      expect(chefPayoutStatusLabel('awaiting_account'), contains('bank account'));
      expect(chefPayoutStatusLabel('failed'), contains('retry'));
      expect(chefPayoutStatusLabel(null), 'Payout pending');
    });
  });

  group('uniqueReviewableOrderItems', () {
    test('keeps one row per meal so every dish can be rated', () {
      final unique = uniqueReviewableOrderItems([
        {'source_meal_id': 'dal', 'title': 'Dal'},
        {'source_meal_id': 'dal', 'title': 'Dal'},
        {'source_meal_id': 'rice', 'title': 'Rice'},
      ]);
      expect(unique, hasLength(2));
      expect(unique.map((item) => item['title']), ['Dal', 'Rice']);
    });
  });

  group('dietSkipReason', () {
    test('blocks an allergen listed on the customer profile', () {
      expect(
        dietSkipReason(
          {'title': 'Butter chicken', 'description': 'Rich dairy gravy'},
          allergies: 'dairy',
        ),
        contains('allergen'),
      );
    });
  });

  group('cartAcceptsHotpotCoins', () {
    test('refuses the cart when any line opts out', () {
      expect(
        cartAcceptsHotpotCoins([
          {'title': 'Dal', 'accepts_hotpot_coins': true},
          {'title': 'Biryani', 'accepts_hotpot_coins': false},
        ]),
        isFalse,
      );
    });
  });
}
