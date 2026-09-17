/// Chef publish-meal catalog fields used by the kitchen form and diner plate.
const List<String> kMealCuisines = [
  'Maharashtrian',
  'Punjabi',
  'South Indian',
  'North Indian',
  'Indian',
  'Italian',
  'Fusion',
  'Chinese',
  'Mexican',
  'Continental',
  'Healthy & Salads',
  'Other',
];

const List<String> kMealCourses = [
  'Starter',
  'Main Course',
  'Dessert',
  'Snack',
];

const List<String> kMealAllergens = [
  'Nuts',
  'Dairy',
  'Gluten',
  'Soy',
  'Egg',
  'Shellfish',
  'Sesame',
];

const List<String> kMealDietLabels = [
  'Vegan',
  'Vegetarian',
  'Non-Veg',
  'Gluten-Free',
];

String mealCatalogCategory({
  required String cuisine,
  required String dishCourse,
  required bool hamper,
  required bool society,
  required bool shelf,
}) {
  if (hamper) return 'Festival Hamper';
  if (society) return 'Society Night';
  if (shelf) return 'Shelf';
  switch (dishCourse) {
    case 'Dessert':
      return 'Desserts';
    case 'Snack':
      return 'Snacks';
    default:
      return cuisine.trim().isEmpty ? 'Indian' : cuisine.trim();
  }
}

String inferMealCuisine(Map<String, dynamic> meal) {
  final stored = meal['cuisine']?.toString().trim() ?? '';
  if (stored.isNotEmpty) {
    return kMealCuisines.contains(stored) ? stored : 'Other';
  }
  final category = meal['category']?.toString().trim() ?? '';
  if (kMealCuisines.contains(category)) return category;
  if (category == 'Festival Hamper' || category == 'Society Night' || category == 'Shelf') {
    return 'Indian';
  }
  if (category == 'Desserts' || category == 'Snacks') return 'Indian';
  return 'Maharashtrian';
}

String inferMealCourse(Map<String, dynamic> meal) {
  final stored = meal['dish_course']?.toString().trim() ?? '';
  if (kMealCourses.contains(stored)) return stored;
  final category = meal['category']?.toString().trim() ?? '';
  if (category == 'Desserts') return 'Dessert';
  if (category == 'Snacks') return 'Snack';
  return 'Main Course';
}

String inferMealAvailabilityMode(Map<String, dynamic> meal, {bool Function(String?)? isLiveSlot}) {
  final stored = meal['availability_mode']?.toString().trim().toLowerCase() ?? '';
  if (stored == 'live' || stored == 'preorder' || stored == 'pre-order') {
    return stored == 'live' ? 'live' : 'preorder';
  }
  final slot = meal['time_slot']?.toString();
  if (isLiveSlot != null && isLiveSlot(slot)) return 'live';
  return 'preorder';
}

List<String> mealAllergenList(Map<String, dynamic> meal) {
  final raw = meal['allergens'] ?? meal['allergen_tags'];
  if (raw is Iterable) {
    return [
      for (final item in raw)
        for (final known in kMealAllergens)
          if (known.toLowerCase() == item.toString().trim().toLowerCase()) known,
    ];
  }
  final text = raw?.toString() ?? '';
  if (text.isEmpty) return const [];
  return [
    for (final part in text.split(RegExp(r'[,|/]')))
      for (final known in kMealAllergens)
        if (known.toLowerCase() == part.trim().toLowerCase()) known,
  ];
}

String mealIngredientsLine(Map<String, dynamic> meal) {
  return meal['ingredients']?.toString().trim() ?? '';
}

String mealChefTipLine(Map<String, dynamic> meal) {
  return meal['chef_tip']?.toString().trim() ?? '';
}

String mealPrepServingLine(Map<String, dynamic> meal) {
  final prep = int.tryParse(meal['prep_minutes']?.toString() ?? '');
  final cook = int.tryParse(meal['cook_minutes']?.toString() ?? '');
  final serve = meal['serving_size']?.toString().trim() ?? '';
  final store = int.tryParse(meal['storage_hours']?.toString() ?? '');
  final parts = <String>[
    if (prep != null && prep > 0) 'Prep $prep min',
    if (cook != null && cook > 0) 'Cook $cook min',
    if (serve.isNotEmpty) serve,
    if (store != null && store > 0) 'Best within $store hr',
  ];
  return parts.join(' · ');
}

bool mealIsSeasonal(Map<String, dynamic> meal) {
  final flag = meal['is_seasonal'];
  if (flag == true) return true;
  final tags = meal['health_tags'] ?? meal['tags'];
  if (tags is Iterable) {
    return tags.any((tag) => tag.toString().toLowerCase().contains('seasonal') || tag.toString().toLowerCase().contains('limited'));
  }
  return false;
}

bool mealAllowsAvailabilityNotify(Map<String, dynamic> meal) {
  final flag = meal['allow_notify_when_available'];
  if (flag == false) return false;
  return true;
}
