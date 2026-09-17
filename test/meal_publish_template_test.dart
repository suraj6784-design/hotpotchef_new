import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/meal_publish_template.dart';

void main() {
  test('catalog category keeps hamper and dessert buckets', () {
    expect(
      mealCatalogCategory(
        cuisine: 'Italian',
        dishCourse: 'Main Course',
        hamper: false,
        society: false,
        shelf: false,
      ),
      'Italian',
    );
    expect(
      mealCatalogCategory(
        cuisine: 'Indian',
        dishCourse: 'Dessert',
        hamper: false,
        society: false,
        shelf: false,
      ),
      'Desserts',
    );
    expect(
      mealCatalogCategory(
        cuisine: 'Indian',
        dishCourse: 'Snack',
        hamper: true,
        society: false,
        shelf: false,
      ),
      'Festival Hamper',
    );
  });

  test('infers cuisine and course from legacy category', () {
    expect(inferMealCuisine({'category': 'Punjabi'}), 'Punjabi');
    expect(inferMealCourse({'category': 'Desserts'}), 'Dessert');
    expect(inferMealCourse({'dish_course': 'Starter', 'category': 'Desserts'}), 'Starter');
  });

  test('prep line and allergens parse from stored meal', () {
    expect(
      mealPrepServingLine({
        'prep_minutes': 15,
        'cook_minutes': 20,
        'serving_size': '2 people',
        'storage_hours': 4,
      }),
      'Prep 15 min · Cook 20 min · 2 people · Best within 4 hr',
    );
    expect(
      mealAllergenList({'allergens': ['dairy', 'Nuts']}).toSet(),
      {'Nuts', 'Dairy'},
    );
  });
}
