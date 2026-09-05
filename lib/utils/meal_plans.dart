const List<int> kWeekdaysMonToSun = [1, 2, 3, 4, 5, 6, 7];
const List<int> kWeekdaysMonToFri = [1, 2, 3, 4, 5];

const Map<int, String> kWeekdayShort = {
  1: 'Mon',
  2: 'Tue',
  3: 'Wed',
  4: 'Thu',
  5: 'Fri',
  6: 'Sat',
  7: 'Sun',
};

List<int> normalizePlanWeekdays(dynamic raw) {
  Iterable<dynamic> values = const [];
  if (raw is Iterable) {
    values = raw;
  } else if (raw is String && raw.trim().isNotEmpty) {
    values = raw.replaceAll(RegExp(r'[{}\[\]]'), '').split(',');
  }
  final days = values
      .map((value) => int.tryParse(value.toString().trim()) ?? 0)
      .where((day) => day >= 1 && day <= 7)
      .toSet()
      .toList()
    ..sort();
  return days;
}

bool planRunsOnDate(dynamic weekdays, DateTime date) {
  return normalizePlanWeekdays(weekdays).contains(date.toLocal().weekday);
}

String formatPlanWeekdays(dynamic weekdays) {
  final days = normalizePlanWeekdays(weekdays);
  if (days.isEmpty) return 'No days selected';
  if (days.length == kWeekdaysMonToFri.length && days.every(kWeekdaysMonToFri.contains)) {
    return 'Mon–Fri';
  }
  if (days.length == 7) return 'Every day';
  if (days.length == 2 && days.contains(6) && days.contains(7)) return 'Weekends';
  return days.map((day) => kWeekdayShort[day] ?? '$day').join(', ');
}

String planDueLabel(dynamic weekdays, {DateTime? now}) {
  final current = now ?? DateTime.now();
  if (planRunsOnDate(weekdays, current)) return 'Due today';
  return formatPlanWeekdays(weekdays);
}

class MealPlan {
  const MealPlan({
    required this.id,
    required this.customerId,
    required this.chefId,
    required this.mealId,
    required this.mealTitle,
    required this.chefName,
    required this.quantity,
    required this.weekdays,
    required this.timeSlot,
    required this.serviceType,
    required this.isActive,
    this.mealSnapshot = const {},
  });

  final String id;
  final String customerId;
  final String chefId;
  final String mealId;
  final String mealTitle;
  final String chefName;
  final int quantity;
  final List<int> weekdays;
  final String timeSlot;
  final String serviceType;
  final bool isActive;
  final Map<String, dynamic> mealSnapshot;

  bool runsOn(DateTime date) => planRunsOnDate(weekdays, date);

  bool get isDueToday => runsOn(DateTime.now());

  String get daysLabel => formatPlanWeekdays(weekdays);

  factory MealPlan.fromJson(Map<String, dynamic> json) {
    final snapshot = json['meal_snapshot'];
    return MealPlan(
      id: json['id']?.toString() ?? '',
      customerId: json['customer_id']?.toString() ?? '',
      chefId: json['chef_id']?.toString() ?? '',
      mealId: json['meal_id']?.toString() ?? '',
      mealTitle: json['meal_title']?.toString() ?? 'Home meal',
      chefName: json['chef_name']?.toString() ?? 'Home kitchen',
      quantity: int.tryParse(json['quantity']?.toString() ?? '1') ?? 1,
      weekdays: normalizePlanWeekdays(json['weekdays']),
      timeSlot: json['time_slot']?.toString() ?? 'ASAP',
      serviceType: json['service_type']?.toString() ?? 'Delivery Partner',
      isActive: json['is_active'] != false,
      mealSnapshot: snapshot is Map ? Map<String, dynamic>.from(snapshot) : const {},
    );
  }

  Map<String, dynamic> toInsertPayload() {
    return {
      'customer_id': customerId,
      'chef_id': chefId,
      'meal_id': mealId.isEmpty ? null : mealId,
      'meal_title': mealTitle,
      'chef_name': chefName,
      'quantity': quantity,
      'weekdays': weekdays,
      'time_slot': timeSlot,
      'service_type': serviceType,
      'meal_snapshot': mealSnapshot,
      'is_active': isActive,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  Map<String, dynamic> mealForCart() {
    final meal = Map<String, dynamic>.from(mealSnapshot);
    meal['id'] = mealId.isNotEmpty ? mealId : (meal['id'] ?? id);
    meal['chef_id'] = chefId;
    meal['title'] = mealTitle;
    meal['time_slot'] = timeSlot;
    meal['service_type'] = serviceType;
    if (chefName.isNotEmpty) meal['chef_name'] = chefName;
    return meal;
  }
}

MealPlan mealPlanDraftFromMeal(
  Map<String, dynamic> meal, {
  required String customerId,
  int quantity = 1,
  List<int> weekdays = kWeekdaysMonToFri,
}) {
  return MealPlan(
    id: '',
    customerId: customerId,
    chefId: meal['chef_id']?.toString() ?? '',
    mealId: meal['id']?.toString() ?? '',
    mealTitle: meal['title']?.toString() ?? meal['name']?.toString() ?? 'Home meal',
    chefName: meal['chef_name']?.toString() ?? meal['name']?.toString() ?? 'Home kitchen',
    quantity: quantity < 1 ? 1 : quantity,
    weekdays: normalizePlanWeekdays(weekdays),
    timeSlot: meal['time_slot']?.toString() ?? 'ASAP',
    serviceType: meal['service_type']?.toString() ?? 'Delivery Partner',
    isActive: true,
    mealSnapshot: Map<String, dynamic>.from(meal),
  );
}

MealPlan? activePlanForMeal(Iterable<MealPlan> plans, String mealId) {
  if (mealId.isEmpty) return null;
  for (final plan in plans) {
    if (plan.isActive && plan.mealId == mealId) return plan;
  }
  return null;
}

List<MealPlan> duePlansMissingFromCart(
  Iterable<MealPlan> plans,
  Iterable<String> cartMealIds, {
  DateTime? now,
}) {
  final inCart = cartMealIds.toSet();
  final current = now ?? DateTime.now();
  return plans
      .where((plan) => plan.isActive && plan.runsOn(current) && !inCart.contains(plan.mealId))
      .toList();
}
