import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/helpers.dart';

void main() {
  group('shelf items', () {
    test('detects flagged pantry goods and builds Home strip list', () {
      expect(isShelfItem({'is_shelf_item': true}), isTrue);
      expect(isShelfItem({'category': 'Shelf'}), isTrue);
      expect(isShelfItem({'title': 'Mango pickle jar'}), isTrue);
      expect(isShelfItem({'shelf_kind': 'Masala'}), isTrue);
      expect(isShelfItem({'category': 'Maharashtrian'}), isFalse);

      final list = shelfItems([
        {
          'id': '1',
          'title': 'Godā masala',
          'chef_name': 'Lata',
          'is_shelf_item': true,
          'shelf_kind': 'Masala',
          'quantity': 8,
          'status': 'Available',
          'price': 120,
        },
        {
          'id': '2',
          'title': 'Dal',
          'quantity': 5,
          'status': 'Available',
          'is_shelf_item': false,
        },
        {
          'id': '3',
          'title': 'Sold pickle',
          'is_shelf_item': true,
          'quantity': 0,
          'status': 'Available',
        },
      ]);
      expect(list, hasLength(1));
      expect(shelfItemHeadline(list.single), 'Masala');
      expect(shelfItemSubhead(list.single), contains('Godā masala'));
      expect(mealMatchesCuisine(list.single, 'Shelf'), isTrue);
      expect(
        mealShareText(list.single),
        contains('Shelf from home (Masala): Godā masala from Lata'),
      );
    });
  });
}
