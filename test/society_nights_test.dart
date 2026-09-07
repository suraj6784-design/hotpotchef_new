import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/helpers.dart';

void main() {
  group('society nights', () {
    test('detects flagged nights and builds Home strip list', () {
      expect(isSocietyNight({'is_society_night': true}), isTrue);
      expect(isSocietyNight({'category': 'Society Night'}), isTrue);
      expect(isSocietyNight({'category': 'RWA dinner'}), isTrue);
      expect(isSocietyNight({'title': 'Society night thali'}), isTrue);
      expect(isSocietyNight({'category': 'Maharashtrian'}), isFalse);

      final list = societyNightMeals([
        {
          'id': '1',
          'title': 'Building Thali',
          'chef_name': 'Meera',
          'is_society_night': true,
          'society_label': 'Green Valley A',
          'quantity': 12,
          'status': 'Available',
          'price': 149,
          'time_slot': '19:30',
        },
        {
          'id': '2',
          'title': 'Dal',
          'quantity': 5,
          'status': 'Available',
          'is_society_night': false,
        },
        {
          'id': '3',
          'title': 'Sold night',
          'is_society_night': true,
          'quantity': 0,
          'status': 'Available',
        },
      ]);
      expect(list, hasLength(1));
      expect(societyNightHeadline(list.single), 'Green Valley A');
      expect(societyNightSubhead(list.single), contains('Building Thali'));
      expect(mealMatchesCuisine(list.single, 'Society Night'), isTrue);
      expect(
        mealShareText(list.single),
        contains('Society night at Green Valley A: Building Thali from Meera'),
      );
    });

    test('hard-matches society_label against diner address', () {
      expect(
        societyLabelMatchesAddress('Green Valley A', {
          'society_name': 'Green Valley Society',
          'wing': 'A',
          'flat_no': '1204',
        }),
        isTrue,
      );
      expect(
        societyLabelMatchesAddress('Green Valley A', {
          'society_name': 'Other Heights',
          'wing': 'B',
        }),
        isFalse,
      );

      final matched = societyNightMeals(
        [
          {
            'id': '1',
            'title': 'Building Thali',
            'is_society_night': true,
            'society_label': 'Green Valley A',
            'quantity': 12,
            'status': 'Available',
            'price': 149,
          },
        ],
        destinationAddress: {
          'society_name': 'Green Valley',
          'wing': 'A',
          'house_no': '12',
        },
      );
      expect(matched, hasLength(1));

      final filtered = societyNightMeals(
        [
          {
            'id': '1',
            'title': 'Building Thali',
            'is_society_night': true,
            'society_label': 'Green Valley A',
            'quantity': 12,
            'status': 'Available',
            'price': 149,
          },
        ],
        destinationAddress: {
          'society_name': 'Lakeview Residency',
          'wing': 'C',
        },
      );
      expect(filtered, isEmpty);
    });
  });
}
