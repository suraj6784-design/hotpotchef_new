import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/delivery_fee.dart';

void main() {
  test('guest Home select stays on granted catalog columns', () {
    expect(kHomeMealCatalogSelect.contains('*'), isFalse);
    expect(kHomeMealCatalogSelectMinimal.contains('*'), isFalse);
    expect(kHomeMealCatalogSelect.contains('hosting_address'), isTrue);
    expect(kHomeMealCatalogSelect.contains('allergens'), isTrue);
    expect(kHomeMealCatalogSelectMinimal.contains('hosting_address'), isFalse);
    expect(kHomeMealCatalogSelect.contains('add_ons'), isTrue);
    expect(kHomeMealCatalogSelect.contains('offer_valid_until'), isTrue);
    expect(kHomeMealCatalogSelect.contains('occasion'), isTrue);
    expect(kHomeMealCatalogSelectMinimal.contains('occasion'), isFalse);
  });
}
