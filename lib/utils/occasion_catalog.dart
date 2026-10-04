import 'package:flutter/material.dart';

/// Home-cooked occasions a diner can browse and broadcast.
class FoodOccasion {
  const FoodOccasion({
    required this.id,
    required this.label,
    required this.groupId,
    required this.groupTitle,
    required this.hint,
    required this.icon,
    required this.keywords,
  });

  final String id;
  final String label;
  final String groupId;
  final String groupTitle;
  final String hint;
  final IconData icon;
  final List<String> keywords;
}

class OccasionGroup {
  const OccasionGroup({
    required this.id,
    required this.title,
    required this.blurb,
    required this.occasions,
  });

  final String id;
  final String title;
  final String blurb;
  final List<FoodOccasion> occasions;
}

const List<OccasionGroup> kOccasionGroups = [
  OccasionGroup(
    id: 'everyday',
    title: 'Everyday',
    blurb: 'Daily meals, diet plates, and the season’s cravings.',
    occasions: [
      FoodOccasion(
        id: 'daily-meals',
        label: 'Daily meals',
        groupId: 'everyday',
        groupTitle: 'Everyday',
        hint: 'Lunch and dinner for work, study, or home.',
        icon: Icons.restaurant_outlined,
        keywords: ['lunch', 'dinner', 'thali', 'tiffin', 'curry', 'roti', 'dal', 'rice', 'meal'],
      ),
      FoodOccasion(
        id: 'healthy-plans',
        label: 'Healthy diet plans',
        groupId: 'everyday',
        groupTitle: 'Everyday',
        hint: 'Balanced, low-oil, and low-sugar plates.',
        icon: Icons.favorite_outline,
        keywords: ['healthy', 'salad', 'low-oil', 'low oil', 'low-sugar', 'low sugar', 'balanced', 'diet', 'bowl'],
      ),
      FoodOccasion(
        id: 'special-diet',
        label: 'Special dietary needs',
        groupId: 'everyday',
        groupTitle: 'Everyday',
        hint: 'Diabetic, gluten-free, vegan, or Ayurvedic.',
        icon: Icons.spa_outlined,
        keywords: ['diabetic', 'gluten', 'vegan', 'ayurvedic', 'jain', 'sattvic', 'sugar-free', 'sugar free'],
      ),
      FoodOccasion(
        id: 'seasonal-cravings',
        label: 'Seasonal cravings',
        groupId: 'everyday',
        groupTitle: 'Everyday',
        hint: 'Winter bhajis and soups, summer buttermilk and light meals.',
        icon: Icons.wb_sunny_outlined,
        keywords: ['bhaji', 'soup', 'buttermilk', 'chaas', 'cooler', 'seasonal'],
      ),
    ],
  ),
  OccasionGroup(
    id: 'family',
    title: 'Family functions',
    blurb: 'Festivals, gatherings, and ceremony spreads.',
    occasions: [
      FoodOccasion(
        id: 'festivals',
        label: 'Festivals',
        groupId: 'family',
        groupTitle: 'Family functions',
        hint: 'Diwali sweets, Holi snacks, Eid biryani, Christmas cakes.',
        icon: Icons.celebration_outlined,
        keywords: ['diwali', 'holi', 'eid', 'christmas', 'gujiya', 'modak', 'festival', 'hamper', 'laddu', 'barfi'],
      ),
      FoodOccasion(
        id: 'family-gatherings',
        label: 'Family gatherings',
        groupId: 'family',
        groupTitle: 'Family functions',
        hint: 'Thalis and combo meals when relatives visit.',
        icon: Icons.groups_outlined,
        keywords: ['family', 'gathering', 'combo', 'jumbo thali', 'relatives'],
      ),
      FoodOccasion(
        id: 'religious',
        label: 'Religious ceremonies',
        groupId: 'family',
        groupTitle: 'Family functions',
        hint: 'Prasad, sattvic meals, and fasting plates.',
        icon: Icons.temple_hindu_outlined,
        keywords: ['prasad', 'sattvic', 'fasting', 'vrat', 'navratri', 'puja'],
      ),
      FoodOccasion(
        id: 'ceremonies',
        label: 'Housewarming & naming',
        groupId: 'family',
        groupTitle: 'Family functions',
        hint: 'Traditional spreads for a new home or a naming day.',
        icon: Icons.home_outlined,
        keywords: ['housewarming', 'naming', 'griha', 'ceremony'],
      ),
    ],
  ),
  OccasionGroup(
    id: 'parties',
    title: 'Parties',
    blurb: 'Birthdays, anniversaries, offices, and community tables.',
    occasions: [
      FoodOccasion(
        id: 'birthday',
        label: 'Birthday parties',
        groupId: 'parties',
        groupTitle: 'Parties',
        hint: 'Snacks, sweets, cakes, and finger food.',
        icon: Icons.cake_outlined,
        keywords: ['birthday', 'cake', 'finger food'],
      ),
      FoodOccasion(
        id: 'anniversary',
        label: 'Anniversaries',
        groupId: 'parties',
        groupTitle: 'Parties',
        hint: 'A chef platter or dessert for the day.',
        icon: Icons.favorite_border,
        keywords: ['anniversary', 'platter'],
      ),
      FoodOccasion(
        id: 'office-parties',
        label: 'Office parties',
        groupId: 'parties',
        groupTitle: 'Parties',
        hint: 'Bulk snacks, sweets, and regional plates.',
        icon: Icons.business_center_outlined,
        keywords: ['office', 'workplace', 'corporate'],
      ),
      FoodOccasion(
        id: 'community-events',
        label: 'Community events',
        groupId: 'parties',
        groupTitle: 'Parties',
        hint: 'Large batches of pickles, laddus, and namkeen.',
        icon: Icons.festival_outlined,
        keywords: ['community', 'society', 'rwa', 'event'],
      ),
    ],
  ),
  OccasionGroup(
    id: 'specialty',
    title: 'Specialty',
    blurb: 'Jars, snacks, sweets, and the season’s batch.',
    occasions: [
      FoodOccasion(
        id: 'pickles',
        label: 'Pickles & preserves',
        groupId: 'specialty',
        groupTitle: 'Specialty',
        hint: 'Mango, lemon, and mixed achar.',
        icon: Icons.kitchen_outlined,
        keywords: ['pickle', 'achar', 'preserve'],
      ),
      FoodOccasion(
        id: 'snacks',
        label: 'Snacks & savories',
        groupId: 'specialty',
        groupTitle: 'Specialty',
        hint: 'Chakli, sev, samosas, and pakoras.',
        icon: Icons.bakery_dining_outlined,
        keywords: ['chakli', 'sev', 'samosa', 'pakora', 'namkeen', 'snack', 'farsan'],
      ),
      FoodOccasion(
        id: 'sweets',
        label: 'Traditional sweets',
        groupId: 'specialty',
        groupTitle: 'Specialty',
        hint: 'Besan and motichoor laddus, pedas, and halwa.',
        icon: Icons.cookie_outlined,
        keywords: ['laddu', 'laddoo', 'peda', 'halwa', 'barfi', 'motichoor', 'mithai', 'sweet', 'dessert'],
      ),
      FoodOccasion(
        id: 'seasonal-batch',
        label: 'Seasonal items',
        groupId: 'specialty',
        groupTitle: 'Specialty',
        hint: 'Til laddus in winter, modaks for Ganesh.',
        icon: Icons.ac_unit_outlined,
        keywords: ['til laddu', 'til laddoo', 'modak', 'ganesh', 'seasonal batch'],
      ),
    ],
  ),
];

List<FoodOccasion> get kFoodOccasions => [
      for (final group in kOccasionGroups) ...group.occasions,
    ];

FoodOccasion? foodOccasionById(String? id) {
  final key = id?.trim().toLowerCase() ?? '';
  if (key.isEmpty) return null;
  for (final occasion in kFoodOccasions) {
    if (occasion.id == key) return occasion;
  }
  return null;
}

FoodOccasion? foodOccasionByLabel(String? label) {
  final key = label?.trim().toLowerCase() ?? '';
  if (key.isEmpty || key == 'all') return null;
  for (final occasion in kFoodOccasions) {
    if (occasion.label.toLowerCase() == key || occasion.id == key) return occasion;
  }
  return null;
}

bool plateMatchesFoodOccasion(Map<String, dynamic> meal, FoodOccasion occasion) {
  final haystack = [
    meal['title'],
    meal['name'],
    meal['category'],
    meal['cuisine'],
    meal['description'],
    meal['dish_course'],
    meal['tags'],
  ].map((value) => value?.toString().toLowerCase() ?? '').join(' ');
  for (final keyword in occasion.keywords) {
    if (haystack.contains(keyword)) return true;
  }
  return false;
}
