import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/meal_catalog.dart';

void main() {
  test('sellable meals are Available inventory only', () {
    expect(
      MealCatalog.isSellable({'status': 'Available', 'customer_name': null}),
      isTrue,
    );
    expect(
      MealCatalog.isSellable({'status': 'Archived', 'customer_name': ''}),
      isFalse,
    );
    expect(
      MealCatalog.isSellable({'status': 'Closed', 'customer_name': ''}),
      isFalse,
    );
    expect(
      MealCatalog.isSellable({'status': 'Paused', 'customer_name': ''}),
      isFalse,
    );
    expect(
      MealCatalog.isSellable({'status': 'cancelled', 'customer_name': ''}),
      isFalse,
    );
    expect(
      MealCatalog.isSellable({'status': 'Available', 'customer_name': 'x@y.com'}),
      isFalse,
    );
  });
}
