import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/helpers.dart';

void main() {
  test('daily plates stay out of festival and pantry jars', () {
    expect(mealMatchesOccasion({'title': 'Veg Biryani', 'category': 'Indian'}, 'daily'), isTrue);
    expect(mealMatchesOccasion({'title': 'Diwali Box', 'is_hamper': true}, 'daily'), isFalse);
    expect(mealMatchesOccasion({'title': 'Mango pickle', 'is_shelf_item': true}, 'festive'), isFalse);
    expect(mealMatchesOccasion({'title': 'Mango pickle', 'is_shelf_item': true}, 'specialty'), isTrue);
  });

  test('festival sweets and family thalis land on the festive journey', () {
    expect(mealMatchesOccasion({'title': 'Motichoor laddu'}, 'festive'), isTrue);
    expect(mealMatchesOccasion({'title': 'Veg Jumbo Thali'}, 'family'), isTrue);
    expect(mealMatchesJourney({'title': 'Eid biryani'}, 'festive'), isTrue);
    expect(mealMatchesJourney({'title': 'Prasad box'}, 'festive', leaf: 'ceremony'), isTrue);
  });

  test('a stored occasion tag wins over the title', () {
    final meal = {
      'title': 'Veg Biryani',
      'health_tags': ['occasion:party'],
    };
    expect(mealStoredOccasionId(meal), 'party');
    expect(mealMatchesOccasion(meal, 'party'), isTrue);
    expect(mealMatchesOccasion(meal, 'daily'), isFalse);
    expect(orderOccasionLabel([meal]), 'Parties');
  });

  test('healthy and dietary chips use the existing diet words', () {
    expect(
      mealMatchesOccasion({'title': 'Millet bowl', 'health_tags': ['Millet']}, 'healthy'),
      isTrue,
    );
    expect(
      mealMatchesOccasion({'title': 'Sugar-free roti', 'health_tags': ['Diabetic']}, 'dietary'),
      isTrue,
    );
  });

  test('winter soups match seasonal in December', () {
    expect(
      mealMatchesOccasion({'title': 'Tomato soup'}, 'seasonal', now: DateTime(2026, 12, 1)),
      isTrue,
    );
    expect(
      mealMatchesOccasion({'title': 'Veg Biryani'}, 'seasonal', now: DateTime(2026, 12, 1)),
      isFalse,
    );
  });
}
