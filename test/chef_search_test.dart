import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/helpers.dart';

void main() {
  group('chefNameMatchesQuery', () {
    test('matches chef and kitchen labels', () {
      expect(
        chefNameMatchesQuery('asha', {'name': 'Asha Patil', 'role': 'Chef'}),
        isTrue,
      );
      expect(
        chefNameMatchesQuery('kitchen', {'local_kitchen_name': 'Asha Kitchen'}),
        isTrue,
      );
      expect(
        chefNameMatchesQuery('paneer', {'chef_name': 'Meera', 'title': 'Paneer Butter'}),
        isFalse,
      );
      expect(chefNameMatchesQuery('', {'name': 'Asha'}), isFalse);
    });

    test('isChefAccount ignores diner and driver rows', () {
      expect(isChefAccount({'role': 'Chef'}), isTrue);
      expect(isChefAccount({'role': 'chef'}), isTrue);
      expect(isChefAccount({'role': 'Customer', 'name': 'Arushi'}), isFalse);
      expect(isChefAccount({'role': 'Chef', 'chef_name': 'Arushi'}), isTrue);
      expect(isChefAccount({'role': 'Driver'}), isFalse);
      expect(isChefAccount({'email': 'hungry7@example.com'}), isFalse);
      expect(isChefAccount({'role': 'Chef', 'name': 'Arushi'}), isTrue);
    });

    test('meal chef labels do not treat a diner name on the meal as a kitchen', () {
      expect(
        mealChefLabelMatchesQuery('arushi', {
          'name': 'Arushi',
          'full_name': 'Arushi',
          'chef_name': 'Meera Kitchen',
          'chef_id': 'customer-1',
        }),
        isFalse,
      );
      expect(
        mealChefLabelMatchesQuery('arushi', {
          'chef_name': 'Arushi',
          'chef_id': 'chef-1',
        }),
        isTrue,
      );
    });
  });
}
