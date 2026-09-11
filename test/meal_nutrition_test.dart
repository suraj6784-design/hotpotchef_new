import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/meal_nutrition.dart';

void main() {
  test('reads chef nutrition fields and aliases', () {
    final facts = mealNutritionFacts({
      'calories_kcal': 320,
      'portion_weight_g': 250,
      'protein_g': 18.5,
      'carbs_g': 40,
      'fat_g': 8,
      'fiber_g': 6,
    });
    expect(facts.hasValues, isTrue);
    expect(facts.tiles.map((t) => t.$1).toList(), ['Cal', 'Wt', 'Protein', 'Carbs', 'Fat', 'Fiber']);
    expect(facts.compactLine, contains('kcal'));
    expect(facts.compactLine, contains('Protein'));
  });

  test('blank and zero nutrition is hidden', () {
    expect(mealNutritionFacts({'calories_kcal': 0, 'protein': ''}).hasValues, isFalse);
  });
}
