import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/helpers.dart';

void main() {
  group('festival hampers', () {
    test('detects flagged hampers and builds Home strip list', () {
      expect(isFestivalHamper({'is_hamper': true}), isTrue);
      expect(isFestivalHamper({'category': 'Festival Hamper'}), isTrue);
      expect(isFestivalHamper({'title': 'Diwali hamper box'}), isTrue);
      expect(isFestivalHamper({'category': 'Maharashtrian'}), isFalse);

      final list = festivalHamperMeals([
        {
          'id': '1',
          'title': 'Diwali Box',
          'chef_name': 'Asha',
          'is_hamper': true,
          'quantity': 3,
          'status': 'Available',
          'price': 499,
        },
        {
          'id': '2',
          'title': 'Dal',
          'quantity': 5,
          'status': 'Available',
          'is_hamper': false,
        },
        {
          'id': '3',
          'title': 'Sold hamper',
          'is_hamper': true,
          'quantity': 0,
          'status': 'Available',
        },
      ]);
      expect(list, hasLength(1));
      expect(festivalHamperHeadline(list.single), 'Festival hamper');
      expect(festivalHamperSubhead(list.single), contains('Diwali Box'));
      expect(mealMatchesCuisine(list.single, 'Festival Hamper'), isTrue);
      expect(
        mealShareText(list.single),
        contains('Festival hamper: Diwali Box from Asha'),
      );
    });
  });
}
