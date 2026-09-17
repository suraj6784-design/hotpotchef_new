import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/helpers.dart';

void main() {
  group('chef card locale', () {
    test('normalizes locales and prefers local kitchen names', () {
      expect(normalizeChefCardLocale('MR'), 'mr');
      expect(normalizeChefCardLocale('gu'), 'en');
      expect(chefCardLocaleLabel('hi'), 'हिन्दी');
      expect(chefCardLocaleLabel('mr'), 'मराठी');

      expect(
        chefCardDisplayName({
          'chef_name': 'Asha Kitchen',
          'local_kitchen_name': 'आशा किचन',
          'card_locale': 'mr',
        }),
        'आशा किचन',
      );
      expect(
        chefCardDisplayName({
          'chef_name': 'Asha Kitchen',
          'local_kitchen_name': 'आशा किचन',
          'card_locale': 'en',
        }),
        'Asha Kitchen',
      );

      expect(chefCardCopy('mr').homeKitchen, 'घरची स्वयंपाकघर');
      expect(chefCardCopy('hi').cookedMeals(12), '12 प्लेटें पकाईं');
      expect(chefCardCopy('en').followKitchen, 'Follow kitchen');
    });
  });
}
