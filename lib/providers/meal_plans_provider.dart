import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../utils/meal_plans.dart';

final mealPlansProvider = NotifierProvider<MealPlansNotifier, List<MealPlan>>(MealPlansNotifier.new);

class MealPlansNotifier extends Notifier<List<MealPlan>> {
  final _supabase = Supabase.instance.client;

  @override
  List<MealPlan> build() {
    fetchPlans();
    return const [];
  }

  Future<void> fetchPlans() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        state = const [];
        return;
      }

      final res = await _supabase
          .from('meal_plans')
          .select()
          .eq('customer_id', user.id)
          .eq('is_active', true)
          .order('created_at', ascending: false);

      state = [
        for (final row in res) MealPlan.fromJson(Map<String, dynamic>.from(row)),
      ];
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to fetch meal plans');
    }
  }

  Future<bool> savePlan(MealPlan plan) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;
    if (plan.weekdays.isEmpty || plan.chefId.isEmpty) return false;

    final payload = plan.toInsertPayload()..['customer_id'] = user.id;
    final existing = activePlanForMeal(state, plan.mealId);

    try {
      if (existing != null && existing.id.isNotEmpty) {
        await _supabase.from('meal_plans').update(payload).eq('id', existing.id).eq('customer_id', user.id);
      } else {
        await _supabase.from('meal_plans').insert(payload);
      }
      await fetchPlans();
      return true;
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to save meal plan');
      await fetchPlans();
      return false;
    }
  }

  Future<bool> pausePlan(String planId) async {
    final user = _supabase.auth.currentUser;
    if (user == null || planId.isEmpty) return false;

    try {
      await _supabase.from('meal_plans').update({
        'is_active': false,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', planId).eq('customer_id', user.id);
      state = [for (final plan in state) if (plan.id != planId) plan];
      return true;
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to pause meal plan');
      await fetchPlans();
      return false;
    }
  }

  Future<Map<String, dynamic>> resolveMeal(MealPlan plan) async {
    if (plan.mealId.isEmpty) return plan.mealForCart();
    try {
      final live = await _supabase.from('meals').select().eq('id', plan.mealId).maybeSingle();
      if (live != null) return Map<String, dynamic>.from(live);
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to resolve planned meal');
    }
    return plan.mealForCart();
  }

  void clear() {
    state = const [];
  }
}
