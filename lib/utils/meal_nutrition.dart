double? parseMealNutritionNumber(dynamic raw) {
  if (raw == null) return null;
  final text = raw.toString().trim().replaceAll(RegExp(r'[^0-9.]'), '');
  if (text.isEmpty) return null;
  final value = double.tryParse(text);
  if (value == null || value <= 0) return null;
  return value;
}

double? mealNutritionField(Map<String, dynamic>? meal, List<String> keys) {
  if (meal == null) return null;
  for (final key in keys) {
    final value = parseMealNutritionNumber(meal[key]);
    if (value != null) return value;
  }
  return null;
}

class MealNutritionFacts {
  const MealNutritionFacts({
    this.caloriesKcal,
    this.weightG,
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.fiberG,
  });

  final double? caloriesKcal;
  final double? weightG;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;
  final double? fiberG;

  bool get hasValues =>
      caloriesKcal != null ||
      weightG != null ||
      proteinG != null ||
      carbsG != null ||
      fatG != null ||
      fiberG != null;

  String _n(double value) =>
      value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(1);

  List<(String label, String value)> get tiles {
    return [
      if (caloriesKcal != null) ('Cal', '${_n(caloriesKcal!)} kcal'),
      if (weightG != null) ('Wt', '${_n(weightG!)} g'),
      if (proteinG != null) ('Protein', '${_n(proteinG!)} g'),
      if (carbsG != null) ('Carbs', '${_n(carbsG!)} g'),
      if (fatG != null) ('Fat', '${_n(fatG!)} g'),
      if (fiberG != null) ('Fiber', '${_n(fiberG!)} g'),
    ];
  }

  String get compactLine => tiles.map((t) => t.$2.startsWith(t.$1) ? t.$2 : '${t.$1} ${t.$2}').join(' · ');
}

MealNutritionFacts mealNutritionFacts(Map<String, dynamic>? meal) {
  return MealNutritionFacts(
    caloriesKcal: mealNutritionField(meal, const ['calories_kcal', 'calories', 'kcal', 'cal']),
    weightG: mealNutritionField(meal, const ['portion_weight_g', 'weight_g', 'weight', 'wt']),
    proteinG: mealNutritionField(meal, const ['protein_g', 'protein']),
    carbsG: mealNutritionField(meal, const ['carbs_g', 'carbohydrates', 'carbs', 'carb']),
    fatG: mealNutritionField(meal, const ['fat_g', 'fat']),
    fiberG: mealNutritionField(meal, const ['fiber_g', 'fibre_g', 'fiber', 'fibre']),
  );
}

Map<String, dynamic> mealNutritionPayload({
  required double? caloriesKcal,
  required double? weightG,
  required double? proteinG,
  required double? carbsG,
  required double? fatG,
  required double? fiberG,
}) {
  return {
    'calories_kcal': caloriesKcal,
    'portion_weight_g': weightG,
    'protein_g': proteinG,
    'carbs_g': carbsG,
    'fat_g': fatG,
    'fiber_g': fiberG,
  };
}
