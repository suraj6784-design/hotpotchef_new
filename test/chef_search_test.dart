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
  });
}
