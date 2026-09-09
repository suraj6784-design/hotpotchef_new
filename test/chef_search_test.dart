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
      expect(isChefAccount({'role': 'Customer', 'name': 'User_hungry7'}), isFalse);
      expect(isChefAccount({'role': 'Driver'}), isFalse);
      expect(isChefAccount({'email': 'hungry7@example.com'}), isFalse);
    });
  });
}
