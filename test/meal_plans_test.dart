import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/meal_plans.dart';

MealPlan _plan({
  String id = 'p1',
  String mealId = 'm1',
  List<int> weekdays = const [1, 2, 3, 4, 5],
  bool isActive = true,
}) {
  return MealPlan(
    id: id,
    customerId: 'diner-1',
    chefId: 'chef-1',
    mealId: mealId,
    mealTitle: 'Dal rice',
    chefName: 'Asha',
    quantity: 2,
    weekdays: weekdays,
    timeSlot: '12:00 PM - 1:00 PM',
    serviceType: 'Delivery Partner',
    isActive: isActive,
  );
}

void main() {
  test('weekday labels collapse common tiffin weeks', () {
    expect(formatPlanWeekdays([1, 2, 3, 4, 5]), 'Mon–Fri');
    expect(formatPlanWeekdays([1, 2, 3, 4, 5, 6, 7]), 'Every day');
    expect(formatPlanWeekdays([6, 7]), 'Weekends');
    expect(formatPlanWeekdays([1, 3, 5]), 'Mon, Wed, Fri');
    expect(formatPlanWeekdays([]), 'No days selected');
    expect(formatPlanWeekdays('{1,2,3,4,5}'), 'Mon–Fri');
  });

  test('a plan is due only on its weekdays', () {
    final monday = DateTime(2026, 9, 7);
    final saturday = DateTime(2026, 9, 5);
    expect(planRunsOnDate([1, 2, 3, 4, 5], monday), isTrue);
    expect(planRunsOnDate([1, 2, 3, 4, 5], saturday), isFalse);
    expect(planDueLabel([6, 7], now: saturday), 'Due today');
    expect(planDueLabel([1, 2, 3, 4, 5], now: saturday), 'Mon–Fri');
  });

  test('home banner hides plans already in the cart', () {
    final due = _plan();
    final weekend = _plan(id: 'p2', mealId: 'm2', weekdays: const [6, 7]);
    final monday = DateTime(2026, 9, 7);
    expect(
      duePlansMissingFromCart([due, weekend], const [], now: monday).map((plan) => plan.mealId),
      ['m1'],
    );
    expect(
      duePlansMissingFromCart([due], const ['m1'], now: monday),
      isEmpty,
    );
    expect(activePlanForMeal([due, weekend], 'm2')?.id, 'p2');
  });

  test('draft from a meal keeps the kitchen slot and does not invent a charge', () {
    final draft = mealPlanDraftFromMeal(
      {
        'id': 'meal-9',
        'chef_id': 'chef-1',
        'title': 'Tiffin',
        'chef_name': 'Asha',
        'time_slot': '8:00 PM - 9:00 PM',
        'service_type': 'Pickup, Delivery Partner',
      },
      customerId: 'diner-1',
    );
    expect(draft.timeSlot, '8:00 PM - 9:00 PM');
    expect(draft.serviceType, 'Pickup, Delivery Partner');
    expect(draft.weekdays, kWeekdaysMonToFri);
    expect(draft.mealForCart()['id'], 'meal-9');
  });
}
