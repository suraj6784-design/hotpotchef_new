import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/occasion_catalog.dart';

void main() {
  test('home lists every occasion group the diner can broadcast', () {
    expect(kOccasionGroups.map((group) => group.title), [
      'Everyday',
      'Family functions',
      'Parties',
      'Specialty',
    ]);
    expect(kFoodOccasions, hasLength(16));
    expect(kFoodOccasions.map((occasion) => occasion.id).toSet(), hasLength(16));
  });

  test('a plate can belong to more than one occasion', () {
    const laddu = {'title': 'Motichoor laddu', 'category': 'Desserts'};
    expect(plateMatchesFoodOccasion(laddu, foodOccasionById('festivals')!), isTrue);
    expect(plateMatchesFoodOccasion(laddu, foodOccasionById('sweets')!), isTrue);
    expect(plateMatchesFoodOccasion(laddu, foodOccasionById('pickles')!), isFalse);
  });

  test('daily meals match a thali and not a pickle jar', () {
    expect(
      plateMatchesFoodOccasion({'title': 'Veg Jumbo Thali'}, foodOccasionById('daily-meals')!),
      isTrue,
    );
    expect(
      plateMatchesFoodOccasion({'title': 'Mango pickle'}, foodOccasionById('daily-meals')!),
      isFalse,
    );
    expect(foodOccasionByLabel('Daily meals')?.id, 'daily-meals');
  });
}
